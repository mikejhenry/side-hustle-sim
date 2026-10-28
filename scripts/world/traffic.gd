class_name Traffic
extends Node3D
## AI traffic. Cars drive the street grid in the right-hand lane, pick a random turn at each
## intersection, slow down for corners, and brake for anything ahead of them (you, your car,
## or other traffic). They are kinematic bodies, so you can still crash into them.

const COUNT := 14
const LANE := 3.5          # lane center, meters right of the road center line
const HALF := 9.0          # where the intersection box starts, meters from its center
const CRUISE := 11.0       # ~25 mph
const TURN_SPEED := 5.0
const ACCEL := 3.0
const BRAKE := 9.0
const LOOK_AHEAD := 16.0
const PAINT := [Color(0.75, 0.77, 0.8), Color(0.1, 0.1, 0.12), Color(0.85, 0.85, 0.86),
	Color(0.55, 0.08, 0.08), Color(0.12, 0.22, 0.45), Color(0.3, 0.32, 0.3), Color(0.8, 0.7, 0.5),
	Color(0.15, 0.35, 0.2)]

var town: Node = null
var main: Node = null
var cars: Array = []
var _rng := RandomNumberGenerator.new()


func build() -> void:
	_rng.seed = 911
	var avoid: Vector3 = main.actor_position() if main else Vector3.ZERO
	var tries := 0
	while cars.size() < COUNT and tries < 400:
		tries += 1
		var node := Vector2i(_rng.randi_range(0, town.N), _rng.randi_range(0, town.N))
		var dirs := _exits(node, Vector2i.ZERO)
		var d: Vector2i = dirs[_rng.randi() % dirs.size()]
		var car := AICar.new()
		car.traffic = self
		add_child(car)
		car.setup(_random_data(), node, d, _rng.randf_range(0.1, 0.8))
		if car.global_position.distance_to(avoid) < 30.0 or _too_close(car):
			cars.erase(car)
			car.queue_free()
			continue
		cars.append(car)


func _too_close(car: Node3D) -> bool:
	for c in cars:
		if c != car and c.global_position.distance_to(car.global_position) < 12.0:
			return true
	return false


## Quaternius car models (CC0) used for part of the traffic when the files are present.
const QUATERNIUS_CARS := ["Cop", "NormalCar1", "NormalCar2", "SUV", "SportsCar", "Taxi"]


func _random_data() -> Dictionary:
	var keys: Array = GameData.CARS.keys()
	var base: Dictionary = GameData.CARS[keys[_rng.randi() % keys.size()]]
	var data := {"size": base.size, "color": PAINT[_rng.randi() % PAINT.size()]}
	var have := []
	for n in QUATERNIUS_CARS:
		if ResourceLoader.exists("res://assets/quaternius/%s.fbx" % n):
			have.append(n)
	# The cop car shows up once; other models make up about half the traffic.
	if not have.is_empty() and _rng.randf() < 0.5:
		var pick: String = have[_rng.randi() % have.size()]
		if pick != "Cop" or not _cop_used:
			_cop_used = _cop_used or pick == "Cop"
			data["model"] = pick
			data["size"] = Vector3(2.0, 1.4, 4.4)
	return data


var _cop_used := false


func node_pos(n: Vector2i) -> Vector3:
	return Vector3(n.x * town.B, 0, n.y * town.B)


## Directions you can leave an intersection by, never straight back the way you came.
func _exits(n: Vector2i, came: Vector2i) -> Array:
	var out := []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var m: Vector2i = n + d
		if m.x < 0 or m.y < 0 or m.x > town.N or m.y > town.N:
			continue
		if d == -came and came != Vector2i.ZERO:
			continue
		out.append(d)
	return out


func pick_exit(n: Vector2i, came: Vector2i) -> Vector2i:
	var opts := _exits(n, came)
	if opts.is_empty():
		return -came
	# Going straight is a bit more common than turning.
	if came in opts and _rng.randf() < 0.45:
		return came
	return opts[_rng.randi() % opts.size()]


## Things a car must not drive into, as [position, is_ai_car]: you, your car, other traffic.
func obstacles(except: Node) -> Array:
	var out := []
	if main:
		out.append([main.car.global_position, false])
		if not main.is_driving():
			out.append([main.player.global_position, false])
	for c in cars:
		if c != except:
			out.append([c.global_position, true])
	return out


static func right_of(d: Vector3) -> Vector3:
	return Vector3(-d.z, 0, d.x)


