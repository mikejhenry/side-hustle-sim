class_name HUD
extends CanvasLayer
## Heads-up display: money/clock, need bars, car gauges, prompts, toasts, minimap, menus.

var main: Node = null
var menu_open := false
var help_open := false

var _money: Label
var _clock: Label
var _bills: Label
var _bars := {}
var _prompt: Label
var _objective: Label
var _toasts: VBoxContainer
var _nav: PanelContainer
var _nav_arrow: Control
var _nav_text: Label
var _nav_dist: Label
var _nav_turn := "straight"
var _drive: PanelContainer
var _speed: Label
var _fuel: ProgressBar
var _car_warn: Label
var _menu: PanelContainer
var _menu_title: Label
var _menu_list: VBoxContainer
var _fade: ColorRect
var _fade_label: Label
var _drowsy: ColorRect
var _help: PanelContainer
var _mm_cam: Camera3D
var _mm_marker: MeshInstance3D
var _limit: Label
var _police: PanelContainer
var _police_label: Label
var _mirrors := {}          # "rear" / "left" / "right" -> PanelContainer holding a TextureRect
var _mirrors_shown := false

const TOAST_COLORS := {
	"info": Color(0.9, 0.92, 1.0), "good": Color(0.55, 1.0, 0.6), "warn": Color(1.0, 0.85, 0.35),
	"bad": Color(1.0, 0.45, 0.4), "money": Color(0.4, 1.0, 0.5),
}


