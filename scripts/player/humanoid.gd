class_name Humanoid
extends Node3D
## A Quaternius character (CC0, assets/quaternius/char_*.fbx) animated in code.
## The models ship rigged (spine, arms, legs, feet, every finger joint) but with no animation
## clips, so this drives the bones procedurally:
##   walk and run cycles with stride length and cadence matched to your speed (no foot
##   sliding), knees that bend on the swing and absorb weight on landing, feet that roll from
##   heel to toe, hips that bob, sway and twist with a counter-rotating chest, a steady head,
##   arms that swing with relaxed elbows and hands, and curled fingers;
##   an idle with breathing and a slow weight shift;
##   a split-leg jump (lead leg up in front, trail leg stretched behind, arms opposite) that
##   tucks for the landing as you fall, then a knee-bending landing;
##   smooth blending between all of them.
## Faces +Z, feet at y = 0.

var skeleton: Skeleton3D
var _bones := {}            # name -> bone index
var _rest_local := {}       # bone index -> Basis (rest pose, relative to parent)
var _rest_global := {}      # bone index -> Basis (rest pose, skeleton space)
var _to_skel: Basis         # model space -> skeleton space
var _arm_side := {}         # "L"/"R" -> +1 when that arm points to +X in model space
var _fingers: Array = []    # [bone index, curl amount] for every finger joint
var _leg_len := 0.9         # hip to ankle, meters

var _phase := 0.0           # walk cycle position, radians
var _move := 0.0            # smoothed 0 (standing) .. 1 (walking) .. 1.8 (running)
var _idle_t := 0.0
var _carry := 0.0           # smoothed 0..1, both arms forward holding a box
var _hang := {"L": 0.0, "R": 0.0}   # smoothed 0..1, that hand holds a bag hanging at your side
var _air := 0.0             # smoothed 0..1, in a jump
var _rise := 0.0            # 1 going up, 0 coming down (legs come together to land)
var _lead := 1.0            # +1: left leg leads the jump, -1: right
var _land := 0.0            # 1 right after landing, fades out: knees soak it up
var _was_air := false

const BODY_BONES := ["Hips", "Abdomen", "Torso", "Chest", "Neck", "Head", "Shoulder.L", "Shoulder.R",
	"UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R", "Hand.L", "Hand.R",
	"UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R", "Foot.L", "Foot.R"]
const WALK_SPEED := 4.2
const RUN_CROSS := 0.22
const CARRY_IN := 0.15


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
	for i in skeleton.get_bone_count():
		var bn := skeleton.get_bone_name(i)
		if bn in BODY_BONES:
			_bones[bn] = i
			_rest_local[i] = skeleton.get_bone_rest(i).basis.orthonormalized()
			_rest_global[i] = skeleton.get_bone_global_rest(i).basis.orthonormalized()
		elif not bn.ends_with("_end"):
			# Finger joints: index to pinky curl more toward the tip, the thumb only a little.
			for f in ["Index", "Middle", "Ring", "Pinky", "Thumb"]:
				if bn.begins_with(f):
					var seg := int(bn.substr(f.length(), 1))
					var curl := 0.25 + 0.2 * (seg - 2)
					if f == "Thumb":
						curl = 0.15
					elif f == "Pinky" or f == "Ring":
						curl += 0.1
					_fingers.append([i, curl, skeleton.get_bone_rest(i).basis.orthonormalized()])
	for side in ["L", "R"]:
		var u: int = _bones.get("UpperArm." + side, -1)
		var l: int = _bones.get("LowerArm." + side, -1)
		if u >= 0 and l >= 0:
			var a := skeleton.get_bone_global_rest(u).origin
			var b := skeleton.get_bone_global_rest(l).origin
			_arm_side[side] = signf((skel_to_model * (b - a)).x)
	var hip: int = _bones.get("UpperLeg.L", -1)
	var foot: int = _bones.get("Foot.L", -1)
	if hip >= 0 and foot >= 0:
		_leg_len = clampf((rel.basis * (skeleton.get_bone_global_rest(hip).origin - skeleton.get_bone_global_rest(foot).origin)).length(), 0.5, 1.4)
	_curl_fingers()
	_apply(0.0, 0.0, 0.0, 0.0)


