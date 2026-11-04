class_name Pedestrians
extends Node3D
## People with daily routines. Each person has a home (a house or apartment door), a role
## (student, office worker, shopper or warehouse worker) and a plan for the day: leave home
## in the morning, walk to work or class, go out for lunch, run errands, stroll, and head
## home in the evening. At night the streets empty out, apart from a few night owls.
##
## They walk the sidewalks and cross streets at the crosswalks: at a traffic light they wait
## for the walk phase, elsewhere they wait for a gap in traffic, and cars stop for anyone in
## the crosswalk. Arriving at a door, they go inside for a while. They're solid, so you can't
## drive through them, and hitting one in front of a cop counts as reckless driving.
##
## People far from you skip the walk and simply show up where their plan says they should
## be, so the town is right wherever you go (and after you sleep).

const COUNT := 30
const INSET := 9.2           # sidewalk path, meters from the road center line
const MODELS := ["Casual2", "Suit", "Casual", "Worker"]
const ROLES := ["student", "office", "shopper", "worker"]   # one per model, same order
const DOWNTOWN := [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(1, 3), Vector2i(2, 3)]
const CAMPUS := [Vector2i(0, 1), Vector2i(0, 2)]
const PARK := Vector2i(2, 1)
const SNAP_DIST := 200.0     # people farther than this from you skip walking to a new activity

var town: Node = null
var main: Node = null
var people: Array = []
var _rng := RandomNumberGenerator.new()
var _graph := AStar3D.new()
var _homes: Array = []       # doors: {pos, walk (sidewalk point), block}
var _food: Array = []
var _shops: Array = []
var _work := {}              # role -> [door]
var _jump := 0.0             # game minutes advanced this frame (big jumps re-place everyone)


func build() -> void:
	_rng.seed = 4242
	var have := MODELS.filter(func(m): return ResourceLoader.exists("res://assets/quaternius/char_%s.fbx" % m))
	if have.is_empty():
		return
	_build_graph()
	_collect_doors()
	for i in COUNT:
		var model: String = have[i % have.size()]
		var p := Walker.new()
		p.owner_set = self
		p.index = i
		p.role = ROLES[MODELS.find(model)]
		p.night_owl = i % 6 == 5
		p.home = _homes[_rng.randi() % _homes.size()]
		p.work = _pick(_work[p.role], p.home.pos)
		p.speed = _rng.randf_range(1.2, 1.6)
		add_child(p)
		p.setup(model)
		people.append(p)
	for p in people:
		p.refresh(true)
	Game.minutes_advanced.connect(func(m): _jump += m)


func _process(_delta: float) -> void:
	if _jump > 15.0:
		for p in people:
			p.refresh(true)
	_jump = 0.0


func player_position() -> Vector3:
	return main.actor_position() if main else Vector3(1e6, 0, 1e6)


## People out in the street right now (not inside a building).
func outside_count() -> int:
	return people.filter(func(p): return p.state != "inside").size()


## Positions of people crossing a street, for traffic to stop for.
func in_road() -> Array:
	var out := []
	for p in people:
		if p.crossing:
			out.append(p.global_position)
	return out


# --- Sidewalk graph --------------------------------------------------------------------
# Every block has a sidewalk loop with four corners. Corners of neighboring blocks are
# joined by the crosswalks, so a walk between two doors is: along the sidewalk to a corner,
# corner to corner (crossing streets on the zebras), then along the last sidewalk.

func _corner_id(b: Vector2i, k: int) -> int:
	return (b.x * town.N + b.y) * 4 + k


## Corner k of block b: 0 north-west, 1 north-east, 2 south-east, 3 south-west.
func corner(b: Vector2i, k: int) -> Vector3:
	var x0: float = b.x * town.B + INSET
	var z0: float = b.y * town.B + INSET
	var x1: float = (b.x + 1) * town.B - INSET
	var z1: float = (b.y + 1) * town.B - INSET
	return [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)][k]


