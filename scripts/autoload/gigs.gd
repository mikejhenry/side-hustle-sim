extends Node
## Gig economy (autoload "Gigs"): which apps are online, incoming offers, the active job.
##
## Job flow by kind:
##   ride:    to_pickup -> (phone: Start Trip) -> to_dropoff -> (phone: Complete Trip)
##   food:    to_restaurant -> (counter: pick up) -> to_customer -> (door) -> confirm_photo -> (phone)
##   grocery: to_store -> shopping (shelves) -> checkout (register) -> to_customer -> (door) -> confirm_photo
##   flex:    to_station -> (phone: Scan packages at loading zone) -> delivering (doors) -> done
##
## Rides, food and grocery orders come with a customer personality (CustomerData) that changes
## tips, deadlines and how they rate you, and may plan random events for the job (a spilled
## drink, a new drop-off, a wrong address, a tip taken back). Your star rating per app sets your
## tier: Platinum gets priority offers, and falling too low gets you deactivated.

signal offers_changed
signal job_changed
signal offer_received(offer: Dictionary)

var online := {}
var offers: Array = []
var job: Dictionary = {}
var ratings := {}
var recent := {}           # app id -> latest star ratings, newest first
var deactivated := {}      # app id -> the day you can appeal and take the course
var random_events := true  # tests turn this off to get predictable jobs
var town: Node = null      # set by main: provides addresses, restaurants, stores, station
var main: Node = null      # set by main: provides actor position / driving state

var _accum := 0.0
var _next_id := 100
var _flex_blocks_seen := {}


func _ready() -> void:
	for id in GameData.APPS:
		online[id] = false
		ratings[id] = CustomerData.START_RATING
		recent[id] = []
	Game.minutes_advanced.connect(_on_minutes)
	Game.bladder_accident.connect(_on_bladder_accident)


func reset_jobs() -> void:
	offers.clear()
	job = {}
	for id in online:
		online[id] = false
	offers_changed.emit()
	job_changed.emit()


func app(id: String) -> Dictionary:
	return GameData.APPS[id]


func any_online() -> bool:
	for id in online:
		if online[id]:
			return true
	return false


# --- Demand / peak times ------------------------------------------------------

func surge(id: String, h := -1) -> float:
	if h < 0:
		h = Game.hour()
	for p in app(id).peaks:
		if h >= p[0] and h < p[1]:
			return p[2]
	return 1.0


func demand_label(id: String) -> String:
	var s := surge(id)
	if s >= 1.7:
		return "VERY BUSY  %.1fx" % s
	if s > 1.0:
		return "Busy  %.1fx" % s
	return "Normal demand"


# --- Online state ----------------------------------------------------------------

func ineligible_reason(id: String) -> String:
	if not Game.phone_service:
		return "Phone service suspended. Pay your phone bill."
	if Game.phone_battery <= 0.0:
		return "Your phone is dead. Charge it in your car."
	var a := app(id)
	if deactivated.has(id):
		return "%s deactivated your account (rating %.2f). %s" % [a.name, ratings[id], reactivation_text(id)]
	if a.has("min_year") and Game.car().year < a.min_year:
		return "%s requires a %d or newer vehicle. Your %s doesn't qualify." % [a.name, a.min_year, Game.car().name]
	return ""


func set_online(id: String, on: bool) -> void:
	if on:
		var reason := ineligible_reason(id)
		if reason != "":
			Game.notify(reason, "bad")
			return
	online[id] = on
	if not on:
		offers = offers.filter(func(o): return o.app != id)
	Game.notify("%s: you're %s." % [app(id).name, "online" if on else "offline"], "info")
	offers_changed.emit()


func go_offline_all() -> void:
	var was := any_online()
	for id in online:
		online[id] = false
	offers.clear()
	if was:
		offers_changed.emit()


# --- Ticking ----------------------------------------------------------------------

func _on_minutes(m: float) -> void:
	if Game.sleeping:
		_accum = 0.0
		if not job.is_empty():
			_check_job_time(Game.total_minutes())
		return
	if any_online() and (Game.phone_battery <= 0.0 or not Game.phone_service):
		go_offline_all()
		Game.notify("Your phone can't stay online. All gig apps went offline.", "bad")
	_accum += m
	while _accum >= 1.0:
		_accum -= 1.0
		_tick_minute()


