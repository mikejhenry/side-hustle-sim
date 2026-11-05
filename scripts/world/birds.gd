class_name Birds
extends Node3D
## Birds. Flocks of pigeons peck around the park, the campus and downtown sidewalks; walk
## up to them (or drive past fast) and they burst into the air with a flutter, circle for
## a while and land again once you've gone. Gulls glide high over the port and downtown.
## They roost at night. All built from a few primitive meshes.

const SPOTS := [   # flock home: [position in blocks (x, z), extra meters along z, birds, ground height]
	[Vector2(2.5, 1.5), 9.0, 7, 0.07],     # Rodknee Square, on the path by the statue
	[Vector2(2.5, 2.0), 9.2, 6, 0.12],     # downtown sidewalk by the restaurants
	[Vector2(1.5, 2.0), 9.2, 5, 0.12],     # outside Ackme Market
	[Vector2(0.5, 3.0), -9.2, 6, 0.12],    # campus side of Lancaster Ave
	[Vector2(3.6, 2.0), 9.2, 5, 0.12],     # ShopWrite
]
const SCARE_WALK := 5.5
const SCARE_CAR := 15.0
const GULLS := 7

var town: Node = null
var main: Node = null
var flocks: Array = []       # {home, state (ground, flying, landing), timer, center, birds: [Bird]}
var gulls: Array = []
var _rng := RandomNumberGenerator.new()
var _pigeon_mats: Array = []
var _gull_mat: StandardMaterial3D
var _dark_mat: StandardMaterial3D


func build() -> void:
	_rng.seed = 77
	for c in [Color(0.45, 0.47, 0.52), Color(0.36, 0.37, 0.42), Color(0.55, 0.53, 0.5)]:
		_pigeon_mats.append(Kit.mat(c))
	_gull_mat = Kit.mat(Color(0.92, 0.92, 0.9))
	_dark_mat = Kit.mat(Color(0.15, 0.15, 0.17))
	var B: float = town.B
	for s in SPOTS:
		var v: Vector2 = s[0]
		var home := Vector3(v.x * B, s[3], v.y * B + s[1])
		var flock := {"home": home, "state": "ground", "timer": 0.0, "center": home, "birds": [], "sound": null}
		for i in s[2]:
			var b := _bird(_pigeon_mats[_rng.randi() % _pigeon_mats.size()], 1.0)
			b.position = home + Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-1.2, 1.2))
			b.rotation.y = _rng.randf() * TAU
			b.set_meta("ground", b.position)
			flock.birds.append(b)
		var snd := AudioStreamPlayer3D.new()
		snd.stream = Ambience.stream("flutter")
		snd.unit_size = 8.0
		snd.max_distance = 60.0
		snd.position = home + Vector3(0, 1, 0)
		add_child(snd)
		flock.sound = snd
		flocks.append(flock)
	for i in GULLS:
		var g := _bird(_gull_mat, 1.7)
		var over_port := i < 4
		g.set_meta("center", Vector3((4.4 if over_port else 2.5) * B, 0, (3.6 if over_port else 2.4) * B))
		g.set_meta("radius", _rng.randf_range(25.0, 60.0))
		g.set_meta("height", _rng.randf_range(28.0, 45.0))
		g.set_meta("angle", _rng.randf() * TAU)
		g.set_meta("rate", _rng.randf_range(0.12, 0.22) * (1.0 if i % 2 == 0 else -1.0))
		gulls.append(g)