func _build_graph() -> void:
	var N: int = town.N
	for bx in N:
		for bz in N:
			for k in 4:
				_graph.add_point(_corner_id(Vector2i(bx, bz), k), corner(Vector2i(bx, bz), k))
	for bx in N:
		for bz in N:
			var b := Vector2i(bx, bz)
			for k in 4:
				_graph.connect_points(_corner_id(b, k), _corner_id(b, (k + 1) % 4))
			if bx + 1 < N:
				_graph.connect_points(_corner_id(b, 1), _corner_id(b + Vector2i(1, 0), 0))
				_graph.connect_points(_corner_id(b, 2), _corner_id(b + Vector2i(1, 0), 3))
			if bz + 1 < N:
				_graph.connect_points(_corner_id(b, 3), _corner_id(b + Vector2i(0, 1), 0))
				_graph.connect_points(_corner_id(b, 2), _corner_id(b + Vector2i(0, 1), 1))


func block_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(floori(p.x / town.B), 0, town.N - 1), clampi(floori(p.z / town.B), 0, town.N - 1))


## The two corner ids at the ends of the sidewalk side that `p` is on.
func _side_of(p: Vector3) -> Array:
	var b := block_of(p)
	var fx: float = p.x - b.x * town.B
	var fz: float = p.z - b.y * town.B
	var far: float = town.B - INSET
	var d := [absf(fz - INSET), absf(fx - far), absf(fz - far), absf(fx - INSET)]   # N, E, S, W
	var side := 0
	for i in 4:
		if d[i] < d[side]:
			side = i
	return [_corner_id(b, side), _corner_id(b, (side + 1) % 4)]


## Waypoints along the sidewalks from `from` to `to` (both on sidewalks):
## [{p, cross (this leg crosses a street), node (its intersection)}]
func route(from: Vector3, to: Vector3) -> Array:
	var sa := _side_of(from)
	var sb := _side_of(to)
	if sa[0] in sb and sa[1] in sb:
		return [{"p": to, "cross": false}]
	var best: PackedInt64Array
	var best_cost := INF
	for a in sa:
		for b in sb:
			var ids := _graph.get_id_path(a, b)
			var cost := from.distance_to(_graph.get_point_position(a)) + _graph.get_point_position(b).distance_to(to)
			for i in ids.size() - 1:
				cost += _graph.get_point_position(ids[i]).distance_to(_graph.get_point_position(ids[i + 1]))
			if cost < best_cost:
				best_cost = cost
				best = ids
	var out := []
	for i in best.size():
		var leg := {"p": _graph.get_point_position(best[i]), "cross": false}
		if i > 0 and best[i] / 4 != best[i - 1] / 4:
			var a: Vector3 = out[i - 1].p
			var mid: Vector3 = (a + leg.p) / 2.0
			leg.cross = true
			leg.node = Vector2i(roundi(mid.x / town.B), roundi(mid.z / town.B))
			leg.axis = "ew" if absf(leg.p.x - a.x) > absf(leg.p.z - a.z) else "ns"
		out.append(leg)
	if out.is_empty() or out.back().p.distance_to(to) > 0.2:
		out.append({"p": to, "cross": false})
	return out


# --- Places people go -----------------------------------------------------------------

func _in_grid(p: Vector3) -> bool:
	var size: float = town.N * town.B
	return p.x > 0.0 and p.z > 0.0 and p.x < size and p.z < size


## A door and the point on the sidewalk in front of it.
func _door(pos: Vector3) -> Dictionary:
	var b := block_of(pos)
	var x0: float = b.x * town.B + INSET
	var x1: float = (b.x + 1) * town.B - INSET
	var north: bool = pos.z - b.y * town.B < town.B / 2.0
	var z: float = b.y * town.B + (INSET if north else town.B - INSET)
	return {"pos": Vector3(pos.x, 0, pos.z), "walk": Vector3(clampf(pos.x, x0, x1), 0, z), "block": b}