func _tick_minute() -> void:
	var now := Game.total_minutes()
	var changed := false
	for o in offers.duplicate():
		if now > o.expires:
			offers.erase(o)
			changed = true
	if not job.is_empty():
		_job_events(now)
	if not job.is_empty():
		_check_job_time(now)
	elif town != null:
		for id in GameData.APP_ORDER:
			if not online[id] or app(id).kind == "flex" or _has_offer(id):
				continue
			var rating_mult := clampf(ratings[id] - 3.9, 0.2, 1.0)
			if randf() < GameData.BASE_OFFER_CHANCE * surge(id) * Game.weather_boost(app(id).kind) * rating_mult:
				_make_offer(id)
				changed = true
	if online.get("jungleflex", false) and town != null:
		changed = _offer_flex_blocks(now) or changed
	if changed:
		offers_changed.emit()


func _has_offer(id: String) -> bool:
	for o in offers:
		if o.app == id:
			return true
	return false


func _actor_pos() -> Vector3:
	return main.actor_position() if main else Vector3.ZERO


func _miles(a: Vector3, b: Vector3) -> float:
	# Streets are a grid, so use Manhattan distance.
	return (absf(a.x - b.x) + absf(a.z - b.z)) / GameData.METERS_PER_MILE


func _make_offer(id: String) -> void:
	var a := app(id)
	var now := Game.total_minutes()
	var o := {"id": _next_id, "app": id, "kind": a.kind, "expires": now + GameData.OFFER_MINUTES}
	_next_id += 1
	var me := _actor_pos()
	var s := surge(id)
	var wb := Game.weather_boost(a.kind)
	match a.kind:
		"ride":
			var p: Dictionary = town.addresses.pick_random()
			var d: Dictionary = _pick_far(p, town.addresses + town.restaurants + town.stores)
			var trip := _miles(p.curb, d.curb)
			o.pickup = p
			o.dropoff = d
			o.passenger = GameData.FIRST_NAMES.pick_random()
			o.miles = trip
			o.pickup_miles = _miles(me, p.curb)
			o.pay = (a.base + a.per_mile * trip) * s * wb * Game.car().comfort
			o.weather_pay = (a.base + a.per_mile * trip) * s * (wb - 1.0) * Game.car().comfort
			o.tip = 0.0
			o.deadline = now + 25.0 + (o.pickup_miles + trip) * 8.0
		"food":
			var r: Dictionary = town.restaurants.pick_random()
			var c: Dictionary = _pick_far(r, town.addresses)
			var miles := _miles(me, r.curb) + _miles(r.curb, c.curb)
			o.restaurant = r
			o.customer = c
			o.customer_name = GameData.FIRST_NAMES.pick_random()
			o.order_no = randi_range(1000, 9999)
			o.miles = miles
			o.tip = float(randi_range(0, 7))
			o.peak_pay = (s - 1.0) * 4.0
			o.weather_pay = snappedf((a.base + a.per_mile * miles) * (wb - 1.0), 0.01)
			o.pay = a.base + a.per_mile * miles + o.peak_pay + o.weather_pay + o.tip
			o.deadline = now + 35.0 + miles * 9.0
		"grocery":
			var st: Dictionary = town.stores.pick_random()
			var c: Dictionary = _pick_far(st, town.addresses)
			var items: Array = GameData.GROCERY_ITEMS.duplicate()
			items.shuffle()
			items = items.slice(0, randi_range(3, 6))
			var miles := _miles(me, st.curb) + _miles(st.curb, c.curb)
			o.store = st
			o.customer = c
			o.customer_name = GameData.FIRST_NAMES.pick_random()
			o.items = items
			o.miles = miles
			o.tip = float(randi_range(2, 12))
			o.peak_pay = (s - 1.0) * 5.0
			o.weather_pay = snappedf((a.base + a.per_item * items.size() + a.per_mile * miles) * (wb - 1.0), 0.01)
			o.pay = a.base + a.per_item * items.size() + a.per_mile * miles + o.peak_pay + o.weather_pay + o.tip
			o.deadline = now + 50.0 + items.size() * 6.0 + miles * 9.0
	_add_customer(o, id)
	o.miles = snappedf(o.miles, 0.1)
	o.pay = snappedf(o.pay, 0.01)
	offers.append(o)
	offer_received.emit(o)


func _pick_far(from: Dictionary, pool: Array) -> Dictionary:
	for i in 12:
		var c: Dictionary = pool.pick_random()
		var d := _miles(from.curb, c.curb)
		if d > 0.8 and d < 4.5 and c.name != from.name:
			return c
	return pool.pick_random()