func _ready() -> void:
	layer = 1
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_drowsy = ColorRect.new()
	_drowsy.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drowsy.color = Color(0, 0, 0, 0)
	_drowsy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_drowsy)

	# Top-left status panel
	var tl := _panel(root, Vector2(16, 16), Vector2(300, 0))
	var v := VBoxContainer.new()
	tl.add_child(v)
	_money = _label(v, "$0", 30, Color(0.5, 1.0, 0.55))
	_clock = _label(v, "", 20)
	_bills = _label(v, "", 15, Color(1, 0.85, 0.5))
	for spec in [["Hunger", Color(0.95, 0.6, 0.2)], ["Bladder", Color(0.95, 0.85, 0.2)], ["Energy", Color(0.35, 0.7, 1.0)], ["Phone", Color(0.6, 0.6, 0.65)]]:
		var row := HBoxContainer.new()
		v.add_child(row)
		var l := _label(row, spec[0], 15)
		l.custom_minimum_size.x = 70
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(200, 16)
		bar.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = spec[1]
		fill.set_corner_radius_all(4)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.5)
		bg.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bg)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		_bars[spec[0]] = bar

	# Minimap (top-right)
	var mm_frame := _panel(root, Vector2(0, 16), Vector2(236, 236))
	mm_frame.anchor_left = 1.0
	mm_frame.anchor_right = 1.0
	mm_frame.offset_left = -252
	mm_frame.offset_right = -16
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(220, 220)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mm_frame.add_child(svc)
	var sv := SubViewport.new()
	sv.size = Vector2i(220, 220)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)
	_mm_cam = Camera3D.new()
	_mm_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_mm_cam.size = 150.0
	_mm_cam.near = 1.0
	_mm_cam.far = 300.0
	_mm_cam.rotation = Vector3(-PI / 2.0, 0, 0)
	var mm_env := Environment.new()
	mm_env.background_mode = Environment.BG_COLOR
	mm_env.background_color = Color(0.2, 0.3, 0.2)
	mm_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	mm_env.ambient_light_color = Color(1, 1, 1)
	mm_env.ambient_light_energy = 0.9
	_mm_cam.environment = mm_env
	sv.add_child(_mm_cam)
	_mm_marker = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(6, 8, 1)
	_mm_marker.mesh = pm
	_mm_marker.material_override = Kit.mat(Color(1, 0.9, 0.1), 2.0)
	_mm_marker.layers = 2
	add_child(_mm_marker)

	_objective = _label(root, "", 17, Color(1, 1, 0.75))
	_objective.anchor_left = 1.0
	_objective.anchor_right = 1.0
	_objective.offset_left = -420
	_objective.offset_right = -16
	_objective.offset_top = 262
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Toasts (top center)
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.offset_left = -330
	_toasts.offset_right = 330
	_toasts.offset_top = 112
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)

	# Turn-by-turn banner (top center)
	_nav = PanelContainer.new()
	_nav.add_theme_stylebox_override("panel", _style(Color(0.05, 0.25, 0.5, 0.88), 10))
	_nav.anchor_left = 0.5
	_nav.anchor_right = 0.5
	_nav.offset_left = -260
	_nav.offset_right = 260
	_nav.offset_top = 16
	_nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav.visible = false
	root.add_child(_nav)
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 14)
	_nav.add_child(nh)
	_nav_arrow = Control.new()
	_nav_arrow.custom_minimum_size = Vector2(72, 72)
	_nav_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav_arrow.draw.connect(_draw_nav_arrow)
	nh.add_child(_nav_arrow)
	var nv := VBoxContainer.new()
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nh.add_child(nv)
	_nav_dist = _label(nv, "", 28, Color.WHITE)
	_nav_text = _label(nv, "", 19, Color(0.85, 0.93, 1.0))
	_nav_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Interaction prompt (bottom center)
	_prompt = _label(root, "", 22, Color(1, 1, 1))
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_left = -400
	_prompt.offset_right = 400
	_prompt.offset_top = -190
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Driving gauges (bottom left)
	_drive = _panel(root, Vector2(16, 0), Vector2(260, 0))
	_drive.anchor_top = 1.0
	_drive.anchor_bottom = 1.0
	_drive.offset_top = -150
	_drive.offset_bottom = -16
	var dv := VBoxContainer.new()
	_drive.add_child(dv)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 16)
	dv.add_child(srow)
	_speed = _label(srow, "0 MPH", 34)
	_limit = _label(srow, "LIMIT\n30", 13, Color(0.1, 0.1, 0.1))
	_limit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_limit.label_settings.outline_size = 0
	var sign_style := StyleBoxFlat.new()
	sign_style.bg_color = Color(0.95, 0.95, 0.92)
	sign_style.set_border_width_all(2)
	sign_style.border_color = Color(0.1, 0.1, 0.1)
	sign_style.set_corner_radius_all(4)
	sign_style.content_margin_left = 6
	sign_style.content_margin_right = 6
	_limit.add_theme_stylebox_override("normal", sign_style)
	_limit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frow := HBoxContainer.new()
	dv.add_child(frow)
	_label(frow, "Fuel", 15).custom_minimum_size.x = 50
	_fuel = ProgressBar.new()
	_fuel.custom_minimum_size = Vector2(180, 14)
	_fuel.show_percentage = false
	_fuel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frow.add_child(_fuel)
	_car_warn = _label(dv, "", 15, Color(1, 0.5, 0.35))
	_drive.visible = false

	# Police alert (lower center)
	_police = PanelContainer.new()
	_police.add_theme_stylebox_override("panel", _style(Color(0.6, 0.05, 0.05, 0.9), 8))
	_police.anchor_left = 0.5
	_police.anchor_right = 0.5
	_police.anchor_top = 1.0
	_police.anchor_bottom = 1.0
	_police.offset_left = -230
	_police.offset_right = 230
	_police.offset_top = -262
	_police.offset_bottom = -214
	_police.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_police.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_police.visible = false
	root.add_child(_police)
	_police_label = _label(_police, "POLICE: pull over and stop", 22)
	_police_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Mirrors (first-person driving): rearview top center, side mirrors left and right.
	for key in ["rear", "left", "right"]:
		var frame := PanelContainer.new()
		var fs := _style(Color(0.05, 0.05, 0.06, 0.95), 10)
		fs.set_content_margin_all(4)
		frame.add_theme_stylebox_override("panel", fs)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.flip_h = true    # a mirror shows things the other way around
		tr.custom_minimum_size = Vector2(400, 100) if key == "rear" else Vector2(200, 130)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(tr)
		match key:
			"rear":
				frame.anchor_left = 0.5
				frame.anchor_right = 0.5
				frame.offset_left = -204
				frame.offset_top = 12
			"left":
				frame.anchor_top = 0.5
				frame.offset_left = 16
				frame.offset_top = 70
			"right":
				frame.anchor_left = 1.0
				frame.anchor_right = 1.0
				frame.anchor_top = 0.5
				frame.offset_left = -224
				frame.offset_top = 70
		frame.visible = false
		root.add_child(frame)
		_mirrors[key] = frame

	# Menu popup (center)
	_menu = PanelContainer.new()
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.custom_minimum_size = Vector2(560, 0)
	_menu.add_theme_stylebox_override("panel", _style(Color(0.08, 0.09, 0.12, 0.96), 12))
	root.add_child(_menu)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	_menu.add_child(mv)
	_menu_title = _label(mv, "", 20, Color(1, 0.95, 0.7))
	_menu_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_list = VBoxContainer.new()
	_menu_list.add_theme_constant_override("separation", 6)
	mv.add_child(_menu_list)
	_menu.visible = false

	# Help
	_help = PanelContainer.new()
	_help.set_anchors_preset(Control.PRESET_CENTER)
	_help.add_theme_stylebox_override("panel", _style(Color(0.05, 0.06, 0.08, 0.94), 12))
	root.add_child(_help)
	var hl := _label(_help, HELP_TEXT, 17)
	hl.custom_minimum_size = Vector2(640, 0)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.visible = false

	# Fade for sleeping
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	_fade_label = _label(_fade, "", 36)
	_fade_label.set_anchors_preset(Control.PRESET_CENTER)
	_fade_label.modulate.a = 0.0

	Game.notified.connect(toast)
	Gigs.offer_received.connect(_on_offer)
	Game.slept.connect(_on_slept)


