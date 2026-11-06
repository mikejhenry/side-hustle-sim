class_name Transit
extends Node3D
## Getting around without your car: Hail Yeah Cab (a taxi you call from the phone, anywhere
## to anywhere) and DART Last State buses (cheap, but only between bus stops and only
## while the buses run). Both skip the trip: the screen fades, the clock moves on by the
## trip time, and you're there. Your car stays where you left it.

var town: Node = null
var main: Node = null
## [{name, pos (on the sidewalk by the sign), kind = "bus"}]
var stops: Array = []

## Where the bus stops are: [block column, horizontal street index, on the street's north side].
## Spread over the town so one is a short walk from most places.
const STOP_PLAN := [
	[1, 2, true],    # 4th St, by Dottie's Boarding House
	[3, 2, false],   # 4th St, east side
	[0, 0, false],   # Route 202, west
	[2, 0, false],   # Route 202, Brandywine Apartments
	[2, 3, false],   # Pennsylvania Ave, downtown
	[4, 3, true],    # Pennsylvania Ave, east
	[1, 4, false],   # Lancaster Ave, west
	[3, 5, true],    # Route 40, south
]
const CURB_INSET := 7.6      # sign pole, meters from the road center line (pedestrians walk at 9.2)


func build() -> void:
	var B: float = town.B
	for s in STOP_PLAN:
		var bx: int = s[0]
		var kz: int = s[1]
		var north: bool = s[2]
		var x: float = bx * B + 10.0 + town.SLOT_W
		var z: float = kz * B + (-CURB_INSET if north else CURB_INSET)
		var pole := Vector3(x, 0, z)
		_stop_sign(pole, north)
		var stop_name := "%s at %s" % [town.H_STREETS[kz], town.V_STREETS[bx]]
		# Stand on the sidewalk next to the sign, away from the road.
		var wait := pole + Vector3(1.2, 0, (-1.0 if north else 1.0))
		var stop := {"name": "Bus stop: " + stop_name, "short": stop_name, "pos": wait, "kind": "bus"}
		stops.append(stop)
		Kit.interactable(self, pole + Vector3(0, 1, 0), 3.0,
			func(): return "Take the %s bus" % GameData.BUS_NAME if not main.is_driving() else "",
			func(): bus_menu(stop))


func _stop_sign(at: Vector3, north: bool) -> void:
	var s := Node3D.new()
	s.position = at
	# The sign faces along the street so you can read it from the sidewalk.
	s.rotation.y = PI / 2.0
	add_child(s)
	Kit.cylinder(s, 0.05, 2.8, Vector3(0, 1.4, 0), Color(0.55, 0.57, 0.6))
	Kit.box(s, Vector3(0.62, 0.62, 0.05), Vector3(0, 2.55, 0), Color(0.85, 0.35, 0.6), false)
	Kit.label(s, "BUS", Vector3(0, 2.62, 0.04), 40)
	var back := Kit.label(s, "BUS", Vector3(0, 2.62, -0.04), 40)
	back.rotation.y = PI
	Kit.label(s, GameData.BUS_NAME, Vector3(0, 2.38, 0.04), 18)
	# A bench by the curb next to the sign, out of the walkers' path (they keep to the
	# property side of the sidewalk).
	var bench := Vector3(at.x - 2.2, 0.12, at.z)
	Kit.prop(self, "modular_street_seating", bench, 0.0 if north else PI, "", 0.9, "", 80.0)


# --- Rules ---------------------------------------------------------------------------

## Why you can't take a taxi or bus right now ("" when you can).
func blocked_reason() -> String:
	if main.is_driving():
		return "Park and get out of your car first."
	if not Gigs.job.is_empty():
		return "Finish your current job first."
	if main.tutorial and main.tutorial.active:
		return "Finish or skip the tutorial first."
	if Game.sleeping:
		return "You're asleep."
	return ""


## Rough road distance in meters (the streets are a grid, so it's the blocks you go around).
func road_meters(from: Vector3, to: Vector3) -> float:
	return (absf(to.x - from.x) + absf(to.z - from.z)) * 1.1


func taxi_quote(to: Vector3) -> Dictionary:
	var m := road_meters(main.actor_position(), to)
	var miles := m / GameData.METERS_PER_MILE
	var fare := GameData.TAXI_BASE + GameData.TAXI_PER_MILE * miles
	var h := Game.hour()
	var night := h >= 23 or h < 5
	if night:
		fare *= GameData.TAXI_NIGHT_MULT
	var mins := GameData.TAXI_WAIT + m / GameData.TAXI_METERS_PER_MIN
	return {"fare": snappedf(fare, 0.01), "minutes": ceilf(mins), "miles": miles, "night": night}


