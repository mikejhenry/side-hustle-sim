class_name Player
extends CharacterBody3D
## On-foot character with a third-person orbit camera.

const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.5
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.0028

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var active := true
var input_locked := false
var yaw := 0.0
var pitch := -0.25
var _look_vel := Vector2.ZERO   # smoothed right-stick turn rate

var camera: Camera3D
var _pivot: Node3D
var _spring: SpringArm3D
var _model: Node3D
var _carry_kind := ""
var _carry_nodes: Array = []    # one item, or one per hand for grocery bags
var _phone_mesh: MeshInstance3D
var _col: CollisionShape3D
var _walk_t := 0.0
var _legs: Array = []
var _arms: Array = []
var _human: Humanoid


func _ready() -> void:
	_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	_col.shape = cap
	_col.position.y = 0.9
	add_child(_col)

	_model = Node3D.new()
	add_child(_model)
	_human = Humanoid.create("Casual2")
	if _human:
		_model.add_child(_human)
	else:
		_build_simple_model()
	_phone_mesh = Kit.box(_model, Vector3(0.08, 0.15, 0.02), Vector3(0.2, 1.2, 0.3), Color(0.05, 0.05, 0.05), false)
	_phone_mesh.visible = false

	_pivot = Node3D.new()
	_pivot.position.y = 1.6
	add_child(_pivot)
	_spring = SpringArm3D.new()
	_spring.spring_length = 3.6
	_spring.margin = 0.2
	_spring.add_excluded_object(get_rid())
	_pivot.add_child(_spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.cull_mask = 0xFFFFF & ~2
	_spring.add_child(camera)


## Fallback character made of capsules, used if the Quaternius model is missing.
func _build_simple_model() -> void:
	var skin := Kit.mat(Color(0.86, 0.66, 0.52))
	var shirt := Kit.mat(Color(0.18, 0.42, 0.72))
	var pants := Kit.mat(Color(0.16, 0.18, 0.24))
	var shoes := Kit.mat(Color(0.12, 0.1, 0.09))
	_capsule(_model, 0.21, 0.62, Vector3(0, 1.22, 0), shirt, Vector3(1.15, 1.0, 0.75))   # torso
	_capsule(_model, 0.06, 0.16, Vector3(0, 1.56, 0), skin)                             # neck
	var head := Kit.sphere(_model, 0.13, Vector3(0, 1.72, 0.01), skin)
	head.scale = Vector3(0.9, 1.08, 1.0)
	var hair := Kit.sphere(_model, 0.135, Vector3(0, 1.76, -0.015), Kit.mat(Color(0.18, 0.12, 0.08)))
	hair.scale = Vector3(0.95, 0.85, 1.0)
	Kit.box(_model, Vector3(0.26, 0.05, 0.12), Vector3(0, 1.845, 0.1), Kit.mat(Color(0.8, 0.2, 0.2)), false)  # cap brim
	var hat := Kit.sphere(_model, 0.14, Vector3(0, 1.8, 0.0), Kit.mat(Color(0.8, 0.2, 0.2)))
	hat.scale = Vector3(1.0, 0.55, 1.0)
	for sx in [-0.04, 0.04]:
		Kit.sphere(_model, 0.015, Vector3(sx, 1.74, 0.115), Kit.mat(Color(0.05, 0.05, 0.05)))
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.1, 0.92, 0)
		_model.add_child(hip)
		_capsule(hip, 0.085, 0.86, Vector3(0, -0.43, 0), pants)
		Kit.box(hip, Vector3(0.12, 0.08, 0.26), Vector3(0, -0.88, 0.05), shoes, false)
		_legs.append(hip)
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.27, 1.45, 0)
		_model.add_child(shoulder)
		_capsule(shoulder, 0.065, 0.36, Vector3(0, -0.15, 0), shirt)
		_capsule(shoulder, 0.055, 0.32, Vector3(0, -0.42, 0), skin)
		_arms.append(shoulder)


