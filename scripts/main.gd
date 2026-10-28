extends Node3D
## Wires the game together: builds the world, spawns the player and car, and handles
## switching between walking (third person) and driving (first person).

const Town := preload("res://scripts/world/town.gd")

var town: Town
var player: Player
var car: Car
var hud: HUD
var phone: Phone
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var beacon: Node3D
var driving := false
var map_waypoint: Dictionary = {}
var gps: GPS
var traffic: Traffic
var traffic_control: TrafficControl
var pedestrians: Pedestrians
var pause_menu: PauseMenu
var tutorial: Tutorial
var auto_tutorial := true     # tests turn this off
var _gps_timer := 0.0

var _current: Interactable = null
var _was_night := false
var _enter_point: Interactable


func _ready() -> void:
	_build_environment()
	town = Town.new()
	town.main = self
	add_child(town)
	town.build()
	Gigs.town = town
	Gigs.main = self

	player = Player.new()
	add_child(player)
	player.global_position = town.spawn_point
	player.yaw = PI   # face the street

	car = Car.new()
	add_child(car)
	car.teleport(town.car_spawn)
	_enter_point = Kit.interactable(car, Vector3(1.4, 1, 0.2), 2.6,
		func(): return "Get in your %s" % Game.car().name if not driving else "",
		func(): enter_car())

	hud = HUD.new()
	hud.main = self
	add_child(hud)
	phone = Phone.new()
	phone.main = self
	add_child(phone)

	beacon = Kit.beacon(Color(0.2, 1.0, 0.4))
	add_child(beacon)
	beacon.visible = false
	gps = GPS.new()
	gps.town = town
	add_child(gps)
	traffic = Traffic.new()
	traffic.town = town
	traffic.main = self
	add_child(traffic)
	traffic.build()
	traffic_control = TrafficControl.new()
	traffic_control.town = town
	traffic_control.main = self
	add_child(traffic_control)
	traffic_control.build()
	traffic_control.ran_red_light.connect(traffic.on_ran_red_light)
	pedestrians = Pedestrians.new()
	pedestrians.town = town
	pedestrians.main = self
	add_child(pedestrians)
	pedestrians.build()
	tutorial = Tutorial.new()
	tutorial.main = self
	add_child(tutorial)
	pause_menu = PauseMenu.new()
	pause_menu.main = self
	add_child(pause_menu)

	var amb := AudioStreamPlayer.new()
	amb.stream = Sfx.get_stream("ambience")
	amb.volume_db = -20.0
	add_child(amb)
	amb.play()
	Game.notified.connect(_notify_sound)
	Gigs.offer_received.connect(func(_o): Sfx.play(self, "ping", -2.0))

	player.set_active(true)
	Game.home_changed.connect(_on_home_changed)
	update_mouse_mode()
	if auto_tutorial and not Tutorial.is_done():
		tutorial.start()
	else:
		hud.toast("Welcome to New Castlewood County! %s shows the controls. %s opens your phone." % [Game.key("help"), Game.key("phone")], "info")
		hud.toast("Rent is due at the end of the month and your Rustwagon needs an oil change. Time to hustle.", "warn")


func _notify_sound(_text: String, kind: String) -> void:
	match kind:
		"money", "good": Sfx.play(self, "money", -8.0)
		"bad": Sfx.play(self, "bad", -8.0)
		_: Sfx.play(self, "ping", -12.0)


func start_tutorial() -> void:
	tutorial.start()


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	_sky = sky
	sky.sky_material = sky_mat
	# Small, incrementally updated reflection map: the sky colors change every frame with the
	# day/night cycle, and a big map rebuilt each frame can hang weaker GPUs.
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_density = 0.0012
	env.fog_aerial_perspective = 0.4
	# Screen-space ambient occlusion grounds objects; glow makes lights and the sun bloom.
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	sky_mat.sun_angle_max = 20.0
	sky_mat.sky_curve = 0.12
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	apply_graphics(_load_low_graphics())
	print("Graphics: %s on %s / %s" % ["low" if low_graphics else "high",
		RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name()])


# --- Graphics quality ----------------------------------------------------------------
# Low graphics turns off sky reflections, ambient occlusion and glow, and uses cheaper
# shadows. It's on by default for Intel integrated graphics, whose older Vulkan drivers
# crash ("device lost") on the sky reflection pass. F3 toggles it and the choice is saved.

const SETTINGS_PATH := "user://settings.cfg"
var low_graphics := false
var _sky: Sky


func _load_low_graphics() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.has_section_key("graphics", "low"):
		return cfg.get_value("graphics", "low")
	# The Compatibility (OpenGL) renderer is fine on Intel; only Forward+ (Vulkan) crashes.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return false
	var vendor := RenderingServer.get_video_adapter_vendor().to_lower()
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	return "intel" in vendor or "intel" in adapter