func _offer_flex_blocks(now: float) -> bool:
	var a := app("jungleflex")
	var changed := false
	for start_h in a.blocks:
		var start: float = (Game.day - 1) * 1440.0 + start_h * 60.0
		var key := "%d-%d" % [Game.day, start_h]
		if _flex_blocks_seen.has(key):
			continue
		if now >= start - 150.0 and now < start - 10.0:
			_flex_blocks_seen[key] = true
			var s := surge("jungleflex", start_h) * Game.weather_boost("flex")
			var o := {"id": _next_id, "app": "jungleflex", "kind": "flex", "expires": start - 10.0,
				"start": start, "end": start + a.block_minutes, "packages": randi_range(4, 6),
				"miles": 0.0, "tip": 0.0}
			_next_id += 1
			o.pay = snappedf(a.block_pay * s, 0.01)
			o.deadline = o.end
			offers.append(o)
			offer_received.emit(o)
			changed = true
	return changed


# --- Accepting / declining ----------------------------------------------------------

func find_offer(offer_id: int) -> Dictionary:
	for o in offers:
		if o.id == offer_id:
			return o
	return {}


func accept(offer_id: int) -> void:
	var o := find_offer(offer_id)
	if o.is_empty():
		return
	if not job.is_empty():
		Game.notify("Finish your current job first.", "warn")
		return
	offers.erase(o)
	job = o.duplicate()
	job.crashes = 0
	job.accepted_at = Game.total_minutes()
	job.spilled = false
	job.events = _plan_events(job) if random_events else []
	match job.kind:
		"ride":
			job.stage = "to_pickup"
			Game.notify("Ride accepted. Pick up %s (%s)." % [job.passenger, customer_tag(job)], "good")
		"food":
			job.stage = "to_restaurant"
			Game.notify("Order #%d accepted. Head to %s." % [job.order_no, job.restaurant.name], "good")
		"grocery":
			job.stage = "to_store"
			job.picked = []
			Game.notify("Shopping order accepted. Head to %s." % job.store.name, "good")
		"flex":
			job.stage = "to_station"
			job.stops = _flex_stops(job.packages)
			job.delivered = 0
			Game.notify("Block reserved! Be at the Jungle Flex station by %s." % Game.abs_time_string(job.start), "good")
	offers_changed.emit()
	job_changed.emit()


func decline(offer_id: int) -> void:
	var o := find_offer(offer_id)
	if o.is_empty():
		return
	offers.erase(o)
	offers_changed.emit()


func cancel_job() -> void:
	if job.is_empty():
		return
	_rate(job.app, 3.0)
	Game.notify("You cancelled the %s job. Your rating took a hit." % app(job.app).name, "bad")
	job = {}
	job_changed.emit()


func _flex_stops(n: int) -> Array:
	# Packages go to a cluster of nearby houses, like a real route.
	var first: Dictionary = town.addresses.pick_random()
	var pool: Array = town.addresses.duplicate()
	pool.sort_custom(func(a, b): return _miles(a.curb, first.curb) < _miles(b.curb, first.curb))
	var stops := []
	for addr in pool.slice(0, n * 2):
		if stops.size() < n and randf() < 0.7:
			stops.append(addr)
	while stops.size() < n:
		stops.append(pool[stops.size()])
	return stops


# --- Job progress (called from phone buttons and world interactables) ----------------

func target() -> Dictionary:
	if job.is_empty():
		return {}
	match job.kind:
		"ride":
			if job.stage == "to_pickup":
				return {"pos": job.pickup.curb, "label": "Pick up " + job.passenger}
			return {"pos": job.dropoff.curb, "label": "Drop off at " + job.dropoff.name}
		"food":
			if job.stage == "to_restaurant":
				return {"pos": job.restaurant.door, "label": "Pick up at " + job.restaurant.name}
			if job.stage == "to_customer":
				return {"pos": job.customer.door, "label": "Deliver to " + job.customer.name}
		"grocery":
			if job.stage in ["to_store", "shopping", "checkout"]:
				return {"pos": job.store.door, "label": "Shop at " + job.store.name}
			if job.stage == "to_customer":
				return {"pos": job.customer.door, "label": "Deliver to " + job.customer.name}
		"flex":
			if job.stage == "to_station":
				return {"pos": town.station.door, "label": "Jungle Flex station"}
			if job.stage == "delivering" and not job.get("photo_due", {}).is_empty():
				return {"pos": job.photo_due.door, "label": "Photo at " + job.photo_due.name}
			if job.stage == "delivering" and not job.stops.is_empty():
				var me := _actor_pos()
				var best: Dictionary = job.stops[0]
				for s in job.stops:
					if s.door.distance_to(me) < best.door.distance_to(me):
						best = s
				return {"pos": best.door, "label": "Package to " + best.name}
	return {}


