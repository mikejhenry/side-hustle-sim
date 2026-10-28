class_name Humanoid
extends Node3D
## A Quaternius character (CC0, assets/quaternius/char_*.fbx) with a procedural walk cycle.
## The models ship in a T-pose without animations, so this rotates the arm and leg bones in
## code: arms lowered to the sides, legs and arms swing while walking, knees bend.
## Faces +Z, feet at y = 0.

var skeleton: Skeleton3D
var _bones := {}            # name -> bone index
var _rest_local := {}       # bone index -> Basis (rest pose, relative to parent)
var _rest_global := {}      # bone index -> Basis (rest pose, skeleton space)
var _to_skel: Basis         # model space -> skeleton space
var _arm_side := {}         # "L"/"R" -> +1 when that arm points to +X in model space


## Returns null if the model file is missing, so callers can fall back to simple shapes.
static func create(model_name: String) -> Humanoid:
	var path := "res://assets/quaternius/char_%s.fbx" % model_name
	if not ResourceLoader.exists(path):
		return null
	var h := Humanoid.new()
	var scene: Node3D = load(path).instantiate()
	h.add_child(scene)
	h._setup(scene)
	return h


func _setup(scene: Node3D) -> void:
	var found := scene.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	skeleton = found[0]
	var rel := Transform3D.IDENTITY
	var n: Node = skeleton
	while n != null and n != self:
		if n is Node3D:
			rel = (n as Node3D).transform * rel
		n = n.get_parent()
	var skel_to_model := rel.basis.orthonormalized()
	_to_skel = skel_to_model.inverse()
	for bn in ["UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R", "UpperLeg.L", "UpperLeg.R",
			"LowerLeg.L", "LowerLeg.R", "Head", "Torso"]:
		var i := skeleton.find_bone(bn)
		if i < 0:
			continue
		_bones[bn] = i
		_rest_local[i] = skeleton.get_bone_rest(i).basis.orthonormalized()
		_rest_global[i] = skeleton.get_bone_global_rest(i).basis.orthonormalized()
	for side in ["L", "R"]:
		var u: int = _bones.get("UpperArm." + side, -1)
		var l: int = _bones.get("LowerArm." + side, -1)
		if u >= 0 and l >= 0:
			var a := skeleton.get_bone_global_rest(u).origin
			var b := skeleton.get_bone_global_rest(l).origin
			_arm_side[side] = signf((skel_to_model * (b - a)).x)
	pose(0.0, 0.0)


## Rotation about a model-space axis, converted to skeleton space.
func _rot(axis: Vector3, angle: float) -> Basis:
	return _to_skel * Basis(axis, angle) * _to_skel.inverse()


func _set_bone(bone: String, total: Basis, parent_total := Basis.IDENTITY) -> void:
	var i: int = _bones.get(bone, -1)
	if i < 0:
		return
	var g: Basis = _rest_global[i]
	var delta := g.inverse() * (parent_total.inverse() * total) * g
	skeleton.set_bone_pose_rotation(i, (_rest_local[i] * delta).get_rotation_quaternion())


## phase: walk cycle position in radians; amount: 0 standing still .. 1 full stride.
## carrying: arms held forward (a delivery bag).
func pose(phase: float, amount: float, carrying := false) -> void:
	if skeleton == null:
		return
	var swing := sin(phase) * 0.5 * amount
	var sides := {"L": 1.0, "R": -1.0}
	for side in ["L", "R"]:
		var s: float = sides[side]
		# Legs: swing forward/back about X, knee bends on the back swing.
		var leg_total := _rot(Vector3.RIGHT, swing * s)
		_set_bone("UpperLeg." + side, leg_total)
		var knee := maxf(0.0, sin(phase + (PI / 2.0 if s > 0 else -PI / 2.0))) * 0.7 * amount
		_set_bone("LowerLeg." + side, _rot(Vector3.RIGHT, swing * s + knee), leg_total)
		# Arms: lowered from the T-pose, then swing opposite to the leg on the same side.
		var out: float = _arm_side.get(side, s)
		var down := _rot(Vector3.BACK, -1.3 * out)
		var fwd := -0.9 if carrying else -swing * s * 0.8
		var arm_total := _rot(Vector3.RIGHT, fwd) * down
		_set_bone("UpperArm." + side, arm_total)
		var elbow := -0.5 if carrying else -0.25
		_set_bone("LowerArm." + side, _rot(Vector3.RIGHT, fwd + elbow) * down, arm_total)
