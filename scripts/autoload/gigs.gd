extends Node
## Gig economy (autoload "Gigs"): which apps are online, incoming offers, the active job.
##
## Job flow by kind:
##   ride:    to_pickup -> (phone: Start Trip) -> to_dropoff -> (phone: Complete Trip)
##   food:    to_restaurant -> (counter: pick up) -> to_customer -> (door) -> confirm_photo -> (phone)
##   grocery: to_store -> shopping (shelves) -> checkout (register) -> to_customer -> (door) -> confirm_photo
##   flex:    to_station -> (phone: Scan packages at loading zone) -> delivering (doors) -> done

signal offers_changed
signal job_changed
signal offer_received(offer: Dictionary)

var online := {}
var offers: Array = []
var job: Dictionary = {}
var ratings := {}
var town: Node = null      # set by main: provides addresses, restaurants, stores, station
var main: Node = null      # set by main: provides actor position / driving state

var _accum := 0.0
var _next_id := 100
var _flex_blocks_seen := {}


func _ready() -> void:
	for id in GameData.APPS:
		online[id] = false
		ratings[id] = 4.85
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
		_check_job_time(now)
	elif town != null:
		for id in GameData.APP_ORDER:
			if not online[id] or app(id).kind == "flex" or _has_offer(id):
				continue
			var rating_mult := clampf(ratings[id] - 3.9, 0.2, 1.0)
			if randf() < GameData.BASE_OFFER_CHANCE * surge(id) * rating_mult:
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
			o.pay = (a.base + a.per_mile * trip) * s * Game.car().comfort
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
			o.pay = a.base + a.per_mile * miles + o.peak_pay + o.tip
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
			o.pay = a.base + a.per_item * items.size() + a.per_mile * miles + o.peak_pay + o.tip
			o.deadline = now + 50.0 + items.size() * 6.0 + miles * 9.0
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
			var s := surge("jungleflex", start_h)
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
	match job.kind:
		"ride":
			job.stage = "to_pickup"
			Game.notify("Yoober-style ride accepted. Pick up %s." % job.passenger, "good")
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
		"to_customer": t = "Bring the order to %s's door at %s." % [job.customer_name, job.customer.name]
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
	Game.notify("%s hopped in. \"Hey! Can you turn the music up?\"" % job.passenger, "info")
	job_changed.emit()


func can_end_trip() -> bool:
	return job.get("stage", "") == "to_dropoff" and main.is_driving() and main.car_speed() < 3.0 \
		and near(job.dropoff.curb, 16.0)


func end_trip() -> void:
	if not can_end_trip():
		return
	var stars: float = 5.0 - job.crashes * 1.0
	if Game.car().comfort < 0.9:
		stars -= 0.5
	if Game.total_minutes() > job.deadline:
		stars -= 1.0
	stars = clampf(stars, 1.0, 5.0)
	var tip := 0.0
	if stars >= 4.5 and randf() < 0.45:
		tip = float(randi_range(1, 6))
	_complete(stars, tip, "%s rated you %d stars." % [job.passenger, int(stars)])


func pick_up_food() -> void:
	job.stage = "to_customer"
	Game.notify("Picked up order #%d. Don't eat the fries." % job.order_no, "good")
	job_changed.emit()


func grab_item(item: String) -> void:
	if not job.get("stage", "") in ["to_store", "shopping"]:
		return
	job.stage = "shopping"
	job.picked.append(item)
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
	job.stage = "confirm_photo"
	Game.notify("Order left at the door. Take the drop-off photo in the app.", "info")
	job_changed.emit()


func confirm_photo() -> void:
	if job.get("stage", "") != "confirm_photo" or not can_take_photo():
		return
	var late: bool = Game.total_minutes() > job.deadline
	var stars := 4.0 if late else 5.0
	stars -= job.crashes * 0.5
	var tip_note := ""
	if late:
		job.pay -= job.tip * 0.5
		tip_note = " You were late, so the customer cut the tip."
	_complete(stars, 0.0, "Delivered!" + tip_note)


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
	ratings[id] = clampf(lerpf(ratings[id], stars, 0.12), 1.0, 5.0)


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
		Game.notify("You hear the order slide across the back seat...", "warn")


func _on_bladder_accident() -> void:
	if job.get("stage", "") == "to_dropoff":
		job.crashes += 4
		Game.notify("%s is horrified. That's going to be one star." % job.passenger, "bad")