class AICar:
	extends AnimatableBody3D

	var traffic: Traffic
	var speed := 0.0
	var waited := 0.0
	var _creep := 0.0        # seconds left ignoring other AI cars (breaks intersection standoffs)
	var _node_from: Vector2i
	var _dir: Vector2i
	var _legs: Array = []     # each leg: [p0, control, p1, length, is_turn, is_road_segment]
	var _s := 0.0             # distance travelled along the current leg
	var _wheels: Array = []

	func setup(data: Dictionary, node: Vector2i, d: Vector2i, start_frac: float) -> void:
		sync_to_physics = false
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var size: Vector3 = data.size
		box.size = Vector3(size.x, 1.2, size.z)
		col.shape = box
		col.position.y = 0.85
		add_child(col)
		var model: Node3D
		if data.has("model"):
			model = load("res://assets/quaternius/%s.fbx" % data.model).instantiate()
			model.scale = Vector3.ONE * 1.18
		else:
			model = CarModel.build(data, false, true)
		add_child(model)
		for c in model.get_children():
			if c.get_child_count() > 0 and c.get_child(0) is MeshInstance3D and (c.get_child(0) as MeshInstance3D).mesh is CylinderMesh:
				_wheels.append(c)
		_node_from = node
		_dir = d
		_queue_straight()
		_s = _legs[0][3] * start_frac
		_apply_pose()

	func _queue_straight() -> void:
		var a := traffic.node_pos(_node_from)
		var d3 := Vector3(_dir.x, 0, _dir.y)
		var r := Traffic.right_of(d3)
		var b := traffic.node_pos(_node_from + _dir)
		var p0 := a + d3 * Traffic.HALF + r * Traffic.LANE
		var p1 := b - d3 * Traffic.HALF + r * Traffic.LANE
		_legs.append([p0, (p0 + p1) / 2.0, p1, p0.distance_to(p1), false, true])

	func _queue_turn() -> void:
		var n := _node_from + _dir
		var came := _dir
		var nd := traffic.pick_exit(n, came)
		var c := traffic.node_pos(n)
		var d1 := Vector3(came.x, 0, came.y)
		var d2 := Vector3(nd.x, 0, nd.y)
		var r1 := Traffic.right_of(d1)
		var r2 := Traffic.right_of(d2)
		var p0 := c - d1 * Traffic.HALF + r1 * Traffic.LANE
		var p1 := c + d2 * Traffic.HALF + r2 * Traffic.LANE
		var ctrl := (p0 + p1) / 2.0 if nd == came else c + (r1 + r2) * Traffic.LANE
		var length := p0.distance_to(ctrl) + ctrl.distance_to(p1)
		_legs.append([p0, ctrl, p1, length * 0.9, nd != came, false])
		_node_from = n
		_dir = nd

	func _point(leg: Array, t: float) -> Vector3:
		var p0: Vector3 = leg[0]
		var c: Vector3 = leg[1]
		var p1: Vector3 = leg[2]
		return p0.lerp(c, t).lerp(c.lerp(p1, t), t)

	func _apply_pose() -> void:
		var leg: Array = _legs[0]
		var t := clampf(_s / float(leg[3]), 0.0, 1.0)
		var p := _point(leg, t)
		var ahead := _point(leg, minf(t + 0.02, 1.0))
		var fwd := ahead - p
		if t >= 0.98:
			var p0: Vector3 = leg[0]
			var p1: Vector3 = leg[2]
			fwd = p1 - _point(leg, 0.96) if leg[4] else p1 - p0
		fwd.y = 0.0
		if fwd.length() < 0.001:
			fwd = Vector3(_dir.x, 0, _dir.y)
		fwd = fwd.normalized()
		# Car models face +Z.
		var basis := Basis(Vector3.UP.cross(fwd).normalized(), Vector3.UP, fwd)
		global_transform = Transform3D(basis, p)

	func _physics_process(delta: float) -> void:
		var leg: Array = _legs[0]
		var target := Traffic.TURN_SPEED if leg[4] else Traffic.CRUISE
		# Ease off before a corner.
		if not leg[4]:
			var left := float(leg[3]) - _s
			if left < 14.0:
				target = lerpf(Traffic.TURN_SPEED + 2.0, Traffic.CRUISE, left / 14.0)
		# Brake for anything ahead in our lane.
		var fwd := global_basis.z
		var right := Traffic.right_of(fwd)
		var gap := INF
		_creep = maxf(0.0, _creep - delta)
		for o in traffic.obstacles(self):
			if o[1] and _creep > 0.0:
				continue
			var rel: Vector3 = o[0] - global_position
			rel.y = 0.0
			var ahead := rel.dot(fwd)
			if ahead > 0.0 and ahead < Traffic.LOOK_AHEAD and absf(rel.dot(right)) < 2.4:
				gap = minf(gap, ahead)
		if gap < INF:
			target = minf(target, maxf(0.0, (gap - 6.5) * 1.2))
		if speed < 0.3 and target < 0.5:
			waited += delta
			# Two AI cars blocking each other would wait forever, so one creeps through.
			if waited > 4.0 + randf() * 2.0:
				_creep = 2.5
				waited = 0.0
		else:
			waited = 0.0
		var rate := Traffic.ACCEL if target > speed else Traffic.BRAKE
		speed = move_toward(speed, target, rate * delta)
		_s += speed * delta
		while _s >= float(_legs[0][3]):
			_s -= float(_legs[0][3])
			var done: Array = _legs.pop_front()
			# After a road segment comes an intersection, and after an intersection a road.
			if done[5]:
				_queue_turn()
			else:
				_queue_straight()
		_apply_pose()
		for w in _wheels:
			w.rotation.x += speed * delta / CarModel.WHEEL_R