func _collect_doors() -> void:
	for a in town.addresses:
		if not a.has("floor") and _in_grid(a.door):
			_homes.append(_door(a.door))
	var work_all := []
	var downtown := []
	var campus := []
	var industry := []
	for pl in town.places:
		if not _in_grid(pl.door):
			continue
		var d := _door(pl.door)
		match pl.kind:
			"food": _food.append(d)
			"grocery", "gas": _shops.append(d)
		if pl.kind in ["mechanic", "flex", "cars", "gas"]:
			industry.append(d)
		if d.block in DOWNTOWN:
			downtown.append(d)
		if d.block in CAMPUS:
			campus.append(d)
		work_all.append(d)
	if campus.is_empty():
		campus = _homes.filter(func(h): return h.block in CAMPUS)
	_work = {"office": downtown if not downtown.is_empty() else work_all,
		"student": campus if not campus.is_empty() else work_all,
		"shopper": _shops + _food,
		"worker": industry if not industry.is_empty() else work_all}


## One of `list`, preferring ones near `near`.
func _pick(list: Array, near: Vector3, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = _rng
	var best: Dictionary = list[rng.randi() % list.size()]
	for i in 2:
		var c: Dictionary = list[rng.randi() % list.size()]
		if c.pos.distance_to(near) < best.pos.distance_to(near):
			best = c
	return best


## Today's plan for a person: [{at (minute of day), do (home, visit, stroll), door, stay, block}],
## sorted by time. Each day is a little different but the same every time you replay it.
func plan_for(p: Walker, day: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = p.index * 7919 + day * 104729
	var j := func(spread: float) -> float: return r.randf_range(-spread, spread)
	var home := {"do": "home", "door": p.home}
	var plan := []
	var add := func(h: float, entry: Dictionary) -> void:
		var e := entry.duplicate()
		e.at = clampf(h * 60.0, 0.0, 1439.0)
		plan.append(e)
	var near_food := func(at: Vector3) -> Dictionary: return _pick(_food, at, r)
	var near_shop := func(at: Vector3) -> Dictionary: return _pick(_shops, at, r)
	var downtown: Vector2i = DOWNTOWN[r.randi() % DOWNTOWN.size()]
	if p.night_owl:
		add.call(0.0, {"do": "stroll", "block": downtown})
		add.call(3.75 + j.call(30) / 60.0, home)
	else:
		add.call(0.0, home)
	match p.role:
		"office":
			add.call(7.25 + j.call(40) / 60.0, {"do": "visit", "door": p.work, "stay": r.randf_range(50, 200)})
			add.call(12.0 + j.call(20) / 60.0, {"do": "visit", "door": near_food.call(p.work.pos), "stay": r.randf_range(20, 40)})
			add.call(13.0 + j.call(10) / 60.0, {"do": "visit", "door": p.work, "stay": r.randf_range(50, 200)})
			if r.randf() < 0.5:
				add.call(17.0 + j.call(40) / 60.0, {"do": "visit", "door": near_shop.call(p.work.pos), "stay": r.randf_range(15, 30)})
			else:
				add.call(17.0 + j.call(40) / 60.0, {"do": "stroll", "block": p.work.block})
			add.call(18.25 + j.call(40) / 60.0, {"do": "stroll", "block": p.home.block})
			add.call(20.5 + j.call(40) / 60.0, home)
		"student":
			add.call(8.0 + j.call(40) / 60.0, {"do": "visit", "door": p.work, "stay": r.randf_range(80, 140)})
			add.call(12.0 + j.call(20) / 60.0, {"do": "visit", "door": near_food.call(p.work.pos), "stay": r.randf_range(25, 45)})
			add.call(13.25 + j.call(15) / 60.0, {"do": "visit", "door": p.work, "stay": r.randf_range(120, 200)})
			add.call(17.0 + j.call(40) / 60.0, {"do": "stroll", "block": downtown})
			add.call(19.0 + j.call(40) / 60.0, {"do": "visit", "door": _food[r.randi() % _food.size()], "stay": r.randf_range(30, 60)})
			add.call(21.0 + j.call(40) / 60.0, {"do": "stroll", "block": p.home.block})
			add.call(23.0 + j.call(25) / 60.0, home)
		"shopper":
			add.call(9.0 + j.call(40) / 60.0, {"do": "stroll", "block": p.home.block})
			add.call(10.0 + j.call(40) / 60.0, {"do": "visit", "door": near_shop.call(p.home.pos), "stay": r.randf_range(25, 50)})
			add.call(11.75 + j.call(40) / 60.0, {"do": "visit", "door": _food[r.randi() % _food.size()], "stay": r.randf_range(25, 45)})
			add.call(13.5 + j.call(40) / 60.0, {"do": "stroll", "block": PARK})
			add.call(15.0 + j.call(40) / 60.0, {"do": "visit", "door": _shops[r.randi() % _shops.size()], "stay": r.randf_range(20, 40)})
			add.call(17.0 + j.call(40) / 60.0, {"do": "stroll", "block": p.home.block})
			add.call(19.0 + j.call(40) / 60.0, home)
		_:   # worker
			add.call(6.0 + j.call(30) / 60.0, {"do": "visit", "door": p.work, "stay": r.randf_range(50, 200)})
			add.call(11.5 + j.call(20) / 60.0, {"do": "visit", "door": near_food.call(p.work.pos), "stay": r.randf_range(20, 35)})
			add.call(12.5 + j.call(10) / 60.0, {"do": "visit", "door": p.work, "stay": r.randf_range(50, 200)})
			add.call(15.5 + j.call(20) / 60.0, {"do": "visit", "door": near_shop.call(p.work.pos), "stay": r.randf_range(15, 30)})
			add.call(16.5 + j.call(40) / 60.0, {"do": "stroll", "block": p.home.block})
			add.call(18.5 + j.call(40) / 60.0, home)
	if p.night_owl:
		add.call(21.5 + j.call(40) / 60.0, {"do": "stroll", "block": downtown})
	plan.sort_custom(func(a, b): return a.at < b.at)
	return plan


class Walker:
	extends AnimatableBody3D

	var owner_set: Pedestrians
	var human: Humanoid
	var index := 0
	var role := "shopper"
	var night_owl := false
	var home: Dictionary
	var work: Dictionary
	var speed := 1.4
	var state := "inside"      # walk, stroll, wait (at a crosswalk), inside
	var crossing := false      # in the street right now
	var plan: Array = []
	var activity: Dictionary = {}
	var _plan_day := -1
	var _entry_at := -1.0      # start time of the plan entry we're on
	var _in_door: Dictionary   # the door we went in by
	var _path: Array = []      # waypoints (see Pedestrians.route)
	var _loop: Array = []      # corners of the block we're strolling around
	var _loop_i := 0
	var _arrive := ""          # what to do when the path ends: inside, stroll
	var _inside_until := -1.0  # game minute to come out (-1: until the next activity)
	var _pending := false      # a new activity is waiting for us to finish crossing
	var _wait := 0.0
	var _pause := 0.0
	var _cur := 0.0            # current speed
	var _anim_dt := 0.0
	var _col: CollisionShape3D
	var _rng := RandomNumberGenerator.new()

	func setup(model: String) -> void:
		sync_to_physics = false
		_col = CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.75
		_col.shape = cap
		_col.position.y = 0.88
		add_child(_col)
		human = Humanoid.create(model)
		add_child(human)
		_rng.seed = 991 + index * 31
		_in_door = home
		global_position = home.walk

	## Work out what we should be doing now. snap: jump straight there instead of walking.
	func refresh(snap := false) -> void:
		if _plan_day != Game.day:
			_plan_day = Game.day
			plan = owner_set.plan_for(self, Game.day)
		var cur: Dictionary = plan[0]
		for e in plan:
			if e.at <= Game.minute:
				cur = e
		if not snap and cur.at == _entry_at:
			return
		_entry_at = cur.at
		activity = cur
		var far := global_position.distance_to(owner_set.player_position()) > Pedestrians.SNAP_DIST
		if snap or far:
			_snap_to(cur)
		elif crossing:
			_pending = true
		else:
			_start(cur)

	func _start(a: Dictionary) -> void:
		var from := global_position
		if state == "inside":
			var d: Dictionary = _in_door
			from = d.walk
			_show(true)
			global_position = d.pos
			_path = [{"p": d.walk, "cross": false}]
		else:
			_path = []
		_inside_until = -1.0
		if a.do == "stroll":
			_loop = _block_loop(a.block)
			_loop_i = _nearest_corner(_loop, from)
			_path += owner_set.route(from, _loop[_loop_i])
			_arrive = "stroll"
		else:
			var door: Dictionary = a.door
			_path += owner_set.route(from, door.walk)
			_path.append({"p": door.pos, "cross": false})
			_arrive = "inside"
		state = "walk"

	## Put ourselves wherever this activity would have us by now.
	func _snap_to(a: Dictionary) -> void:
		crossing = false
		_pending = false
		_path = []
		if a.do == "stroll":
			_loop = _block_loop(a.block)
			_loop_i = _rng.randi() % 4
			var prev: Vector3 = _loop[(_loop_i + 3) % 4]
			global_position = prev.lerp(_loop[_loop_i], _rng.randf())
			_face(_loop[_loop_i] - prev)
			_show(true)
			state = "stroll"
			return
		var door: Dictionary = a.door
		var stay: float = a.get("stay", -1.0)
		var since := fposmod(Game.minute - a.at, 1440.0)
		if since < 45.0 and a.has("at"):
			# Just set off: somewhere along the way from wherever we were before.
			var prev := _previous(a)
			_in_door = prev.door if prev.has("door") else home
			state = "inside"
			_start(a)
			_skip(owner_set._rng.randf_range(0.0, 1.0) * since / 45.0 * _path_length())
			return
		if stay > 0.0 and since > stay + 10.0:
			# Done inside already: strolling around the block.
			_snap_to({"do": "stroll", "block": door.block})
			return
		_go_inside(door, a)

	## The plan entry before `a` (yesterday's last one if `a` is the first).
	func _previous(a: Dictionary) -> Dictionary:
		var i := plan.find(a)
		return plan[i - 1] if i > 0 else plan.back()

	func _path_length() -> float:
		var total := 0.0
		var at := global_position
		for w in _path:
			total += at.distance_to(w.p)
			at = w.p
		return total

	## Jumps `dist` meters down the current path.
	func _skip(dist: float) -> void:
		while not _path.is_empty():
			var w: Vector3 = _path[0].p
			var d := global_position.distance_to(w)
			if d > dist:
				var dir := (w - global_position).normalized()
				global_position += dir * dist
				_face(dir)
				return
			dist -= d
			global_position = w
			_path.pop_front()
		_arrived()

	func _go_inside(door: Dictionary, a: Dictionary) -> void:
		_in_door = door
		global_position = door.walk
		state = "inside"
		var stay: float = a.get("stay", -1.0)
		_inside_until = fmod(a.at + stay, 1440.0) if stay > 0.0 else -1.0
		_show(false)

	func _inside_door() -> Dictionary:
		var a := activity
		if a.has("door"):
			return a.door
		return home

	func _show(on: bool) -> void:
		visible = on
		_col.disabled = not on

	func _block_loop(b: Vector2i) -> Array:
		var pts := []
		for k in 4:
			pts.append(owner_set.corner(b, k))
		if index % 2 == 1:
			pts.reverse()
		return pts

	func _nearest_corner(pts: Array, p: Vector3) -> int:
		var best := 0
		for i in pts.size():
			if pts[i].distance_to(p) < pts[best].distance_to(p):
				best = i
		return best

	func _face(d: Vector3) -> void:
		d.y = 0.0
		if d.length() < 0.01:
			return
		d = d.normalized()
		global_transform = Transform3D(Basis(Vector3.UP.cross(d).normalized(), Vector3.UP, d), global_position)

	## Safe to step into this crosswalk? Walk signal at lights, otherwise a gap in traffic.
	func _can_cross(leg: Dictionary) -> bool:
		var main: Node = owner_set.main
		if main == null:
			return true
		var tc: TrafficControl = main.traffic_control
		if tc and tc.has_light(leg.node) and tc.color(leg.axis) != "green":
			return false
		var mid: Vector3 = (global_position + leg.p) / 2.0
		var movers := []
		if main.traffic:
			for c in main.traffic.cars:
				movers.append([c.global_position, c.global_basis.z, c.speed])
		if main.car:
			movers.append([main.car.global_position, main.car.global_basis.z, main.car.linear_velocity.length()])
		for m in movers:
			var rel: Vector3 = mid - m[0]
			rel.y = 0.0
			if rel.length() < 22.0 and m[2] > 1.5 and rel.dot(m[1]) > 0.0:
				return false
		return true

	func _physics_process(delta: float) -> void:
		refresh()
		if state == "inside":
			if _inside_until >= 0.0 and fposmod(Game.minute - _inside_until, 1440.0) < 720.0:
				# Done in here: come out and stroll around the block until the next activity.
				var door: Dictionary = _in_door
				activity = activity.duplicate()
				activity.do = "stroll"
				activity.block = door.block
				_start(activity)
			return
		var me := global_position
		var player := owner_set.player_position()
		var dist := me.distance_to(player)
		visible = dist < 220.0
		var target: Vector3
		var leg: Dictionary = {}
		if state == "stroll":
			target = _loop[_loop_i]
		else:
			if _path.is_empty():
				_arrived()
				return
			leg = _path[0]
			target = leg.p
		var to := target - me
		to.y = 0.0
		var want := speed * (1.25 if Game.weather in ["rain", "storm", "snow"] and Game.weather_amount > 0.3 else 1.0)
		if _pause > 0.0:
			_pause -= delta
			want = 0.0
		# Waiting at the curb for the light or a gap in traffic.
		if leg.get("cross", false) and not crossing:
			if _can_cross(leg) or _wait > 18.0:
				crossing = true
				_wait = 0.0
			else:
				_wait += delta
				want = 0.0
		# Don't walk into you.
		var rel := player - me
		rel.y = 0.0
		if rel.length() < 2.2 and rel.dot(global_basis.z) > 0.0 and not crossing:
			want = 0.0
		_cur = move_toward(_cur, want, delta * 3.0)
		if to.length() < 0.3:
			if state == "stroll":
				_loop_i = (_loop_i + 1) % _loop.size()
				if _rng.randf() < 0.25:
					_pause = _rng.randf_range(1.0, 4.0)
			else:
				_path.pop_front()
				crossing = false
				if _pending:
					_pending = false
					_start(activity)
				elif _path.is_empty():
					_arrived()
		else:
			var step := minf(_cur * delta, to.length())
			global_position = me + to.normalized() * step
			# Turn smoothly toward where we're heading.
			var fwd := global_basis.z
			var yaw := lerp_angle(atan2(fwd.x, fwd.z), atan2(to.x, to.z), clampf(delta * 6.0, 0.0, 1.0))
			_face(Vector3(sin(yaw), 0, cos(yaw)))
		_animate(delta, dist)

	## The walk cycle is the expensive part, so it updates less often farther away
	## (every frame up close, every third frame out to 80 m, not at all beyond).
	func _animate(delta: float, dist: float) -> void:
		if human == null or dist > 80.0:
			return
		_anim_dt += delta
		var every := 1 if dist < 30.0 else 3
		if (Engine.get_physics_frames() + index) % every == 0:
			human.animate(_anim_dt, _cur)
			_anim_dt = 0.0

	func _arrived() -> void:
		if _arrive == "stroll":
			state = "stroll"
		else:
			_go_inside(_inside_door(), activity)
