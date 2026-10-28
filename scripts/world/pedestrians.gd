class_name Pedestrians
extends Node3D
## People walking the sidewalks. Each one loops around a block (clockwise or not), pausing
## now and then, and stops if you're standing in their way. They're solid, so you can't
## drive through them, and hitting one in front of a cop counts as reckless driving.

const COUNT := 12
const INSET := 9.2           # sidewalk path, meters from the road center line
const MODELS := ["Casual2", "Suit", "Casual", "Worker"]

var town: Node = null
var main: Node = null
var people: Array = []
var _rng := RandomNumberGenerator.new()


func build() -> void:
	_rng.seed = 4242
	var have := MODELS.filter(func(m): return ResourceLoader.exists("res://assets/quaternius/char_%s.fbx" % m))
	if have.is_empty():
		return
	for i in COUNT:
		var p := Walker.new()
		p.owner_set = self
		add_child(p)
		var bx := _rng.randi_range(0, town.N - 1)
		var bz := _rng.randi_range(0, town.N - 1)
		p.setup(have[i % have.size()], _corners(bx, bz), _rng.randf() < 0.5, _rng.randf(), _rng.randf_range(1.2, 1.6))
		people.append(p)


## The four sidewalk corners around block (bx, bz), in walking order.
func _corners(bx: int, bz: int) -> Array:
	var x0: float = bx * town.B + INSET
	var z0: float = bz * town.B + INSET
	var x1: float = (bx + 1) * town.B - INSET
	var z1: float = (bz + 1) * town.B - INSET
	return [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]


func player_position() -> Vector3:
	return main.actor_position() if main else Vector3(1e6, 0, 1e6)


class Walker:
	extends AnimatableBody3D

	var owner_set: Pedestrians
	var human: Humanoid
	var _pts: Array = []
	var _i := 0                # index of the corner we're walking to
	var _speed := 1.4
	var _pause := 0.0
	var _cur := 0.0            # current speed
	var _rng := RandomNumberGenerator.new()

	func setup(model: String, corners: Array, reverse: bool, start: float, speed: float) -> void:
		sync_to_physics = false
		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.75
		col.shape = cap
		col.position.y = 0.88
		add_child(col)
		human = Humanoid.create(model)
		add_child(human)
		_pts = corners.duplicate()
		if reverse:
			_pts.reverse()
		_speed = speed
		_rng.seed = hash(corners[0]) + int(start * 1000.0)
		# Start somewhere along the first side.
		var a: Vector3 = _pts[0]
		var b: Vector3 = _pts[1]
		_i = 1
		global_position = a.lerp(b, start)
		_face(b - a)

	func _face(d: Vector3) -> void:
		d.y = 0.0
		if d.length() < 0.01:
			return
		d = d.normalized()
		global_transform = Transform3D(Basis(Vector3.UP.cross(d).normalized(), Vector3.UP, d), global_position)

	func _physics_process(delta: float) -> void:
		var me := global_position
		var far := me.distance_to(owner_set.player_position()) > 120.0
		visible = me.distance_to(owner_set.player_position()) < 220.0
		var target: Vector3 = _pts[_i]
		var to := target - me
		to.y = 0.0
		var want := _speed
		if _pause > 0.0:
			_pause -= delta
			want = 0.0
		# Don't walk into you.
		var rel := owner_set.player_position() - me
		rel.y = 0.0
		if rel.length() < 2.2 and rel.dot(global_basis.z) > 0.0:
			want = 0.0
		_cur = move_toward(_cur, want, delta * 3.0)
		if to.length() < 0.3:
			_i = (_i + 1) % _pts.size()
			if _rng.randf() < 0.25:
				_pause = _rng.randf_range(1.0, 4.0)
		else:
			var step := minf(_cur * delta, to.length())
			global_position = me + to.normalized() * step
			# Turn smoothly toward where we're heading.
			var fwd := global_basis.z
			var d := fwd.slerp(to.normalized(), clampf(delta * 6.0, 0.0, 1.0))
			_face(d)
		if not far:
			human.animate(delta, _cur)
