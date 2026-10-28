class_name StripDistrict
extends RefCounted
## The Route 40 strip east of the beltway, along the curved Churchmans Loop (see Roads):
## a row of fast-food parodies, a couple of strip-mall shops, the Christiana Maul, and
## Churchmans Crossing, an apartment building you can walk into, with stairs and an
## elevator, so some deliveries go to an upstairs door.

const FLOOR_H := 3.4
const FAST_FOOD := [
	# name, brand color, accent, sign text
	["McDougal's", Color(0.85, 0.1, 0.08), Color(1.0, 0.8, 0.1), "M"],
	["Burger Monarch", Color(0.15, 0.3, 0.7), Color(1.0, 0.6, 0.15), "BM"],
	["Chick-Fil-Hey", Color(0.85, 0.08, 0.2), Color(1, 1, 1), "Hey!"],
	["Wendell's", Color(0.85, 0.12, 0.15), Color(1, 1, 1), "W"],
	["Pizza Hutch", Color(0.75, 0.1, 0.1), Color(0.15, 0.15, 0.15), "PH"],
	["Taco Bellhop", Color(0.45, 0.15, 0.6), Color(1.0, 0.75, 0.2), "TB"],
	["Domino Effect Pizza", Color(0.0, 0.4, 0.7), Color(0.9, 0.1, 0.2), "DE"],
	["Five Dudes Burgers", Color(0.8, 0.12, 0.12), Color(1, 1, 1), "5D"],
	["Pop-Eyed Chicken", Color(0.95, 0.45, 0.1), Color(1, 1, 1), "PE"],
	["Sub Way Out", Color(0.1, 0.5, 0.25), Color(1.0, 0.85, 0.1), "SW"],
]

var town: Node
var pts: PackedVector3Array
var total := 0.0


func build(t: Node) -> void:
	town = t
	var link: Dictionary = Roads.links(town.B, town.N)[0]
	pts = link.pts
	total = Roads.length(pts)
	_pavement()
	_buildings()


# --- Road ---------------------------------------------------------------------------

func _pavement() -> void:
	# Start where the grid street's pavement ends, just past the beltway.
	var s0: float = town.N * town.B + town.RING + 23.0 - pts[0].x
	var road := Roads.cut(pts, s0, total - s0)
	var hw: float = town.ROAD_W / 2.0
	_ribbon(road, -hw, hw, 0.043, 0.04, Kit.surf("asphalt"), false)
	_ribbon(road, -hw - town.WALK, -hw, 0.12, 0.12, Kit.surf("concrete"), true)
	_ribbon(road, hw, hw + town.WALK, 0.12, 0.12, Kit.surf("concrete"), true)
	# Double yellow center line and white edge lines, as short straight pieces.
	var yellow := []
	var white := []
	for i in road.size() - 1:
		var a := road[i]
		var b := road[i + 1]
		var d := (b - a)
		var seg := d.length()
		if seg < 0.05:
			continue
		var dir := d / seg
		var right := Vector3(-dir.z, 0, dir.x)
		var basis := Basis(right, Vector3.UP, dir).scaled(Vector3(1, 1, seg + 0.05))
		var mid := (a + b) / 2.0 + Vector3(0, 0.065, 0)
		for off in [-0.15, 0.15]:
			yellow.append(Transform3D(basis, mid + right * off))
		for off in [-hw + 0.4, hw - 0.4]:
			white.append(Transform3D(basis, mid + right * off))
	Kit.multibox(town, Vector3(0.12, 0.02, 1), yellow, Color(0.95, 0.75, 0.15))
	Kit.multibox(town, Vector3(0.14, 0.02, 1), white, Color(0.9, 0.9, 0.88))
	# Street lights every 45 m on the outside of the curve.
	var s := s0 + 20.0
	while s < total - s0 - 10.0:
		var smp := Roads.sample(pts, s)
		var p: Vector3 = smp[0]
		var right := Vector3(-smp[1].z, 0, smp[1].x)
		var base := p - right * (hw + 1.0)
		Kit.cylinder(town, 0.12, 6.0, base + Vector3(0, 3, 0), Color(0.25, 0.25, 0.27))
		var l := OmniLight3D.new()
		l.position = base + right * 0.8 + Vector3(0, 5.8, 0)
		l.omni_range = 22.0
		l.light_energy = 1.5
		l.light_color = Color(1.0, 0.85, 0.6)
		l.visible = false
		town.add_child(l)
		town._street_lights.append(l)
		s += 45.0