## Rotation about a model-space axis, converted to skeleton space.
func _rot(axis: Vector3, angle: float) -> Basis:
	return _to_skel * Basis(axis, angle) * _to_skel.inverse()


## Sets a bone so that its total rotation (relative to the rest pose, in model space terms) is
## `total`, given the total rotation of its nearest animated parent.
func _set_bone(bone: String, total: Basis, parent_total := Basis.IDENTITY) -> void:
	var i: int = _bones.get(bone, -1)
	if i < 0:
		return
	var g: Basis = _rest_global[i]
	var delta := g.inverse() * (parent_total.inverse() * total) * g
	skeleton.set_bone_pose_rotation(i, (_rest_local[i] * delta).get_rotation_quaternion())


## Relaxed hands: every finger joint bends a little, more toward the tips. `grip` closes
## them toward a loose fist (running, carrying).
var _grip_set := -1.0

func _curl_fingers(grip := 0.0) -> void:
	if absf(grip - _grip_set) < 0.02:
		return
	_grip_set = grip
	for f in _fingers:
		var rest: Basis = f[2]
		var amount: float = f[1] * (1.0 + 1.8 * grip)
		skeleton.set_bone_pose_rotation(f[0], (rest * Basis(Vector3.RIGHT, -amount)).get_rotation_quaternion())


## Call every frame with your horizontal speed in m/s. `carry`: "" (hands free), "front"
## (a box held in front with both hands), "hang_r" (a bag in the right hand) or "hang_both"
## (a bag in each hand).
## `airborne` is true during a jump or a fall, `vy` the vertical speed (m/s).
func animate(delta: float, speed: float, carry := "", airborne := false, vy := 0.0) -> void:
	if skeleton == null:
		return
	if airborne and not _was_air:
		# Take off from whichever leg is behind: the front one leads.
		_lead = 1.0 if sin(_phase) >= 0.0 else -1.0
		if speed < 0.5:
			_lead = -_lead if randf() < 0.5 else _lead
	if _was_air and not airborne:
		_land = clampf(0.4 + _air * 0.6, 0.0, 1.0)
	_was_air = airborne
	_air = move_toward(_air, 1.0 if airborne else 0.0, delta * (9.0 if airborne else 12.0))
	_rise = move_toward(_rise, clampf(0.5 + vy / 4.0, 0.0, 1.0), delta * 6.0)
	_land = move_toward(_land, 0.0, delta * 2.5)
	var target := clampf(speed / WALK_SPEED, 0.0, 1.8)
	# Blend quickly into motion and a little slower back to standing.
	_move = move_toward(_move, target, delta * (4.0 if target > _move else 3.0))
	_carry = move_toward(_carry, 1.0 if carry == "front" else 0.0, delta * 4.0)
	_hang.R = move_toward(_hang.R, 1.0 if carry in ["hang_r", "hang_both"] else 0.0, delta * 4.0)
	_hang.L = move_toward(_hang.L, 1.0 if carry == "hang_both" else 0.0, delta * 4.0)
	_idle_t += delta
	if speed > 0.05:
		# Cadence from stride length so feet don't slide: one cycle is two steps.
		var stride := 4.0 * _leg_len * sin(_amp(_move)) * 0.95
		_phase = fmod(_phase + TAU * speed / maxf(stride, 0.4) * delta, TAU * 4.0)
	elif _move < 0.05:
		# Settle the cycle toward a neutral stance while standing.
		_phase = lerpf(_phase, roundf(_phase / PI) * PI, delta * 3.0)
	_apply(_phase, _move, _carry, _idle_t)


