class_name GpsScreen
extends Control
## What the phone on the windshield mount shows: the next turn and its distance on the left,
## and a heading-up map of the nearby streets with your route on the right. Drawn into a
## small SubViewport that Dashboard puts on the phone's screen.

const MAP_SCALE := 0.55     # pixels per meter
var car: Car


func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.07, 0.08, 0.1))
	var font := ThemeDB.fallback_font
	if Game.phone_battery <= 0.0:
		draw_string(font, Vector2(0, sz.y / 2.0 + 6), "Battery dead", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 20, Color(0.5, 0.5, 0.55))
		return
	var main: Node = car.main if car else null
	var gps: GPS = main.gps if main else null
	var left := 150.0
	_draw_map(Rect2(left, 0, sz.x - left, sz.y), gps)
	# Left panel: next turn.
	draw_rect(Rect2(0, 0, left, sz.y), Color(0.05, 0.25, 0.5))
	if gps and gps.instruction != "":
		_draw_arrow(Vector2(left / 2.0, 44), gps.turn)
		var dist := gps.distance_text if gps.distance_text != "" else ""
		if dist != "":
			draw_string(font, Vector2(0, 104), dist, HORIZONTAL_ALIGNMENT_CENTER, left, 26, Color.WHITE)
		draw_multiline_string(font, Vector2(6, 124 if dist != "" else 100), gps.instruction, HORIZONTAL_ALIGNMENT_CENTER, left - 12, 13, 3, Color(0.85, 0.93, 1.0))
	else:
		draw_string(font, Vector2(0, 70), "Wayz", HORIZONTAL_ALIGNMENT_CENTER, left, 28, Color.WHITE)
		draw_multiline_string(font, Vector2(8, 96), "No route. Accept a job or pick a place in Maps.", HORIZONTAL_ALIGNMENT_CENTER, left - 16, 13, 3, Color(0.8, 0.88, 1.0))
	# Status bar.
	draw_rect(Rect2(left, sz.y - 22, sz.x - left, 22), Color(0, 0, 0, 0.6))
	var mph := int(car.speed_mph()) if car else 0
	draw_string(font, Vector2(left + 8, sz.y - 6), "%d mph" % mph, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	draw_string(font, Vector2(left, sz.y - 6), Game.time_string(), HORIZONTAL_ALIGNMENT_RIGHT, sz.x - left - 8, 14, Color(0.85, 0.85, 0.9))


func _draw_map(r: Rect2, gps: GPS) -> void:
	draw_rect(r, Color(0.16, 0.22, 0.16))
	if car == null:
		return
	var center := r.position + Vector2(r.size.x / 2.0, r.size.y * 0.68)
	var p := car.global_position
	var f := car.global_basis.z
	var yaw := atan2(f.x, f.z)
	var to_screen := func(w: Vector3) -> Vector2:
		var d := Vector2(w.x - p.x, w.z - p.z).rotated(yaw)
		# Heading up: forward is screen up; the car's left (+X) is screen left.
		return center + Vector2(-d.x, -d.y) * MAP_SCALE
	var reach := r.size.length() / MAP_SCALE
	if gps:
		if gps._edges.is_empty() and gps.town:
			gps._build_graph()
		for e in gps._edges:
			var pts: PackedVector3Array = e.pts
			var near := false
			for q in pts:
				if Vector2(q.x - p.x, q.z - p.z).length() < reach:
					near = true
					break
			if not near:
				continue
			var line := PackedVector2Array()
			for q in pts:
				line.append(to_screen.call(q))
			draw_polyline(line, Color(0.42, 0.44, 0.46), 9.0)
		if gps.route.size() > 1:
			var rl := PackedVector2Array()
			for q in gps.route:
				rl.append(to_screen.call(q))
			draw_polyline(rl, GPS.ROUTE_COLOR, 5.0)
	# You.
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -11), center + Vector2(-8, 8), center + Vector2(0, 4), center + Vector2(8, 8)]), Color(1, 0.9, 0.2))


func _draw_arrow(c: Vector2, turn: String) -> void:
	var white := Color.WHITE
	var w := 8.0
	match turn:
		"left", "right":
			var s := -1.0 if turn == "left" else 1.0
			draw_polyline(PackedVector2Array([c + Vector2(-s * 8, 28), c + Vector2(-s * 8, -4), c + Vector2(-s * 2, -10), c + Vector2(s * 12, -10)]), white, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 28, -10), c + Vector2(s * 10, -25), c + Vector2(s * 10, 5)]), white)
		"uturn":
			draw_line(c + Vector2(10, -12), c + Vector2(10, 28), white, w)
			draw_arc(c + Vector2(-2, -12), 12.0, PI, TAU, 16, white, w)
			draw_line(c + Vector2(-14, -12), c + Vector2(-14, 8), white, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-14, 24), c + Vector2(-27, 6), c + Vector2(-1, 6)]), white)
		"arrive":
			draw_circle(c + Vector2(0, -6), 16.0, white)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-13, 3), c + Vector2(13, 3), c + Vector2(0, 26)]), white)
			draw_circle(c + Vector2(0, -6), 6.0, Color(0.05, 0.25, 0.5))
		_:
			draw_line(c + Vector2(0, 28), c + Vector2(0, -8), white, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -28), c + Vector2(-15, -7), c + Vector2(15, -7)]), white)