## A strip of surface between two sideways offsets of the center line (+ is right of the
## direction of travel), with its top at `y`. Raised strips (sidewalks) get curb faces and
## collision.
func _ribbon(line: PackedVector3Array, w0: float, w1: float, y: float, depth: float, mat: Material, collide: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left := Roads.offset(line, w0)
	var right := Roads.offset(line, w1)
	for i in line.size() - 1:
		var a0 := left[i] + Vector3(0, y, 0)
		var a1 := left[i + 1] + Vector3(0, y, 0)
		var b0 := right[i] + Vector3(0, y, 0)
		var b1 := right[i + 1] + Vector3(0, y, 0)
		_quad(st, a0, a1, b1, b0, Vector3.UP)
		if depth > 0.06:
			var dn := Vector3(0, -depth, 0)
			var out_l := (a0 - b0).normalized()
			_quad(st, a0 + dn, a1 + dn, a1, a0, out_l)
			_quad(st, b0, b1, b1 + dn, b0 + dn, -out_l)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	town.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		body.add_child(cs)
		town.add_child(body)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	# Two triangles, wound so they face `n`.
	var face := (b - a).cross(c - a)
	if face.dot(n) > 0.0:
		var tmp := b
		b = d
		d = tmp
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.add_vertex(v)


# --- Lots ---------------------------------------------------------------------------

## A lot facing the road at distance `s` along the loop. side +1: outside of the curve
## (left of travel), -1: inside. Like grid lots, +Z points at the road and the origin is
## 10 m from the center line.
func lot(s: float, side: int) -> Node3D:
	var smp := Roads.sample(pts, s)
	var p: Vector3 = smp[0]
	var dir: Vector3 = smp[1]
	var right := Vector3(-dir.z, 0, dir.x)
	var away := -right if side > 0 else right
	var n := Node3D.new()
	var z := -away
	n.transform = Transform3D(Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z), p + away * 10.0)
	town.add_child(n)
	return n


func _buildings() -> void:
	var first := 125.0
	var spacing := 27.0
	var k := 0
	var s := first
	var outside := []
	while s < total - first:
		outside.append(s)
		s += spacing
	# Fast food along the outside of the curve, shops after them.
	for i in outside.size():
		var l := lot(outside[i], 1)
		if k < FAST_FOOD.size():
			var f: Array = FAST_FOOD[k]
			town._restaurant(l, f[0], f[1])
			_pole_sign(l, f[3], f[1], f[2])
			k += 1
		else:
			var shop: Array = [["Dollar Dime", Color(0.2, 0.55, 0.3)], ["Mattress Firmament", Color(0.2, 0.3, 0.6)],
				["Cellfone Fix-It", Color(0.55, 0.2, 0.55)], ["Vape Escape", Color(0.3, 0.3, 0.35)]][(i - FAST_FOOD.size()) % 4]
			town._shop(l, shop[0], Vector3(14, 5, 12), shop[1])
	# Inside the curve: the apartment building at the far end, the mall in the middle.
	var apex := _apex_s()
	walkup(lot(apex, -1), "Churchmans Crossing", 4, "2400 Churchmans Loop")
	_mall()


## Distance along the loop of its easternmost point.
func _apex_s() -> float:
	var best := 0.0
	var best_x := -INF
	var s := 0.0
	while s < total:
		var x: float = Roads.sample(pts, s)[0].x
		if x > best_x:
			best_x = x
			best = s
		s += 4.0
	return best