## World position of the middle of a palm ("L" or "R"), for putting things in that hand.
func palm(side: String) -> Vector3:
	var h: int = _bones.get("Hand." + side, -1)
	if skeleton == null or h < 0:
		return global_position
	var xf := skeleton.global_transform
	var wrist := xf * skeleton.get_bone_global_pose(h).origin
	var mid := skeleton.find_bone("Middle1." + side)
	if mid < 0:
		return wrist
	return wrist.lerp(xf * skeleton.get_bone_global_pose(mid).origin, 0.6)


## Stride angle of the thighs: longer strides when running.
func _amp(m: float) -> float:
	return 0.18 + 0.32 * minf(m, 1.0) + 0.18 * maxf(m - 1.0, 0.0)


## Old interface, kept for anything that sets the pose directly.
func pose(phase: float, amount: float, carrying := false) -> void:
	_apply(phase, amount, 1.0 if carrying else 0.0, _idle_t)


func _apply(phase: float, m: float, carry: float, t: float) -> void:
	if skeleton == null:
		return
	var walk := minf(m, 1.0)
	var run := clampf(m - 1.0, 0.0, 0.8) / 0.8
	var amp := _amp(m)
	var sides := {"L": 1.0, "R": -1.0}
	_curl_fingers(maxf(maxf(run, carry * 0.7), maxf(_hang.L, _hang.R)))

	# Idle: breathing and a slow weight shift, faded out while moving.
	var still := 1.0 - walk
	var breathe := sin(t * 1.6) * 0.025 * still
	var shift := sin(t * 0.45) * 0.04 * still

	# Body bob: lowest when both feet are down (twice per cycle), higher when running.
	var bob := -absf(cos(phase)) * 0.035 * walk - run * 0.03 + absf(sin(phase)) * 0.02 * run
	var sway := sin(phase) * 0.025 * walk + shift * 0.5
	var air := _air
	bob *= 1.0 - air
	# Landing: the body drops as the knees bend, then comes back up.
	var land := _land * _land * (3.0 - 2.0 * _land)
	bob -= land * 0.13
	position = Vector3(sway * (1.0 - air), bob, 0)
	# Jump split: wide while rising, legs closing up and front knee lifting to land.
	var spread := lerpf(0.6, 1.0, _rise) * air

	# Hips twist with the legs and tip toward the standing leg; chest counter-rotates.
	var hips := _rot(Vector3.UP, -sin(phase) * 0.14 * walk) * _rot(Vector3.BACK, -cos(phase * 2.0) * 0.025 * walk + shift)
	_set_bone("Hips", hips)
	var lean := (0.04 * walk + 0.16 * run) * (1.0 - air) + 0.1 * air + 0.22 * land
	var spine := _rot(Vector3.RIGHT, lean * 0.5 - breathe) * _rot(Vector3.UP, sin(phase) * 0.03 * walk)
	_set_bone("Abdomen", spine, hips)
	var chest := _rot(Vector3.RIGHT, lean - breathe * 0.5) * _rot(Vector3.UP, sin(phase) * 0.12 * walk) \
		* _rot(Vector3.BACK, -shift * 0.6)
	_set_bone("Chest", chest, spine)
	# Head stays level and looks where you're going.
	var head := _rot(Vector3.RIGHT, -lean * 0.4 + sin(phase * 2.0) * 0.015 * walk)
	_set_bone("Neck", head, chest)
	_set_bone("Head", head, head)

	for side in ["L", "R"]:
		var s: float = sides[side]
		var c := sin(phase) * s               # +1: this leg fully forward
		var v := cos(phase) * s               # >0: this leg swinging forward
		# Thigh: forward/back swing; a little higher on the swing when running.
		var thigh := -c * amp - maxf(v, 0.0) * 0.25 * run
		# In a jump: lead leg up in front, trail leg stretched out behind.
		var leads := s == _lead
		var air_thigh := -1.45 * spread if leads else 0.85 * spread
		thigh = lerpf(thigh, air_thigh, air)
		thigh -= land * (0.55 if leads else 0.3)
		var thigh_b := hips * _rot(Vector3.RIGHT, thigh) * _rot(Vector3.BACK, s * 0.02 * still)
		_set_bone("UpperLeg." + side, thigh_b, hips)
		# Knee: big bend while the foot swings through, small bend absorbing the landing.
		var swing := pow(maxf(v, 0.0), 1.3)
		var plant := maxf(c, 0.0) * maxf(-v, 0.0)
		var knee := (swing * (0.95 + 0.7 * run) + plant * 0.25 + 0.04) * walk + 0.03 * still
		var air_knee := (1.0 + 0.3 * (1.0 - _rise)) if leads else (0.2 + 0.7 * (1.0 - _rise))
		knee = lerpf(knee, air_knee, air) + land * (0.9 if leads else 0.6)
		var shin_b := thigh_b * _rot(Vector3.RIGHT, knee)
		_set_bone("LowerLeg." + side, shin_b, thigh_b)
		# Foot: heel strike in front, push off the toes behind, level in between.
		var foot_angle := -thigh - knee                 # cancel the leg: flat on the ground
		foot_angle += -maxf(c, 0.0) * 0.18 * walk       # toes up at heel strike
		foot_angle += maxf(-c, 0.0) * maxf(v, 0.0) * 0.6 * walk   # toe-off
		foot_angle = lerpf(foot_angle, -thigh - knee + (0.15 if leads else 0.5), air)  # toes point in the air
		var foot_b := hips * _rot(Vector3.RIGHT, (thigh + knee) + foot_angle)
		_set_bone("Foot." + side, foot_b, shin_b)

		# Arms: down from the T-pose, relaxed at the sides, swinging opposite to the leg.
		var out: float = _arm_side.get(side, s)
		var hang: float = _hang[side]
		# Holding a bag: the arm hangs a little away from the leg so the bag clears it.
		var down := _rot(Vector3.BACK, -(1.36 - 0.05 * walk - 0.1 * hang - 0.3 * air * (1.0 - hang)) * out)
		# Negative is forward. The arm swings opposite to the leg on its side; running swings
		# further, mostly backward (elbow behind the body), with the forearm crossing in a bit.
		var arm_swing := (c * (0.3 * walk + 0.3 * run) + 0.12 * run) * (1.0 - 0.75 * hang)
		# In a jump the arms go opposite the legs: the arm on the lead-leg side swings back,
		# the other reaches forward and up for balance.
		arm_swing = lerpf(arm_swing, (0.55 if leads else -1.1) * spread * (1.0 - 0.75 * hang), air)
		var fwd := lerpf(arm_swing + breathe * 0.5, -0.25, carry)
		var arm_b := _rot(Vector3.RIGHT, fwd) * _rot(Vector3.UP, -out * (0.3 * carry + RUN_CROSS * run * (1.0 - hang))) * down
		_set_bone("UpperArm." + side, chest * arm_b, chest)
		# Elbow: relaxed when walking, about 90 degrees when running, bending a little more as
		# the arm comes forward. Smooth all the way round (no kinks in the cycle).
		var ahead := 0.5 - 0.5 * c
		var elbow := -(0.18 + 0.22 * ahead * walk + (1.3 + 0.35 * ahead) * run)
		elbow = lerpf(elbow, -0.45, air)
		elbow = lerpf(lerpf(elbow, -0.1, hang), -1.2, carry)
		# Carrying in front: forearms angle in so the palms meet the box's sides.
		var fore_b := chest * _rot(Vector3.UP, -out * CARRY_IN * carry) * _rot(Vector3.RIGHT, fwd + elbow) * down
		_set_bone("LowerArm." + side, fore_b, chest * arm_b)
		# Hands turn in toward the body.
		var hand_b := fore_b * _rot(Vector3.UP, out * 0.35)
		_set_bone("Hand." + side, hand_b, fore_b)
