class_name PauseMenu
extends CanvasLayer
## Esc / Start pauses the game: resume, map, save/load slots, settings, controls, tutorial,
## new game, quit.
## Runs while the tree is paused (process_mode ALWAYS).

var main: Node = null
var is_open := false

var _list: VBoxContainer
var _menu: PanelContainer
var _help: PanelContainer
var _settings: PanelContainer
var _map: PanelContainer
var _map_view: WorldMap
var _map_list: VBoxContainer
var _map_only := false     # opened straight from the map key: Back closes the menu
var _mirror_btn: Button
var _slots: PanelContainer
var _slots_list: VBoxContainer
var _slots_title: Label
var _slots_mode := "save"
var _confirm_new := false
var _map_travel: VBoxContainer
const MIRROR_NAMES := ["in the car", "in the car + on screen", "off"]


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	add_child(dim)
	var panel := _centered_panel(dim, 380)
	_menu = panel
	_help = _centered_panel(dim, 700)
	var hl := Label.new()
	hl.text = HUD.HELP_TEXT + "\n\n(Esc / B to go back)"
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl.add_theme_font_size_override("font_size", 16)
	_help.add_child(hl)
	_help.visible = false
	_settings = _centered_panel(dim, 560)
	_build_settings()
	_settings.visible = false
	_slots = _centered_panel(dim, 640)
	_build_slots()
	_slots.visible = false
	_build_map(dim)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	v.add_child(title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	v.add_child(_list)
	visible = false


func _centered_panel(parent: Control, width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.08, 0.11, 0.97)
	st.set_corner_radius_all(14)
	st.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", st)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(width, 0)
	parent.add_child(panel)
	return panel


## Gamepad highlight back on the main list's button that starts with `text`.
func _focus_item(text: String) -> void:
	var i := 0
	for b in _list.get_children():
		if b is Button and (b as Button).text.begins_with(text):
			Game.pad_focus.call_deferred(_list, i)
			return
		i += 1
	Game.pad_focus.call_deferred(_list)


func _show_help(on: bool) -> void:
	_help.visible = on
	_settings.visible = false
	_slots.visible = false
	_map.visible = false
	_menu.visible = not on
	if not on:
		_focus_item("Controls")


func _show_settings(on: bool) -> void:
	_map.visible = false
	_slots.visible = false
	_settings.visible = on
	_menu.visible = not on
	if on:
		_mirror_btn.text = "Mirrors: %s" % MIRROR_NAMES[Game.mirror_mode]
		_refresh_toggles()
		Game.pad_focus.call_deferred(_settings)
	else:
		Game.save_options()
		_focus_item("Settings")


func _build_settings() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_settings.add_child(v)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	v.add_child(title)
	_section(v, "Sound")
	_slider(v, "Volume", 0.0, 1.0, Game.volume, func(x):
		Game.volume = x
		Game.apply_volume())
	_section(v, "Controls")
	_slider(v, "Mouse sensitivity", 0.3, 2.5, Game.mouse_sens, func(x): Game.mouse_sens = x)
	_slider(v, "Gamepad look speed", 0.3, 2.5, Game.pad_sens, func(x): Game.pad_sens = x)
	_toggle(v, "Invert look up/down", func(): return Game.invert_y, func(on): Game.invert_y = on)
	_section(v, "Display")
	_slider(v, "Field of view", 55.0, 100.0, Game.fov, func(x):
		Game.fov = x
		if main:
			main.apply_view_settings(), func(x): return "%d°" % int(x), 1.0)
	_toggle(v, "Fullscreen", func(): return Game.fullscreen, func(on):
		Game.fullscreen = on
		Game.apply_display())
	_toggle(v, "VSync", func(): return Game.vsync, func(on):
		Game.vsync = on
		Game.apply_display())
	_toggle(v, "High quality graphics (F3)", func(): return main != null and not main.low_graphics, func(on):
		if main and on == main.low_graphics:
			main.toggle_graphics())
	_mirror_btn = Button.new()
	_mirror_btn.add_theme_font_size_override("font_size", 16)
	_mirror_btn.custom_minimum_size.y = 34
	_mirror_btn.pressed.connect(func():
		Game.mirror_mode = (Game.mirror_mode + 1) % 3
		_mirror_btn.text = "Mirrors: %s" % MIRROR_NAMES[Game.mirror_mode])
	v.add_child(_mirror_btn)
	_section(v, "Gameplay")
	_slider(v, "Hunger / tired screen effects", 0.0, 1.0, Game.screen_fx, func(x): Game.screen_fx = x)
	_toggle(v, "Autosave when you sleep and at midnight", func(): return Game.autosave, func(on): Game.autosave = on)
	var hint := Label.new()
	hint.text = "Gamepad: D-pad up/down to pick, left/right to change."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	v.add_child(hint)
	var back := Button.new()
	back.text = "Back"
	back.add_theme_font_size_override("font_size", 20)
	back.custom_minimum_size.y = 44
	back.pressed.connect(func(): _show_settings(false))
	v.add_child(back)


func _section(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	parent.add_child(l)


var _toggles: Array = []      # [{button, text, get}]


## An on/off button. `getter` returns the current state; `setter` gets the new one.
func _toggle(parent: Control, text: String, getter: Callable, setter: Callable) -> void:
	var b := Button.new()
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size.y = 34
	var entry := {"button": b, "text": text, "get": getter}
	_toggles.append(entry)
	b.pressed.connect(func():
		setter.call(not getter.call())
		_refresh_toggles())
	parent.add_child(b)
	_refresh_toggles()


func _refresh_toggles() -> void:
	for t in _toggles:
		(t.button as Button).text = "%s: %s" % [t.text, "On" if t.get.call() else "Off"]


func _slider(parent: Control, text: String, lo: float, hi: float, value: float, cb: Callable,
		fmt := Callable(), step := 0.05) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 240
	l.add_theme_font_size_override("font_size", 16)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = value
	sl.custom_minimum_size = Vector2(200, 28)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pct := Label.new()
	pct.custom_minimum_size.x = 50
	var show := func(x: float) -> String: return fmt.call(x) if fmt.is_valid() else "%d%%" % int(round(x * 100))
	pct.text = show.call(value)
	sl.value_changed.connect(func(x):
		pct.text = show.call(x)
		cb.call(x))
	row.add_child(sl)
	row.add_child(pct)


func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_confirm_new = false
	_add("Resume", close)
	_add("Map", func(): _show_map(true))
	_add("Save game", func(): _show_slots(true, "save"))
	_add("Load game", func(): _show_slots(true, "load"))
	_add("Settings", func(): _show_settings(true))
	_add("Controls", func(): _show_help(true))
	if main.tutorial and main.tutorial.active:
		_add("Skip tutorial", func():
			main.tutorial.finish(true)
			close())
	else:
		_add("Start tutorial", func():
			main.start_tutorial()
			close())
	var new_btn: Button
	new_btn = _add("New game", func():
		if not _confirm_new:
			_confirm_new = true
			new_btn.text = "New game: press again to start over"
			return
		close()
		main.new_game())
	_add("Quit to desktop", func(): get_tree().quit())


func _add(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size.y = 44
	b.pressed.connect(cb)
	_list.add_child(b)
	return b


# --- Save slots ------------------------------------------------------------------------

func _build_slots() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_slots.add_child(v)
	_slots_title = Label.new()
	_slots_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slots_title.add_theme_font_size_override("font_size", 28)
	v.add_child(_slots_title)
	_slots_list = VBoxContainer.new()
	_slots_list.add_theme_constant_override("separation", 8)
	v.add_child(_slots_list)
	var back := Button.new()
	back.text = "Back"
	back.add_theme_font_size_override("font_size", 20)
	back.custom_minimum_size.y = 44
	back.pressed.connect(func(): _show_slots(false))
	v.add_child(back)


func _show_slots(on: bool, mode := "save") -> void:
	_map.visible = false
	_settings.visible = false
	_help.visible = false
	_slots.visible = on
	_menu.visible = not on
	if on:
		_slots_mode = mode
		_fill_slots()
		Game.pad_focus.call_deferred(_slots_list)
	else:
		_focus_item("Save game" if _slots_mode == "save" else "Load game")


func _fill_slots() -> void:
	for c in _slots_list.get_children():
		_slots_list.remove_child(c)
		c.queue_free()
	var saving := _slots_mode == "save"
	_slots_title.text = "SAVE GAME" if saving else "LOAD GAME"
	var first := Game.AUTOSAVE_SLOT if not saving else 1
	for slot in range(first, Game.SLOT_COUNT + 1):
		var s: int = slot
		var info := Game.slot_info(s)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_slots_list.add_child(row)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 52
		b.add_theme_font_size_override("font_size", 15)
		var mark := "  (current)" if s == Game.current_slot and s != Game.AUTOSAVE_SLOT else ""
		b.text = "%s%s\n%s" % [Game.slot_name(s), mark, Game.slot_summary(s)]
		if saving:
			b.pressed.connect(func():
				Game.save_game(s)
				_fill_slots())
		else:
			b.disabled = info.is_empty() or info.get("corrupt", false)
			b.pressed.connect(func():
				close()
				main.load_game(s))
		row.add_child(b)
		if not info.is_empty() and s != Game.AUTOSAVE_SLOT:
			var del := Button.new()
			del.text = "Delete"
			del.custom_minimum_size = Vector2(80, 52)
			del.add_theme_font_size_override("font_size", 14)
			del.pressed.connect(func():
				if del.text == "Delete":
					del.text = "Sure?"
					return
				Game.delete_save(s)
				_fill_slots())
			row.add_child(del)
	var hint := Label.new()
	hint.text = "F5 saves to your current slot. F9 loads your latest save." if saving \
		else "The autosave is written when you sleep and at midnight (turn it off in Settings)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	_slots_list.add_child(hint)


## Straight to the full map (G / D-pad right).
func open_map() -> void:
	open()
	_map_only = true
	_show_map(true)


func _build_map(parent: Control) -> void:
	_map = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.08, 0.11, 0.97)
	st.set_corner_radius_all(14)
	st.set_content_margin_all(16)
	_map.add_theme_stylebox_override("panel", st)
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_map.set_anchor_and_offset(side, 1.0 if side in [SIDE_RIGHT, SIDE_BOTTOM] else 0.0, -30.0 if side in [SIDE_RIGHT, SIDE_BOTTOM] else 30.0)
	parent.add_child(_map)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_map.add_child(row)
	_map_view = WorldMap.new()
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.place_picked.connect(func(p): _pick(p))
	_map_view.point_picked.connect(func(at):
		main.drop_pin(at)
		_fill_map_list())
	_map_view.clear_requested.connect(func():
		main.map_waypoint = {}
		main.refresh_gps()
		_fill_map_list())
	row.add_child(_map_view)
	var side_col := VBoxContainer.new()
	side_col.custom_minimum_size.x = 320
	side_col.add_theme_constant_override("separation", 8)
	row.add_child(side_col)
	var title := Label.new()
	title.text = "MAP"
	title.add_theme_font_size_override("font_size", 28)
	side_col.add_child(title)
	var hint := Label.new()
	hint.text = "Click an icon or pick a place below to set your GPS. Click anywhere else to drop a pin, right-click to clear it. Esc / B to go back."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.75, 0.77, 0.82))
	side_col.add_child(hint)
	WorldMap.legend(side_col, 2, 13)
	_map_travel = VBoxContainer.new()
	_map_travel.add_theme_constant_override("separation", 4)
	side_col.add_child(_map_travel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	side_col.add_child(scroll)
	_map_list = VBoxContainer.new()
	_map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_map_list)
	_map.visible = false