func _pole_sign(l: Node3D, text: String, color: Color, accent: Color) -> void:
	var p := Vector3(-9.5, 0, 1.0)
	Kit.cylinder(l, 0.18, 8.0, p + Vector3(0, 4.0, 0), Color(0.55, 0.55, 0.58))
	Kit.box(l, Vector3(3.4, 2.2, 0.4), p + Vector3(0, 8.6, 0), color, false, 0.4)
	for face in [1.0, -1.0]:
		var lb := Kit.label(l, text, p + Vector3(0, 8.6, face * 0.22), 260, accent)
		lb.outline_size = 0
		if face < 0:
			lb.rotation.y = PI


func _mall() -> void:
	var c := Vector3(pts[0].x + 150.0, 0, (pts[0].z + pts[pts.size() - 1].z) / 2.0)
	var m := Node3D.new()
	m.position = c
	town.add_child(m)
	# Parking lot, the building, a sign.
	Kit.box(m, Vector3(80, 0.05, 110), Vector3(0, 0.03, 0), Kit.surf("asphalt", Color(0.75, 0.75, 0.78)), false)
	var lines := []
	for row in [-30.0, 30.0]:
		for i in 18:
			lines.append(Transform3D(Basis.IDENTITY, Vector3(row, 0.06, -42.0 + i * 5.0)))
	Kit.multibox(m, Vector3(5.0, 0.02, 0.12), lines, Color(0.9, 0.9, 0.88))
	Kit.box(m, Vector3(36, 9, 60), Vector3(-2, 4.5, 0), Kit.surf("stucco", Color(0.85, 0.8, 0.72)))
	Kit.box(m, Vector3(37, 1.2, 61), Vector3(-2, 9.2, 0), Color(0.6, 0.2, 0.2), false)
	var lb := Kit.label(m, "CHRISTIANA MAUL", Vector3(16.2, 6.5, 0), 220, Color(1, 0.95, 0.85))
	lb.rotation.y = PI / 2.0
	Kit.box(m, Vector3(0.3, 3.0, 8.0), Vector3(16.1, 1.5, 0), Kit.glass(), false)


# --- Walk-up apartments -----------------------------------------------------------

