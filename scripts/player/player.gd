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

var camera: Camera3D
var _pivot: Node3D
var _spring: SpringArm3D
var _model: Node3D
var _bag: MeshInstance3D
var _phone_mesh: MeshInstance3D
var _col: CollisionShape3D
var _walk_t := 0.0
var _legs: Array = []


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
	var torso := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.3
	tm.height = 1.0
	torso.mesh = tm
	torso.material_override = Kit.mat(Color(0.2, 0.45, 0.75))
	torso.position.y = 1.15
	_model.add_child(torso)
	Kit.sphere(_model, 0.2, Vector3(0, 1.82, 0), Color(0.85, 0.65, 0.5))
	Kit.box(_model, Vector3(0.42, 0.08, 0.3), Vector3(0, 1.98, 0.05), Color(0.8, 0.2, 0.2), false) # cap
	for sx in [-0.13, 0.13]:
		var leg := Kit.box(_model, Vector3(0.18, 0.7, 0.2), Vector3(sx, 0.35, 0), Color(0.2, 0.2, 0.25), false)
		_legs.append(leg)
	_bag = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 0.4, 0.35)
	_bag.mesh = bm
	_bag.material_override = Kit.mat(Color(0.75, 0.6, 0.4))
	_bag.position = Vector3(0, 1.05, 0.45)
	_bag.visible = false
	_model.add_child(_bag)
	_phone_mesh = Kit.box(_model, Vector3(0.08, 0.15, 0.02), Vector3(0.22, 1.25, 0.35), Color(0.05, 0.05, 0.05), false)
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


func set_active(on: bool) -> void:
	active = on
	visible = on
	_col.disabled = not on
	if on:
		camera.current = true
		velocity = Vector3.ZERO


func set_carrying(on: bool) -> void:
	_bag.visible = on


func set_phone_visible(on: bool) -> void:
	_phone_mesh.visible = on


func facing() -> float:
	return _model.rotation.y


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.2, 0.6)


func _physics_process(delta: float) -> void:
	if not active:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	var input_dir := Vector2.ZERO
	if not input_locked:
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
	for i in _legs.size():
		_legs[i].rotation.x = sin(_walk_t + i * PI) * 0.5
	move_and_slide()
	_pivot.rotation = Vector3(pitch, yaw, 0)
	if global_position.y < -20.0:
		global_position.y = 2.0
