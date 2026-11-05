class_name Construction
extends Node3D
## Road work. Every day a couple of street blocks are closed for construction: barricades
## with flashing lamps and ROAD CLOSED / DETOUR signs at both ends, cones, a dug-up patch
## with an excavator, and a crew. You can't drive through, the GPS routes around them,
## AI traffic and police stop turning into them, and the closures show on the minimap.
## Only cross streets are closed (no addresses face them), so every door stays reachable.

const PER_DAY := 2
const END_GAP := 12.0        # barricade distance from the intersection center

var town: Node = null
var main: Node = null
var sites: Array = []        # {a, b (Vector2i intersections), node (Node3D), lamps: [material]}
var _closed := {}            # [a, b] (both orders) -> true
var _blink := 0.0
var _stripes: StandardMaterial3D


func build() -> void:
	Game.day_changed.connect(func(_d): pick_for_day(Game.day))
	pick_for_day(Game.day)


func is_closed(a: Vector2i, b: Vector2i) -> bool:
	return _closed.has([a, b])


## Closed roads as [[a, b], ...].
func closures() -> Array:
	return sites.map(func(s): return [s.a, s.b])


func clear() -> void:
	for s in sites:
		s.node.queue_free()
	sites.clear()
	_closed.clear()
	_sync()


## Picks today's closures (the same for a given day every time).
func pick_for_day(day: int) -> void:
	clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = day * 7919 + 13
	var cands := []
	var N: int = town.N
	for x in N + 1:
		for z in N:
			cands.append([Vector2i(x, z), Vector2i(x, z + 1)])
	var used := {}
	var tries := 0
	while sites.size() < PER_DAY and tries < 60:
		tries += 1
		var c: Array = cands[rng.randi() % cands.size()]
		if used.has(c[0]) or used.has(c[1]) or not _allowed(c[0], c[1]):
			continue
		used[c[0]] = true
		used[c[1]] = true
		close(c[0], c[1], false)
	_sync()
	if not sites.is_empty():
		var names := sites.map(func(s): return _describe(s.a, s.b))
		Game.notify("Road work today: %s. Expect detours." % " and ".join(names), "info")


## Not a road with a speed camera, and not one you're on right now.
func _allowed(a: Vector2i, b: Vector2i) -> bool:
	for spec in TrafficControl.SPEED_CAMERAS:
		if (spec[0] == a and spec[1] == b) or (spec[0] == b and spec[1] == a):
			return false
	if main:
		var pa := _pos(a)
		var pb := _pos(b)
		for p in [main.actor_position(), main.car.global_position]:
			var q := Geometry3D.get_closest_point_to_segment(Vector3(p.x, 0, p.z), pa, pb)
			if q.distance_to(Vector3(p.x, 0, p.z)) < 40.0:
				return false
	return true


func _describe(a: Vector2i, b: Vector2i) -> String:
	if a.x == b.x:
		return "%s closed between %s and %s" % [town.V_STREETS[a.x], town.H_STREETS[mini(a.y, b.y)], town.H_STREETS[maxi(a.y, b.y)]]
	return "%s closed between %s and %s" % [town.H_STREETS[a.y], town.V_STREETS[mini(a.x, b.x)], town.V_STREETS[maxi(a.x, b.x)]]


func _pos(n: Vector2i) -> Vector3:
	return Vector3(n.x * town.B, 0, n.y * town.B)


## Closes the road between intersections a and b and builds the work site.
func close(a: Vector2i, b: Vector2i, sync := true) -> void:
	_closed[[a, b]] = true
	_closed[[b, a]] = true
	var site := {"a": a, "b": b, "lamps": []}
	var root := Node3D.new()
	add_child(root)
	site.node = root
	var pa := _pos(a)
	var pb := _pos(b)
	var along := (pb - pa).normalized()
	_barricade(site, pa + along * END_GAP, -along)
	_barricade(site, pb - along * END_GAP, along)
	_work_zone(root, (pa + pb) / 2.0, along)
	_minimap_marker(root, (pa + pb) / 2.0)
	sites.append(site)
	if main and main.traffic:
		main.traffic.clear_segment(a, b)
	if sync:
		_sync()