## An apartment building you can go inside: a lobby with an elevator and a stairwell, and
## four apartments (A-D) on every floor above the lobby. Each door is a delivery address.
func walkup(l: Node3D, bname: String, floors: int, street: String) -> void:
	var w := 24.0
	var d := 18.0
	var h := floors * FLOOR_H
	var b := Node3D.new()
	b.position = Vector3(0, 0, -(6.0 + d / 2.0))
	l.add_child(b)
	var walls := Kit.surf("brick")
	var t := 0.3
	# Outer walls (front wall has the lobby door).
	Kit.box(b, Vector3(w, h, t), Vector3(0, h / 2.0, -d / 2.0 + t / 2.0), walls)
	Kit.box(b, Vector3(t, h, d), Vector3(-w / 2.0 + t / 2.0, h / 2.0, 0), walls)
	Kit.box(b, Vector3(t, h, d), Vector3(w / 2.0 - t / 2.0, h / 2.0, 0), walls)
	var door_w := 2.6
	var side_w := (w - door_w) / 2.0
	for sx in [-1.0, 1.0]:
		Kit.box(b, Vector3(side_w, h, t), Vector3(sx * (door_w + side_w) / 2.0, h / 2.0, d / 2.0 - t / 2.0), walls)
	Kit.box(b, Vector3(door_w, h - 3.0, t), Vector3(0, 3.0 + (h - 3.0) / 2.0, d / 2.0 - t / 2.0), walls)
	Kit.box(b, Vector3(w + 0.4, 0.4, d + 0.4), Vector3(0, h + 0.2, 0), Kit.surf("concrete", Color(0.7, 0.7, 0.7)))
	Kit.box(b, Vector3(w - 0.6, 0.04, d - 0.6), Vector3(0, 0.02, 0), Kit.surf("tile", Color(0.85, 0.83, 0.8)), false)
	# Windows on the front and sides of every floor.
	var panes := []
	for f in floors:
		for i in 6:
			var x := -w / 2.0 + 2.0 + i * (w - 4.0) / 5.0
			if f == 0 and absf(x) < 3.0:
				continue
			panes.append(Transform3D(Basis.IDENTITY, Vector3(x, 1.8 + f * FLOOR_H, d / 2.0 + 0.03)))
		for sx in [-1.0, 1.0]:
			for i in 3:
				panes.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(sx * (w / 2.0 + 0.03), 1.8 + f * FLOOR_H, -5.0 + i * 5.0)))
	Kit.multibox(b, Vector3(1.6, 1.5, 0.06), panes, Kit.glass())
	Kit.label(b, bname, Vector3(0, 3.6, d / 2.0 + 0.1), 90, Color(1, 0.95, 0.8))
	Kit.box(b, Vector3(4.0, 0.25, 2.0), Vector3(0, 3.1, d / 2.0 + 1.0), Color(0.3, 0.12, 0.1), false)
	Kit.box(l, Vector3(2.6, 0.05, 6.2), Vector3(0, 0.035, -3.0), Kit.surf("concrete"), false)

	# Stairwell on the right: one straight flight per floor, alternating lanes, so each
	# flight starts where the last one ended.
	var run := 6.6
	var flights := []
	town.walkups.append({"node": b, "name": bname, "floors": floors, "flights": flights})
	var z_lo := -4.6
	var lanes := [7.2, 9.6]    # lane center x
	for f in floors:
		# Slab for this floor (f > 0), with a hole over the flight that arrives here.
		if f > 0:
			var y := f * FLOOR_H
			var lane_x: float = lanes[(f - 1) % 2]
			_slab_with_hole(b, w - 2.0 * t, d - 2.0 * t, y, Rect2(lane_x - 1.2, z_lo, 2.4, run))
		if f < floors - 1:
			var lane: float = lanes[f % 2]
			var up_z := f % 2 == 0     # even floors climb toward +z
			var y0 := f * FLOOR_H
			var fa := Vector3(lane, y0, z_lo if up_z else z_lo + run)
			var fc := Vector3(lane, y0 + FLOOR_H, z_lo + run if up_z else z_lo)
			_flight(b, fa, fc)
			flights.append([fa, fc])
	var stairs_sign := Kit.label(b, "STAIRS", Vector3(8.4, 2.6, z_lo - 0.6), 48, Color(1, 1, 1))
	stairs_sign.rotation.y = PI   # reads from the lobby side

	# Elevator by the front left corner, one call button per floor.
	var addr_floor := []
	for f in floors:
		var y := f * FLOOR_H
		var ep := Vector3(-w / 2.0 + 2.2, y, d / 2.0 - 3.0)
		Kit.box(b, Vector3(2.0, 2.4, 0.15), ep + Vector3(0, 1.2, -1.2), Color(0.7, 0.72, 0.75), false)
		Kit.label(b, "ELEVATOR", ep + Vector3(0, 2.7, -1.1), 40, Color(1, 1, 1))
		var floor_i: int = f
		Kit.interactable(b, ep + Vector3(0, 1, 0), 1.8,
			func(): return "Take the elevator (floor %d)" % (floor_i + 1),
			func(): _elevator_menu(b, bname, floors, floor_i, w, d))
		# Ceiling light for this floor.
		var light := OmniLight3D.new()
		light.position = Vector3(0, y + FLOOR_H - 0.5, 0)
		light.omni_range = 13.0
		light.light_energy = 1.2
		light.light_color = Color(1.0, 0.95, 0.85)
		b.add_child(light)
		if f == 0:
			continue
		# Apartment doors along the back wall.
		var letters := ["A", "B", "C", "D"]
		for i in 4:
			var x := -9.0 + i * 4.6
			var door_z := -d / 2.0 + t
			Kit.box(b, Vector3(1.1, 2.2, 0.08), Vector3(x, y + 1.1, door_z + 0.04), Color(0.45, 0.3, 0.2), false)
			Kit.label(b, "%d%s" % [f + 1, letters[i]], Vector3(x, y + 2.5, door_z + 0.1), 40, Color(1, 0.95, 0.8))
			addr_floor.append([Vector3(x, y, door_z + 0.8), "%s Apt %d%s (%s)" % [bname, f + 1, letters[i], street], f + 1])
	for a in addr_floor:
		var local_door: Vector3 = b.position + a[0]
		var addr: Dictionary = town._register_address(l, a[1], local_door)
		addr["floor"] = a[2]