const HELP_TEXT := """SIDE HUSTLE SIM: CONTROLS            (keyboard  /  gamepad)

WASD or arrows / left stick: walk or drive      Mouse / right stick: look
Gamepad driving: RT gas, LT brake and reverse, left stick steers
Shift / L3: sprint        Space / A: jump or handbrake
E / X: interact, get in or out of the car
Tab or P / Y: phone (gig apps, bank, garage, maps)     B: back
C / LB: driving camera (first person / chase)     M / D-pad up: mirrors
L / RB: headlights     R / D-pad down: flip car upright     H / R3: horn
Esc / Start: pause menu     F1 / Back: this help     F3: graphics quality
F5: save        F9: load

THE LAW
Speed limit is 30 mph in town and 45 on the beltway. Police only notice
you if you're in front of them or off to the side with nothing in the way.
If one lights you up, pull over and stop to take the ticket. Running makes
it worse. An upgraded phone (Me app) shows nearby cops on your map.

HOW TO PLAY
Open your phone and go online in a gig app. Accept offers, follow the
beacon, and use the phone when the job asks for it. Keep yourself fed,
rested and relieved, keep gas in the tank, change your oil, and pay
your bills every 3 days. Save up for a better car (Honest Al's) and a
better place to live (leasing desks at Maple Court, Lakeview Towers).

Rideshare apps need a 2011 or newer car. Your 1999 Rustwagon won't cut it,
so start with DoorDish, Instacrate and Jungle Flex.

Dev cheats: F7 = 10x time speed, F8 = +$500"""


func _style(c: Color, radius := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _panel(parent: Control, pos: Vector2, min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.custom_minimum_size = min_size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0.45)))
	parent.add_child(p)
	return p


