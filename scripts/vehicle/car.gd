class_name Car
extends VehicleBody3D
## The player's car. Forward is local +Z. First-person camera in the driver's seat
## (C toggles a chase camera for parking). Stats come from Game.car() and wear from Game.

const STEER_LIMIT := 0.55
const BRAKE_FORCE := 28.0
const MOUSE_SENS := 0.0025

signal crashed(strength: float)

var driver_active := false
var input_locked := false
var chase_cam := false
var headlights_on := false

var fp_camera: Camera3D
var chase_camera: Camera3D
var _look_yaw := 0.0
var _look_pitch := -0.08
var _visual: Node3D
var _steering_wheel: Node3D
var _wheels: Array = []
var _lights: Array = []
var _last_pos: Vector3
var _prev_velocity := Vector3.ZERO
var _crash_cooldown := 0.0
var _flip_timer := 0.0

# Mirrors: small extra views of the world rendered from cameras on the car. The HUD shows
# their textures (flipped like a real mirror) while you drive in first person.
var mirrors_enabled := true
var mirror_views := {}      # "rear" / "left" / "right" -> SubViewport
var _mirror_cams := {}      # same keys -> [Camera3D, local Transform3D]
var _mirror_frame := 0
var _engine: AudioStreamPlayer3D


func _ready() -> void:
	mass = 1150.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.25, 0.1)
	contact_monitor = true
	max_contacts_reported = 4
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 0.8, 4.3)
	col.shape = shape
	col.position = Vector3(0, 0.75, 0)
	add_child(col)
	var cab_col := CollisionShape3D.new()
	var cab_shape := BoxShape3D.new()
	cab_shape.size = Vector3(1.6, 0.4, 2.0)
	cab_col.shape = cab_shape
	cab_col.position = Vector3(0, 1.22, -0.2)
	add_child(cab_col)

	for spec in [[0.85, 1.35, true], [-0.85, 1.35, true], [0.85, -1.35, false], [-0.85, -1.35, false]]:
		var w := VehicleWheel3D.new()
		w.position = Vector3(spec[0], 0.5, spec[1])
		w.use_as_steering = spec[2]
		w.use_as_traction = not spec[2]
		w.wheel_radius = 0.36
		w.wheel_rest_length = 0.22
		w.suspension_travel = 0.25
		w.suspension_stiffness = 40.0
		w.damping_compression = 0.9
		w.damping_relaxation = 1.2
		w.wheel_roll_influence = 0.05
		w.wheel_friction_slip = 3.0
		add_child(w)
		w.add_child(CarModel.wheel_mesh())
		_wheels.append(w)

	fp_camera = Camera3D.new()
	fp_camera.position = Vector3(0.38, 1.24, -0.15)
	fp_camera.rotation.y = PI
	fp_camera.fov = 78.0
	fp_camera.near = 0.05
	fp_camera.cull_mask = 0xFFFFF & ~2
	add_child(fp_camera)
	chase_camera = Camera3D.new()
	chase_camera.position = Vector3(0, 3.2, -7.5)
	chase_camera.rotation = Vector3(-0.22, PI, 0)
	chase_camera.cull_mask = 0xFFFFF & ~2
	add_child(chase_camera)

	for x in [0.6, -0.6]:
		var l := SpotLight3D.new()
		l.position = Vector3(x, 0.8, 2.2)
		l.rotation = Vector3(-0.08, PI, 0)
		l.spot_range = 45.0
		l.spot_angle = 30.0
		l.light_energy = 3.0
		l.visible = false
		add_child(l)
		_lights.append(l)

	_build_mirrors()
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = Sfx.get_stream("engine")
	_engine.position = Vector3(0, 0.8, 1.6)
	_engine.unit_size = 6.0
	_engine.volume_db = -10.0
	add_child(_engine)
	apply_model()
	Game.car_changed.connect(apply_model)
	_last_pos = global_position


func _build_mirrors() -> void:
	for key in ["rear", "left", "right"]:
		var sv := SubViewport.new()
		sv.size = Vector2i(400, 100) if key == "rear" else Vector2i(200, 130)
		sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
		sv.positional_shadow_atlas_size = 0
		add_child(sv)
		var cam := Camera3D.new()
		cam.cull_mask = 0xFFFFF & ~2
		cam.fov = 34.0 if key == "rear" else 42.0
		cam.near = 0.1
		cam.far = 160.0
		sv.add_child(cam)
		mirror_views[key] = sv
		_mirror_cams[key] = [cam, Transform3D.IDENTITY]
	_place_mirror_cams()


## Puts the mirror cameras where the mirrors are on the current car. A camera looks down
## its -Z, which is the car's rear, so the rear one needs no turn; the side ones angle out.
func _place_mirror_cams() -> void:
	if _mirror_cams.is_empty():
		return
	var sz: Vector3 = Game.car().size
	_mirror_cams.rear[1] = Transform3D(Basis(Vector3.RIGHT, -0.04), Vector3(0, 1.35, -sz.z / 2.0 - 0.15))
	_mirror_cams.left[1] = Transform3D(Basis(Vector3.UP, -0.22) * Basis(Vector3.RIGHT, -0.05), Vector3(sz.x / 2.0 + 0.12, 1.08, 0.7))
	_mirror_cams.right[1] = Transform3D(Basis(Vector3.UP, 0.22) * Basis(Vector3.RIGHT, -0.05), Vector3(-sz.x / 2.0 - 0.12, 1.08, 0.7))