func _elevator_menu(b: Node3D, bname: String, floors: int, here: int, w: float, d: float) -> void:
	var opts := []
	for f in floors:
		if f == here:
			continue
		var target_f: int = f
		opts.append({"text": "Lobby" if f == 0 else "Floor %d" % (f + 1), "cb": func():
			var p := b.to_global(Vector3(-w / 2.0 + 2.2, target_f * FLOOR_H + 0.2, d / 2.0 - 4.4))
			town.main.player.global_position = p
			town.main.player.velocity = Vector3.ZERO
			Sfx.play(town.main, "ping", -6.0)})
	town.main.hud.show_menu("%s elevator" % bname, opts)


## A floor slab at height y (top surface) with a rectangular hole (x, z, width, depth).
func _slab_with_hole(b: Node3D, w: float, d: float, y: float, hole: Rect2) -> void:
	var th := 0.25
	var cy := y - th / 2.0
	var x0 := -w / 2.0
	var x1 := w / 2.0
	var z0 := -d / 2.0
	var z1 := d / 2.0
	var hx0 := hole.position.x
	var hx1 := hole.position.x + hole.size.x
	var hz0 := hole.position.y
	var hz1 := hole.position.y + hole.size.y
	var mat := Kit.surf("tile", Color(0.8, 0.78, 0.74))
	# Left of the hole, right of the hole, and in front of / behind it.
	_slab_box(b, x0, hx0, z0, z1, cy, th, mat)
	_slab_box(b, hx1, x1, z0, z1, cy, th, mat)
	_slab_box(b, hx0, hx1, z0, hz0, cy, th, mat)
	_slab_box(b, hx0, hx1, hz1, z1, cy, th, mat)


func _slab_box(b: Node3D, xa: float, xb: float, za: float, zb: float, cy: float, th: float, mat: Material) -> void:
	if xb - xa < 0.05 or zb - za < 0.05:
		return
	Kit.box(b, Vector3(xb - xa, th, zb - za), Vector3((xa + xb) / 2.0, cy, (za + zb) / 2.0), mat)


## One flight of stairs from `a` (bottom, floor level) to `c` (top): a smooth ramp you
## walk on, with steps drawn over it.
func _flight(b: Node3D, a: Vector3, c: Vector3) -> void:
	var span := c - a
	var flat := Vector3(span.x, 0, span.z)
	var length := span.length()
	var dir := span / length
	var th := 0.2
	var side := Vector3.UP.cross(flat.normalized())
	var up := dir.cross(side).normalized()
	if up.y < 0.0:
		up = -up
	var ramp := Kit.box(b, Vector3(2.2, th, length + 0.1), (a + c) / 2.0 - up * th / 2.0, Kit.surf("concrete", Color(0.75, 0.75, 0.75)))
	ramp.basis = Basis(up.cross(dir), up, dir)
	var steps := []
	var n := 17
	for i in n:
		var tpos := a + flat * (float(i) + 0.5) / n + Vector3(0, FLOOR_H * (float(i) + 0.5) / n, 0)
		steps.append(Transform3D(Basis.looking_at(flat.normalized(), Vector3.UP), tpos))
	Kit.multibox(b, Vector3(2.2, 0.2, flat.length() / n + 0.02), steps, Color(0.62, 0.62, 0.64))