func _show_map(on: bool) -> void:
	_map.visible = on
	_help.visible = false
	_settings.visible = false
	_slots.visible = false
	_menu.visible = not on
	if on:
		_map_view.main = main
		_fill_map_list()
		Game.pad_focus.call_deferred(_map_list)
	else:
		_map_only = false
		_focus_item("Map")


func _fill_map_list() -> void:
	for c in _map_list.get_children():
		_map_list.remove_child(c)
		c.queue_free()
	_fill_travel()
	if not main.map_waypoint.is_empty():
		_map_button("Clear GPS (%s)" % main.map_waypoint.label, Color(0.4, 0.2, 0.2), func():
			main.map_waypoint = {}
			main.refresh_gps()
			_fill_map_list())
	if not Gigs.job.is_empty():
		var note := Label.new()
		note.text = "Your current job's stop comes first on the GPS."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
		_map_list.add_child(note)
	var here: Vector3 = main.actor_position()
	for kind in WorldMap.KINDS:
		var group: Array = _map_view.places().filter(func(p): return p.get("kind", "") == kind)
		if group.is_empty():
			continue
		group.sort_custom(func(a, b): return here.distance_to(a.pos) < here.distance_to(b.pos))
		var k: Array = WorldMap.KINDS[kind]
		var head := Label.new()
		head.text = "%s  %s" % [k[1], k[0]]
		head.add_theme_font_size_override("font_size", 15)
		head.add_theme_color_override("font_color", k[2])
		_map_list.add_child(head)
		for p in group:
			var place: Dictionary = p
			var mi := here.distance_to(place.pos) / GameData.METERS_PER_MILE
			_map_button("%s   %.1f mi" % [place.name, mi], Color(0.16, 0.17, 0.21), func(): _pick(place))


