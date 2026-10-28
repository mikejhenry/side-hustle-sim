class_name GPS
extends Node3D
## Turn-by-turn navigation on the street grid. Builds a route from the player to the
## current target, draws it on the minimap (render layer 2 only) and produces the
## next-turn instruction shown on the HUD.

const LINE_Y := 45.0
const ROUTE_COLOR := Color(0.2, 0.6, 1.0)

var town: Node = null
var route := PackedVector3Array()
var instruction := ""      # e.g. "Turn left onto Market St"
var distance_text := ""    # e.g. "0.3 mi"
var turn := "straight"     # straight, left, right, uturn, arrive
var _line: MultiMeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = ROUTE_COLOR
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func clear() -> void:
	route = PackedVector3Array()
	instruction = ""
	distance_text = ""
	if _line:
		_line.visible = false


## Recomputes the route and instruction. heading = direction the player is facing/driving.
func update(from: Vector3, heading: Vector3, target: Vector3, label: String, driving: bool) -> void:
	route = _compute_route(Vector3(from.x, 0, from.z), Vector3(target.x, 0, target.z))
	_draw_route()
	_make_instruction(from, heading, label, driving)


# --- Routing ---------------------------------------------------------------------

func _road_name(a: Vector3, b: Vector3) -> String:
	var B: float = town.B
	if absf(a.z - b.z) < 0.5:
		var k := roundi(a.z / B)
		if absf(a.z - k * B) < 1.0 and k >= 0 and k < town.H_STREETS.size():
			return town.H_STREETS[k]
	elif absf(a.x - b.x) < 0.5:
		var k := roundi(a.x / B)
		if absf(a.x - k * B) < 1.0 and k >= 0 and k < town.V_STREETS.size():
			return town.V_STREETS[k]
	return ""


## Nearest point on the street grid: {point, horizontal: bool, ends: [Vector2i, Vector2i]}
func _snap(p: Vector3) -> Dictionary:
	var B: float = town.B
	var N: int = town.N
	var best := {}
	var best_d := INF
	for k in N + 1:
		var x := clampf(p.x, 0.0, N * B)
		var q := Vector3(x, 0, k * B)
		var d := q.distance_to(p)
		if d < best_d:
			best_d = d
			var i := clampi(int(floor(x / B)), 0, N - 1)
			best = {"point": q, "horizontal": true, "ends": [Vector2i(i, k), Vector2i(i + 1, k)]}
		var z := clampf(p.z, 0.0, N * B)
		q = Vector3(k * B, 0, z)
		d = q.distance_to(p)
		if d < best_d:
			best_d = d
			var j := clampi(int(floor(z / B)), 0, N - 1)
			best = {"point": q, "horizontal": false, "ends": [Vector2i(k, j), Vector2i(k, j + 1)]}
	return best


func _node_pos(n: Vector2i) -> Vector3:
	var B: float = town.B
	return Vector3(n.x * B, 0, n.y * B)


func _compute_route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := _snap(from)
	var b := _snap(to)
	var pts: Array = [from, a.point]
	var same_road: bool = a.horizontal == b.horizontal and (
		(a.horizontal and absf(a.point.z - b.point.z) < 0.5) or (not a.horizontal and absf(a.point.x - b.point.x) < 0.5))
	if same_road:
		pts.append(b.point)
	else:
		var best_cost := INF
		var best_path: Array = []
		for s in a.ends:
			for t in b.ends:
				var sp := _node_pos(s)
				var tp := _node_pos(t)
				var cost: float = a.point.distance_to(sp) + absf(sp.x - tp.x) + absf(sp.z - tp.z) + tp.distance_to(b.point)
				if cost < best_cost - 0.01:
					best_cost = cost
					# Keep going along the road we start on, then turn once.
					var corner := Vector3(tp.x, 0, sp.z) if a.horizontal else Vector3(sp.x, 0, tp.z)
					best_path = [sp, corner, tp]
		pts.append_array(best_path)
		pts.append(b.point)
	pts.append(to)
	# Drop duplicate and collinear points.
	var clean: Array = []
	for p in pts:
		if clean.is_empty() or clean.back().distance_to(p) > 0.5:
			clean.append(p)
	var out := PackedVector3Array()
	for i in clean.size():
		if i > 0 and i < clean.size() - 1:
			var d1: Vector3 = (clean[i] - clean[i - 1]).normalized()
			var d2: Vector3 = (clean[i + 1] - clean[i]).normalized()
			if d1.dot(d2) > 0.999:
				continue
		out.append(clean[i])
	return out


func _draw_route() -> void:
	var xforms := []
	for i in route.size() - 1:
		var a := route[i]
		var b := route[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len < 0.1:
			continue
		var mid := (a + b) / 2.0 + Vector3(0, LINE_Y, 0)
		var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var side := Vector3.UP.cross(dir)
		var basis := Basis(side * 5.0, Vector3.UP, dir * (seg_len + 5.0))
		xforms.append(Transform3D(basis, mid))
	if _line == null:
		_line = Kit.multibox(self, Vector3(1, 0.5, 1), [], _mat)
		_line.layers = 2
		_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := _line.multimesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	_line.visible = xforms.size() > 0


# --- Instructions ----------------------------------------------------------------

func _fmt(meters: float) -> String:
	var miles := meters / GameData.METERS_PER_MILE
	if miles >= 0.1:
		return "%.1f mi" % miles
	var feet := int(round(meters * 5280.0 / GameData.METERS_PER_MILE / 50.0)) * 50
	return "%d ft" % maxi(feet, 50)


func _make_instruction(from: Vector3, heading: Vector3, label: String, driving: bool) -> void:
	var total := 0.0
	for i in route.size() - 1:
		total += route[i].distance_to(route[i + 1])
	if total < 18.0 or route.size() < 2:
		turn = "arrive"
		instruction = "Arrived: " + label
		distance_text = ""
		return
	# Skip the tiny hop from the player onto the road.
	var start := 0
	if route.size() > 2 and route[0].distance_to(route[1]) < 12.0:
		start = 1
	var first_dir := (route[start + 1] - route[start]).normalized()
	var flat_heading := Vector3(heading.x, 0, heading.z).normalized()
	if driving and flat_heading.dot(first_dir) < -0.5:
		turn = "uturn"
		instruction = "Make a U-turn"
		distance_text = ""
		return
	var dist := from.distance_to(route[start])
	for i in range(start + 1, route.size()):
		dist += route[i - 1].distance_to(route[i]) if i - 1 >= start else 0.0
		if i == route.size() - 1:
			turn = "arrive"
			instruction = "%s ahead" % label
			distance_text = _fmt(dist)
			return
		var d_in := (route[i] - route[i - 1]).normalized()
		var d_out := (route[i + 1] - route[i]).normalized()
		if d_in.dot(d_out) < 0.7:
			var right := Vector3(-d_in.z, 0, d_in.x)
			var dir := "right" if d_out.dot(right) > 0.0 else "left"
			var road := _road_name(route[i], route[i + 1])
			distance_text = _fmt(dist)
			turn = dir
			if road == "":
				instruction = "Destination on your %s" % dir
			else:
				instruction = "Turn %s onto %s" % [dir, road]
			return
	turn = "straight"
	instruction = "Continue straight"
	distance_text = _fmt(dist)
