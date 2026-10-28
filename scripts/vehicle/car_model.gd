class_name CarModel
extends RefCounted
## Builds a sedan-shaped car body from extruded side profiles (CSG), with wheel arches,
## tinted glass, bumpers, lights and mirrors. Forward is +Z. Used by the player's car
## and the dealership display cars.

const WHEEL_Z := 1.35
const WHEEL_Y := 0.38
const WHEEL_R := 0.36


static func paint(c: Color, rusty := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if rusty:
		m.roughness = 0.75
		m.metallic = 0.1
	else:
		m.metallic = 0.55
		m.roughness = 0.28
		m.clearcoat_enabled = true
		m.clearcoat = 0.6
		m.clearcoat_roughness = 0.15
	return m


## Returns a Node3D containing the car's visuals. with_wheels adds static wheel meshes
## (for display cars; the drivable car uses VehicleWheel3D nodes instead).
static func build(data: Dictionary, rusty := false, with_wheels := false) -> Node3D:
	var root := Node3D.new()
	var size: Vector3 = data.size
	var w := size.x
	var hl := size.z / 2.0
	var body_mat := paint(data.color, rusty)
	var trim := Kit.mat(Color(0.08, 0.08, 0.09))

	# Lower body: side profile extruded across the width, minus wheel arches.
	var combiner := CSGCombiner3D.new()
	root.add_child(combiner)
	var body := CSGPolygon3D.new()
	body.polygon = PackedVector2Array([
		Vector2(-hl, 0.32), Vector2(-hl + 0.05, 0.98), Vector2(-hl + 1.05, 1.02),
		Vector2(hl - 1.35, 1.0), Vector2(hl - 0.2, 0.86), Vector2(hl, 0.7), Vector2(hl, 0.32),
	])
	body.depth = w
	body.rotation.y = -PI / 2.0
	body.position.x = -w / 2.0
	body.material = body_mat
	combiner.add_child(body)
	for z in [WHEEL_Z, -WHEEL_Z]:
		var arch := CSGCylinder3D.new()
		arch.radius = WHEEL_R + 0.07
		arch.height = w + 0.4
		arch.sides = 20
		arch.rotation.z = PI / 2.0
		arch.position = Vector3(0, WHEEL_Y, z)
		arch.operation = CSGShape3D.OPERATION_SUBTRACTION
		combiner.add_child(arch)

	# Cabin: glass greenhouse plus a painted roof cap.
	var cabin := CSGPolygon3D.new()
	cabin.polygon = PackedVector2Array([
		Vector2(-hl + 1.0, 1.0), Vector2(-0.8, 1.42), Vector2(0.35, 1.44), Vector2(hl - 1.4, 1.0),
	])
	cabin.depth = w - 0.16
	cabin.rotation.y = -PI / 2.0
	cabin.position.x = -(w - 0.16) / 2.0
	cabin.material = Kit.glass()
	root.add_child(cabin)
	var roof := CSGPolygon3D.new()
	roof.polygon = PackedVector2Array([
		Vector2(-0.85, 1.4), Vector2(-0.8, 1.46), Vector2(0.38, 1.47), Vector2(0.45, 1.41),
	])
	roof.depth = w - 0.14
	roof.rotation.y = -PI / 2.0
	roof.position.x = -(w - 0.14) / 2.0
	roof.material = body_mat
	root.add_child(roof)
	# Bumpers, grille, lights, mirrors, plate
	Kit.box(root, Vector3(w + 0.04, 0.22, 0.18), Vector3(0, 0.42, hl + 0.02), trim, false)
	Kit.box(root, Vector3(w + 0.04, 0.22, 0.18), Vector3(0, 0.42, -hl - 0.02), trim, false)
	Kit.box(root, Vector3(0.8, 0.16, 0.04), Vector3(0, 0.66, hl + 0.01), trim, false)
	for x in [w / 2.0 - 0.3, -w / 2.0 + 0.3]:
		Kit.box(root, Vector3(0.42, 0.13, 0.06), Vector3(x, 0.74, hl - 0.01), Color(1, 1, 0.9), false, 1.2)
		Kit.box(root, Vector3(0.4, 0.14, 0.06), Vector3(x, 0.84, -hl + 0.02), Color(0.85, 0.05, 0.05), false, 0.8)
		var mirror := Kit.box(root, Vector3(0.18, 0.12, 0.1), Vector3(signf(x) * (w / 2.0 + 0.08), 1.08, 0.7), body_mat, false)
		mirror.rotation.y = signf(x) * 0.2
	Kit.box(root, Vector3(0.5, 0.15, 0.02), Vector3(0, 0.55, -hl - 0.12), Color(0.95, 0.95, 0.9), false)
	Kit.box(root, Vector3(w - 0.1, 0.05, 0.03), Vector3(0, 0.62, hl - 0.15), trim, false)
	# Door seams and handles
	for x in [w / 2.0 + 0.003, -w / 2.0 - 0.003]:
		Kit.box(root, Vector3(0.01, 0.6, 0.02), Vector3(x, 0.68, 0.05), trim, false)
		Kit.box(root, Vector3(0.01, 0.6, 0.02), Vector3(x, 0.68, -1.0), trim, false)
		Kit.box(root, Vector3(0.02, 0.04, 0.16), Vector3(x, 0.86, -0.2), Color(0.7, 0.7, 0.72), false)
		Kit.box(root, Vector3(0.02, 0.04, 0.16), Vector3(x, 0.86, 0.6), Color(0.7, 0.7, 0.72), false)
	if rusty:
		var rust := Kit.mat(Color(0.42, 0.2, 0.08))
		Kit.box(root, Vector3(0.01, 0.25, 0.55), Vector3(w / 2.0 + 0.004, 0.55, -1.75), rust, false)
		Kit.box(root, Vector3(0.01, 0.2, 0.4), Vector3(-w / 2.0 - 0.004, 0.5, 1.8), rust, false)
		Kit.box(root, Vector3(0.6, 0.01, 0.4), Vector3(0.3, 1.01, -1.6), rust, false)
		Kit.box(root, Vector3(0.012, 0.5, 0.9), Vector3(-w / 2.0 - 0.006, 0.7, 0.5), Kit.mat(Color(0.55, 0.56, 0.6)), false)

	if with_wheels:
		for z in [WHEEL_Z, -WHEEL_Z]:
			for x in [w / 2.0 - 0.12, -w / 2.0 + 0.12]:
				var wheel := wheel_mesh()
				wheel.position = Vector3(x, WHEEL_Y, z)
				root.add_child(wheel)
	return root


static func wheel_mesh() -> Node3D:
	var n := Node3D.new()
	var tire := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = WHEEL_R
	cm.bottom_radius = WHEEL_R
	cm.height = 0.24
	cm.radial_segments = 24
	tire.mesh = cm
	tire.rotation.z = PI / 2.0
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.06, 0.06, 0.06)
	rubber.roughness = 0.9
	tire.material_override = rubber
	n.add_child(tire)
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = WHEEL_R * 0.62
	rm.bottom_radius = WHEEL_R * 0.62
	rm.height = 0.26
	rm.radial_segments = 16
	rim.mesh = rm
	rim.rotation.z = PI / 2.0
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.75, 0.76, 0.78)
	chrome.metallic = 0.9
	chrome.roughness = 0.25
	rim.material_override = chrome
	n.add_child(rim)
	# Spokes so you can see the wheels turn
	for i in 5:
		var spoke := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.27, 0.05, WHEEL_R * 1.1)
		spoke.mesh = sm
		spoke.material_override = chrome
		spoke.rotation.x = i * TAU / 5.0
		n.add_child(spoke)
	return n
