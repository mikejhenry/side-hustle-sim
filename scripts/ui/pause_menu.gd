class_name PauseMenu
extends CanvasLayer
## Esc / Start pauses the game: resume, controls, save/load, graphics, tutorial, quit.
## Runs while the tree is paused (process_mode ALWAYS).

var main: Node = null
var is_open := false

var _list: VBoxContainer
var _menu: PanelContainer
var _help: PanelContainer
var _settings: PanelContainer


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
	_settings = _centered_panel(dim, 460)
	_build_settings()
	_settings.visible = false
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


func _show_help(on: bool) -> void:
	_help.visible = on
	_settings.visible = false
	_menu.visible = not on
	if not on:
		Game.pad_focus.call_deferred(_list, 1)


func _show_settings(on: bool) -> void:
	_settings.visible = on
	_menu.visible = not on
	if on:
		Game.pad_focus.call_deferred(_settings)
	else:
		Game.save_options()
		Game.pad_focus.call_deferred(_list, 2)


func _build_settings() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_settings.add_child(v)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	v.add_child(title)
	_slider(v, "Volume", 0.0, 1.0, Game.volume, func(x):
		Game.volume = x
		Game.apply_volume())
	_slider(v, "Mouse sensitivity", 0.3, 2.5, Game.mouse_sens, func(x): Game.mouse_sens = x)
	_slider(v, "Gamepad look speed", 0.3, 2.5, Game.pad_sens, func(x): Game.pad_sens = x)
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


func _slider(parent: Control, text: String, lo: float, hi: float, value: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 190
	l.add_theme_font_size_override("font_size", 17)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.05
	sl.value = value
	sl.custom_minimum_size = Vector2(200, 28)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pct := Label.new()
	pct.custom_minimum_size.x = 50
	pct.text = "%d%%" % int(value * 100)
	sl.value_changed.connect(func(x):
		pct.text = "%d%%" % int(x * 100)
		cb.call(x))
	row.add_child(sl)
	row.add_child(pct)


func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_add("Resume", close)
	_add("Controls", func(): _show_help(true))
	_add("Settings", func(): _show_settings(true))
	_add("Save game", func(): Game.save_game())
	_add("Load game", func():
		close()
		main.load_game())
	_add("Graphics: %s" % ("Low" if main.low_graphics else "High"), func():
		main.toggle_graphics()
		_rebuild()
		Game.pad_focus.call_deferred(_list, 5))
	if main.tutorial and main.tutorial.active:
		_add("Skip tutorial", func():
			main.tutorial.finish(true)
			close())
	else:
		_add("Start tutorial", func():
			main.start_tutorial()
			close())
	_add("Quit to desktop", func(): get_tree().quit())


func _add(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size.y = 44
	b.pressed.connect(cb)
	_list.add_child(b)


func open() -> void:
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
	is_open = false
	visible = false
	get_tree().paused = false
	main.update_mouse_mode()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("back"):
		if _help.visible:
			_show_help(false)
		elif _settings.visible:
			_show_settings(false)
		else:
			close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("help"):
		_show_help(not _help.visible)
		get_viewport().set_input_as_handled()
