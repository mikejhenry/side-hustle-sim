class_name Dashboard
extends Node3D
## The car's controls you can use from the driver's seat: turn signals (with blinking lamps
## on the car and auto-cancel after a turn), hazards, wipers, the radio and the phone GPS
## mount. In first person the center console has buttons: look at one and press interact
## (or click) to use it. Keys work too (see Game._setup_input).
##
## Built by Car.apply_model() for each car, since every car's cockpit is a bit different.

const GAZE_ANGLE := 0.085       # radians: how close to a control you have to look

var car: Car
var signal_dir := ""            # "", "left" or "right"
var hazards := false
var wiper_mode := 0             # 0 off, 1 normal, 2 fast
var wiper_phase := 0.0          # 0..2 per wipe cycle: 0->1 sweeps up, 1->2 sweeps back
var gps_mount := true           # phone on the windshield mount
var blink_on := false
var focused: Interactable = null
var near_console := false       # looking roughly at the console (the HUD shows a dot)

var _blink_t := 0.0
var _lamps: Array = []          # [MeshInstance3D, side (1 left, -1 right)]
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _controls: Array = []       # Interactable nodes on the console
var _ctrl_mats := {}            # Interactable -> [StandardMaterial3D, base color]
var _console: Node3D
var _radio_label: Label3D
var _hazard_mat: StandardMaterial3D
var _wiper_label: Label3D
var _gps_label: Label3D
var _cancel_ready := false      # steered into the turn; cancel once the wheel comes back
var _signal_yaw := 0.0
var _wiper_pause := 0.0

var phone_screen: SubViewport
var gps_screen: GpsScreen
var _phone: Node3D
var _screen_frame := 0


func build(c: Dictionary) -> void:
	for ch in get_children():
		ch.queue_free()
	_lamps.clear()
	_controls.clear()
	_ctrl_mats.clear()
	focused = null
	var sz: Vector3 = c.size
	var eye: Vector3 = c.get("eye", Vector3(0.38, 1.24, -0.15))
	_build_lamps(sz)
	_build_console(c, eye)
	_build_phone_mount(c, eye)
	_refresh_labels()


# --- Turn signals --------------------------------------------------------------------

func _build_lamps(sz: Vector3) -> void:
	_lamp_off = StandardMaterial3D.new()
	_lamp_off.albedo_color = Color(0.55, 0.32, 0.05)
	_lamp_on = StandardMaterial3D.new()
	_lamp_on.albedo_color = Color(1.0, 0.6, 0.1)
	_lamp_on.emission_enabled = true
	_lamp_on.emission = Color(1.0, 0.55, 0.05)
	_lamp_on.emission_energy_multiplier = 4.0
	for side in [1.0, -1.0]:
		for end in [1.0, -1.0]:
			var m := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.13, 0.06, 0.04)
			m.mesh = bm
			m.position = Vector3(side * (sz.x / 2.0 - 0.14), 0.62, end * (sz.z / 2.0 + 0.005))
			m.material_override = _lamp_off
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(m)
			_lamps.append([m, side])


func set_signal(dir: String) -> void:
	signal_dir = "" if dir == signal_dir else dir
	_cancel_ready = false
	_signal_yaw = car.global_rotation.y
	_blink_t = 0.0
	blink_on = signal_dir != ""
	_click(blink_on)
	_refresh_lamps()


## D-pad left on a gamepad: left, then right, then off.
func cycle_signal() -> void:
	match signal_dir:
		"": set_signal("left")
		"left": set_signal("right")
		_: set_signal("")


func toggle_hazards() -> void:
	hazards = not hazards
	_blink_t = 0.0
	blink_on = hazards or signal_dir != ""
	_click(true)
	_refresh_lamps()
	_refresh_labels()


func _click(on: bool) -> void:
	if car.driver_active:
		Sfx.play(car, "tick" if on else "tock", -14.0)


func _refresh_lamps() -> void:
	for l in _lamps:
		var side: float = l[1]
		var lit := blink_on and (hazards or (signal_dir == "left" and side > 0.0) or (signal_dir == "right" and side < 0.0))
		(l[0] as MeshInstance3D).material_override = _lamp_on if lit else _lamp_off
	if _hazard_mat:
		_hazard_mat.emission_energy_multiplier = 2.5 if hazards and blink_on else 0.0


func _update_signals(delta: float) -> void:
	if signal_dir == "" and not hazards:
		return
	_blink_t += delta
	if _blink_t >= 0.38:
		_blink_t = 0.0
		blink_on = not blink_on
		_click(blink_on)
		_refresh_lamps()
	# Auto-cancel, like a real stalk: once you've turned the wheel into the turn and the car
	# has swung round, letting the wheel come back cancels the signal. Lane changes (a small
	# turn) keep it on.
	if signal_dir != "" and not hazards:
		var want := 1.0 if signal_dir == "left" else -1.0
		var turned := absf(wrapf(car.global_rotation.y - _signal_yaw, -PI, PI))
		if car.steering * want > 0.12 and turned > 0.6:
			_cancel_ready = true
		if _cancel_ready and absf(car.steering) < 0.04:
			signal_dir = ""
			blink_on = false
			_cancel_ready = false
			_click(false)
			_refresh_lamps()


