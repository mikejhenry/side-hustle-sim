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
	if data.has("model") and ResourceLoader.exists(data.model):
		return _from_model(data, with_wheels)
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



# --- Real car models (glTF) ----------------------------------------------------------
# data.model: the glTF file. data.model_axes: how the file is oriented, as the car-space
# direction of its x, y and z axes (forward is +Z, up is +Y). data.model_length: meters,
# bumper to bumper. The model's tire and rim meshes are cut into four wheels so the
# drivable car can spin and steer them; build() stores them in the root's "wheels" meta:
# [{node (Node3D centered on the hub), center (Vector3), radius}].


static func _from_model(data: Dictionary, with_wheels: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "CarModel"
	var holder := Node3D.new()
	root.add_child(holder)
	var scene: Node3D = load(data.model).instantiate()
	holder.add_child(scene)
	var axes: Array = data.get("model_axes", [Vector3.RIGHT, Vector3.UP, Vector3.BACK])
	var basis := Basis(axes[0], axes[1], axes[2])
	# Size: measure, then scale to the real length.
	var meshes: Array = []
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		meshes.append(n)
	var box := _bounds(scene, meshes, Transform3D(basis, Vector3.ZERO))
	var k: float = data.get("model_length", 4.0) / maxf(box.size.z, 0.01)
	var xf := Transform3D(basis.scaled(Vector3.ONE * k), Vector3.ZERO)
	# Wheels: split the tire and rim meshes into four by corner.
	var wheel_tris := {}      # corner key -> SurfaceTool per material
	var wheel_meshes: Array = []
	for mi in meshes:
		var mat: Material = (mi as MeshInstance3D).get_active_material(0)
		var mname := mat.resource_name if mat else ""
		if mname.contains("tire") or mname.contains("rim") or mname.contains("wheel"):
			wheel_meshes.append(mi)
	var corners := {}         # key -> {lo, hi, parts: [[ArrayMesh arrays, material]]}
	for mi in wheel_meshes:
		var m: MeshInstance3D = mi
		var to_car: Transform3D = xf * _rel(scene, m)
		for surf in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(surf)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				for i in verts.size():
					idx.append(i)
			var per: Dictionary = {}
			for t in range(0, idx.size(), 3):
				var a := to_car * verts[idx[t]]
				var b := to_car * verts[idx[t + 1]]
				var c := to_car * verts[idx[t + 2]]
				var ctr := (a + b + c) / 3.0
				var key := "%d%d" % [1 if ctr.x > 0.0 else 0, 1 if ctr.z > 0.0 else 0]
				if not per.has(key):
					per[key] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array()]
				for j in 3:
					var vi := idx[t + j]
					per[key][0].append(to_car * verts[vi])
					per[key][1].append((to_car.basis * norms[vi]).normalized() if not norms.is_empty() else Vector3.UP)
					per[key][2].append(uvs[vi] if not uvs.is_empty() else Vector2.ZERO)
			for key in per:
				if not corners.has(key):
					corners[key] = {"lo": Vector3.INF, "hi": -Vector3.INF, "parts": []}
				var cdata: Dictionary = corners[key]
				for v in per[key][0]:
					cdata.lo = cdata.lo.min(v)
					cdata.hi = cdata.hi.max(v)
				cdata.parts.append([per[key], m.get_active_material(surf)])
		m.visible = false
	# Place the body: centered, tires touching y = 0.
	var hub_y := 0.0
	var tire_r := 0.0
	var count := 0
	for key in corners:
		hub_y += (corners[key].lo.y + corners[key].hi.y) / 2.0
		tire_r += (corners[key].hi.y - corners[key].lo.y) / 2.0
		count += 1
	hub_y = hub_y / count if count > 0 else 0.0
	tire_r = tire_r / count if count > 0 else WHEEL_R
	box = _bounds(scene, meshes, xf)
	var shift := Vector3(-(box.position.x + box.size.x / 2.0), tire_r - hub_y, -(box.position.z + box.size.z / 2.0))
	holder.transform = Transform3D(xf.basis, shift)
	var wheels: Array = []
	for key in corners:
		var cdata: Dictionary = corners[key]
		var center: Vector3 = (cdata.lo + cdata.hi) / 2.0
		var radius: float = (cdata.hi.y - cdata.lo.y) / 2.0
		var hub := Node3D.new()
		for part in cdata.parts:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			var local := PackedVector3Array()
			for v in part[0][0]:
				local.append(v - center)
			arrays[Mesh.ARRAY_VERTEX] = local
			arrays[Mesh.ARRAY_NORMAL] = part[0][1]
			arrays[Mesh.ARRAY_TEX_UV] = part[0][2]
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var wmi := MeshInstance3D.new()
			wmi.mesh = am
			wmi.material_override = part[1]
			hub.add_child(wmi)
		wheels.append({"node": hub, "center": center + shift, "radius": radius})
		if with_wheels:
			hub.position = center + shift
			root.add_child(hub)
	root.set_meta("wheels", wheels)
	root.set_meta("size", box.size)
	return root


## Transform of `n` in the space `top` sits in, including top's own transform (works
## outside the scene tree).
static func _rel(top: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		if cur == top:
			break
		cur = cur.get_parent()
	return t


static func _bounds(top: Node3D, meshes: Array, xf: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in meshes:
		var m: MeshInstance3D = mi
		var mat: Material = m.get_active_material(0)
		if mat and mat.resource_name.contains("shadow"):
			continue
		var ab: AABB = (xf * _rel(top, m)) * m.get_aabb()
		box = ab if first else box.merge(ab)
		first = false
	return box
