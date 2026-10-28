class_name Tutorial
extends CanvasLayer
## Guided first-day tour. Walks you through the controls, the phone and your needs, then
## drives you around town to the key places with the GPS, explaining each one, and ends by
## going online in a gig app. Starts on the first launch; the pause menu can skip or
## restart it.

const SETTINGS_PATH := "user://settings.cfg"
const ARRIVE := 16.0
## Bump this when the tour changes, so players who finished an older one see it again once.
const VERSION := 2

var main: Node = null
var active := false
var step := 0

var _steps: Array = []
var _panel: PanelContainer
var _title: Label
var _body: Label
var _start_pos := Vector3.ZERO
var _step_time := 0.0
var _phone_seen := false


static func is_done() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(SETTINGS_PATH) == OK and int(cfg.get_value("tutorial", "version", 0)) >= VERSION


func _ready() -> void:
	layer = 2
	_panel = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.2, 0.16, 0.9)
	st.set_corner_radius_all(10)
	st.set_border_width_all(2)
	st.border_color = Color(0.4, 1.0, 0.6, 0.8)
	st.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", st)
	_panel.position = Vector2(16, 248)
	_panel.custom_minimum_size = Vector2(380, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 19)
	_title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	v.add_child(_title)
	_body = Label.new()
	_body.add_theme_font_size_override("font_size", 15)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 352
	v.add_child(_body)
	var hint := Label.new()
	hint.text = "Skip from the pause menu"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.75, 0.8, 0.78))
	v.add_child(hint)
	visible = false


## Picks the keyboard or gamepad name of a control, whichever you're using.
func k(keyboard: String, pad: String) -> String:
	return pad if Game.using_pad else keyboard


func _place(prefix: String) -> Dictionary:
	for p in main.town.places:
		if str(p.name).begins_with(prefix):
			return p
	return {}


func _near(p: Dictionary) -> bool:
	return not p.is_empty() and main.actor_position().distance_to(p.curb) < ARRIVE


func _visit(prefix: String, title: String, text: Callable) -> Dictionary:
	var p := _place(prefix)
	return {"title": title, "text": text,
		"target": func(): return {"pos": p.curb, "label": p.name} if not p.is_empty() else {},
		"done": func(): return _near(p)}