func apply_graphics(low: bool) -> void:
	low_graphics = low
	# Low mode skips the sky shader completely (plain colored background), since the sky
	# pass is where Intel's older Vulkan drivers lose the device.
	env.background_mode = Environment.BG_COLOR if low else Environment.BG_SKY
	env.sky = null if low else _sky
	env.fog_aerial_perspective = 0.0 if low else 0.4
	env.fog_sky_affect = 0.0 if low else 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if low else Environment.REFLECTION_SOURCE_SKY
	env.ssao_enabled = not low
	env.glow_enabled = not low
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if low else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 110.0 if low else 160.0
	sun.shadow_blur = 1.0 if low else 1.5


func toggle_graphics() -> void:
	apply_graphics(not low_graphics)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "low", low_graphics)
	cfg.save(SETTINGS_PATH)
	hud.toast("Graphics: %s" % ("low" if low_graphics else "high"), "info")


# --- Queries used by other systems ------------------------------------------------

func is_driving() -> bool:
	return driving


func car_speed() -> float:
	return car.linear_velocity.length()


func actor_position() -> Vector3:
	return car.global_position if driving else player.global_position


func actor_heading() -> float:
	var f: Vector3
	if driving:
		f = car.global_basis.z
	else:
		var y := player.facing()
		f = Vector3(sin(y), 0, cos(y))
	return atan2(-f.x, -f.z)


# --- Enter / exit car ---------------------------------------------------------------

func enter_car() -> void:
	if driving:
		return
	driving = true
	Game.in_car = true
	player.set_active(false)
	car.set_driver(true)
	car.set_headlights(Game.is_night())


func exit_car() -> void:
	if not driving:
		return
	if car_speed() > 2.5:
		hud.toast("Stop the car before getting out.", "warn")
		return
	driving = false
	Game.in_car = false
	car.set_driver(false)
	var out := car.global_transform * Vector3(1.6, 0.3, 0.2)
	player.global_position = out
	player.yaw = atan2(car.global_basis.z.x, car.global_basis.z.z) + PI
	player.set_active(true)


# --- Frame update --------------------------------------------------------------------

func _process(delta: float) -> void:
	# Find the nearest usable interactable.
	var pos := actor_position()
	var best: Interactable = null
	var best_d := INF
	var best_prompt := ""
	for n in get_tree().get_nodes_in_group("interactable"):
		var it := n as Interactable
		if driving and not it.in_car:
			continue
		var d := it.global_position.distance_to(pos)
		if d < it.radius and d < best_d:
			var p := it.get_prompt()
			if p != "":
				best = it
				best_d = d
				best_prompt = p
	_current = best
	if hud.menu_open:
		hud.set_prompt("")
	elif best:
		hud.set_prompt(best_prompt)
	elif driving and car_speed() < 2.5:
		hud.set_prompt("Get out of the car")
	else:
		hud.set_prompt("")

	# Carrying an order?
	var j := Gigs.job
	player.set_carrying(not j.is_empty() and j.stage in ["to_customer", "checkout"] or j.get("stage", "") == "delivering")
	player.set_phone_visible(phone.is_open)

	# GPS beacon: active job first, then map waypoint.
	var t := Gigs.target()
	if t.is_empty():
		t = map_waypoint
	if t.is_empty():
		t = tutorial.target()
	beacon.visible = not t.is_empty()
	var obj := Gigs.status_text()
	if not t.is_empty():
		beacon.global_position = t.pos
		var dist := pos.distance_to(t.pos)
		if dist < 6.0 and t == map_waypoint:
			map_waypoint = {}
		obj += ("\n" if obj != "" else "") + "GPS: %s  (%.2f mi)" % [t.label, dist / GameData.METERS_PER_MILE]
	hud.set_objective(obj)
	_update_gps(delta, t)
	_update_sky()
	# With a gamepad, the stick and A button drive the phone's menus, not the character.
	var locked: bool = hud.menu_open or (phone.is_open and Game.using_pad)
	player.input_locked = locked
	car.input_locked = locked


func _update_gps(delta: float, t: Dictionary) -> void:
	_gps_timer -= delta
	if t.is_empty():
		if gps.instruction != "":
			gps.clear()
			hud.set_nav(gps)
		return
	if _gps_timer > 0.0:
		return
	_gps_timer = 0.35
	var f: Vector3
	if driving:
		f = car.global_basis.z
	else:
		var y := player.facing()
		f = Vector3(sin(y), 0, cos(y))
	gps.update(actor_position(), f, t.pos, t.label, driving)
	hud.set_nav(gps)


