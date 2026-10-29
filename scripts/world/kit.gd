class_name Kit
extends RefCounted
## Tiny procedural building kit: boxes, labels, hollow buildings with doors you can walk through.

static var _mats := {}


## Texture size in meters for each generated surface (see tools/gen_textures.py).
const SURFACES := {
	"asphalt": [3.0, 0.9], "concrete": [1.8, 0.85], "grass": [3.0, 0.95], "brick": [1.2, 0.85],
	"siding": [2.0, 0.7], "shingles": [5.0, 0.9], "stucco": [2.0, 0.9], "tile": [2.0, 0.35],
	"wood": [1.7, 0.6], "gravel": [2.2, 0.95], "leaves": [1.6, 0.8], "bark": [1.0, 0.95],
}
static var _glass: StandardMaterial3D


## Textured PBR material, mapped in world space so any box size tiles correctly.
static func surf(kind: String, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "surf|%s|%s" % [kind, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var spec: Array = SURFACES[kind]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(kind, "albedo")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = _tex(kind, "normal")
	m.roughness = spec[1]
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / float(spec[0])
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


## Photo-scanned Poly Haven textures are .jpg; the procedurally generated ones are .png.
static func _tex(kind: String, map: String) -> Texture2D:
	var base := "res://assets/textures/%s_%s" % [kind, map]
	return load(base + ".jpg") if ResourceLoader.exists(base + ".jpg") else load(base + ".png")


static func glass() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.albedo_color = Color(0.12, 0.17, 0.22)
		_glass.metallic = 0.6
		_glass.roughness = 0.08
		_glass.metallic_specular = 0.9
	return _glass


static func _resolve(c, emission := 0.0) -> Material:
	if c is Material:
		return c
	return mat(c, emission)


static func mat(c: Color, emission := 0.0) -> StandardMaterial3D:
	var key := "%s|%s" % [c.to_html(), emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


## Adds a box. With collide=true it is a StaticBody3D you can bump into.
static func box(parent: Node, size: Vector3, pos: Vector3, color, collide := true, emission := 0.0) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _resolve(color, emission)
	if not collide:
		mi.position = pos
		parent.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.add_child(mi)
	parent.add_child(body)
	return body


static func cylinder(parent: Node, radius: float, height: float, pos: Vector3, color, collide := true) -> Node3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = _resolve(color)
	if not collide:
		mi.position = pos
		parent.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	body.add_child(cs)
	body.add_child(mi)
	parent.add_child(body)
	return body


static func sphere(parent: Node, radius: float, pos: Vector3, color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = _resolve(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func label(parent: Node, text: String, pos: Vector3, font_size := 64, color := Color.WHITE, billboard := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.outline_size = maxi(6, int(font_size / 8.0))
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.position = pos
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	parent.add_child(l)
	return l


static func interactable(parent: Node, pos: Vector3, radius: float, prompt: Callable, action: Callable, in_car := false) -> Interactable:
	var i := Interactable.new()
	i.position = pos
	i.radius = radius
	i.prompt = prompt
	i.action = action
	i.in_car = in_car
	parent.add_child(i)
	return i


## Hollow building, origin at ground center, front (with a door gap) facing local +Z.
static func hollow_building(parent: Node, size: Vector3, wall, roof,
		door_w := 2.6, door_h := 3.0, floor_color = null, windows := true) -> Node3D:
	var b := Node3D.new()
	parent.add_child(b)
	var w := size.x
	var h := size.y
	var d := size.z
	var t := 0.3
	box(b, Vector3(w, h, t), Vector3(0, h / 2, -d / 2 + t / 2), wall)
	box(b, Vector3(t, h, d), Vector3(-w / 2 + t / 2, h / 2, 0), wall)
	box(b, Vector3(t, h, d), Vector3(w / 2 - t / 2, h / 2, 0), wall)
	var side_w := (w - door_w) / 2.0
	box(b, Vector3(side_w, h, t), Vector3(-(door_w / 2 + side_w / 2), h / 2, d / 2 - t / 2), wall)
	box(b, Vector3(side_w, h, t), Vector3(door_w / 2 + side_w / 2, h / 2, d / 2 - t / 2), wall)
	if h > door_h:
		box(b, Vector3(door_w, h - door_h, t), Vector3(0, door_h + (h - door_h) / 2, d / 2 - t / 2), wall)
	box(b, Vector3(w + 0.4, 0.3, d + 0.4), Vector3(0, h + 0.15, 0), roof)
	box(b, Vector3(w - 2 * t, 0.04, d - 2 * t), Vector3(0, 0.02, 0), floor_color if floor_color != null else surf("tile", Color(0.9, 0.88, 0.84)), false)
	if windows and side_w > 3.0:
		var ww := side_w - 1.6
		var wh := minf(2.2, h - 1.6)
		for sx in [-1.0, 1.0]:
			var cx: float = sx * (door_w / 2 + side_w / 2)
			box(b, Vector3(ww, wh, 0.06), Vector3(cx, 1.0 + wh / 2, d / 2 + 0.03), glass(), false)
			box(b, Vector3(ww + 0.2, 0.12, 0.14), Vector3(cx, 1.0 + wh + 0.06, d / 2 + 0.06), Color(0.15, 0.15, 0.16), false)
			box(b, Vector3(ww + 0.3, 0.1, 0.25), Vector3(cx, 0.95, d / 2 + 0.1), Color(0.15, 0.15, 0.16), false)
		# door frame
		box(b, Vector3(0.15, door_h, 0.2), Vector3(-door_w / 2 - 0.07, door_h / 2, d / 2 + 0.02), Color(0.15, 0.15, 0.16), false)
		box(b, Vector3(0.15, door_h, 0.2), Vector3(door_w / 2 + 0.07, door_h / 2, d / 2 + 0.02), Color(0.15, 0.15, 0.16), false)
	# cornice trim
	box(b, Vector3(w + 0.3, 0.3, 0.3), Vector3(0, h - 0.15, d / 2 + 0.05), Color(0.85, 0.83, 0.78), false)
	# Ceiling lights on a grid with short range so they don't spill outside through the walls.
	var nx := maxi(1, int(round(w / 10.0)))
	var nz := maxi(1, int(round(d / 10.0)))
	var r := minf(7.0, minf(w / nx, d / nz) * 0.75 + 1.5)
	for ix in nx:
		for iz in nz:
			var light := OmniLight3D.new()
			light.position = Vector3(-w / 2.0 + (ix + 0.5) * w / nx, minf(h - 0.6, 3.6), -d / 2.0 + (iz + 0.5) * d / nz)
			light.omni_range = r
			light.omni_attenuation = 1.6
			light.light_energy = 1.4
			light.light_color = Color(1.0, 0.95, 0.85)
			b.add_child(light)
			box(b, Vector3(1.2, 0.06, 0.4), light.position + Vector3(0, 0.45, 0) if h - 0.6 > 3.6 else Vector3(light.position.x, h - 0.05, light.position.z), Color(1, 1, 0.9), false, 2.0)
	return b


## Flat glowing beacon used for GPS targets (visible on the minimap too).
static func beacon(color: Color) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 0.6
	cm.height = 60.0
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.position = Vector3(0, 30, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.4
	tm.outer_radius = 1.8
	ring.mesh = tm
	ring.material_override = mat(color, 2.0)
	ring.position = Vector3(0, 0.15, 0)
	root.add_child(ring)
	var dot := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 7.0
	dm.bottom_radius = 7.0
	dm.height = 0.2
	dot.mesh = dm
	dot.material_override = mat(color, 1.0)
	dot.position = Vector3(0, 60, 0)
	dot.layers = 2   # minimap only
	root.add_child(dot)
	return root


## Many identical boxes in one draw call (lane dashes, window panes, crosswalks).
static func multibox(parent: Node, size: Vector3, transforms: Array, color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = size
	mm.mesh = bm
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _resolve(color)
	parent.add_child(mmi)
	return mmi


## A leafy tree: textured trunk plus a few overlapping foliage blobs.
## Quaternius tree models (CC0) and their native heights in meters; missing files are skipped.
const TREE_MODELS := {"CommonTree_1": 0.0, "CommonTree_2": 0.0, "CommonTree_3": 0.0, "BirchTree_1": 3.57, "PineTree_1": 2.7}
static var _tree_scenes: Array = []


static func _tree_models() -> Array:
	if _tree_scenes.is_empty():
		for n in TREE_MODELS:
			var path := "res://assets/quaternius/%s.fbx" % n
			if ResourceLoader.exists(path):
				_tree_scenes.append(load(path))
	return _tree_scenes


static func tree(parent: Node, pos: Vector3, scale := 1.0, leaf_tint := Color(0.35, 0.55, 0.25)) -> void:
	var models := _tree_models()
	if not models.is_empty():
		# Pick a model from the position so the town looks the same every time.
		var h := absi(int(pos.x * 7.0) * 31 + int(pos.z * 13.0))
		var t: Node3D = models[h % models.size()].instantiate()
		t.position = pos
		t.rotation.y = float(h % 360) * PI / 180.0
		t.scale = Vector3.ONE * scale * (2.0 + float(h % 5) * 0.15)
		parent.add_child(t)
		return
	var t := Node3D.new()
	t.position = pos
	parent.add_child(t)
	cylinder(t, 0.22 * scale, 3.2 * scale, Vector3(0, 1.6 * scale, 0), surf("bark"))
	var leaves := surf("leaves", leaf_tint)
	var blobs := [Vector3(0, 4.0, 0), Vector3(0.9, 3.5, 0.3), Vector3(-0.8, 3.6, -0.4), Vector3(0.2, 4.6, -0.6), Vector3(-0.3, 3.3, 0.9)]
	var radii := [1.7, 1.2, 1.3, 1.1, 1.1]
	for i in blobs.size():
		var s := sphere(t, radii[i] * scale, blobs[i] * scale, leaves)
		s.scale = Vector3(1.0, 0.85, 1.0)


static func _name_has_any(n: String, list: String) -> bool:
	for part in list.split(","):
		if part.strip_edges() in n:
			return true
	return false


## A solid invisible box to bump into (for props whose meshes have no collision).
static func collider(parent: Node, size: Vector3, pos: Vector3, rot_y := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body


static func bush(parent: Node, pos: Vector3, scale := 1.0) -> void:
	if ResourceLoader.exists("res://assets/quaternius/Bush_1.fbx"):
		var b: Node3D = load("res://assets/quaternius/Bush_1.fbx").instantiate()
		b.position = pos
		b.rotation.y = fposmod(pos.x * 1.7 + pos.z, TAU)
		b.scale = Vector3.ONE * scale * 0.9
		parent.add_child(b)
		return
	var s := sphere(parent, 0.7 * scale, pos + Vector3(0, 0.45 * scale, 0), surf("leaves", Color(0.3, 0.5, 0.22)))
	s.scale = Vector3(1.3, 0.8, 1.0)


## Places a Poly Haven model (assets/models/<name>/<name>.gltf). Variant meshes whose names
## contain `drop` (for example "rust" or "aged") are removed, and the rest is centered on
## `pos` with its base on the ground. These are real scanned props (CC0).
## `keep`: only meshes whose names contain one of these (comma separated). `vis`: stop
## drawing it past this many meters (small props and interiors don't need to be seen from
## across town, which keeps the Iris Xe fast).
static func prop(parent: Node, name: String, pos: Vector3, rot_y := 0.0, drop := "", scale := 1.0,
		keep := "", vis := 0.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	root.scale = Vector3.ONE * scale
	parent.add_child(root)
	var model: Node3D = load("res://assets/models/%s/%s.gltf" % [name, name]).instantiate()
	root.add_child(model)
	var box := AABB()
	var first := true
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if drop != "" and drop in String(mi.name) or keep != "" and not _name_has_any(String(mi.name), keep):
			mi.get_parent().remove_child(mi)
			mi.queue_free()
			continue
		if vis > 0.0:
			mi.visibility_range_end = vis
			mi.visibility_range_end_margin = 2.0
		var ab: AABB = (model.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb() if mi.is_inside_tree() else mi.transform * mi.get_aabb()
		box = ab if first else box.merge(ab)
		first = false
	var c := box.get_center()
	model.position = Vector3(-c.x, -box.position.y, -c.z)
	return root
