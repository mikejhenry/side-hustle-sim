class_name GPS
extends Node3D
## Turn-by-turn navigation on the road network (the street grid plus curved roads). Builds a route from the player to the
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
# The road network is a graph: grid intersections are nodes, and every road between two of
# them is an edge with its own center line (straight for the grid, curved for the links
# in Roads). Routes snap you and the target onto the nearest edge and search between them,
# with a small penalty per turn so routes prefer fewer, simpler turns.

const TURN_PENALTY := 25.0

var _edges: Array = []        # {a, b (Vector2i), pts (PackedVector3Array a -> b), len, name}
var _adj := {}                # Vector2i -> [edge index]
var _names := PackedStringArray()   # road name for each route segment (route[i] -> route[i+1])


func _build_graph() -> void:
	_edges.clear()
	_adj.clear()
	var N: int = town.N
	for x in N + 1:
		for z in N + 1:
			var n := Vector2i(x, z)
			if x < N:
				_add_edge(n, n + Vector2i(1, 0), PackedVector3Array([_node_pos(n), _node_pos(n + Vector2i(1, 0))]), town.H_STREETS[z])
			if z < N:
				_add_edge(n, n + Vector2i(0, 1), PackedVector3Array([_node_pos(n), _node_pos(n + Vector2i(0, 1))]), town.V_STREETS[x])
	for l in Roads.links(town.B, N):
		_add_edge(l.from, l.to, l.pts, l.name)


func _add_edge(a: Vector2i, b: Vector2i, pts: PackedVector3Array, road: String) -> void:
	var i := _edges.size()
	_edges.append({"a": a, "b": b, "pts": pts, "len": Roads.length(pts), "name": road})
	for n in [a, b]:
		if not _adj.has(n):
			_adj[n] = []
		_adj[n].append(i)


## Nearest point on any road: {point, edge, s (distance along the edge from its start)}
func _snap(p: Vector3) -> Dictionary:
	if _edges.is_empty():
		_build_graph()
	var best := {}
	var best_d := INF
	for ei in _edges.size():
		var pts: PackedVector3Array = _edges[ei].pts
		var acc := 0.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ab := b - a
			var seg := ab.length()
			var t := clampf((p - a).dot(ab) / maxf(seg * seg, 0.0001), 0.0, 1.0)
			var q := a + ab * t
			var d := q.distance_to(p)
			if d < best_d:
				best_d = d
				best = {"point": q, "edge": ei, "s": acc + seg * t}
			acc += seg
	return best


func _node_pos(n: Vector2i) -> Vector3:
	var B: float = town.B
	return Vector3(n.x * B, 0, n.y * B)


## Edge center line oriented to start at node `from`.
func _edge_from(ei: int, from: Vector2i) -> PackedVector3Array:
	var e: Dictionary = _edges[ei]
	return e.pts if e.a == from else Roads.reversed(e.pts)