func _capsule(parent: Node3D, radius: float, height: float, pos: Vector3, m: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = maxf(height, radius * 2.0)
	cm.radial_segments = 12
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


func set_active(on: bool) -> void:
	active = on
	visible = on
	_col.disabled = not on
	if on:
		camera.current = true
		velocity = Vector3.ZERO


## What you're carrying: "" for nothing, or a CarryItem kind (parcel, pizza, food_bag, grocery).
func set_carrying(kind: String) -> void:
	if kind == _carry_kind:
		return
	_carry_kind = kind
	for n in _carry_nodes:
		n.queue_free()
	_carry_nodes.clear()
	if kind == "":
		return
	for i in (2 if kind == "grocery" else 1):
		var item := CarryItem.build(kind)
		item.top_level = true
		add_child(item)
		_carry_nodes.append(item)


func carrying() -> String:
	return _carry_kind


## Puts carried items in his hands (after the pose for this frame is set).
func _place_carry() -> void:
	if _carry_nodes.is_empty():
		return
	var b := _model.global_basis.orthonormalized()
	if _human == null:
		for n in _carry_nodes:
			n.global_transform = Transform3D(b, _model.global_transform * Vector3(0, 1.05, 0.38))
		return
	var hold: String = CarryItem.HOLD.get(_carry_kind, "front")
	if hold == "front":
		var l := _human.palm("L")
		var r := _human.palm("R")
		var item: Node3D = _carry_nodes[0]
		# Palms press on the item's sides: fit its width to the gap between them.
		var w: float = CarryItem.WIDTH.get(_carry_kind, 0.4)
		var sx := clampf((l.distance_to(r) - 0.03) / w, 0.75, 1.25)
		item.global_transform = Transform3D(b.scaled(Vector3(sx, 1, 1)), (l + r) / 2.0)
	else:
		var sides := ["R", "L"]
		for i in _carry_nodes.size():
			var n: Node3D = _carry_nodes[i]
			n.global_transform = Transform3D(b, _human.palm(sides[i]))


func set_phone_visible(on: bool) -> void:
	_phone_mesh.visible = on


func facing() -> float:
	return _model.rotation.y


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS * Game.mouse_sens
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS * Game.mouse_sens, -1.2, 0.6)


func _physics_process(delta: float) -> void:
	if not active:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	var input_dir := Vector2.ZERO
	if not input_locked:
		# Right stick: curved response plus a little acceleration so turns start and stop smoothly.
		var look := Game.look_stick()
		var want := Vector2(-look.x * 2.3, -look.y * 1.5) * Game.pad_sens
		_look_vel = _look_vel.lerp(want, 1.0 - exp(-9.0 * delta))
		yaw += _look_vel.x * delta
		pitch = clampf(pitch + _look_vel.y * delta, -1.2, 0.6)
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
	var dir := Basis(Vector3.UP, yaw) * Vector3(input_dir.x, 0, input_dir.y)
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	# Needs slow you down: starving, exhausted or bursting bladder.
	if Game.energy < 15.0 or Game.hunger <= 0.0:
		speed *= 0.65
	if Game.bladder > 85.0:
		speed *= 0.8
	if dir.length() > 0.01:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		var target := atan2(dir.x, dir.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target, 12.0 * delta)
		_walk_t += delta * speed * 2.2
	else:
		velocity.x = move_toward(velocity.x, 0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 30.0 * delta)
		_walk_t = 0.0
	if _human:
		var hspeed := Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0
		_human.animate(delta, hspeed, CarryItem.HOLD.get(_carry_kind, "") if _carry_kind != "" else "")
	for i in _legs.size():
		_legs[i].rotation.x = sin(_walk_t + i * PI) * 0.55
		_arms[i].rotation.x = -sin(_walk_t + i * PI) * 0.45
	move_and_slide()
	_place_carry()
	_pivot.rotation = Vector3(pitch, yaw, 0)
	if global_position.y < -20.0:
		global_position.y = 2.0
