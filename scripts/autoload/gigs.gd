extends Node
## Gig economy (autoload "Gigs"): which apps are online, incoming offers, the active job.
##
## Job flow by kind:
##   ride:    to_pickup -> (phone: Start Trip) -> to_dropoff -> (phone: Complete Trip)
##   food:    to_restaurant -> (counter: pick up) -> to_customer -> (door) -> confirm_photo -> (phone)
##   grocery: to_store -> shopping (shelves) -> checkout (register) -> to_customer -> (door) -> confirm_photo
##   flex:    to_station -> (phone: Scan packages at loading zone) -> delivering (doors) -> done
##
## Multi-apping: you can run up to GameData.MAX_JOBS jobs at once, one per app and only one
## passenger at a time. Each app has at most one job, and each kind of job belongs to one app
## at a time, so job_for(kind) finds the job a world object (counter, shelf, door) is about.
## `job` is the one the GPS and HUD follow; switch it with focus().

signal offers_changed
signal job_changed
signal offer_received(offer: Dictionary)

var online := {}
var offers: Array = []
var jobs: Array = []            # every active job
var job: Dictionary = {}        # the focused job (one of `jobs`), or {}
var ratings := {}
var town: Node = null      # set by main: provides addresses, restaurants, stores, station
var main: Node = null      # set by main: provides actor position / driving state

var _accum := 0.0
var _next_id := 100
var _flex_blocks_seen := {}
var _heat_cells := {}           # Vector2i -> {"res", "food", "shop", "center"}
var _heat_cache := {}           # "app-day-hour" -> {Vector2i: 0..1}
var _events := {}               # "app-day" -> hot event dictionary


func _ready() -> void:
	for id in GameData.APPS:
		online[id] = false
		ratings[id] = 4.85
	Game.minutes_advanced.connect(_on_minutes)
	Game.bladder_accident.connect(_on_bladder_accident)


func reset_jobs() -> void:
	offers.clear()
	jobs.clear()
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

## Demand multiplier for an app at hour `h` (0-23) on weekday `wd` (0 = Mon). Defaults to now.
func surge(id: String, h := -1, wd := -1) -> float:
	if h < 0:
		h = Game.hour()
	if wd < 0:
		wd = (Game.day - 1) % 7
	var day_mult: float = GameData.DAY_DEMAND.get(app(id).kind, [1, 1, 1, 1, 1, 1, 1])[wd]
	for p in app(id).peaks:
		if h >= p[0] and h < p[1]:
			return p[2] * day_mult
	return day_mult


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
	_check_job_time(now)
	if town != null and jobs.size() < GameData.MAX_JOBS:
		var busy_mult := 1.0 if jobs.is_empty() else GameData.BUSY_OFFER_MULT
		for id in GameData.APP_ORDER:
			if not online[id] or app(id).kind == "flex" or _has_offer(id) or not job_for_app(id).is_empty():
				continue
			if app(id).kind == "ride" and not job_for("ride").is_empty():
				continue
			var rating_mult := clampf(ratings[id] - 3.9, 0.2, 1.0)
			if randf() < GameData.BASE_OFFER_CHANCE * surge(id) * Game.weather_boost(app(id).kind) * rating_mult * busy_mult:
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
			var p: Dictionary = _pick_hot(id, town.addresses + town.restaurants + town.stores)
			var d: Dictionary = _pick_far(p, town.addresses + town.restaurants + town.stores)
			var trip := _miles(p.curb, d.curb)
			var zone := zone_mult(heat_at(id, p.curb))
			o.pickup = p
			o.dropoff = d
			o.passenger = GameData.FIRST_NAMES.pick_random()
			o.miles = trip
			o.pickup_miles = _miles(me, p.curb)
			o.pay = (a.base + a.per_mile * trip) * s * wb * zone * Game.car().comfort
			o.weather_pay = (a.base + a.per_mile * trip) * s * (wb - 1.0) * Game.car().comfort
			o.zone_pay = snappedf((a.base + a.per_mile * trip) * s * wb * (zone - 1.0) * Game.car().comfort, 0.01)
			o.tip = 0.0
			o.deadline = now + 25.0 + (o.pickup_miles + trip) * 8.0
		"food":
			var r: Dictionary = _pick_hot(id, town.restaurants)
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
			o.zone_pay = snappedf((a.base + a.per_mile * miles) * (zone_mult(heat_at(id, r.curb)) - 1.0), 0.01)
			o.pay = a.base + a.per_mile * miles + o.peak_pay + o.weather_pay + o.zone_pay + o.tip
			o.deadline = now + 35.0 + miles * 9.0
		"grocery":
			# Grocery demand comes from where customers live, so the heat follows them.
			var st: Dictionary = town.stores.pick_random()
			var c: Dictionary = _pick_hot(id, town.addresses.filter(func(x): return _miles(x.curb, st.curb) > 0.8))
			if c.is_empty():
				c = _pick_far(st, town.addresses)
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
			o.zone_pay = snappedf((a.base + a.per_mile * miles) * (zone_mult(heat_at(id, c.curb)) - 1.0), 0.01)
			o.pay = a.base + a.per_item * items.size() + a.per_mile * miles + o.peak_pay + o.weather_pay + o.zone_pay + o.tip
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


