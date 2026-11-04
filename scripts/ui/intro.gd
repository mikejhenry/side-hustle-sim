class_name Intro
extends CanvasLayer
## The story intro: a few title cards on why you're hustling. Plays once, on your first game,
## before the tutorial. The Hustle Hub app can replay it. Pauses the game while it's up.

signal finished

const SETTINGS_PATH := "user://settings.cfg"

var main: Node = null
var _page := 0
var _title: Label
var _body: Label
var _count: Label
var _next: Button
var _box: VBoxContainer


static func is_seen() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(SETTINGS_PATH) == OK and bool(cfg.get_value("story", "intro_seen", false))


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.03, 0.05, 0.94)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(640, 0)
	_box.add_theme_constant_override("separation", 18)
	center.add_child(_box)
	_count = _label(14, Color(0.6, 0.65, 0.7))
	_title = _label(40, Color(1.0, 0.85, 0.35))
	_body = _label(21, Color(0.92, 0.92, 0.95))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	_box.add_child(row)
	var skip := _button(row, "Skip")
	skip.pressed.connect(close)
	_next = _button(row, "Next")
	_next.pressed.connect(next)
	visible = false


func _label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 640
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	_box.add_child(l)
	return l


func _button(parent: Node, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(130, 46)
	b.add_theme_font_size_override("font_size", 19)
	parent.add_child(b)
	return b


func start() -> void:
	_page = 0
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show()


func _show() -> void:
	var p: Array = StoryData.INTRO[_page]
	_count.text = "%d / %d" % [_page + 1, StoryData.INTRO.size()]
	_title.text = p[0]
	_body.text = p[1]
	_next.text = "Let's go" if _page == StoryData.INTRO.size() - 1 else "Next"
	Game.pad_focus.call_deferred(_next.get_parent(), 1)


func next() -> void:
	_page += 1
	if _page >= StoryData.INTRO.size():
		close()
	else:
		_show()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("story", "intro_seen", true)
	cfg.save(SETTINGS_PATH)
	if main:
		main.update_mouse_mode()
	finished.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Space, Enter, E or A moves on; Esc or B skips the rest.
	if event.is_action_pressed("pause") or event.is_action_pressed("back"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or (event.is_action_pressed("ui_accept") and not Game.using_pad):
		next()
		get_viewport().set_input_as_handled()