func _map_button(text: String, color: Color, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 14)
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.set_corner_radius_all(6)
	st.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", st)
	b.pressed.connect(cb)
	_map_list.add_child(b)


func _pick(place: Dictionary) -> void:
	main.set_waypoint(place.pos, place.name)
	main.map_waypoint["drop"] = main.transit.drop_point(place)
	_fill_map_list()


## "Take a cab to your pin" under the legend, once there's a pin.
func _fill_travel() -> void:
	for c in _map_travel.get_children():
		_map_travel.remove_child(c)
		c.queue_free()
	var wp: Dictionary = main.map_waypoint
	if wp.is_empty():
		return
	var tr: Transit = main.transit
	var why := tr.blocked_reason()
	var drop: Vector3 = wp.get("drop", wp.pos)
	if why != "":
		var l := Label.new()
		l.text = "Taxi: " + why
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
		_map_travel.add_child(l)
		return
	var q := tr.taxi_quote(drop)
	var b := Button.new()
	b.text = "Take a %s there: $%.2f, about %d min%s" % [GameData.TAXI_NAME, q.fare, q.minutes, " (night rate)" if q.night else ""]
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 14)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.55, 0.45, 0.1)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", st)
	b.disabled = Game.money < q.fare
	var label: String = wp.label
	b.pressed.connect(func(): tr.ride_taxi(drop, label))
	_map_travel.add_child(b)


func open() -> void:
	_map_only = false
	is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild()
	Game.pad_focus.call_deferred(_list)


func close() -> void:
	if _settings.visible:
		Game.save_options()
	_show_help(false)
	_slots.visible = false
	_map_only = false
	is_open = false
	visible = false
	get_tree().paused = false
	main.update_mouse_mode()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("map") and _map.visible:
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") or event.is_action_pressed("back"):
		if _map.visible:
			if _map_only:
				close()
			else:
				_show_map(false)
		elif _help.visible:
			_show_help(false)
		elif _settings.visible:
			_show_settings(false)
		elif _slots.visible:
			_show_slots(false)
		else:
			close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("help"):
		_show_help(not _help.visible)
		get_viewport().set_input_as_handled()