func status_text() -> String:
	if job.is_empty():
		return ""
	var a := app(job.app)
	var t := ""
	match job.stage:
		"to_pickup": t = "Drive to %s to pick up %s, then tap Start Trip." % [job.pickup.name, job.passenger]
		"to_dropoff": t = "Take %s to %s, then tap Complete Trip." % [job.passenger, job.dropoff.name]
		"to_restaurant": t = "Go inside %s and pick up order #%d at the counter." % [job.restaurant.name, job.order_no]
		"to_customer":
			t = "Bring the order to %s's door at %s." % [job.customer_name, job.customer.name]
			if job.customer.has("floor"):
				t += " It's on floor %d: take the stairs or the elevator." % job.customer.floor
		"confirm_photo": t = "Open your phone and take the drop-off photo."
		"to_store": t = "Go to %s and start shopping." % job.store.name
		"shopping": t = "Grab items from the shelves (%d/%d). List is in the app." % [job.picked.size(), job.items.size()]
		"checkout": t = "Check out at the register."
		"to_station":
			if Game.total_minutes() < job.start - 30.0:
				t = "Block starts %s. Scanning opens 30 min before." % Game.abs_time_string(job.start)
			else:
				t = "Drive into the Jungle Flex station and scan your packages in the app."
		"delivering":
			if not job.get("photo_due", {}).is_empty():
				t = "Open your phone and take the drop-off photo."
			else:
				t = "Deliver packages: %d left. Ends %s." % [job.stops.size(), Game.abs_time_string(job.end)]
	return "%s: %s" % [a.name, t]


func near(pos: Vector3, radius: float) -> bool:
	return main != null and main.actor_position().distance_to(pos) < radius


func can_start_trip() -> bool:
	return job.get("stage", "") == "to_pickup" and main.is_driving() and main.car_speed() < 3.0 \
		and near(job.pickup.curb, 16.0)


func start_trip() -> void:
	if not can_start_trip():
		return
	job.stage = "to_dropoff"
	job.crashes = 0
	var now := Game.total_minutes()
	job.trip_start = now
	job.next_chat = now + randf_range(2.0, 4.0)
	job.new_stop_at = randf_range(1.5, 3.0)
	job.spill_at = randf_range(2.0, 5.0)
	var greet := customer_line(job.get("personality", ""), "greet")
	Game.notify(_say(job.passenger, greet if greet != "" else "\"Hey! Can you turn the music up?\""), "info")
	job_changed.emit()


func can_end_trip() -> bool:
	return job.get("stage", "") == "to_dropoff" and main.is_driving() and main.car_speed() < 3.0 \
		and near(job.dropoff.curb, 16.0)


func end_trip() -> void:
	if not can_end_trip():
		return
	var p := persona()
	var late: bool = Game.total_minutes() > job.deadline
	var stars: float = 5.0 - job.crashes * float(p.crash_mult)
	if Game.car().comfort < 0.9:
		stars -= 0.5
	if late:
		stars -= 1.0 if p.hurry >= 1.0 else 2.0
	stars = _final_stars(stars + float(p.stars))
	var tip := 0.0
	if stars >= 4.5 and randf() < clampf(0.45 * p.tip, 0.0, 0.95):
		tip = float(randi_range(1, 6)) * float(p.tip)
	if not late and stars >= 4.0:
		tip += float(p.on_time_tip)
	var extra := ""
	if job.get("cleaning_fee", 0.0) > 0.0:
		tip += job.cleaning_fee
		extra = " Includes a $%.0f cleaning fee." % job.cleaning_fee
	var bye := customer_line(job.get("personality", ""), "bye")
	var msg := "%s rated you %d★." % [job.passenger, int(stars)]
	if bye != "":
		msg = _say(job.passenger, bye) + " " + msg
	if tip > 0.0:
		msg += " Tip $%.2f." % tip
	_complete(stars, snappedf(tip, 0.01), msg + extra)


func pick_up_food() -> void:
	job.stage = "to_customer"
	Game.notify("Picked up order #%d. Don't eat the fries." % job.order_no, "good")
	job_changed.emit()


func grab_item(item: String) -> void:
	if not job.get("stage", "") in ["to_store", "shopping"]:
		return
	job.stage = "shopping"
	job.picked.append(item)
	if _take_event("out_of_stock"):
		_out_of_stock()
	Game.notify("Grabbed %s (%d/%d)" % [item, job.picked.size(), job.items.size()], "info")
	if job.picked.size() >= job.items.size():
		job.stage = "checkout"
		Game.notify("All items found. Head to the register.", "good")
	job_changed.emit()


func begin_shopping() -> void:
	job.stage = "shopping"
	job_changed.emit()


func checkout() -> void:
	job.stage = "to_customer"
	Game.notify("Checked out with the Instacrate card. Now deliver it.", "good")
	job_changed.emit()


func leave_at_door() -> void:
	if _take_event("wrong_address"):
		_wrong_address()
		return
	job.stage = "confirm_photo"
	Game.notify("Order left at the door. Take the drop-off photo in the app.", "info")
	job_changed.emit()