## A bird: body, head, beak and two wings on pivots. Faces +Z.
func _bird(m: Material, size: float) -> Node3D:
	var b := Node3D.new()
	add_child(b)
	b.scale = Vector3.ONE * size
	var body := Kit.sphere(b, 0.11, Vector3(0, 0.12, 0), m)
	body.scale = Vector3(0.9, 0.85, 1.45)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var head := Kit.sphere(b, 0.065, Vector3(0, 0.22, 0.12), m)
	head.name = "Head"
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var beak := Kit.box(head, Vector3(0.025, 0.02, 0.05), Vector3(0, -0.01, 0.07), _dark_mat if m != _gull_mat else Kit.mat(Color(0.95, 0.75, 0.2)), false)
	(beak as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "WingL" if side < 0.0 else "WingR"
		pivot.position = Vector3(side * 0.07, 0.16, 0.0)
		b.add_child(pivot)
		var w := Kit.box(pivot, Vector3(0.22, 0.015, 0.12), Vector3(side * 0.11, 0, -0.01), m, false)
		(w as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return b


func _flap(b: Node3D, angle: float) -> void:
	(b.get_node("WingL") as Node3D).rotation.z = -angle
	(b.get_node("WingR") as Node3D).rotation.z = angle


func _process(delta: float) -> void:
	if main == null:
		return
	var night := Game.is_night()
	var t := Time.get_ticks_msec() / 1000.0
	var me: Vector3 = main.actor_position()
	var speed: float = main.car_speed() if main.is_driving() else 0.0
	for f in flocks:
		var near: bool = me.distance_to(f.home) < 160.0
		for b in f.birds:
			b.visible = near and not night
		if not near or night:
			if f.state != "ground":
				_land_now(f)
			continue
		var d: float = Vector3(me.x, f.home.y, me.z).distance_to(f.home)
		var scared: bool = (d < SCARE_WALK + 2.5 and not main.is_driving()) or (main.is_driving() and d < SCARE_CAR and speed > 3.0)
		match f.state:
			"ground":
				if scared:
					take_off(f)
				else:
					_peck(f, delta, t)
			"flying":
				f.timer -= delta
				_fly(f, delta, t)
				if f.timer <= 0.0 and not scared:
					f.state = "landing"
			"landing":
				if scared:
					f.state = "flying"
					f.timer = _rng.randf_range(5.0, 9.0)
				elif _fly(f, delta, t):
					f.state = "ground"
	for g in gulls:
		g.visible = not night
		if night:
			continue
		var a: float = g.get_meta("angle") + g.get_meta("rate") * delta
		g.set_meta("angle", a)
		var c: Vector3 = g.get_meta("center")
		var r: float = g.get_meta("radius")
		var p := c + Vector3(cos(a) * r, g.get_meta("height") + sin(a * 3.0) * 2.0, sin(a) * r)
		var fwd := Vector3(-sin(a), 0, cos(a)) * signf(g.get_meta("rate"))
		g.global_transform = Transform3D(Basis(Vector3.UP.cross(fwd).normalized(), Vector3.UP, fwd).rotated(fwd, -0.25 * signf(g.get_meta("rate"))), p)
		g.scale = Vector3.ONE * 1.7
		# Mostly gliding, with a few lazy flaps now and then.
		var flapping := fmod(t + r, 7.0) < 1.2
		_flap(g, sin(t * 9.0) * 0.6 if flapping else 0.08)


## Pecking about: small hops, head bobs, the odd turn.
func _peck(f: Dictionary, delta: float, t: float) -> void:
	for b in f.birds:
		var head := b.get_node("Head") as Node3D
		var k := float(b.get_instance_id() % 97)
		head.position.y = 0.22 - (0.06 if fmod(t * 1.3 + k, 2.0) < 0.35 else 0.0)
		_flap(b, 0.0)
		if _rng.randf() < delta * 0.4:
			b.rotation.y += _rng.randf_range(-1.2, 1.2)
		if _rng.randf() < delta * 0.5:
			var step := Vector3(sin(b.rotation.y), 0, cos(b.rotation.y)) * 0.25
			var g: Vector3 = b.get_meta("ground")
			var np: Vector3 = b.position + step
			if np.distance_to(f.home) < 3.0:
				b.position = np
				b.set_meta("ground", np)
		var g2: Vector3 = b.get_meta("ground")
		b.position.y = g2.y + maxf(0.0, sin(fmod(t * 6.0 + k, TAU))) * 0.02


func take_off(f: Dictionary) -> void:
	f.state = "flying"
	f.timer = _rng.randf_range(9.0, 15.0)
	f.center = f.home + Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-8, 8))
	for b in f.birds:
		b.set_meta("vel", Vector3(_rng.randf_range(-2, 2), 4.5, _rng.randf_range(-2, 2)))
		b.set_meta("phase", _rng.randf() * TAU)
	if f.sound and f.sound.is_inside_tree():
		f.sound.play()


## Moves a flock in the air (circling, or coming in to land). True once all have landed.
func _fly(f: Dictionary, delta: float, t: float) -> bool:
	var landed := 0
	for b in f.birds:
		var ph: float = b.get_meta("phase") + delta * 0.9
		b.set_meta("phase", ph)
		var aim: Vector3
		var g: Vector3 = b.get_meta("ground")
		if f.state == "landing":
			aim = g
		else:
			aim = f.center + Vector3(cos(ph) * 9.0, 11.0 + sin(ph * 2.0) * 1.5, sin(ph) * 9.0)
		var pos: Vector3 = b.position
		var vel: Vector3 = b.get_meta("vel", Vector3.ZERO)
		var to := aim - pos
		var want := to.normalized() * minf(7.0, to.length() * 1.6 + 0.5)
		vel = vel.move_toward(want, 9.0 * delta)
		pos += vel * delta
		if f.state == "landing" and pos.distance_to(g) < 0.15:
			pos = g
			vel = Vector3.ZERO
			landed += 1
			_flap(b, 0.0)
		else:
			_flap(b, sin(t * 22.0 + ph) * 0.9)
		b.position = pos
		b.set_meta("vel", vel)
		var flat := Vector3(vel.x, 0, vel.z)
		if flat.length() > 0.3:
			b.rotation.y = atan2(flat.x, flat.z)
	return landed == f.birds.size()


func _land_now(f: Dictionary) -> void:
	f.state = "ground"
	for b in f.birds:
		b.position = b.get_meta("ground")
		b.set_meta("vel", Vector3.ZERO)
		_flap(b, 0.0)