func _label(parent: Node, text: String, font_size := 16, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font_size = font_size
	ls.font_color = color
	ls.outline_size = 4
	ls.outline_color = Color(0, 0, 0, 0.8)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _process(_delta: float) -> void:
	_money.text = "$%s" % _fmt_money(Game.money)
	_clock.text = "%s  Day %d   %s" % [Game.weekday(), Game.day, Game.time_string()]
	if Game.time_multiplier > 1.0:
		_clock.text += "  (%dx)" % Game.time_multiplier
	var due := Game.unpaid_bills()
	if due.is_empty():
		_bills.text = "No bills due"
	else:
		var total := 0.0
		var overdue := false
		for b in due:
			total += b.amount
			overdue = overdue or b.overdue
		var first: Dictionary = due[0]
		var days: int = first.due_day - Game.day
		var when := "OVERDUE" if overdue else ("due today" if days <= 0 else "due in %d day%s" % [days, "" if days == 1 else "s"])
		_bills.text = "Bills: $%.0f %s" % [total, when]
		_bills.label_settings.font_color = Color(1, 0.4, 0.35) if overdue else Color(1, 0.85, 0.5)
	_bars["Hunger"].value = Game.hunger
	_bars["Bladder"].value = Game.bladder
	_bars["Energy"].value = Game.energy
	_bars["Phone"].value = Game.phone_battery
	_drowsy.color.a = clampf((18.0 - Game.energy) / 18.0, 0.0, 1.0) * 0.55

	if main:
		var driving: bool = main.is_driving()
		_drive.visible = driving
		_update_mirrors()
		_update_police()
		if driving:
			var mph: float = main.car.speed_mph()
			var limit: float = main.traffic.speed_limit(main.car.global_position) if main.traffic else GameData.SPEED_LIMIT
			_speed.text = "%d MPH" % int(mph)
			_speed.label_settings.font_color = Color(1, 0.4, 0.35) if mph > limit + GameData.TICKET_SLACK else Color.WHITE
			_limit.text = "LIMIT\n%d" % int(limit)
			_fuel.value = Game.fuel / Game.car().tank * 100.0
			var warns := []
			if Game.fuel <= 0.0:
				warns.append("OUT OF GAS")
			if Game.oil_life < 10.0:
				warns.append("OIL CHANGE")
			if Game.tire_tread < 15.0:
				warns.append("BALD TIRES")
			if Game.engine_health < 50.0:
				warns.append("CHECK ENGINE")
			_car_warn.text = "  ".join(warns)
		var pos: Vector3 = main.actor_position()
		_mm_cam.global_position = Vector3(pos.x, 150.0, pos.z)
		_mm_marker.global_position = Vector3(pos.x, 100.0, pos.z)
		_mm_marker.rotation = Vector3(-PI / 2.0, 0, 0)
		_mm_marker.global_rotation.y = main.actor_heading()


func _update_mirrors() -> void:
	var on: bool = main.car.mirrors_visible()
	if on == _mirrors_shown:
		return
	_mirrors_shown = on
	for key in _mirrors:
		var frame: PanelContainer = _mirrors[key]
		frame.visible = on
		if on:
			(frame.get_child(0) as TextureRect).texture = main.car.mirror_texture(key)
	# Make room under the rearview mirror for the directions and messages.
	_nav.offset_top = 132 if on else 16
	_toasts.offset_top = 228 if on else 112


func _update_police() -> void:
	var tr: Traffic = main.traffic
	var on := tr != null and tr.chaser != null
	_police.visible = on
	if on:
		var flash := fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.3
		(_police.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(0.65, 0.05, 0.05, 0.9) if flash else Color(0.05, 0.15, 0.6, 0.9)
		_police_label.text = "POLICE: pull over and stop  (%s)" % tr.chase_reason


func _fmt_money(v: float) -> String:
	var s := "%.2f" % absf(v)
	var parts := s.split(".")
	var whole: String = parts[0]
	var out := ""
	while whole.length() > 3:
		out = "," + whole.substr(whole.length() - 3) + out
		whole = whole.substr(0, whole.length() - 3)
	return ("-" if v < 0 else "") + whole + out + "." + parts[1]


func set_prompt(text: String) -> void:
	_prompt.text = "[E]  " + text if text != "" else ""


## Updates the turn-by-turn banner from the GPS node (hidden when there is no route).
func set_nav(gps: GPS) -> void:
	_nav.visible = gps.instruction != ""
	if not _nav.visible:
		return
	_nav_text.text = gps.instruction
	_nav_dist.text = gps.distance_text if gps.distance_text != "" else gps.instruction
	_nav_dist.visible = gps.distance_text != ""
	if gps.turn != _nav_turn:
		_nav_turn = gps.turn
		_nav_arrow.queue_redraw()


func _draw_nav_arrow() -> void:
	var c := _nav_arrow.size / 2.0
	var white := Color.WHITE
	var w := 9.0
	match _nav_turn:
		"left", "right":
			var s := -1.0 if _nav_turn == "left" else 1.0
			# Stem up from the bottom, then bend toward the turn.
			_nav_arrow.draw_polyline(PackedVector2Array([
				c + Vector2(-s * 8, 30), c + Vector2(-s * 8, -4), c + Vector2(-s * 2, -10), c + Vector2(s * 12, -10)]), white, w)
			_nav_arrow.draw_colored_polygon(PackedVector2Array([
				c + Vector2(s * 30, -10), c + Vector2(s * 10, -26), c + Vector2(s * 10, 6)]), white)
		"uturn":
			_nav_arrow.draw_line(c + Vector2(10, -12), c + Vector2(10, 30), white, w)
			_nav_arrow.draw_arc(c + Vector2(-2, -12), 12.0, PI, TAU, 16, white, w)
			_nav_arrow.draw_line(c + Vector2(-14, -12), c + Vector2(-14, 8), white, w)
			_nav_arrow.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-14, 26), c + Vector2(-28, 6), c + Vector2(0, 6)]), white)
		"arrive":
			_nav_arrow.draw_circle(c + Vector2(0, -6), 18.0, white)
			_nav_arrow.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-15, 4), c + Vector2(15, 4), c + Vector2(0, 30)]), white)
			_nav_arrow.draw_circle(c + Vector2(0, -6), 7.0, Color(0.05, 0.25, 0.5))
		_:
			_nav_arrow.draw_line(c + Vector2(0, 30), c + Vector2(0, -10), white, w)
			_nav_arrow.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -30), c + Vector2(-16, -8), c + Vector2(16, -8)]), white)