func confirm_photo() -> void:
	if job.get("stage", "") != "confirm_photo" or not can_take_photo():
		return
	var p := persona()
	var who: String = job.customer_name
	var late: bool = Game.total_minutes() > job.deadline
	var stars := 5.0
	if late:
		stars -= 1.0 if p.hurry >= 1.0 else 2.0
	stars -= job.crashes * 0.5 * float(p.crash_mult)
	var notes := ""
	if job.spilled:
		stars -= 1.5
		job.pay -= job.tip
		job.tip = 0.0
		notes += " %s: \"The drink spilled all over the bag!\" They took back the tip." % who
	elif late:
		job.pay -= job.tip * 0.5
		job.tip *= 0.5
		notes += " You were late, so the customer cut the tip."
	stars = _final_stars(stars + float(p.stars))
	var extra := 0.0
	if _take_event("tip_bait") and job.tip > 0.0:
		job.pay -= job.tip
		notes += " Then %s removed the $%.2f tip. Ouch." % [who, job.tip]
		job.tip = 0.0
	elif stars >= 4.0:
		if not late:
			extra += float(p.on_time_tip)
		if p.tip >= 2.0:
			extra += float(randi_range(3, 8))
		if extra > 0.0:
			notes += " %s added $%.2f to the tip!" % [who, extra]
	var bye := customer_line(job.get("personality", ""), "bye")
	if not bye.begins_with("\""):
		bye = ""
	var msg := "Delivered! %s rated you %d★." % [who, int(stars)]
	if bye != "":
		msg += " " + _say(who, bye)
	_complete(stars, extra, msg + notes)


func can_scan() -> bool:
	return job.get("stage", "") == "to_station" and Game.total_minutes() >= job.start - 30.0 \
		and near(town.station.load_point, 18.0)


func scan_packages() -> void:
	if not can_scan():
		return
	job.stage = "delivering"
	Game.notify("Scanned and loaded %d packages. Route is in the app." % job.stops.size(), "good")
	job_changed.emit()


## Leaves a Jungle Flex package at the door. Like the other apps, it only counts once you
## take the drop-off photo in the app.
func deliver_package(addr_name: String) -> void:
	if job.get("photo_due", {}).size() > 0:
		return
	for s in job.stops:
		if s.name == addr_name:
			job.photo_due = s
			break
	Game.notify("Package left at %s. Take the drop-off photo in the app." % addr_name, "info")
	job_changed.emit()


## Drop-off photo for a Jungle Flex package. You have to be near the door.
func confirm_package_photo() -> void:
	var s: Dictionary = job.get("photo_due", {})
	if s.is_empty() or not can_take_photo():
		return
	job.photo_due = {}
	job.stops.erase(s)
	job.delivered += 1
	Game.notify("Photo sent. Package delivered to %s." % s.name, "good")
	if job.stops.is_empty():
		var stars := 5.0 if Game.total_minutes() <= job.end else 4.0
		_complete(stars, 0.0, "Block complete!")
	else:
		job_changed.emit()


## Drop-off photos are taken at the door (within a few steps of it).
func can_take_photo() -> bool:
	if job.is_empty():
		return false
	if job.get("stage", "") == "confirm_photo":
		return near(job.customer.door, 8.0)
	var s: Dictionary = job.get("photo_due", {})
	return not s.is_empty() and near(s.door, 8.0)


func door_prompt(addr: Dictionary) -> String:
	if job.is_empty():
		return ""
	if job.kind in ["food", "grocery"] and job.stage == "to_customer" and job.customer.name == addr.name:
		return "Leave %s order at the door" % app(job.app).name
	if job.kind == "flex" and job.stage == "delivering" and job.get("photo_due", {}).is_empty():
		for s in job.stops:
			if s.name == addr.name:
				return "Deliver Jungle Flex package"
	return ""


func door_action(addr: Dictionary) -> void:
	if job.kind == "flex":
		deliver_package(addr.name)
	else:
		leave_at_door()


func _complete(stars: float, extra_tip: float, msg: String) -> void:
	var a := app(job.app)
	var pay: float = job.pay + extra_tip
	Game.earn(pay, "%s payout" % a.name)
	Game.stats.jobs += 1
	_rate(job.app, stars)
	Game.notify("%s +$%.2f. %s" % [a.name, pay, msg], "money")
	job = {}
	job_changed.emit()


func _rate(id: String, stars: float) -> void:
	var before: float = ratings[id]
	ratings[id] = clampf(lerpf(before, stars, CustomerData.RATING_WEIGHT), 1.0, 5.0)
	var rec: Array = recent.get(id, [])
	rec.push_front(int(roundf(stars)))
	if rec.size() > CustomerData.RECENT_KEEP:
		rec.resize(CustomerData.RECENT_KEEP)
	recent[id] = rec
	_check_standing(id, before)