# --- Wipers ----------------------------------------------------------------------------

func cycle_wipers() -> void:
	wiper_mode = (wiper_mode + 1) % 3
	_click(true)
	_refresh_labels()
	if car.driver_active:
		Game.notify("Wipers: %s" % ["off", "on", "fast"][wiper_mode], "info")


func _update_wipers(delta: float) -> void:
	if wiper_mode == 0 and wiper_phase <= 0.0:
		return
	if _wiper_pause > 0.0:
		_wiper_pause -= delta
		return
	var speed := 1.25 if wiper_mode == 1 else 2.2
	var was := wiper_phase
	wiper_phase += delta * speed
	if was < 1.0 and wiper_phase >= 1.0 and car.driver_active and not car.chase_cam:
		Sfx.play(car, "wiper", -16.0)
	if wiper_phase >= 2.0:
		wiper_phase = 0.0
		if wiper_mode == 0:
			return
		_wiper_pause = 0.35 if wiper_mode == 1 else 0.0


## Blade angle (0 = parked along the bottom of the windshield, 1 = fully up).
func wiper_angle() -> float:
	var p := wiper_phase if wiper_phase <= 1.0 else 2.0 - wiper_phase
	return 0.5 - 0.5 * cos(PI * p)


# --- Console and its controls -----------------------------------------------------------

func _build_console(c: Dictionary, eye: Vector3) -> void:
	_console = Node3D.new()
	var at: Vector3 = c.get("console", Vector3(0.02, eye.y - 0.255, eye.z + 0.67))
	_console.position = at
	_console.scale = Vector3.ONE * 0.85
	add_child(_console)
	# Face the driver's eyes.
	var to_eye := (eye - at)
	_console.rotation.y = atan2(to_eye.x, to_eye.z)
	_console.rotation.x = -atan2(to_eye.y, Vector2(to_eye.x, to_eye.z).length()) * 0.8
	var dark := Color(0.06, 0.06, 0.07)
	Kit.box(_console, Vector3(0.36, 0.17, 0.03), Vector3(0, 0, -0.016), dark, false)
	# Radio head unit: a display with tune buttons either side.
	Kit.box(_console, Vector3(0.2, 0.055, 0.006), Vector3(0, 0.04, 0.002), Color(0.02, 0.05, 0.04), false, 0.3)
	_radio_label = _text(_console, "", Vector3(0, 0.04, 0.007), 20, Color(0.45, 1.0, 0.7))
	_add_control("<", Vector3(-0.14, 0.04, 0), Vector2(0.05, 0.05), Color(0.2, 0.2, 0.22),
		func(): return "Radio: previous station",
		func(): car.radio.prev_station())
	_add_control(">", Vector3(0.14, 0.04, 0), Vector2(0.05, 0.05), Color(0.2, 0.2, 0.22),
		func(): return "Radio: next station" if car.radio.power else "Radio: turn on",
		func(): car.radio.next_station())
	_add_control("", Vector3(0, 0.04, 0), Vector2(0.2, 0.055), Color(0.0, 0.0, 0.0, 0.0),
		func(): return "Radio: turn off" if car.radio.power else "Radio: turn on",
		func(): car.radio.toggle_power(), false)
	# Bottom row: wipers, hazards, GPS mount.
	var w := _add_control("WIPERS", Vector3(-0.11, -0.04, 0), Vector2(0.09, 0.05), Color(0.2, 0.2, 0.22),
		func(): return "Wipers: %s" % ["turn on", "go fast", "turn off"][wiper_mode],
		func(): cycle_wipers())
	_wiper_label = w.get_meta("label")
	var hz := _add_control("", Vector3(0, -0.04, 0), Vector2(0.07, 0.05), Color(0.55, 0.08, 0.06),
		func(): return "Hazard lights: %s" % ("off" if hazards else "on"),
		func(): toggle_hazards())
	_hazard_mat = _ctrl_mats[hz][0]
	_hazard_mat.emission_enabled = true
	_hazard_mat.emission = Color(1.0, 0.15, 0.1)
	_hazard_mat.emission_energy_multiplier = 0.0
	_text(hz, "/!\\", Vector3(0, 0, 0.012), 16, Color(1, 0.9, 0.85))
	var g := _add_control("GPS", Vector3(0.11, -0.04, 0), Vector2(0.09, 0.05), Color(0.2, 0.2, 0.22),
		func(): return "Phone mount: %s" % ("put the phone away" if gps_mount else "put the phone up"),
		func():
			gps_mount = not gps_mount
			_click(true)
			_phone.visible = gps_mount
			_refresh_labels())
	_gps_label = g.get_meta("label")