# --- Hot zones (heatmaps) -------------------------------------------------------------

func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GameData.HEAT_CELL), floori(p.z / GameData.HEAT_CELL))


## Every map square with somewhere to pick up or deliver, and what's in it.
func heat_cells() -> Dictionary:
	if _heat_cells.is_empty() and town != null:
		for group in [["res", town.addresses], ["food", town.restaurants], ["shop", town.stores]]:
			for place in group[1]:
				var k := _cell_of(place.curb)
				if not _heat_cells.has(k):
					_heat_cells[k] = {"res": 0, "food": 0, "shop": 0, "names": []}
				_heat_cells[k][group[0]] += 1
				if group[0] != "res":
					_heat_cells[k].names.append(place.name)
	return _heat_cells


## World rectangle (x, z) a map square covers.
func cell_rect(cell: Vector2i) -> Rect2:
	var s: float = GameData.HEAT_CELL
	return Rect2(cell.x * s, cell.y * s, s, s)


## How busy each square is for an app at hour `h` today, 0 (quiet) to 1 (hottest).
func heat_map(id: String, h := -1) -> Dictionary:
	if h < 0:
		h = Game.hour()
	var day := Game.day + floori(h / 24.0)
	h = h % 24
	var key := "%s-%d-%d" % [id, day, h]
	if _heat_cache.has(key):
		return _heat_cache[key]
	if _heat_cache.size() > 400:
		_heat_cache.clear()
	var kind: String = app(id).kind
	var raw := {}
	var top := 0.001
	for k in heat_cells():
		var c: Dictionary = _heat_cells[k]
		var v := 0.0
		match kind:
			"ride":
				# Mornings start in the neighborhoods, evenings and nights at restaurants and shops.
				if h >= 6 and h < 10:
					v = c.res * 1.0 + (c.food + c.shop) * 0.6
				elif h >= 16 and h < 21:
					v = c.res * 0.35 + (c.food + c.shop) * 1.6
				elif h >= 21 or h < 3:
					v = c.res * 0.15 + c.food * 2.0
				else:
					v = c.res * 0.5 + (c.food + c.shop) * 0.8
			"food":
				v = c.food * 1.0 + c.res * 0.04
			"grocery":
				# Weekend mornings and weekday evenings, mostly from the neighborhoods.
				v = c.res * 1.0 + c.shop * 1.5
		raw[k] = v
		top = maxf(top, v)
	var out := {}
	var ev := hot_event(id, day)
	for k in raw:
		var v: float = pow(raw[k] / top, 0.8)
		if not ev.is_empty() and k == ev.cell and h >= ev.start and h < ev.end:
			v = minf(1.0, v + 0.7)
		out[k] = v
	_heat_cache[key] = out
	return out