func _check_job_time(now: float) -> void:
	if job.kind == "flex":
		if job.stage == "to_station" and now > job.start + 30.0:
			_rate("jungleflex", 2.0)
			Game.notify("You missed your Jungle Flex block. Rating hit.", "bad")
			job = {}
			job_changed.emit()
		elif job.stage == "delivering" and now > job.end + 60.0:
			var frac := float(job.delivered) / float(job.packages)
			var pay: float = snappedf(job.pay * frac, 0.01)
			Game.earn(pay, "Jungle Flex partial block")
			_rate("jungleflex", 3.0)
			Game.notify("Block ended. Undelivered packages returned. Paid $%.2f." % pay, "warn")
			job = {}
			job_changed.emit()
	elif now > job.deadline + 75.0:
		_rate(job.app, 1.5)
		Game.notify("%s: you took too long and the job was reassigned." % app(job.app).name, "bad")
		job = {}
		job_changed.emit()


func on_crash(strength: float) -> void:
	if job.is_empty():
		return
	if job.kind == "ride" and job.stage == "to_dropoff":
		job.crashes += 1
		Game.notify("%s: \"WHOA! Are you trying to kill me?!\"" % job.passenger, "bad")
	elif job.kind in ["food", "grocery"] and job.stage == "to_customer" and strength > 8.0:
		job.crashes += 1
		if job.kind == "food" and random_events and not job.get("spilled", false) \
				and randf() < CustomerData.DRINK_SPILL_ON_CRASH:
			job.spilled = true
			Game.notify("Uh oh. The drink tipped over inside the bag...", "bad")
		else:
			Game.notify("You hear the order slide across the back seat...", "warn")


func _on_bladder_accident() -> void:
	if job.get("stage", "") == "to_dropoff":
		job.crashes += 4
		Game.notify("%s is horrified. That's going to be one star." % job.passenger, "bad")


# --- Customers: personalities and what they say ------------------------------------

## Gives a ride, food or grocery offer its customer: personality, their own star rating,
## and your tier's effect on pay (Platinum offers pay more, At risk offers pay less).
func _add_customer(o: Dictionary, id: String) -> void:
	if o.kind == "flex":
		return
	var now := Game.total_minutes()
	var r: float = ratings[id]
	var pid := _pick_personality(r)
	var p: Dictionary = CustomerData.PERSONALITIES[pid]
	o.personality = pid
	o.customer_rating = snappedf(randf_range(p.rating[0], p.rating[1]), 0.01)
	if o.kind in ["food", "grocery"]:
		# Delivery tips are shown up front, so the personality changes them now.
		var new_tip := float(roundi(o.tip * float(p.tip)))
		o.pay += new_tip - o.tip
		o.tip = new_tip
		o.note = customer_line(pid, "note")
	o.priority = r >= CustomerData.TIERS[0][0]
	var mult := 1.0
	if o.priority:
		mult = CustomerData.PLATINUM_PAY
	elif r < CustomerData.TIERS[2][0]:
		mult = CustomerData.AT_RISK_PAY
	o.tier_pay = snappedf(o.pay * (mult - 1.0), 0.01)
	o.pay *= mult
	o.deadline = now + (o.deadline - now) * float(p.hurry)


func _pick_personality(rating: float) -> String:
	var h := Game.hour()
	var night := h >= CustomerData.NIGHT_START or h < CustomerData.NIGHT_END
	var platinum := rating >= CustomerData.TIERS[0][0]
	var weights := {}
	var total := 0.0
	for pid in CustomerData.PERSONALITIES:
		var p: Dictionary = CustomerData.PERSONALITIES[pid]
		var w: float = float(p.night_weight if night else p.weight)
		if platinum:
			w = 0.0 if pid in CustomerData.PLATINUM_SKIP else w * float(CustomerData.PLATINUM_BOOST.get(pid, 1.0))
		weights[pid] = w
		total += w
	var roll := randf() * total
	for pid in weights:
		roll -= weights[pid]
		if roll <= 0.0 and weights[pid] > 0.0:
			return pid
	return "friendly"


## The active job's customer personality.
func persona() -> Dictionary:
	return CustomerData.PERSONALITIES.get(job.get("personality", "friendly"), CustomerData.PERSONALITIES.friendly)


## "💬 Chatty • 4.92★", for offers and the job card.
func customer_tag(o: Dictionary) -> String:
	if not o.has("personality"):
		return ""
	var p: Dictionary = CustomerData.PERSONALITIES[o.personality]
	return "%s %s • %.2f★" % [p.icon, p.label, o.customer_rating]