## Minutes until the next bus leaves (-1 when buses aren't running, midnight to 5 AM).
func bus_wait() -> float:
	var m := Game.minute
	if m < GameData.BUS_FIRST_HOUR * 60.0:
		return -1.0
	var next := ceilf(m / GameData.BUS_EVERY) * GameData.BUS_EVERY
	if next >= 1440.0:
		return -1.0
	return next - m


func bus_quote(from: Dictionary, to: Dictionary) -> Dictionary:
	var wait := bus_wait()
	var ride := 2.0 + road_meters(from.pos, to.pos) / GameData.BUS_METERS_PER_MIN
	return {"fare": GameData.BUS_FARE, "wait": wait, "minutes": ceilf(maxf(wait, 0.0) + ride)}


func nearest_stop(p: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for s in stops:
		var d: float = p.distance_to(s.pos)
		if d < best_d:
			best_d = d
			best = s
	return best


func at_stop() -> Dictionary:
	var s := nearest_stop(main.actor_position())
	if s.is_empty() or main.actor_position().distance_to(s.pos) > GameData.BUS_STOP_RADIUS:
		return {}
	return s


## Where you get dropped off for a map place: on the sidewalk in front of its door.
func drop_point(place: Dictionary) -> Vector3:
	if place.has("drop"):
		var dp: Vector3 = place.drop
		return Vector3(dp.x, maxf(dp.y, 0.0) + 0.6, dp.z)
	var p: Vector3 = place.get("pos", place.get("door", Vector3.ZERO))
	if place.has("curb") and place.has("door"):
		var out: Vector3 = place.curb - place.door
		out.y = 0.0
		if out.length() > 0.1:
			p = place.door + out.normalized() * 1.8
	return Vector3(p.x, maxf(p.y, 0.0) + 0.6, p.z)


# --- Riding --------------------------------------------------------------------------

func ride_taxi(to: Vector3, label: String) -> bool:
	var why := blocked_reason()
	if why != "":
		main.hud.toast(why, "warn")
		return false
	if not Game.phone_service or Game.phone_battery <= 0.0:
		main.hud.toast("You need a working phone to call a cab.", "warn")
		return false
	var q := taxi_quote(to)
	if not Game.spend(q.fare, "%s to %s" % [GameData.TAXI_NAME, label]):
		return false
	Game.stats["taxi_rides"] = int(Game.stats.get("taxi_rides", 0)) + 1
	main.travel(to, q.minutes, "%s to %s\n%d minutes" % [GameData.TAXI_NAME, label, q.minutes],
		"You got out at %s. That took %d minutes." % [label, q.minutes])
	return true


func ride_bus(from: Dictionary, to: Dictionary) -> bool:
	var why := blocked_reason()
	if why != "":
		main.hud.toast(why, "warn")
		return false
	var q := bus_quote(from, to)
	if q.wait < 0.0:
		main.hud.toast("The buses stop at midnight and start again at %d AM." % GameData.BUS_FIRST_HOUR, "warn")
		return false
	if not Game.spend(q.fare, "%s bus" % GameData.BUS_NAME):
		return false
	Game.stats["bus_rides"] = int(Game.stats.get("bus_rides", 0)) + 1
	main.travel(to.pos + Vector3(0, 0.6, 0), q.minutes, "%s to %s\n%d minutes" % [GameData.BUS_NAME, to.short, q.minutes],
		"The bus dropped you at %s. That took %d minutes." % [to.short, q.minutes])
	return true


func bus_menu(from: Dictionary) -> void:
	var why := blocked_reason()
	var wait := bus_wait()
	var title := "%s bus, $%.2f. " % [GameData.BUS_NAME, GameData.BUS_FARE]
	if why != "":
		title += why
	elif wait < 0.0:
		title += "No buses until %d AM." % GameData.BUS_FIRST_HOUR
	else:
		title += "Next bus in %d min. Where to?" % int(wait)
	var opts: Array = []
	var here: Vector3 = from.pos
	var others := stops.filter(func(s): return s != from)
	others.sort_custom(func(a, b): return here.distance_to(a.pos) < here.distance_to(b.pos))
	for s in others:
		var to: Dictionary = s
		var q := bus_quote(from, to)
		opts.append({"text": "%s   (%d min)" % [to.short, q.minutes], "cb": func(): ride_bus(from, to),
			"disabled": why != "" or wait < 0.0 or Game.money < GameData.BUS_FARE})
	main.hud.show_menu(title, opts)
