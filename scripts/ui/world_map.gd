class_name WorldMap
extends Control
## A drawn map of the whole town: streets and the beltway, the curved Churchmans Loop, an
## icon for every place you can go, your position and heading, the GPS route, and where it
## leads. Click (or tap) an icon to set the GPS there. Used by the phone's Maps app and the
## full map in the pause menu (G / D-pad right).

signal place_picked(place: Dictionary)

## kind -> [legend name, icon text, color]
const KINDS := {
	"food": ["Restaurants", "F", Color(0.95, 0.5, 0.15)],
	"grocery": ["Grocery stores", "S", Color(0.25, 0.7, 0.3)],
	"gas": ["Gas station", "$", Color(0.85, 0.2, 0.2)],
	"mechanic": ["Mechanic", "M", Color(0.45, 0.55, 0.7)],
	"cars": ["Car lots", "C", Color(0.15, 0.65, 0.65)],
	"flex": ["Jungle Flex station", "J", Color(0.8, 0.65, 0.2)],
	"housing": ["Housing for rent", "R", Color(0.6, 0.4, 0.75)],
	"restroom": ["Restroom", "WC", Color(0.4, 0.65, 0.9)],
	"home": ["Your home", "H", Color(1.0, 0.85, 0.2)],
}

var main: Node = null
var show_street_names := true

var _scale := 1.0
var _origin := Vector2.ZERO        # world (x, z) at the top-left corner
var _hover := {}
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_font = get_theme_default_font()
	resized.connect(queue_redraw)


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


## Everything the map shows fits this world rectangle (x, z).
func _bounds() -> Rect2:
	var town: Node = main.town
	var size: float = town.B * town.N
	var ring: float = main.town.RING
	var r := Rect2(-ring - 15.0, -ring - 15.0, size + 2.0 * ring + 30.0, size + 2.0 * ring + 30.0)
	for e in _edges():
		for p in e.pts:
			r = r.expand(Vector2(p.x + 25.0, p.z + 25.0))
	return r


func _edges() -> Array:
	var gps: Node = main.gps
	if gps._edges.is_empty():
		gps._build_graph()
	return gps._edges


func _fit() -> void:
	var b := _bounds()
	_scale = minf(size.x / b.size.x, size.y / b.size.y)
	# Center the town in the control.
	_origin = b.position - (size / _scale - b.size) / 2.0


func to_map(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.z) - _origin) * _scale


func places() -> Array:
	var out: Array = []
	for p in main.town.places:
		out.append(p)
	if Game.home_id != "" and main.town.homes.has(Game.home_id):
		var hd: Dictionary = main.town.homes[Game.home_id]
		out.append({"name": "Home", "pos": hd.door, "kind": "home"})
	return out


func _draw() -> void:
	if main == null or main.town == null or size.x < 20.0 or size.y < 20.0:
		return
	_fit()
	var town: Node = main.town
	var B: float = town.B
	var N: int = town.N
	var ring: float = main.town.RING
	var size_m := B * N
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.36, 0.52, 0.32))
	# Town blocks a little lighter than the countryside.
	draw_rect(Rect2(to_map(Vector3(-ring, 0, -ring)), Vector2(size_m + 2 * ring, size_m + 2 * ring) * _scale), Color(0.42, 0.56, 0.38))
	var road_w := maxf(2.0, 14.0 * _scale)
	var street := Color(0.82, 0.82, 0.8)
	var edge := Color(0.25, 0.25, 0.25)
	# Grid streets run out to the beltway.
	var lines: Array = []
	for i in N + 1:
		lines.append([Vector3(i * B, 0, -ring), Vector3(i * B, 0, size_m + ring)])
		lines.append([Vector3(-ring, 0, i * B), Vector3(size_m + ring, 0, i * B)])
	var curves: Array = []
	for e in _edges():
		if e.pts.size() > 2:
			curves.append(e.pts)
	# Outlines first, then fill, so crossings look clean.
	for pass_i in 2:
		var w := road_w + (2.0 if pass_i == 0 else 0.0)
		var c := edge if pass_i == 0 else street
		for l in lines:
			draw_line(to_map(l[0]), to_map(l[1]), c, w)
		for pts in curves:
			var poly := PackedVector2Array()
			for p in pts:
				poly.append(to_map(p))
			draw_polyline(poly, c, w)
	# I-95 beltway.
	var hw := Color(0.95, 0.75, 0.3)
	var corners := [Vector3(-ring, 0, -ring), Vector3(size_m + ring, 0, -ring), Vector3(size_m + ring, 0, size_m + ring), Vector3(-ring, 0, size_m + ring)]
	for i in 4:
		draw_line(to_map(corners[i]), to_map(corners[(i + 1) % 4]), edge, road_w * 1.4 + 2.0)
	for i in 4:
		draw_line(to_map(corners[i]), to_map(corners[(i + 1) % 4]), hw, road_w * 1.4)
	if show_street_names and _scale > 0.6:
		_street_names(town, B, N, ring)
	# GPS route.
	var route: PackedVector3Array = main.gps.route
	if route.size() > 1:
		var rp := PackedVector2Array()
		for p in route:
			rp.append(to_map(p))
		draw_polyline(rp, Color(0.1, 0.45, 1.0), maxf(3.0, road_w * 0.45))
	# Place icons.
	var r := clampf(9.0 * _scale, 7.0, 13.0)
	var fs := int(r * 1.15)
	_hover = {}
	var mouse := get_local_mouse_position()
	for p in places():
		var k: Array = KINDS.get(p.get("kind", ""), ["", "?", Color(0.6, 0.6, 0.6)])
		var at := to_map(p.pos)
		draw_circle(at, r + 1.5, Color(0, 0, 0, 0.6))
		draw_circle(at, r, k[2])
		_text_centered(k[1], at, fs if k[1].length() == 1 else int(fs * 0.75), Color.WHITE)
		if at.distance_to(mouse) < r + 3.0:
			_hover = p
	# Where the GPS is taking you.
	var t: Dictionary = main.nav_target()
	if not t.is_empty():
		_pin(to_map(t.pos), Color(0.95, 0.15, 0.2))
	# You.
	_player_arrow(to_map(main.actor_position()), main.actor_heading(), r)
	if not _hover.is_empty():
		_tooltip(_hover.name, to_map(_hover.pos) + Vector2(0, -r - 8))