func _text(parent: Node3D, t: String, pos: Vector3, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = t
	l.font_size = size
	l.pixel_size = 0.0008
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	l.double_sided = false
	l.shaded = false
	l.fixed_size = false
	l.no_depth_test = false
	parent.add_child(l)
	return l


func _add_control(label: String, pos: Vector3, size: Vector2, color: Color, prompt: Callable, action: Callable, visible_box := true) -> Interactable:
	var it := Interactable.new()
	it.radius = 0.0          # never picked by distance; Dashboard picks it by gaze
	it.in_car = true
	it.prompt = prompt
	it.action = func():
		action.call()
		_refresh_labels()
	it.position = pos
	_console.add_child(it)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if visible_box:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(size.x, size.y, 0.014)
		m.mesh = bm
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		it.add_child(m)
	if label != "":
		it.set_meta("label", _text(it, label, Vector3(0, 0, 0.009), 15, Color(0.85, 0.88, 0.9)))
	_controls.append(it)
	_ctrl_mats[it] = [mat, color]
	return it


func _refresh_labels() -> void:
	if _radio_label and car and car.radio:
		var r: Radio = car.radio
		_radio_label.text = "%s  %s" % [r.current().freq, r.current().short] if r.power else "-- OFF --"
	if _wiper_label:
		_wiper_label.text = ["WIPERS", "WIPE >", "WIPE >>"][wiper_mode]
	if _gps_label:
		_gps_label.text = "GPS" if gps_mount else "GPS off"


func _update_gaze() -> void:
	var was := focused
	focused = null
	near_console = false
	if car.driver_active and not car.chase_cam and _console:
		var cam := car.fp_camera
		var fwd := -cam.global_basis.z
		var from := cam.global_position
		near_console = fwd.angle_to(_console.global_position - from) < 0.3
		var best := GAZE_ANGLE
		for it in _controls:
			var a := fwd.angle_to((it as Node3D).global_position - from)
			if a < best:
				best = a
				focused = it
	if focused != was:
		for it in _ctrl_mats:
			var e: Array = _ctrl_mats[it]
			var m: StandardMaterial3D = e[0]
			if m == _hazard_mat:
				m.albedo_color = (e[1] as Color).lightened(0.35) if it == focused else e[1]
			else:
				m.albedo_color = Color(0.35, 0.55, 0.75) if it == focused else e[1]


# --- Phone GPS mount ---------------------------------------------------------------------

func _build_phone_mount(c: Dictionary, eye: Vector3) -> void:
	_phone = Node3D.new()
	var at: Vector3 = c.get("phone_mount", Vector3(eye.x - 0.36, eye.y - 0.09, eye.z + 0.6))
	_phone.position = at
	var to_eye := eye - at
	_phone.rotation.y = atan2(to_eye.x, to_eye.z)
	_phone.rotation.x = -atan2(to_eye.y, Vector2(to_eye.x, to_eye.z).length())
	add_child(_phone)
	var black := Color(0.03, 0.03, 0.035)
	Kit.box(_phone, Vector3(0.172, 0.088, 0.01), Vector3(0, 0, -0.006), black, false)
	# The mount: a clamp and an arm down to the dash.
	Kit.box(_phone, Vector3(0.05, 0.02, 0.02), Vector3(0, -0.05, -0.012), Color(0.12, 0.12, 0.13), false)
	var arm := Kit.box(_phone, Vector3(0.016, 0.07, 0.016), Vector3(0, -0.085, -0.03), Color(0.12, 0.12, 0.13), false)
	arm.rotation.x = 0.4
	if phone_screen == null:
		phone_screen = SubViewport.new()
		phone_screen.size = Vector2i(344, 176)
		phone_screen.render_target_update_mode = SubViewport.UPDATE_ONCE
		phone_screen.transparent_bg = false
		gps_screen = GpsScreen.new()
		gps_screen.car = car
		gps_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
		phone_screen.add_child(gps_screen)
		car.add_child(phone_screen)
	var scr := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.162, 0.08)
	scr.mesh = qm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = phone_screen.get_texture()
	scr.material_override = sm
	scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scr.position = Vector3(0, 0, 0.0)
	_phone.add_child(scr)
	_phone.visible = gps_mount


func _update_phone_screen() -> void:
	if phone_screen == null:
		return
	var on := gps_mount and car.driver_active and not car.chase_cam
	if not on:
		return
	_screen_frame += 1
	if _screen_frame % 6 == 0:
		gps_screen.queue_redraw()
		phone_screen.render_target_update_mode = SubViewport.UPDATE_ONCE


func _process(delta: float) -> void:
	if car == null:
		return
	_update_signals(delta)
	_update_wipers(delta)
	_update_gaze()
	_update_phone_screen()
	if car.radio and _radio_label:
		_refresh_labels()
