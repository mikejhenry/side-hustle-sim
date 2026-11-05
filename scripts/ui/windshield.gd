class_name Windshield
extends Control
## Rain drops and snowflakes on the windshield in first person. They build up while it rains
## or snows (faster when you drive), get pushed up the glass by the wind at speed, and the
## wipers clear them (see Dashboard.cycle_wipers).
##
## Drops live on the glass itself: each has a spot on the windshield (meters across and down),
## and is drawn where that spot appears on screen, so they stay on the glass as you look
## around and never cover the dashboard or side windows.

const MAX_DROPS := 260
var car: Car
var drops: Array = []      # [Vector2 spot on the glass (m), radius (m), life, snow?]
var _last_angle := 0.0
var _rng := RandomNumberGenerator.new()
var _glass := Vector2(1.4, 0.5)     # width and (slanted) height of the glass, meters
var _corners := PackedVector2Array()  # on screen: top-left, top-right, bottom-right, bottom-left


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()


func showing() -> bool:
	return car != null and car.driver_active and not car.chase_cam


## How covered the glass is, 0..1 (tests use it).
func coverage() -> float:
	return drops.size() / float(MAX_DROPS)


func _process(delta: float) -> void:
	visible = showing()
	if car == null:
		return
	var c := car.windshield_corners()
	_glass = Vector2((c[0] as Vector3).distance_to(c[1]) * 0.5 + (c[2] as Vector3).distance_to(c[3]) * 0.5, (c[0] as Vector3).distance_to(c[3]))
	var snow := car.snow_amount()
	var wet := car.wet_amount()
	var spd := car.linear_velocity.length()
	# New drops: more in a storm, and more when you drive into the rain.
	var rate := (wet * 45.0 + snow * 22.0) * (1.0 + spd / 15.0)
	var count := int(rate * delta + _rng.randf())
	if not showing():
		count = 0
	for i in count:
		if drops.size() >= MAX_DROPS:
			break
		var is_snow := snow > 0.0 and _rng.randf() < snow / (snow + wet + 0.001)
		var r := _rng.randf_range(0.004, 0.011) if not is_snow else _rng.randf_range(0.004, 0.008)
		drops.append([Vector2(_rng.randf() * _glass.x, _rng.randf() * _glass.y), r, 1.0, is_snow])
	# Drops creep up the glass at speed, slide down when stopped, and dry out (or melt).
	var drift := (-0.012 * clampf((spd - 8.0) / 15.0, 0.0, 1.0) if spd > 8.0 else 0.002) * delta
	var dry := delta * (0.02 if wet + snow > 0.1 else 0.25)
	for d in drops:
		if not d[3]:
			d[0].y += drift * (d[1] / 0.007)
		d[2] -= dry
	var h := _glass.y
	drops = drops.filter(func(d): return d[2] > 0.0 and d[0].y > -0.01 and d[0].y < h + 0.01)
	_wipe()
	_project(c)
	queue_redraw()


func _project(c: Array) -> void:
	_corners.clear()
	if not showing():
		return
	var cam := car.fp_camera
	for p in c:
		var w := car.to_global(p)
		if cam.is_position_behind(w):
			_corners.clear()
			return
		_corners.append(cam.unproject_position(w))


## Where a spot on the glass (meters across, meters down) is on screen.
func _to_screen(p: Vector2) -> Vector2:
	var u := p.x / _glass.x
	var v := p.y / _glass.y
	var top := _corners[0].lerp(_corners[1], u)
	var bottom := _corners[3].lerp(_corners[2], u)
	return top.lerp(bottom, v)


## Screen pixels per meter of glass near a spot.
func _px_per_m(p: Vector2) -> float:
	var v := clampf(p.y / _glass.y, 0.0, 1.0)
	var top := _corners[0].distance_to(_corners[1])
	var bottom := _corners[3].distance_to(_corners[2])
	return lerpf(top, bottom, v) / _glass.x


## The two blades pivot just below the glass and sweep up and to the left.
func _blades() -> Array:
	return [[Vector2(_glass.x * 0.27, _glass.y * 1.04), _glass.y * 0.98], [Vector2(_glass.x * 0.64, _glass.y * 1.04), _glass.y * 0.82]]


func _blade_angle(a: float) -> float:
	# Parked: lying along the bottom of the glass, pointing right. Fully up: up and to the left.
	return lerpf(-0.08, -PI * 0.8, a)


func _wipe() -> void:
	if car.dash == null:
		return
	var a := car.dash.wiper_angle()
	var a0 := _blade_angle(_last_angle)
	var a1 := _blade_angle(a)
	_last_angle = a
	if absf(a1 - a0) < 0.0001:
		return
	var lo := minf(a0, a1) - 0.03
	var hi := maxf(a0, a1) + 0.03
	var blades := _blades()
	drops = drops.filter(func(d):
		for b in blades:
			var rel: Vector2 = d[0] - b[0]
			var ang := rel.angle()
			if rel.length() < b[1] and ang >= lo and ang <= hi:
				return false
		return true)


func _draw() -> void:
	if _corners.size() != 4:
		return
	for d in drops:
		var p := _to_screen(d[0])
		var r: float = d[1] * _px_per_m(d[0])
		var k: float = clampf(d[2] * 3.0, 0.0, 1.0)
		if d[3]:
			draw_circle(p, r, Color(1, 1, 1, 0.8 * k))
			draw_circle(p + Vector2(r * 0.6, -r * 0.3), r * 0.6, Color(0.95, 0.97, 1.0, 0.65 * k))
		else:
			# A bead of water: a faint lens, a bright glint up top and a lighter crescent below.
			draw_circle(p, r, Color(0.78, 0.84, 0.9, 0.2 * k))
			draw_arc(p, r * 0.8, 0.4, PI - 0.4, 10, Color(0.95, 0.97, 1.0, 0.35 * k), maxf(1.0, r * 0.25))
			draw_circle(p + Vector2(-r * 0.3, -r * 0.4), maxf(1.0, r * 0.22), Color(1, 1, 1, 0.75 * k))
	if car.dash and car.dash.wiper_phase > 0.0:
		var ang := _blade_angle(car.dash.wiper_angle())
		for b in _blades():
			var dir := Vector2.from_angle(ang)
			var pts := PackedVector2Array()
			for i in 9:
				pts.append(_to_screen(b[0] + dir * b[1] * (0.1 + 0.9 * i / 8.0)))
			draw_polyline(pts, Color(0.03, 0.03, 0.03, 0.95), maxf(3.0, 0.012 * _px_per_m(b[0] + dir * b[1] * 0.5)))