func _street_names(town: Node, B: float, N: int, ring: float) -> void:
	var c := Color(0.1, 0.1, 0.1, 0.85)
	var fs := 12
	for i in N + 1:
		_text_centered(town.H_STREETS[i], to_map(Vector3(B * 0.5, 0, i * B)) + Vector2(0, -1), fs, c)
		draw_set_transform(to_map(Vector3(i * B, 0, B * 1.5)), -PI / 2.0)
		_text_centered(town.V_STREETS[i], Vector2.ZERO, fs, c)
		draw_set_transform(Vector2.ZERO)
	_text_centered("I-95 Beltway", to_map(Vector3(B * N * 0.5, 0, -ring)), fs, c)
	_text_centered("Churchmans Loop", to_map(Vector3(B * N + 190.0, 0, B * 2.0)), fs, c)


func _text_centered(text: String, at: Vector2, fs: int, color: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(_font, at + Vector2(-w.x / 2.0, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _tooltip(text: String, at: Vector2) -> void:
	var fs := 14
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var box := Rect2(at - Vector2(w.x / 2.0 + 6, fs + 4), Vector2(w.x + 12, fs + 8))
	box.position.x = clampf(box.position.x, 2.0, size.x - box.size.x - 2.0)
	box.position.y = maxf(box.position.y, 2.0)
	draw_rect(box, Color(0.05, 0.05, 0.08, 0.9))
	draw_string(_font, box.position + Vector2(6, fs + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _pin(at: Vector2, color: Color) -> void:
	var tip := at
	var head := at + Vector2(0, -16)
	draw_colored_polygon(PackedVector2Array([tip, head + Vector2(-6, 2), head + Vector2(6, 2)]), color)
	draw_circle(head, 7.0, color)
	draw_circle(head, 3.0, Color.WHITE)


func _player_arrow(at: Vector2, heading: float, r: float) -> void:
	var f := Vector2(sin(heading), cos(heading))
	var side := Vector2(-f.y, f.x)
	var s := r * 1.2
	var pts := PackedVector2Array([at + f * s * 1.2, at - f * s * 0.7 + side * s * 0.8, at - f * s * 0.3, at - f * s * 0.7 - side * s * 0.8])
	var outline := PackedVector2Array()
	for p in pts:
		outline.append(at + (p - at) * 1.3)
	draw_colored_polygon(outline, Color(0, 0, 0, 0.7))
	draw_colored_polygon(pts, Color(1, 0.92, 0.1))


func _gui_input(event: InputEvent) -> void:
	var press := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		press = true
	elif event is InputEventScreenTouch and event.pressed:
		press = true
	if not press:
		return
	_fit()
	var at: Vector2 = event.position
	var best := {}
	var best_d := 18.0
	for p in places():
		var d := to_map(p.pos).distance_to(at)
		if d < best_d:
			best_d = d
			best = p
	if not best.is_empty():
		place_picked.emit(best)
		accept_event()


## A legend: one row per kind of place.
static func legend(parent: Control, columns := 1, font_size := 14) -> void:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	var rows: Array = []
	for k in KINDS:
		rows.append([KINDS[k][1], KINDS[k][2], KINDS[k][0]])
	rows.append(["▲", Color(1, 0.92, 0.1), "You"])
	rows.append(["●", Color(0.95, 0.15, 0.2), "GPS destination"])
	rows.append(["—", Color(0.1, 0.45, 1.0), "GPS route"])
	for row in rows:
		var l := Label.new()
		l.text = "%s  %s" % [row[0], row[2]]
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", row[1])
		grid.add_child(l)