## Tells the GPS which roads are closed.
func _sync() -> void:
	if main and main.gps:
		main.gps.set_closed(closures())


func _process(delta: float) -> void:
	_blink += delta
	var on := fmod(_blink, 1.0) < 0.5
	for s in sites:
		for i in s.lamps.size():
			var m: StandardMaterial3D = s.lamps[i]
			m.emission_energy_multiplier = 4.0 if on == (i % 2 == 0) else 0.2


func _stripe_mat() -> StandardMaterial3D:
	if _stripes:
		return _stripes
	var img := Image.create(64, 16, false, Image.FORMAT_RGB8)
	for x in 64:
		for y in 16:
			var orange := int(floor((x + y) / 8.0)) % 2 == 0
			img.set_pixel(x, y, Color(1.0, 0.45, 0.05) if orange else Color(0.95, 0.95, 0.92))
	_stripes = StandardMaterial3D.new()
	_stripes.albedo_texture = ImageTexture.create_from_image(img)
	_stripes.uv1_scale = Vector3(6, 1, 1)
	_stripes.roughness = 0.6
	return _stripes


## A barricade across the road at `pos`, its signs facing `out` (toward the intersection).
func _barricade(site: Dictionary, pos: Vector3, out: Vector3) -> void:
	var g := Node3D.new()
	site.node.add_child(g)
	g.global_transform = Transform3D(Basis(Vector3.UP.cross(out).normalized(), Vector3.UP, out), pos)
	var w: float = town.ROAD_W - 0.4
	for x in [-w / 2.0 + 0.2, w / 2.0 - 0.2, 0.0]:
		Kit.box(g, Vector3(0.1, 1.5, 0.1), Vector3(x, 0.75, 0), Color(0.9, 0.9, 0.88), false)
	for y in [0.45, 0.85, 1.25]:
		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, 0.22, 0.05)
		board.mesh = bm
		board.material_override = _stripe_mat()
		board.position = Vector3(0, y, 0.07)
		g.add_child(board)
	Kit.collider(g, Vector3(w, 1.5, 0.5), Vector3(0, 0.75, 0))
	# Sign in the middle, lamps on the ends.
	Kit.box(g, Vector3(2.6, 0.9, 0.04), Vector3(0, 2.05, 0.06), Color(0.96, 0.96, 0.94), false)
	var l := Kit.label(g, "ROAD CLOSED", Vector3(0, 2.2, 0.1), 56, Color(0.05, 0.05, 0.05))
	l.outline_size = 0
	l.double_sided = false
	Kit.box(g, Vector3(2.0, 0.42, 0.04), Vector3(0, 1.82, 0.085), Color(1.0, 0.5, 0.05), false)
	var d := Kit.label(g, "DETOUR", Vector3(0, 1.82, 0.12), 44, Color(0.05, 0.05, 0.05))
	d.outline_size = 0
	d.double_sided = false
	for x in [-w / 2.0 + 0.2, w / 2.0 - 0.2]:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.7, 0.1)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.65, 0.1)
		var lamp := Kit.sphere(g, 0.12, Vector3(x, 1.65, 0.05), m)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		site.lamps.append(m)
	# A taper of cones in front of it.
	for i in 5:
		var x := -w / 2.0 + 1.0 + i * (w - 2.0) / 4.0
		_cone(g, Vector3(x, 0, 2.2 + absf(i - 2) * 0.6))


