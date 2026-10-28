class_name CarryItem
extends RefCounted
## What you carry on a delivery, built from boxes: a cardboard parcel (Jungle Flex), a pizza
## box (pizza places), a paper takeout bag (other restaurants) or plastic grocery bags
## (Instacrate). Each one is built around the spot your hand grips it.

## How each item is held: see Humanoid.animate().
const HOLD := {"parcel": "front", "pizza": "front", "food_bag": "hang_r", "grocery": "hang_both"}
## Width of front-held items between the palms, meters.
const WIDTH := {"parcel": 0.4, "pizza": 0.42}


static func build(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Carry_" + kind
	match kind:
		"parcel":
			# Box centered between the palms.
			Kit.box(root, Vector3(0.4, 0.3, 0.32), Vector3.ZERO, Color(0.72, 0.55, 0.36), false)
			Kit.box(root, Vector3(0.405, 0.305, 0.07), Vector3.ZERO, Color(0.85, 0.75, 0.55), false)    # tape
			Kit.box(root, Vector3(0.16, 0.002, 0.1), Vector3(0.08, 0.152, 0.06), Color(0.95, 0.95, 0.95), false)  # label
			Kit.box(root, Vector3(0.1, 0.002, 0.012), Vector3(0.08, 0.154, 0.05), Color(0.1, 0.1, 0.1), false)   # barcode
		"pizza":
			# Flat box held by its sides, a little lower than a parcel.
			Kit.box(root, Vector3(0.42, 0.06, 0.42), Vector3.ZERO, Color(0.93, 0.9, 0.82), false)
			Kit.box(root, Vector3(0.2, 0.002, 0.2), Vector3(0, 0.031, 0), Color(0.8, 0.15, 0.12), false)
			Kit.box(root, Vector3(0.12, 0.003, 0.03), Vector3(0, 0.032, 0), Color(0.98, 0.95, 0.85), false)
		"food_bag":
			# Paper bag hanging from the hand: origin is the folded top you grip.
			Kit.box(root, Vector3(0.24, 0.27, 0.15), Vector3(0, -0.17, 0), Color(0.7, 0.53, 0.35), false)
			Kit.box(root, Vector3(0.22, 0.05, 0.03), Vector3(0, -0.02, 0), Color(0.66, 0.5, 0.33), false)  # folded top
			Kit.box(root, Vector3(0.1, 0.1, 0.002), Vector3(0, -0.15, 0.076), Color(0.85, 0.2, 0.15), false)  # sticker
		"grocery":
			# Plastic bag hanging from the hand: two handle loops, a bulging body.
			var white := Color(0.94, 0.94, 0.92)
			Kit.box(root, Vector3(0.012, 0.09, 0.012), Vector3(-0.03, -0.045, 0), white, false)
			Kit.box(root, Vector3(0.012, 0.09, 0.012), Vector3(0.03, -0.045, 0), white, false)
			var body := Kit.box(root, Vector3(0.28, 0.26, 0.18), Vector3(0, -0.22, 0), white, false)
			body.rotation.z = 0.04
			Kit.box(root, Vector3(0.1, 0.06, 0.002), Vector3(0, -0.2, 0.091), Color(0.15, 0.6, 0.3), false)  # logo
	return root
