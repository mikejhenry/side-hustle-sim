class_name MixamoRig
extends Humanoid
## The player character from Mixamo (assets/mixamo, kept on your PC and out of git):
## Character.fbx plus Idle, Walk, Run, Jump and Carry_walk animations. An AnimationTree
## blends them: idle / walk / run by speed (played faster or slower so the feet match the
## ground), the carry pose on the upper body when you hold a box, and the jump timed to the
## real jump (takeoff, hang time, landing). Same interface as Humanoid, so the player code
## and carried items work with either.
## If the files are missing, create() returns null and the player falls back to Humanoid.

const DIR := "res://assets/mixamo/"
const CLIPS := {"idle": "Idle", "walk": "Walk", "run": "Run", "jump": "Jump", "carry": "Carry_walk"}
## In-place clips still have a natural pace: the ground speed (m/s) at playback speed 1.
const WALK_PACE := 1.45
const RUN_PACE := 4.2
const GRAVITY := 9.8

var _tree: AnimationTree
var _prefix := ""            # bone name prefix, e.g. "mixamorig12_"
var _jump_up := 0.05         # in the jump clip: when the feet leave the ground
var _jump_down := 0.6        # ... and touch down again
var _jump_len := 1.0
var _jt := 0.0               # where the jump clip is
var _air_t := 0.0            # seconds in the air this jump
var _air_total := 0.9        # predicted hang time
var _jump_w := 0.0           # jump clip weight


static func available() -> bool:
	if not ResourceLoader.exists(DIR + "Character.fbx"):
		return false
	for c in CLIPS.values():
		if not ResourceLoader.exists(DIR + c + ".fbx"):
			return false
	return true


static func create_rig() -> MixamoRig:
	if not available():
		return null
	var rig := MixamoRig.new()
	var scene: Node3D = load(DIR + "Character.fbx").instantiate()
	rig.add_child(scene)
	rig._build(scene)
	return rig


func _build(scene: Node3D) -> void:
	var found := scene.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	skeleton = found[0]
	var hips_name := skeleton.get_bone_name(0)
	_prefix = hips_name.substr(0, hips_name.length() - "Hips".length())
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var m := node as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Mixamo exports its materials 80% see-through. Build fresh, fully solid materials
		# from their textures (eyelashes keep a cut-out edge so they aren't dark blocks).
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, _solid(m.get_active_material(i), m.name.containsn("lash")))
	# Our own player, with the clips from the other files (they share the skeleton).
	for old in scene.find_children("*", "AnimationPlayer", true, false):
		old.get_parent().remove_child(old)
		old.queue_free()
	var player := AnimationPlayer.new()
	player.name = "Anims"
	scene.add_child(player)
	var lib := AnimationLibrary.new()
	var hips_rest := skeleton.get_bone_rest(0).origin
	for key in CLIPS:
		var src: Node = load(DIR + CLIPS[key] + ".fbx").instantiate()
		var ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
		var anim: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
		src.free()
		_pin_hips(anim, key, hips_rest)
		anim.loop_mode = Animation.LOOP_NONE if key == "jump" else Animation.LOOP_LINEAR
		lib.add_animation(key, anim)
	player.add_animation_library("", lib)
	_jump_len = lib.get_animation("jump").length
	_tree = AnimationTree.new()
	_tree.name = "Tree"
	scene.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(player)
	_tree.root_node = _tree.get_path_to(scene)
	_tree.tree_root = _blend_tree()
	_tree.active = true


func _solid(src: Material, cutout: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var base := src as BaseMaterial3D
	if base:
		mat.albedo_texture = base.albedo_texture
		var c := base.albedo_color
		mat.albedo_color = Color(c.r, c.g, c.b, 1.0)
		mat.normal_enabled = base.normal_enabled
		mat.normal_texture = base.normal_texture
		mat.normal_scale = base.normal_scale
		mat.roughness = base.roughness
		mat.roughness_texture = base.roughness_texture
		mat.metallic = base.metallic
		mat.metallic_texture = base.metallic_texture
	else:
		push_warning("MixamoRig: unexpected material %s" % src)
		mat.albedo_color = Color(0.8, 0.7, 0.6)
	if cutout:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	return mat


## Keep the clip in place: the hips may bob and crouch but not travel. For the jump, the
## physics does the rising, so the hips never go above standing height either; the times
## the hips leave and come back to standing height mark takeoff and touchdown.
func _pin_hips(anim: Animation, key: String, rest: Vector3) -> void:
	var t := anim.find_track(NodePath("Skeleton3D:" + _prefix + "Hips"), Animation.TYPE_POSITION_3D)
	if t < 0:
		return
	var n := anim.track_get_key_count(t)
	if n == 0:
		return
	var first: Vector3 = anim.track_get_key_value(t, 0)
	var up := -1.0
	var down := -1.0
	for k in n:
		var v: Vector3 = anim.track_get_key_value(t, k)
		if key == "jump":
			if v.y > rest.y - 0.02:
				if up < 0.0:
					up = anim.track_get_key_time(t, k)
				down = anim.track_get_key_time(t, k)
			v.y = minf(v.y, rest.y - 0.03)
		anim.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))
	if key == "jump" and up >= 0.0:
		_jump_up = maxf(up - 0.05, 0.0)
		_jump_down = maxf(down, _jump_up + 0.1)