func mirrors_visible() -> bool:
	return mirrors_enabled and driver_active and not chase_cam


func mirror_texture(key: String) -> Texture2D:
	return mirror_views[key].get_texture()


func _update_mirrors() -> void:
	var on := mirrors_visible()
	if not on:
		for key in mirror_views:
			mirror_views[key].render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	# One extra view per frame keeps the cost low: the rearview refreshes every other frame
	# and each side mirror every fourth.
	_mirror_frame += 1
	var key := "rear" if _mirror_frame % 2 == 0 else ("left" if _mirror_frame % 4 == 1 else "right")
	var entry: Array = _mirror_cams[key]
	(entry[0] as Camera3D).global_transform = global_transform * (entry[1] as Transform3D)
	mirror_views[key].render_target_update_mode = SubViewport.UPDATE_ONCE


func _process(delta: float) -> void:
	_update_mirrors()
	_update_engine_sound(delta)


## Engine note: idles while you sit in the car, revs with speed through four fake gears.
func _update_engine_sound(delta: float) -> void:
	var on := driver_active and Game.fuel > 0.0
	if on != _engine.playing:
		if on:
			_engine.play()
		else:
			_engine.stop()
	if not on:
		return
	var top: float = Game.car().top_speed
	var g := clampf(absf(linear_velocity.dot(global_basis.z)) / (top / 4.0), 0.0, 3.99)
	var rev := g - floorf(g)
	var throttle := maxf(Input.get_action_strength("move_forward"), Input.get_action_strength("throttle")) if not input_locked else 0.0
	var pitch := 0.75 + 0.55 * rev + 0.12 * floorf(g) + 0.12 * throttle
	_engine.pitch_scale = lerpf(_engine.pitch_scale, pitch, clampf(delta * 8.0, 0.0, 1.0))
	_engine.volume_db = lerpf(_engine.volume_db, -12.0 + 6.0 * throttle + 2.0 * rev, clampf(delta * 6.0, 0.0, 1.0))


## Rebuilds the body meshes to match the owned car.
func apply_model() -> void:
	if _visual:
		_visual.queue_free()
	var c := Game.car()
	_visual = Node3D.new()
	add_child(_visual)
	var sz: Vector3 = c.size
	_place_mirror_cams()
	_visual.add_child(CarModel.build(c, Game.car_id == "rustwagon"))
	# Interior (seen in first person): dashboard, gauges, steering wheel, seats.
	var dash := Kit.mat(Color(0.1, 0.1, 0.11))
	Kit.box(_visual, Vector3(sz.x - 0.2, 0.22, 0.55), Vector3(0, 0.9, 0.78), dash, false)
	var hood := Kit.box(_visual, Vector3(sz.x - 0.2, 0.04, 0.4), Vector3(0, 1.0, 0.6), dash, false)
	hood.rotation.x = -0.2
	Kit.box(_visual, Vector3(0.5, 0.14, 0.05), Vector3(0.38, 1.02, 0.66), Color(0.02, 0.02, 0.03), false)
	Kit.box(_visual, Vector3(0.12, 0.08, 0.02), Vector3(0.28, 1.03, 0.635), Color(0.3, 0.8, 1.0), false, 1.5)
	Kit.box(_visual, Vector3(0.12, 0.08, 0.02), Vector3(0.48, 1.03, 0.635), Color(1.0, 0.6, 0.2), false, 1.5)
	Kit.box(_visual, Vector3(0.3, 0.2, 0.03), Vector3(0.0, 0.98, 0.6), Color(0.05, 0.08, 0.1), false, 0.4)
	_steering_wheel = Node3D.new()
	_steering_wheel.position = Vector3(0.38, 1.0, 0.5)
	_steering_wheel.rotation.x = -0.35
	_visual.add_child(_steering_wheel)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.16
	tm.outer_radius = 0.19
	ring.mesh = tm
	ring.rotation.x = PI / 2.0
	ring.material_override = Kit.mat(Color(0.05, 0.05, 0.05))
	_steering_wheel.add_child(ring)
	Kit.box(_steering_wheel, Vector3(0.3, 0.04, 0.03), Vector3.ZERO, Color(0.1, 0.1, 0.1), false)
	# Seats
	for x in [0.38, -0.38]:
		Kit.box(_visual, Vector3(0.55, 0.15, 0.55), Vector3(x, 0.72, -0.35), Color(0.25, 0.22, 0.2), false)
		Kit.box(_visual, Vector3(0.55, 0.65, 0.12), Vector3(x, 1.05, -0.65), Color(0.25, 0.22, 0.2), false)


func set_driver(on: bool) -> void:
	driver_active = on
	_look_yaw = 0.0
	_look_pitch = -0.08
	if on:
		_active_camera().current = true