func heat_at(id: String, pos: Vector3, h := -1) -> float:
	if app(id).kind == "flex" or town == null:
		return 0.0
	return heat_map(id, h).get(_cell_of(pos), 0.0)


## Hot zone pay multiplier for a square's heat.
func zone_mult(heat: float) -> float:
	return 1.0 + maxf(0.0, heat - GameData.HOT_ZONE_FLOOR) * GameData.HOT_ZONE_PAY


## A daily event that makes one square hot for a few hours: {cell, start, end, label}.
func hot_event(id: String, day := -1) -> Dictionary:
	if day < 0:
		day = Game.day
	if app(id).kind == "flex" or town == null:
		return {}
	var key := "%s-%d" % [id, day]
	if _events.has(key):
		return _events[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var cells := heat_cells().keys().filter(func(k): return not _heat_cells[k].names.is_empty())
	var ev := {}
	if not cells.is_empty() and rng.randf() < 0.8:
		cells.sort()
		var cell: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var start := rng.randi_range(10, 20)
		ev = {"cell": cell, "start": start, "end": start + 3,
			"label": "%s near %s" % [GameData.HOT_EVENTS[rng.randi_range(0, GameData.HOT_EVENTS.size() - 1)],
				_heat_cells[cell].names[0]]}
	_events[key] = ev
	return ev


## The hottest square for an app at hour `h`, as {cell, heat, label}.
func hottest(id: String, h := -1) -> Dictionary:
	var best := {}
	var m := heat_map(id, h)
	for k in m:
		if best.is_empty() or m[k] > best.heat:
			best = {"cell": k, "heat": m[k]}
	if best.is_empty():
		return {}
	var names: Array = _heat_cells[best.cell].names
	best.label = ("around " + names[0]) if not names.is_empty() else "in the neighborhoods"
	return best


## Picks a place, favoring hot squares.
func _pick_hot(id: String, pool: Array) -> Dictionary:
	if pool.is_empty():
		return {}
	var total := 0.0
	var weights := []
	for p in pool:
		var w := 0.2 + heat_at(id, p.curb)
		weights.append(w)
		total += w
	var r := randf() * total
	for i in pool.size():
		r -= weights[i]
		if r <= 0.0:
			return pool[i]
	return pool.back()


# --- Accepting / declining ----------------------------------------------------------

func find_offer(offer_id: int) -> Dictionary:
	for o in offers:
		if o.id == offer_id:
			return o
	return {}


func job_for_app(id: String) -> Dictionary:
	for j in jobs:
		if j.app == id:
			return j
	return {}


## The active job of a kind ("ride", "food", "grocery", "flex"). There's at most one.
func job_for(kind: String) -> Dictionary:
	for j in jobs:
		if j.kind == kind:
			return j
	return {}


## Why you can't take this offer right now, or "" if you can.
func accept_block_reason(o: Dictionary) -> String:
	if not job_for_app(o.app).is_empty():
		return "Finish your current %s job first." % app(o.app).name
	if o.kind == "ride" and not job_for("ride").is_empty():
		return "You already have a passenger. One rider at a time."
	if jobs.size() >= GameData.MAX_JOBS:
		return "You're juggling %d jobs already. That's the limit." % jobs.size()
	return ""


## Point the GPS and HUD at this app's job.
func focus(id: String) -> void:
	var j := job_for_app(id)
	if j.is_empty() or is_same(j, job):
		return
	job = j
	job_changed.emit()


func accept(offer_id: int) -> void:
	var o := find_offer(offer_id)
	if o.is_empty():
		return
	var reason := accept_block_reason(o)
	if reason != "":
		Game.notify(reason, "warn")
		return
	offers.erase(o)
	var j: Dictionary = o.duplicate()
	j.crashes = 0
	match j.kind:
		"ride":
			j.stage = "to_pickup"
			Game.notify("%s ride accepted. Pick up %s." % [app(j.app).name, j.passenger], "good")
		"food":
			j.stage = "to_restaurant"
			Game.notify("Order #%d accepted. Head to %s." % [j.order_no, j.restaurant.name], "good")
		"grocery":
			j.stage = "to_store"
			j.picked = []
			Game.notify("Shopping order accepted. Head to %s." % j.store.name, "good")
		"flex":
			j.stage = "to_station"
			j.stops = _flex_stops(j.packages)
			j.delivered = 0
			Game.notify("Block reserved! Be at the Jungle Flex station by %s." % Game.abs_time_string(j.start), "good")
	jobs.append(j)
	if job.is_empty():
		job = j
	elif jobs.size() > 1:
		Game.notify("Juggling %d jobs. Your GPS stays on %s: switch in the phone." % [jobs.size(), app(job.app).name], "info")
	offers_changed.emit()
	job_changed.emit()


func decline(offer_id: int) -> void:
	var o := find_offer(offer_id)
	if o.is_empty():
		return
	offers.erase(o)
	offers_changed.emit()


## Cancels the focused job, or this app's job.
func cancel_job(id := "") -> void:
	var j := job if id == "" else job_for_app(id)
	if j.is_empty():
		return
	_rate(j.app, 3.0)
	Game.notify("You cancelled the %s job. Your rating took a hit." % app(j.app).name, "bad")
	_finish(j)


## Drops a job from the active list and refocuses on the next one.
func _finish(j: Dictionary) -> void:
	jobs.erase(j)
	if is_same(job, j) or not jobs.any(func(x): return is_same(x, job)):
		job = jobs[0] if not jobs.is_empty() else {}
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

## Where the focused job wants you next.
func target() -> Dictionary:
	return target_for(job)


func target_for(j: Dictionary) -> Dictionary:
	if j.is_empty():
		return {}
	match j.kind:
		"ride":
			if j.stage == "to_pickup":
				return {"pos": j.pickup.curb, "label": "Pick up " + j.passenger}
			return {"pos": j.dropoff.curb, "label": "Drop off at " + j.dropoff.name}
		"food":
			if j.stage == "to_restaurant":
				return {"pos": j.restaurant.door, "label": "Pick up at " + j.restaurant.name}
			if j.stage in ["to_customer", "confirm_photo"]:
				return {"pos": j.customer.door, "label": "Deliver to " + j.customer.name}
		"grocery":
			if j.stage in ["to_store", "shopping", "checkout"]:
				return {"pos": j.store.door, "label": "Shop at " + j.store.name}
			if j.stage in ["to_customer", "confirm_photo"]:
				return {"pos": j.customer.door, "label": "Deliver to " + j.customer.name}
		"flex":
			if j.stage == "to_station":
				return {"pos": town.station.door, "label": "Jungle Flex station"}
			if j.stage == "delivering" and not j.get("photo_due", {}).is_empty():
				return {"pos": j.photo_due.door, "label": "Photo at " + j.photo_due.name}
			if j.stage == "delivering" and not j.stops.is_empty():
				var me := _actor_pos()
				var best: Dictionary = j.stops[0]
				for s in j.stops:
					if s.door.distance_to(me) < best.door.distance_to(me):
						best = s
				return {"pos": best.door, "label": "Package to " + best.name}
	return {}


## What to do next on the focused job.
func status_text() -> String:
	return status_for(job)


func status_for(j: Dictionary) -> String:
	if j.is_empty():
		return ""
	var a := app(j.app)
	var t := ""
	match j.stage:
		"to_pickup": t = "Drive to %s to pick up %s, then tap Start Trip." % [j.pickup.name, j.passenger]
		"to_dropoff": t = "Take %s to %s, then tap Complete Trip." % [j.passenger, j.dropoff.name]
		"to_restaurant": t = "Go inside %s and pick up order #%d at the counter." % [j.restaurant.name, j.order_no]
		"to_customer":
			t = "Bring the order to %s's door at %s." % [j.customer_name, j.customer.name]
			if j.customer.has("floor"):
				t += " It's on floor %d: take the stairs or the elevator." % j.customer.floor
		"confirm_photo": t = "Open your phone and take the drop-off photo."
		"to_store": t = "Go to %s and start shopping." % j.store.name
		"shopping": t = "Grab items from the shelves (%d/%d). List is in the app." % [j.picked.size(), j.items.size()]
		"checkout": t = "Check out at the register."
		"to_station":
			if Game.total_minutes() < j.start - 30.0:
				t = "Block starts %s. Scanning opens 30 min before." % Game.abs_time_string(j.start)
			else:
				t = "Drive into the Jungle Flex station and scan your packages in the app."
		"delivering":
			if not j.get("photo_due", {}).is_empty():
				t = "Open your phone and take the drop-off photo."
			else:
				t = "Deliver packages: %d left. Ends %s." % [j.stops.size(), Game.abs_time_string(j.end)]
	return "%s: %s" % [a.name, t]


## Minutes until a job is due (negative once it's late).
func minutes_left(j: Dictionary) -> int:
	return int(floorf(j.get("deadline", 0.0) - Game.total_minutes()))


## One line about the jobs you're juggling besides the focused one, for the HUD.
func others_text() -> String:
	var parts := []
	for j in jobs:
		if is_same(j, job):
			continue
		var left := minutes_left(j)
		parts.append("%s %s" % [app(j.app).name, ("due in %d min" % left) if left >= 0 else ("LATE %d min" % -left)])
	return "" if parts.is_empty() else "Also running: " + ", ".join(parts)


func near(pos: Vector3, radius: float) -> bool:
	return main != null and main.actor_position().distance_to(pos) < radius


func can_start_trip() -> bool:
	var j := job_for("ride")
	return j.get("stage", "") == "to_pickup" and main.is_driving() and main.car_speed() < 3.0 \
		and near(j.pickup.curb, 16.0)


func start_trip() -> void:
	if not can_start_trip():
		return
	var j := job_for("ride")
	j.stage = "to_dropoff"
	j.crashes = 0
	Game.notify("%s hopped in. \"Hey! Can you turn the music up?\"" % j.passenger, "info")
	job_changed.emit()


func can_end_trip() -> bool:
	var j := job_for("ride")
	return j.get("stage", "") == "to_dropoff" and main.is_driving() and main.car_speed() < 3.0 \
		and near(j.dropoff.curb, 16.0)


func end_trip() -> void:
	if not can_end_trip():
		return
	var j := job_for("ride")
	var stars: float = 5.0 - j.crashes * 1.0
	if Game.car().comfort < 0.9:
		stars -= 0.5
	if Game.total_minutes() > j.deadline:
		stars -= 1.0
	stars = clampf(stars, 1.0, 5.0)
	var tip := 0.0
	if stars >= 4.5 and randf() < 0.45:
		tip = float(randi_range(1, 6))
	_complete(j, stars, tip, "%s rated you %d stars." % [j.passenger, int(stars)])


func pick_up_food() -> void:
	var j := job_for("food")
	if j.get("stage", "") != "to_restaurant":
		return
	j.stage = "to_customer"
	Game.notify("Picked up order #%d. Don't eat the fries." % j.order_no, "good")
	job_changed.emit()


func grab_item(item: String) -> void:
	var j := job_for("grocery")
	if not j.get("stage", "") in ["to_store", "shopping"]:
		return
	j.stage = "shopping"
	j.picked.append(item)
	Game.notify("Grabbed %s (%d/%d)" % [item, j.picked.size(), j.items.size()], "info")
	if j.picked.size() >= j.items.size():
		j.stage = "checkout"
		Game.notify("All items found. Head to the register.", "good")
	job_changed.emit()


func begin_shopping() -> void:
	var j := job_for("grocery")
	if j.is_empty():
		return
	j.stage = "shopping"
	job_changed.emit()


func checkout() -> void:
	var j := job_for("grocery")
	if j.get("stage", "") != "checkout":
		return
	j.stage = "to_customer"
	Game.notify("Checked out with the Instacrate card. Now deliver it.", "good")
	job_changed.emit()


## The food or grocery job being delivered to this address, if any.
func _delivery_to(addr_name: String) -> Dictionary:
	for j in jobs:
		if j.kind in ["food", "grocery"] and j.stage == "to_customer" and j.customer.name == addr_name:
			return j
	return {}


func leave_at_door(addr_name := "") -> void:
	var j := _delivery_to(addr_name) if addr_name != "" else job
	if j.is_empty() or j.get("stage", "") != "to_customer":
		return
	j.stage = "confirm_photo"
	Game.notify("Order left at the door. Take the drop-off photo in the app.", "info")
	job_changed.emit()


## Drop-off photo for a food or grocery order. Pass the app, or it uses the first one waiting.
func confirm_photo(id := "") -> void:
	var j := job_for_app(id) if id != "" else _photo_job()
	if j.get("stage", "") != "confirm_photo" or not can_take_photo(j.app):
		return
	var late: bool = Game.total_minutes() > j.deadline
	var stars := 4.0 if late else 5.0
	stars -= j.crashes * 0.5
	var tip_note := ""
	if late:
		j.pay -= j.tip * 0.5
		tip_note = " You were late, so the customer cut the tip."
	_complete(j, stars, 0.0, "Delivered!" + tip_note)


func _photo_job() -> Dictionary:
	if job.get("stage", "") == "confirm_photo":
		return job
	for j in jobs:
		if j.stage == "confirm_photo":
			return j
	return {}


func can_scan() -> bool:
	var j := job_for("flex")
	return j.get("stage", "") == "to_station" and Game.total_minutes() >= j.start - 30.0 \
		and near(town.station.load_point, 18.0)


func scan_packages() -> void:
	if not can_scan():
		return
	var j := job_for("flex")
	j.stage = "delivering"
	Game.notify("Scanned and loaded %d packages. Route is in the app." % j.stops.size(), "good")
	job_changed.emit()


## Leaves a Jungle Flex package at the door. Like the other apps, it only counts once you
## take the drop-off photo in the app.
func deliver_package(addr_name: String) -> void:
	var j := job_for("flex")
	if j.is_empty() or j.get("photo_due", {}).size() > 0:
		return
	for s in j.stops:
		if s.name == addr_name:
			j.photo_due = s
			break
	Game.notify("Package left at %s. Take the drop-off photo in the app." % addr_name, "info")
	job_changed.emit()


## Drop-off photo for a Jungle Flex package. You have to be near the door.
func confirm_package_photo() -> void:
	var j := job_for("flex")
	var s: Dictionary = j.get("photo_due", {})
	if s.is_empty() or not can_take_photo("jungleflex"):
		return
	j.photo_due = {}
	j.stops.erase(s)
	j.delivered += 1
	Game.notify("Photo sent. Package delivered to %s." % s.name, "good")
	if j.stops.is_empty():
		var stars := 5.0 if Game.total_minutes() <= j.end else 4.0
		_complete(j, stars, 0.0, "Block complete!")
	else:
		job_changed.emit()


## Drop-off photos are taken at the door (within a few steps of it).
func can_take_photo(id := "") -> bool:
	var j := job_for_app(id) if id != "" else _photo_job()
	if j.is_empty():
		j = job_for("flex")
	if j.is_empty():
		return false
	if j.get("stage", "") == "confirm_photo":
		return near(j.customer.door, 8.0)
	var s: Dictionary = j.get("photo_due", {})
	return not s.is_empty() and near(s.door, 8.0)


func door_prompt(addr: Dictionary) -> String:
	var d := _delivery_to(addr.name)
	if not d.is_empty():
		return "Leave %s order at the door" % app(d.app).name
	var f := job_for("flex")
	if f.get("stage", "") == "delivering" and f.get("photo_due", {}).is_empty():
		for s in f.stops:
			if s.name == addr.name:
				return "Deliver Jungle Flex package"
	return ""


func door_action(addr: Dictionary) -> void:
	if not _delivery_to(addr.name).is_empty():
		leave_at_door(addr.name)
	else:
		deliver_package(addr.name)


## Late fee taken off a payout: a flat fee plus a bit per minute, capped.
func late_fee(j: Dictionary, pay: float) -> float:
	var late: float = Game.total_minutes() - j.get("deadline", INF)
	if late <= 0.0:
		return 0.0
	return snappedf(minf(pay * GameData.LATE_FEE_MAX, GameData.LATE_FEE_BASE + late * GameData.LATE_FEE_PER_MIN), 0.01)


func _complete(j: Dictionary, stars: float, extra_tip: float, msg: String) -> void:
	var a := app(j.app)
	var pay: float = j.pay + extra_tip
	var fee := late_fee(j, pay)
	pay -= fee
	if fee > 0.0:
		msg += " Late fee -$%.2f." % fee
		Game.stats["late"] = int(Game.stats.get("late", 0)) + 1
	Game.earn(pay, "%s payout" % a.name)
	Game.stats.jobs += 1
	_rate(j.app, stars)
	Game.notify("%s +$%.2f. %s" % [a.name, pay, msg], "money")
	_finish(j)


func _rate(id: String, stars: float) -> void:
	ratings[id] = clampf(lerpf(ratings[id], stars, 0.12), 1.0, 5.0)


func _check_job_time(now: float) -> void:
	for j in jobs.duplicate():
		_check_one(j, now)


func _check_one(j: Dictionary, now: float) -> void:
	if j.kind == "flex":
		if j.stage == "to_station" and now > j.start + 30.0:
			_rate("jungleflex", 2.0)
			Game.notify("You missed your Jungle Flex block. Rating hit.", "bad")
			_finish(j)
		elif j.stage == "delivering" and now > j.end + 60.0:
			var frac := float(j.delivered) / float(j.packages)
			var pay: float = snappedf(j.pay * frac, 0.01)
			Game.earn(pay, "Jungle Flex partial block")
			_rate("jungleflex", 3.0)
			Game.notify("Block ended. Undelivered packages returned. Paid $%.2f." % pay, "warn")
			_finish(j)
		return
	if now > j.deadline + 75.0:
		_rate(j.app, 1.5)
		Game.notify("%s: you took too long and the job was reassigned." % app(j.app).name, "bad")
		_finish(j)
		return
	# Heads-ups, so a job you're not focused on doesn't sneak up on you.
	if jobs.size() > 1 and not j.get("warned", false) and now > j.deadline - GameData.LATE_WARNING_MIN:
		j.warned = true
		Game.notify("%s: due in %d min!" % [app(j.app).name, maxi(0, int(j.deadline - now))], "warn")
	if not j.get("late_noted", false) and now > j.deadline:
		j.late_noted = true
		Game.notify("%s is late. A late fee is adding up." % app(j.app).name, "bad")


func on_crash(strength: float) -> void:
	for j in jobs:
		if j.kind == "ride" and j.stage == "to_dropoff":
			j.crashes += 1
			Game.notify("%s: \"WHOA! Are you trying to kill me?!\"" % j.passenger, "bad")
		elif j.kind in ["food", "grocery"] and j.stage == "to_customer" and strength > 8.0:
			j.crashes += 1
			Game.notify("You hear the %s order slide across the back seat..." % app(j.app).name, "warn")


func _on_bladder_accident() -> void:
	var j := job_for("ride")
	if j.get("stage", "") == "to_dropoff":
		j.crashes += 4
		Game.notify("%s is horrified. That's going to be one star." % j.passenger, "bad")