func _blend_tree() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	for p in [["idle", 0.0], ["walk", 1.0], ["run", 2.0]]:
		var a := AnimationNodeAnimation.new()
		a.animation = p[0]
		loco.add_blend_point(a, p[1])
	loco.min_space = 0.0
	loco.max_space = 2.0
	bt.add_node("loco", loco, Vector2(0, 0))
	bt.add_node("pace", AnimationNodeTimeScale.new(), Vector2(200, 0))
	bt.connect_node("pace", 0, "loco")
	var carry := AnimationNodeAnimation.new()
	carry.animation = "carry"
	bt.add_node("carry", carry, Vector2(200, 150))
	# Holding a box: arms and chest from the carry clip, legs from walking.
	var hold := AnimationNodeBlend2.new()
	hold.filter_enabled = true
	for i in skeleton.get_bone_count():
		var bn := skeleton.get_bone_name(i).trim_prefix(_prefix)
		if bn.begins_with("Spine") or bn.begins_with("Neck") or bn.begins_with("Head") \
				or bn.begins_with("Left") and not (bn.contains("Leg") or bn.contains("Foot") or bn.contains("Toe")) \
				or bn.begins_with("Right") and not (bn.contains("Leg") or bn.contains("Foot") or bn.contains("Toe")):
			hold.set_filter_path(NodePath("Skeleton3D:" + skeleton.get_bone_name(i)), true)
	bt.add_node("hold", hold, Vector2(400, 0))
	bt.connect_node("hold", 0, "pace")
	bt.connect_node("hold", 1, "carry")
	var jump := AnimationNodeAnimation.new()
	jump.animation = "jump"
	bt.add_node("jump", jump, Vector2(400, 150))
	bt.add_node("jump_at", AnimationNodeTimeSeek.new(), Vector2(600, 150))
	bt.connect_node("jump_at", 0, "jump")
	bt.add_node("air", AnimationNodeBlend2.new(), Vector2(800, 0))
	bt.connect_node("air", 0, "hold")
	bt.connect_node("air", 1, "jump_at")
	bt.connect_node("output", 0, "air")
	return bt


func animate(delta: float, speed: float, carry := "", airborne := false, vy := 0.0) -> void:
	if _tree == null:
		return
	# Speed: 0 standing, 1 walking, 2 running.
	var target := clampf(speed / WALK_PACE, 0.0, 1.0) if speed < 4.2 else 1.0 + clampf((speed - 4.2) / 3.3, 0.0, 1.0)
	_move = move_toward(_move, target, delta * (4.0 if target > _move else 3.0))
	_tree.set("parameters/loco/blend_position", _move)
	var pace := lerpf(WALK_PACE, RUN_PACE, clampf(_move - 1.0, 0.0, 1.0))
	_tree.set("parameters/pace/scale", clampf(speed / pace, 0.7, 1.6) if speed > 0.3 else 1.0)
	_carry = move_toward(_carry, 1.0 if carry == "front" else 0.0, delta * 4.0)
	_tree.set("parameters/hold/blend_amount", _carry)
	# Jump: play the clip's air part stretched over the real hang time, then its landing.
	if airborne and not _was_air:
		_air_t = 0.0
		_air_total = maxf(2.0 * maxf(vy, 1.0) / GRAVITY, 0.4)
	if airborne:
		_air_t += delta
		# Falling further than a jump (off a ledge): hold the last airborne frame.
		var f := clampf(_air_t / _air_total, 0.0, 1.0)
		_jt = lerpf(_jump_up, _jump_down - 0.02, f)
		_jump_w = move_toward(_jump_w, 1.0, delta * 10.0)
	elif _jump_w > 0.0:
		# Landing: let the clip finish its knee bend, then fade back to walking.
		if _was_air:
			_jt = maxf(_jt, _jump_down)
			_land = 1.0
		_jt = minf(_jt + delta, _jump_len)
		var left := _jump_len - _jt
		_jump_w = move_toward(_jump_w, 0.0, delta * (2.5 if speed < 0.3 else 5.0))
		if left <= 0.0:
			_jump_w = move_toward(_jump_w, 0.0, delta * 8.0)
	_land = move_toward(_land, 0.0, delta * 2.5)
	_was_air = airborne
	_air = _jump_w
	_tree.set("parameters/jump_at/seek_request", _jt)
	_tree.set("parameters/air/blend_amount", _jump_w)


func palm(side: String) -> Vector3:
	if skeleton == null:
		return global_position
	var hand := "Left" if side == "L" else "Right"
	var h := skeleton.find_bone(_prefix + hand + "Hand")
	if h < 0:
		return global_position
	var xf := skeleton.global_transform
	var wrist := xf * skeleton.get_bone_global_pose(h).origin
	var mid := skeleton.find_bone(_prefix + hand + "HandMiddle1")
	if mid < 0:
		return wrist
	return wrist.lerp(xf * skeleton.get_bone_global_pose(mid).origin, 0.6)


func pose(_phase: float, _amount: float, _carrying := false) -> void:
	pass