func customer_line(pid: String, key: String) -> String:
	var lines: Array = CustomerData.LINES.get(pid, {}).get(key, [])
	return "" if lines.is_empty() else str(lines.pick_random())


## Quotes get the speaker's name in front; descriptions ("They nod...") get it in brackets.
func _say(who: String, line: String) -> String:
	if line.begins_with("\""):
		return "%s: %s" % [who, line]
	return "(%s) %s" % [who, line]


func _final_stars(stars: float) -> float:
	if random_events and randf() < CustomerData.RANDOM_GRUMP_CHANCE:
		stars -= 1.0
	return clampf(roundf(stars), 1.0, 5.0)


# --- Random job events --------------------------------------------------------------

func _plan_events(j: Dictionary) -> Array:
	var ev := []
	var pid: String = j.get("personality", "friendly")
	match j.kind:
		"ride":
			if randf() < (CustomerData.RIDE_SPILL_CHANCE_PARTY if pid == "partying" else CustomerData.RIDE_SPILL_CHANCE):
				ev.append("spill")
			if randf() < CustomerData.RIDE_NEW_STOP_CHANCE:
				ev.append("new_stop")
			if randf() < CustomerData.RIDE_CANCEL_CHANCE:
				ev.append("rider_cancel")
		"food", "grocery":
			if randf() < CustomerData.WRONG_ADDRESS_CHANCE:
				ev.append("wrong_address")
			if randf() < (CustomerData.TIP_BAIT_CHANCE_RUDE if pid == "rude" else CustomerData.TIP_BAIT_CHANCE):
				ev.append("tip_bait")
			if j.kind == "grocery" and j.items.size() > 3 and randf() < CustomerData.OUT_OF_STOCK_CHANCE:
				ev.append("out_of_stock")
	return ev


## True (and uses it up) if this event is planned for the active job.
func _take_event(e: String) -> bool:
	var ev: Array = job.get("events", [])
	if e in ev:
		ev.erase(e)
		return true
	return false


## Things that happen on the way: rider cancels, passengers talk, spill, or change the drop-off.
func _job_events(now: float) -> void:
	if job.kind != "ride":
		return
	var ev: Array = job.get("events", [])
	if job.stage == "to_pickup" and "rider_cancel" in ev and now - job.accepted_at >= 3.0:
		var a := app(job.app)
		Game.earn(CustomerData.RIDER_CANCEL_FEE, "%s cancellation fee" % a.name)
		Game.notify("%s cancelled the ride. %s paid you a $%.2f cancellation fee." % [job.passenger, a.name, CustomerData.RIDER_CANCEL_FEE], "warn")
		job = {}
		job_changed.emit()
		_refresh_gps()
		return
	if job.stage != "to_dropoff":
		return
	var t: float = now - job.trip_start
	if "new_stop" in ev and t >= job.new_stop_at:
		ev.erase("new_stop")
		_new_stop()
	if "spill" in ev and t >= job.spill_at:
		ev.erase("spill")
		_spill()
	if now >= job.next_chat:
		var chatty: bool = job.personality in ["chatty", "partying"]
		job.next_chat = now + (randf_range(3.0, 5.0) if chatty else randf_range(4.0, 7.0))
		var line := customer_line(job.personality, "chat")
		if line != "" and (chatty or randf() < 0.4):
			Game.notify(_say(job.passenger, line), "info")


func _spill() -> void:
	job.cleaning_fee = CustomerData.CLEANING_FEE
	var msg: String = CustomerData.SPILL_LINES.pick_random() % job.passenger
	msg += " They'll be charged a $%.0f cleaning fee." % CustomerData.CLEANING_FEE
	if Game.money >= CustomerData.DETAILING_COST:
		Game.spend(CustomerData.DETAILING_COST, "Seat shampoo (spill)")
		msg += " You paid $%.0f for seat shampoo." % CustomerData.DETAILING_COST
	Game.notify(msg, "warn")


func _new_stop() -> void:
	var old: Dictionary = job.dropoff
	var d := _pick_far(old, town.addresses + town.restaurants + town.stores)
	if d.name == old.name or d.name == job.pickup.name:
		return
	var a := app(job.app)
	var extra := _miles(old.curb, d.curb)
	var add_pay := snappedf(a.per_mile * extra * surge(job.app) * Game.car().comfort, 0.01)
	job.dropoff = d
	job.pay += add_pay
	job.miles = snappedf(job.miles + extra, 0.1)
	job.deadline += extra * 8.0
	var line: String = CustomerData.NEW_STOP_LINES.pick_random() % [job.passenger, d.name]
	Game.notify("%s The fare went up $%.2f." % [line, add_pay], "warn")
	job_changed.emit()
	_refresh_gps()