func set_objective(text: String) -> void:
	_objective.text = text


func toast(text: String, kind := "info") -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0.6), 6))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(p, text, 18, TOAST_COLORS.get(kind, Color.WHITE))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toasts.add_child(p)
	while _toasts.get_child_count() > 5:
		_toasts.get_child(0).free()
	var tw := p.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.8)
	tw.tween_callback(p.queue_free)


func _on_offer(o: Dictionary) -> void:
	var a: Dictionary = GameData.APPS[o.app]
	var text := "%s: new offer $%.2f" % [a.name, o.pay]
	if o.kind != "flex":
		text += "  •  %.1f mi" % o.miles
	toast(text + "   (Tab to open phone)", "money")


## options: [{text, cb: Callable, disabled: bool}]
func show_menu(title: String, options: Array) -> void:
	for c in _menu_list.get_children():
		c.queue_free()
	_menu_title.text = title
	for o in options:
		var b := Button.new()
		b.text = o.text
		b.disabled = o.get("disabled", false)
		b.add_theme_font_size_override("font_size", 17)
		var cb: Callable = o.cb
		b.pressed.connect(func():
			close_menu()
			cb.call())
		_menu_list.add_child(b)
	var close := Button.new()
	close.text = "Close  (Esc / B)"
	close.pressed.connect(close_menu)
	_menu_list.add_child(close)
	_menu.visible = true
	menu_open = true
	_menu.reset_size()
	_menu.position = (_menu.get_viewport_rect().size - _menu.size) / 2.0
	Game.pad_focus.call_deferred(_menu_list)
	if main:
		main.update_mouse_mode()


func close_menu() -> void:
	_menu.visible = false
	menu_open = false
	if main:
		main.update_mouse_mode()


func toggle_help() -> void:
	help_open = not help_open
	_help.visible = help_open
	_help.reset_size()
	_help.position = (_help.get_viewport_rect().size - _help.size) / 2.0


func _on_slept(hours: float) -> void:
	_fade.color.a = 1.0
	_fade_label.text = "Zzz... %d hours later. %s" % [int(round(hours)), Game.time_string()]
	_fade_label.modulate.a = 1.0
	_fade_label.reset_size()
	_fade_label.position = (_fade.size - _fade_label.size) / 2.0
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(_fade, "color:a", 0.0, 1.2)
	tw.parallel().tween_property(_fade_label, "modulate:a", 0.0, 1.2)