func _cone(parent: Node3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.2
	cm.height = 0.7
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = Kit.mat(Color(1.0, 0.4, 0.05))
	mi.position = pos + Vector3(0, 0.35, 0)
	parent.add_child(mi)
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.1
	bm.bottom_radius = 0.125
	bm.height = 0.12
	bm.radial_segments = 10
	band.mesh = bm
	band.material_override = Kit.mat(Color(0.95, 0.95, 0.95))
	band.position = pos + Vector3(0, 0.42, 0)
	parent.add_child(band)
	Kit.box(parent, Vector3(0.42, 0.04, 0.42), pos + Vector3(0, 0.02, 0), Color(0.1, 0.1, 0.1), false)


## The dig in the middle: dirt, an excavator, pipes and a couple of workers.
func _work_zone(root: Node3D, center: Vector3, along: Vector3) -> void:
	var g := Node3D.new()
	root.add_child(g)
	g.global_transform = Transform3D(Basis(Vector3.UP.cross(along).normalized(), Vector3.UP, along), center)
	Kit.box(g, Vector3(6.0, 0.08, 14.0), Vector3(0, 0.06, 0), Color(0.38, 0.27, 0.17), false)
	Kit.box(g, Vector3(2.6, 0.9, 3.0), Vector3(-0.6, 0.45, -4.5), Color(0.33, 0.24, 0.15))   # dirt pile
	# Excavator: tracks, body, cab, boom.
	var ex := Node3D.new()
	ex.position = Vector3(1.0, 0, 2.5)
	ex.rotation.y = 0.5
	g.add_child(ex)
	var yellow := Color(0.95, 0.72, 0.1)
	for x in [-1.05, 1.05]:
		Kit.box(ex, Vector3(0.6, 0.7, 3.6), Vector3(x, 0.35, 0), Color(0.12, 0.12, 0.12), false)
	Kit.box(ex, Vector3(2.6, 1.0, 2.8), Vector3(0, 1.2, -0.2), yellow)
	Kit.box(ex, Vector3(1.1, 1.2, 1.2), Vector3(0.6, 2.3, 0.4), yellow, false)
	Kit.box(ex, Vector3(1.0, 0.8, 0.05), Vector3(0.6, 2.4, 1.01), Kit.glass(), false)
	var boom := Kit.box(ex, Vector3(0.35, 0.4, 3.2), Vector3(-0.5, 2.6, 2.2), yellow, false)
	boom.rotation.x = -0.55
	var stick := Kit.box(ex, Vector3(0.3, 0.3, 2.2), Vector3(-0.5, 2.3, 4.2), yellow, false)
	stick.rotation.x = 0.9
	Kit.box(ex, Vector3(0.9, 0.6, 0.6), Vector3(-0.5, 0.6, 4.9), Color(0.25, 0.25, 0.25), false)
	# Pipes waiting to go in.
	for i in 3:
		var pipe := Kit.cylinder(g, 0.3, 4.0, Vector3(-1.8 + i * 0.62, 0.32, -0.5), Color(0.55, 0.55, 0.58), false)
		pipe.rotation.x = PI / 2.0
	Kit.collider(g, Vector3(6.0, 1.5, 14.0), Vector3(0, 0.75, 0))
	# The crew, in hard hats.
	var spots := [Vector3(-2.0, 0, 3.8), Vector3(2.2, 0, -3.0)]
	for i in spots.size():
		var h := Humanoid.create("Worker")
		if h == null:
			break
		h.position = spots[i]
		h.rotation.y = 2.6 if i == 0 else -0.6
		g.add_child(h)
		Kit.sphere(h, 0.15, Vector3(0, 1.82, 0), Color(1.0, 0.85, 0.1)).scale = Vector3(1.1, 0.65, 1.2)
		h.animate(0.016, 0.0)


func _minimap_marker(root: Node3D, pos: Vector3) -> void:
	var m := Node3D.new()
	root.add_child(m)
	m.global_position = Vector3(pos.x, 98.0, pos.z)
	var disc := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(10, 0.5, 10)
	disc.mesh = bm
	disc.rotation.y = PI / 4.0
	disc.material_override = Kit.mat(Color(1.0, 0.45, 0.0), 0.8)
	disc.layers = 2
	m.add_child(disc)
	var l := Label3D.new()
	l.text = "ROAD\nWORK"
	l.font_size = 48
	l.pixel_size = 0.06
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position.y = 1.0
	l.layers = 2
	m.add_child(l)