func _wrong_address() -> void:
	var old: Dictionary = job.customer
	var pool := []
	for addr in town.addresses:
		var d := _miles(old.curb, addr.curb)
		if addr.name != old.name and d > 0.3 and d < 1.6:
			pool.append(addr)
	if pool.is_empty():
		pool = town.addresses.filter(func(x): return x.name != old.name)
	var dest: Dictionary = pool.pick_random()
	var extra := _miles(old.curb, dest.curb)
	var bonus := snappedf(CustomerData.WRONG_ADDRESS_BONUS + float(app(job.app).per_mile) * extra, 0.01)
	job.customer = dest
	job.pay += bonus
	job.deadline = maxf(job.deadline, Game.total_minutes()) + 10.0 + extra * 9.0
	Game.notify("%s texted: \"WAIT, wrong address, so sorry! I'm at %s.\" The app added $%.2f." % [job.customer_name, dest.name, bonus], "warn")
	job_changed.emit()
	_refresh_gps()


func _out_of_stock() -> void:
	var left: Array = job.items.filter(func(x): return not x in job.picked)
	if left.size() < 2:
		return
	var gone: String = left.pick_random()
	job.items.erase(gone)
	job.pay -= float(app(job.app).per_item)
	Game.notify("%s is out of stock. %s: \"No worries, just skip it.\"" % [gone, job.customer_name], "warn")


func _refresh_gps() -> void:
	if main != null and main.has_method("refresh_gps"):
		main.refresh_gps()


# --- Star rating: tiers, warnings, deactivation ---------------------------------------

## [min rating, name, color, description] for the app's current rating.
func tier(id: String) -> Array:
	return _tier_for(ratings[id])


func _check_standing(id: String, before: float) -> void:
	var a := app(id)
	var r: float = ratings[id]
	if r < CustomerData.DEACTIVATE_BELOW:
		if deactivated.has(id):
			return
		deactivated[id] = Game.day + CustomerData.REACTIVATION_WAIT_DAYS
		online[id] = false
		offers = offers.filter(func(o): return o.app != id)
		Game.notify("%s DEACTIVATED your account. Your rating fell to %.2f. You can appeal on Day %d." % [a.name, r, deactivated[id]], "bad")
		offers_changed.emit()
		return
	if r < CustomerData.WARN_BELOW and before >= CustomerData.WARN_BELOW:
		Game.notify("%s: your rating is %.2f. Drop below %.2f and you'll be deactivated." % [a.name, r, CustomerData.DEACTIVATE_BELOW], "bad")
		return
	var t_before: String = _tier_for(before)[1]
	var t_now: String = tier(id)[1]
	if t_now != t_before:
		var up := r > before
		Game.notify("%s: you %s %s (%.2f★). %s" % [a.name, "reached" if up else "dropped to", t_now, r, tier(id)[3]], "good" if up else "warn")


func _tier_for(r: float) -> Array:
	for t in CustomerData.TIERS:
		if r >= t[0]:
			return t
	return CustomerData.TIERS.back()


func can_appeal(id: String) -> bool:
	return deactivated.has(id) and Game.day >= int(deactivated[id])


func reactivation_text(id: String) -> String:
	if not deactivated.has(id):
		return ""
	if can_appeal(id):
		return "Take the Driver Quality Course ($%.0f) in the app to get back on." % CustomerData.REACTIVATION_FEE
	return "You can appeal on Day %d." % int(deactivated[id])


## Pays for the course (a long, boring video) and reactivates the account.
func appeal(id: String) -> bool:
	if not can_appeal(id):
		return false
	if not Game.spend(CustomerData.REACTIVATION_FEE, "%s Driver Quality Course" % app(id).name):
		return false
	deactivated.erase(id)
	ratings[id] = maxf(ratings[id], CustomerData.REACTIVATED_RATING)
	recent[id] = []
	Game.advance(40.0)
	Game.notify("You sat through the %s Driver Quality Course (40 minutes of \"Smile more!\"). You're back on at %.2f★." % [app(id).name, ratings[id]], "good")
	offers_changed.emit()
	return true


func save_state() -> Dictionary:
	return {"recent": recent, "deactivated": deactivated}


func load_state(data: Dictionary) -> void:
	deactivated = {}
	for id in recent:
		recent[id] = []
	var rec: Dictionary = data.get("recent", {})
	for k in rec:
		if recent.has(k):
			recent[k] = rec[k].map(func(x): return int(x))
	var de: Dictionary = data.get("deactivated", {})
	for k in de:
		deactivated[k] = int(de[k])