func _update_sky() -> void:
	var m := Game.minute
	var e := (m / 1440.0 - 0.25) * TAU   # sun elevation angle: 6AM = 0, noon = PI/2
	var day_amount := clampf(sin(e) * 2.5 + 0.3, 0.0, 1.0)
	if sin(e) > -0.1:
		sun.rotation = Vector3(-clampf(e, 0.05, PI - 0.05), deg_to_rad(-35.0), 0)
		sun.light_energy = 0.85 * day_amount
		sun.light_color = Color(1.0, 0.75, 0.55).lerp(Color(1.0, 0.97, 0.92), clampf(sin(e) * 2.0, 0.0, 1.0))
	else:
		sun.rotation = Vector3(-0.9, deg_to_rad(30.0), 0)   # moonlight
		sun.light_energy = 0.06
		sun.light_color = Color(0.6, 0.7, 1.0)
	env.background_color = Color(0.03, 0.03, 0.07).lerp(Color(0.55, 0.68, 0.85), day_amount)
	if low_graphics:
		env.ambient_light_color = Color(0.25, 0.28, 0.45).lerp(Color(0.62, 0.66, 0.72), day_amount)
		env.ambient_light_energy = lerpf(0.25, 0.55, day_amount)
		_update_night()
		return
	sky_mat.sky_top_color = Color(0.01, 0.01, 0.04).lerp(Color(0.3, 0.5, 0.85), day_amount)
	sky_mat.sky_horizon_color = Color(0.04, 0.04, 0.08).lerp(Color(0.75, 0.82, 0.9), day_amount)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color(0.05, 0.05, 0.06).lerp(Color(0.3, 0.3, 0.3), day_amount)
	env.ambient_light_color = Color(0.25, 0.28, 0.45).lerp(Color(0.62, 0.66, 0.72), day_amount)
	env.ambient_light_energy = lerpf(0.25, 0.55, day_amount)
	_update_night()


func _update_night() -> void:
	var night := Game.is_night()
	if night != _was_night:
		_was_night = night
		town.set_night(night)
		if driving:
			car.set_headlights(night)


# --- Input ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	Game.track_device(event)
	if event.is_action_pressed("phone"):
		if not hud.menu_open:
			phone.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") or event.is_action_pressed("back"):
		if hud.menu_open:
			hud.close_menu()
		elif phone.is_open:
			if event.is_action_pressed("back") and phone.current_app != "":
				phone.open_app("")
			else:
				phone.close()
		elif hud.help_open:
			hud.toggle_help()
		elif event.is_action_pressed("pause"):
			pause_menu.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("help"):
		hud.toggle_help()
	elif event.is_action_pressed("save_game"):
		Game.save_game()
	elif event.is_action_pressed("load_game"):
		load_game()
	elif event.is_action_pressed("time_warp"):
		Game.time_multiplier = 10.0 if Game.time_multiplier == 1.0 else 1.0
		hud.toast("Time speed: %dx" % Game.time_multiplier, "info")
	elif event.is_action_pressed("graphics"):
		toggle_graphics()
	elif event.is_action_pressed("cheat_money"):
		Game.earn(500.0, "Dev cheat")
	elif event.is_action_pressed("camera_toggle") and driving:
		car.toggle_camera()
	elif event.is_action_pressed("headlights") and driving:
		car.set_headlights(not car.headlights_on)
	elif event.is_action_pressed("mirrors") and driving:
		Game.mirror_mode = (Game.mirror_mode + 1) % 3
		Game.save_options()
		hud.toast("Mirrors: %s (%s to change)" % [["in the car", "in the car + on screen", "off"][Game.mirror_mode], Game.key("mirrors")], "info")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not hud.menu_open:
		if _current:
			_current.use()
		elif driving:
			exit_car()
	elif event is InputEventMouseButton and event.pressed and not phone.is_open and not hud.menu_open and not pause_menu.is_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func update_mouse_mode() -> void:
	var free: bool = phone.is_open or hud.menu_open or (pause_menu != null and pause_menu.is_open)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED
	player.input_locked = hud.menu_open
	car.input_locked = hud.menu_open


func on_phone_toggled(_open: bool) -> void:
	update_mouse_mode()


# --- Actions used by world objects and the phone ----------------------------------------

func set_waypoint(pos: Vector3, label: String) -> void:
	map_waypoint = {"pos": pos, "label": label}
	hud.toast("GPS set: " + label, "info")


func sleep_menu(quality: float) -> void:
	hud.show_menu("Your bed. Sleep quality %d%%." % int(quality * 100), [
		{"text": "Sleep until 6 AM (%.1f hours)" % Game.hours_until(6), "cb": func(): Game.sleep(Game.hours_until(6), quality)},
		{"text": "Nap for 2 hours", "cb": func(): Game.sleep(2.0, quality)},
	])


func sleep_in_car(hours: float) -> void:
	if not driving or car_speed() > 1.0:
		return
	phone.close()
	Game.sleep(hours, 0.55)
	hud.toast("You wake up with a stiff neck.", "warn")


func call_tow() -> void:
	if not Game.spend(GameData.TOW_PRICE, "Tow truck"):
		return
	if driving:
		exit_car()
	car.teleport(town.mechanic_bay)
	Game.fuel = maxf(Game.fuel, 1.0)
	player.global_position = town.mechanic_bay.origin + town.mechanic_bay.basis.x * 3.0
	phone.close()
	Game.advance(40.0)
	hud.toast("Your car was towed to Lube & Tube. That took 40 minutes.", "info")


func load_game() -> void:
	if not Game.load_game():
		return
	if driving:
		driving = false
		car.set_driver(false)
		Game.in_car = false
	var home_id := Game.home_id if Game.home_id != "" else "room"
	var h: Dictionary = town.homes[home_id]
	player.global_position = h.inside
	player.set_active(true)
	car.teleport(h.parking)


func _on_home_changed() -> void:
	pass