func _dir_at(pts: PackedVector3Array, at_end: bool) -> Vector3:
	if at_end:
		return (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
	return (pts[1] - pts[0]).normalized()


func _compute_route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var sa := _snap(from)
	var sb := _snap(to)
	var pts: Array = [from]
	var names: Array = [""]
	var ea: Dictionary = _edges[sa.edge]
	var eb: Dictionary = _edges[sb.edge]
	if sa.edge == sb.edge:
		var piece: PackedVector3Array
		if sa.s <= sb.s:
			piece = Roads.cut(ea.pts, sa.s, sb.s)
		else:
			piece = Roads.reversed(Roads.cut(ea.pts, sb.s, sa.s))
		for q in piece:
			pts.append(q)
			names.append(ea.name)
	else:
		var path := _search(sa, sb)
		# Along the first edge from the snap point to the node we leave it by.
		var first: Vector2i = path[0]
		var lead: PackedVector3Array
		if first == ea.b:
			lead = Roads.cut(ea.pts, sa.s, ea.len)
		else:
			lead = Roads.reversed(Roads.cut(ea.pts, 0.0, sa.s))
		for q in lead:
			pts.append(q)
			names.append(ea.name)
		for k in range(1, path.size(), 2):
			var ei: int = path[k]
			var poly := _edge_from(ei, path[k - 1])
			for i in range(1, poly.size()):
				pts.append(poly[i])
				names.append(_edges[ei].name)
		var last: Vector2i = path[path.size() - 1]
		var tail: PackedVector3Array
		if last == eb.a:
			tail = Roads.cut(eb.pts, 0.0, sb.s)
		else:
			tail = Roads.reversed(Roads.cut(eb.pts, sb.s, eb.len))
		for i in range(1, tail.size()):
			pts.append(tail[i])
			names.append(eb.name)
	pts.append(to)
	names.append("")
	# names[i] is the road leading INTO pts[i]; turn it into the road leaving pts[i].
	var clean: Array = []
	var clean_names: Array = []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var nm: String = names[i + 1] if i + 1 < names.size() else ""
		if not clean.is_empty() and clean.back().distance_to(p) <= 0.5:
			continue
		clean.append(p)
		clean_names.append(nm)
	var out := PackedVector3Array()
	_names = PackedStringArray()
	for i in clean.size():
		if i > 0 and i < clean.size() - 1:
			var d1: Vector3 = (clean[i] - clean[i - 1]).normalized()
			var d2: Vector3 = (clean[i + 1] - clean[i]).normalized()
			if d1.dot(d2) > 0.9995 and clean_names[i] == _names[_names.size() - 1]:
				continue
		out.append(clean[i])
		_names.append(clean_names[i])
	return out


## Dijkstra over (node, edge we arrived by), so turns can cost extra. Returns
## [node, edge, node, edge, ..., node] from an end of the start edge to an end of the goal edge.
func _search(sa: Dictionary, sb: Dictionary) -> Array:
	var ea: Dictionary = _edges[sa.edge]
	var eb: Dictionary = _edges[sb.edge]
	var dist := {}
	var prev := {}
	var open: Array = []    # [cost, node, edge]
	for start in [[ea.a, sa.s], [ea.b, ea.len - sa.s]]:
		var key := [start[0], sa.edge]
		dist[key] = start[1]
		open.append([start[1], start[0], sa.edge])
	var goal_cost := {eb.a: sb.s, eb.b: eb.len - sb.s}
	var best_key = null
	var best_total := INF
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if open[i][0] < open[bi][0]:
				bi = i
		var cur: Array = open[bi]
		open.remove_at(bi)
		var cost: float = cur[0]
		var node: Vector2i = cur[1]
		var via: int = cur[2]
		if cost > dist.get([node, via], INF) + 0.001 or cost >= best_total:
			continue
		if goal_cost.has(node):
			var total: float = cost + goal_cost[node]
			# Arriving on the goal edge from the other side of a node is a turn too.
			if via != sb.edge:
				total += _turn_cost(via, node, sb.edge)
			if total < best_total:
				best_total = total
				best_key = [node, via]
		for ei in _adj.get(node, []):
			if ei == via:
				continue
			var e: Dictionary = _edges[ei]
			var other: Vector2i = e.b if e.a == node else e.a
			var c: float = cost + e.len + _turn_cost(via, node, ei)
			var key := [other, ei]
			if c < dist.get(key, INF):
				dist[key] = c
				prev[key] = [node, via]
				open.append([c, other, ei])
	# Walk back to the start edge.
	var out: Array = []
	var k = best_key
	while k != null:
		out.push_front(k[0])
		var pk = prev.get(k, null)
		if pk == null:
			break
		out.push_front(k[1])
		k = pk
	return out


func _turn_cost(in_edge: int, node: Vector2i, out_edge: int) -> float:
	var d_in := _dir_at(_edge_from(in_edge, _other_end(in_edge, node)), true)
	var d_out := _dir_at(_edge_from(out_edge, node), false)
	return 0.0 if d_in.dot(d_out) > 0.7 else TURN_PENALTY


func _other_end(ei: int, n: Vector2i) -> Vector2i:
	var e: Dictionary = _edges[ei]
	return e.b if e.a == n else e.a


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
		var b3 := Basis(side * 5.0, Vector3.UP, dir * (seg_len + 5.0))
		xforms.append(Transform3D(b3, mid))
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
			var road: String = _names[i] if i < _names.size() else ""
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