func _build_steps() -> void:
	var town = main.town
	var food: Dictionary = town.restaurants[0] if not town.restaurants.is_empty() else {}
	var store: Dictionary = town.stores[0] if not town.stores.is_empty() else {}
	_steps = [
		{"title": "Welcome to New Castlewood County",
			"text": func(): return "This quick tour shows you how to make money and stay alive.\n\nWalk with %s and look around with %s. Take a few steps." % [k("WASD", "the left stick"), k("the mouse", "the right stick")],
			"done": func(): return main.player.global_position.distance_to(_start_pos) > 4.0},
		{"title": "Your phone",
			"text": func(): return "Everything runs through your phone: gig apps, the Bank (bills), Garage, Maps and Me.\n\nOpen it with %s." % k("Tab", "Y"),
			"done": func(): return main.phone.is_open},
		{"title": "Your needs",
			"text": func(): return "Top left are your hunger, bladder, energy and phone battery. Let them run out and you'll pass out, have an accident, or lose your phone. Bills show there too.\n\nClose the phone with %s." % k("Tab", "Y or B"),
			"done": func(): return not main.phone.is_open},
		{"title": "Your car",
			"text": func(): return "That's your 1999 Rustwagon. Follow the green beacon and press %s to get in." % k("E", "X"),
			"target": func(): return {"pos": main.car.global_position, "label": "Your car"},
			"done": func(): return main.is_driving()},
		_visit("Lube & Tube", "Drive to Lube & Tube",
			func(): return "Gas %s, brake and reverse %s, handbrake %s. %s switches camera, %s toggles mirrors, %s headlights.\n\nFollow the blue GPS line. Speed limit is 30 mph in town (sign next to your speed). Police only notice you if you pass in front of or beside them, but if they light you up, pull over and stop. Watch for traffic lights: some have red light cameras, and some streets have speed cameras that mail you a ticket." % [
				k("W", "RT"), k("S", "LT"), k("Space", "A"), k("C", "LB"), k("M", "D-pad up"), k("L", "RB")]),
		_visit("WahWah", "Gas up at WahWah",
			func(): return "Lube & Tube does oil changes, tires and repairs. Your oil is almost gone, so come back soon (walk inside and use the counter).\n\nNext: WahWah, for gas and snacks. Watch your fuel gauge."),
		_visit(str(food.get("name", "")), "Food",
			func(): return "Park at a pump at WahWah and press %s to fill up when you need to.\n\nNext stop: %s. Restaurants feed you and it's where DoorDish pickups happen." % [k("E", "X"), food.get("name", "a restaurant")]),
		_visit(str(store.get("name", "")), "Groceries",
			func(): return "Walk in and order at the counter when you're hungry.\n\nNext: %s. Instacrate shopping jobs happen at grocery stores, and you can stock your fridge at the register." % store.get("name", "the grocery store")),
		_visit("Honest Al", "Honest Al's Used Cars",
			func(): return "Next: Honest Al's. Rideshare apps (Yoober, Drift) need a 2011 or newer car, so save up and trade in the Rustwagon here. DriveThyme next door will finance one with less cash up front, but it costs more in the end and they repossess if you miss a payment."),
		_visit("Jungle Flex", "Jungle Flex Station",
			func(): return "Next: the Jungle Flex station. Accept a delivery block in the app, scan packages here, then deliver the whole route."),
		_visit("Dottie", "Home sweet home",
			func(): return "Last stop: your rented room at Dottie's. Sleep in your bed, eat from the fridge, use the toilet. Rent, phone and insurance are due once a month (they auto-pay if you have the money; check the Bank app). Bigger places to rent have leasing desks."),
		{"title": "Go to work",
			"text": func(): return "Open your phone (%s), open DoorDish and tap GO ONLINE. Offers pop up as messages. Accept one, follow the GPS, and use the phone when the job asks.\n\nTip: the Me app sells a phone upgrade that shows cops and traffic cameras on your map." % k("Tab", "Y"),
			"done": func(): return Gigs.online.values().has(true)},
		{"title": "You're ready",
			"text": func(): return "That's the basics. %s opens the pause menu (save, controls, graphics). %s shows all controls. Good luck out there!" % [k("Esc", "Start"), k("F1", "Back")],
			"done": func(): return _step_time > 9.0},
	]


func start() -> void:
	_build_steps()
	active = true
	visible = true
	_go(0)


func _go(i: int) -> void:
	step = i
	_step_time = 0.0
	_start_pos = main.player.global_position
	if i >= _steps.size():
		finish(false)
		return
	_refresh()


func _refresh() -> void:
	var s: Dictionary = _steps[step]
	_title.text = "Tutorial %d/%d: %s" % [step + 1, _steps.size(), s.title]
	_body.text = s.text.call()
	_panel.reset_size()


## GPS target for the current step, or {} if it has none.
func target() -> Dictionary:
	if not active or step >= _steps.size():
		return {}
	var s: Dictionary = _steps[step]
	return s.target.call() if s.has("target") else {}


func finish(skipped: bool) -> void:
	active = false
	visible = false
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("tutorial", "done", true)
	cfg.set_value("tutorial", "version", VERSION)
	cfg.save(SETTINGS_PATH)
	if not skipped:
		Game.notify("Tutorial complete!", "good")


func _process(delta: float) -> void:
	if not active:
		return
	_step_time += delta
	var s: Dictionary = _steps[step]
	if _step_time > 0.5 and s.done.call():
		if step > 0:
			Game.notify("Tutorial: %s done." % s.title, "good")
		_go(step + 1)
		return
	if fmod(_step_time, 0.5) < delta:
		_refresh()