func _active_camera() -> Camera3D:
	return chase_camera if chase_cam else fp_camera


func toggle_camera() -> void:
	chase_cam = not chase_cam
	if driver_active:
		_active_camera().current = true


func set_headlights(on: bool) -> void:
	headlights_on = on
	for l in _lights:
		l.visible = on


func speed_mph() -> float:
	return linear_velocity.length() * 2.237


func _unhandled_input(event: InputEvent) -> void:
	if not driver_active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_yaw = clampf(_look_yaw - event.relative.x * MOUSE_SENS * Game.mouse_sens, -1.9, 1.9)
		_look_pitch = clampf(_look_pitch - event.relative.y * MOUSE_SENS * Game.mouse_sens, -0.8, 0.5)


func _physics_process(delta: float) -> void:
	var c := Game.car()
	var fwd_speed := linear_velocity.dot(global_basis.z)
	var spd := linear_velocity.length()
	for w in _wheels:
		w.wheel_friction_slip = 3.0 * Game.grip_factor()

	var hard := 0.0
	if driver_active and not input_locked:
		var throttle := maxf(Input.get_action_strength("move_forward"), Input.get_action_strength("throttle"))
		var back := maxf(Input.get_action_strength("move_back"), Input.get_action_strength("brake_reverse"))
		var steer_in := Input.get_axis("move_right", "move_left")
		if Game.energy < 15.0:
			# Drowsy driving: the car wanders.
			steer_in += sin(Time.get_ticks_msec() * 0.0011) * 0.35 * (1.0 - Game.energy / 15.0)
		var limit := lerpf(STEER_LIMIT, 0.16, clampf(spd / 30.0, 0.0, 1.0))
		steering = move_toward(steering, steer_in * limit, 2.2 * delta)
		var power: float = c.engine * Game.engine_factor()
		var ef := 0.0
		var br := 0.0
		if throttle > 0.0:
			if fwd_speed < -1.0:
				br = BRAKE_FORCE * throttle
			else:
				ef = power * throttle * clampf(1.0 - pow(maxf(fwd_speed, 0.0) / c.top_speed, 2.0), 0.0, 1.0)
		if back > 0.0:
			if fwd_speed > 1.0:
				br = BRAKE_FORCE * back
				hard = 0.5
			else:
				ef = -power * 0.6 * back * clampf(1.0 + fwd_speed / 7.0, 0.0, 1.0)
		if Input.is_action_pressed("handbrake"):
			br = BRAKE_FORCE * 0.9
			hard = 1.0
		engine_force = ef
		brake = br
		if Input.is_action_just_pressed("horn"):
			Sfx.play(self, "horn", -4.0)
		if Input.is_action_just_pressed("reset_car") and spd < 4.0:
			reset_upright()
	else:
		engine_force = 0.0
		steering = move_toward(steering, 0.0, delta)
		brake = 6.0 if spd < 3.0 else 1.0

	if driver_active:
		# Right stick looks around; it springs back to the road when released.
		var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if look.length() > 0.05:
			_look_yaw = clampf(-look.x * 1.6, -1.9, 1.9)
			_look_pitch = clampf(-0.08 - look.y * 0.5, -0.8, 0.5)
		elif Game.using_pad:
			_look_yaw = move_toward(_look_yaw, 0.0, 4.0 * delta)
			_look_pitch = move_toward(_look_pitch, -0.08, 2.0 * delta)
	if _steering_wheel:
		_steering_wheel.rotation.z = -steering * 4.0
	fp_camera.rotation = Vector3(_look_pitch, PI + _look_yaw, 0)

	# Wear and tear
	var moved := global_position.distance_to(_last_pos)
	if moved < 20.0:
		Game.add_distance(moved, hard)
	_last_pos = global_position

	# Crash detection from sudden velocity change
	_crash_cooldown = maxf(0.0, _crash_cooldown - delta)
	var dv := (linear_velocity - _prev_velocity).length()
	if dv > 7.0 and _crash_cooldown <= 0.0 and _prev_velocity.length() > 6.0:
		_crash_cooldown = 1.0
		Game.damage_engine(dv * 0.4)
		crashed.emit(dv)
		Gigs.on_crash(dv)
		if driver_active:
			Sfx.play(self, "crash", lerpf(-8.0, 0.0, clampf((dv - 7.0) / 10.0, 0.0, 1.0)))
			Game.notify("CRUNCH! That's going to leave a mark.", "bad")
	_prev_velocity = linear_velocity

	# Auto-right after a rollover
	if global_basis.y.y < 0.3 and spd < 1.0:
		_flip_timer += delta
		if _flip_timer > 2.5:
			reset_upright()
	else:
		_flip_timer = 0.0


func reset_upright() -> void:
	var yaw := atan2(global_basis.z.x, global_basis.z.z)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3(0, 1.2, 0))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_flip_timer = 0.0


func teleport(t: Transform3D) -> void:
	global_transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_last_pos = t.origin
	_prev_velocity = Vector3.ZERO
