class_name Kit
extends RefCounted
## Tiny procedural building kit: boxes, labels, hollow buildings with doors you can walk through.

static var _mats := {}


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
static func box(parent: Node, size: Vector3, pos: Vector3, color: Color, collide := true, emission := 0.0) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(color, emission)
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


static func cylinder(parent: Node, radius: float, height: float, pos: Vector3, color: Color, collide := true) -> Node3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat(color)
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


static func sphere(parent: Node, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func label(parent: Node, text: String, pos: Vector3, font_size := 64, color := Color.WHITE, billboard := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.outline_size = maxi(6, font_size / 8)
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
static func hollow_building(parent: Node, size: Vector3, wall: Color, roof: Color,
		door_w := 2.6, door_h := 3.0, floor_color := Color(0.62, 0.56, 0.48), windows := true) -> Node3D:
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
	box(b, Vector3(w - 2 * t, 0.04, d - 2 * t), Vector3(0, 0.02, 0), floor_color, false)
	if windows and side_w > 3.0:
		var glass := Color(0.35, 0.55, 0.7)
		var ww := side_w - 1.6
		for sx in [-1.0, 1.0]:
			box(b, Vector3(ww, minf(2.2, h - 1.6), 0.06), Vector3(sx * (door_w / 2 + side_w / 2), 1.0 + minf(2.2, h - 1.6) / 2, d / 2 + 0.03), glass, false)
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
