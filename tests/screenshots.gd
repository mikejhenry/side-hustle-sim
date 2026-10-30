extends Node
## Renders a few screenshots (needs a GPU or software GL):
## godot --path . --rendering-driver opengl3 res://tests/screenshots.tscn -- <out_dir>

var main: Node
var out_dir := "user://screenshots"


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name: String) -> void:
	await frames(20)
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/main.tscn").instantiate()
	main.auto_tutorial = false
	add_child(main)
	await frames(30)
	# The software GL renderer used in CI over-brightens shadowed scenes; real GPUs are fine.
	if "--no-shadows" in args:
		main.sun.shadow_enabled = false
	Game.minute = 10 * 60.0
	main.start_tutorial()
	await shot("01_walking")
	main.tutorial.finish(true)
	main.enter_car()
	await shot("02_driving_first_person")
	# A cop pulling you over, seen in the mirrors, with the upgraded phone's minimap badge.
	var tr: Traffic = main.traffic
	var cop = tr.cops[0]
	var car: Node3D = main.car
	cop.global_transform = Transform3D(car.global_basis, Vector3(car.global_position.x, 0, car.global_position.z) - car.global_basis.z * 16.0)
	tr.start_chase(cop, "speeding (44 in a 30)")
	tr._stopped_time = -100000.0
	Game.phone_pro = true
	await frames(30)
	await shot("10_police_in_mirrors")
	tr._end_chase("test")
	main.pause_menu.open()
	await shot("11_pause_menu")
	main.pause_menu.close()
	main.car.toggle_camera()
	await shot("03_driving_chase")
	if "--quick" in args:
		main.car.toggle_camera()
		Game.mirror_mode = 1
		await shot("25_screen_mirrors")
		Game.mirror_mode = 0
		get_tree().quit()
		return
	var far: Dictionary = main.town.restaurants[0]
	main.set_waypoint(far.door, far.name)
	await frames(40)
	await shot("08_gps_directions")
	main.map_waypoint = {}
	main.car.toggle_camera()
	main.exit_car()
	Gigs.set_online("doordish", true)
	Gigs._make_offer("doordish")
	main.phone.open_app("doordish")
	await shot("04_phone_doordish")
	main.phone.close()
	var r: Dictionary = main.town.restaurants[3]
	main.player.global_position = r.door + Vector3(0, 0, 0)
	main.player.yaw = atan2(r.door.x - r.curb.x, r.door.z - r.curb.z) + PI
	main.player.pitch = -0.15
	await frames(5)
	main.player.global_position = r.door + (r.door - r.curb).normalized() * 3.0
	await shot("05_restaurant_interior")
	main.player.global_position = Vector3(225, 1, 225)
	main.player.global_position = main.town.stores[0].door + (main.town.stores[0].door - main.town.stores[0].curb).normalized() * 6.0
	main.player.yaw = atan2(main.town.stores[0].door.x - main.town.stores[0].curb.x, main.town.stores[0].door.z - main.town.stores[0].curb.z) + PI
	await shot("06_grocery_interior")
	# Street corner close-up (lamp head, hydrant)
	main.player.global_position = Vector3(2 * 90 + 6, 1, 2 * 90 + 18)
	main.player.yaw = atan2(-14.0, -14.0) + PI
	main.player.pitch = 0.05
	await shot("09_street_corner")
	# Someone walking the sidewalk.
	var ped: Node3D = main.pedestrians.people[0]
	var pf: Vector3 = ped.global_basis.z
	main.player.global_position = ped.global_position + pf * 5.0 + Vector3(0, 1, 0) + pf.cross(Vector3.UP) * 1.5
	main.player.yaw = atan2(pf.x, pf.z)
	main.player.pitch = -0.1
	await shot("12_pedestrian")
	# Red light camera intersection, first person, light red for us.
	var tc: TrafficControl = main.traffic_control
	tc._t = 25.0
	tc._update_lamps(true)
	tc.set_physics_process(false)
	main.enter_car()
	main.car.teleport(Transform3D(Basis.IDENTITY, Vector3(2 * 90 - 3.5, 0.6, 2 * 90 - 32)))
	await frames(30)
	await shot("13_red_light_camera")
	# Speed camera, chase view, with the phone's camera badges on the minimap.
	var sc: Dictionary = tc.cameras.filter(func(x): return x.kind == "speed")[0]
	var al: Vector3 = sc.axis
	var at: Vector3 = sc.pos - al * 22.0 + Traffic.right_of(al) * Traffic.LANE + Vector3(0, 0.6, 0)
	main.car.teleport(Transform3D(Basis(Vector3.UP.cross(al).normalized(), Vector3.UP, al), at))
	main.car.toggle_camera()
	tc.set_physics_process(true)
	await frames(30)
	await shot("14_speed_camera")
	main.car.toggle_camera()
	main.exit_car()
	# DriveThyme financing lot.
	for pl in main.town.places:
		if str(pl.name).begins_with("DriveThyme"):
			var c: Vector3 = pl.curb
			var d: Vector3 = pl.door
			var back := (c - d).normalized()
			main.player.global_position = c + back * 4.0 + Vector3(0, 1, 0)
			main.player.yaw = atan2(back.x, back.z)
			main.player.pitch = -0.08
			break
	await shot("15_drivethyme_lot")
	# Route 40 strip on the curved road, chase view.
	var loop: PackedVector3Array = Roads.links(main.town.B, main.town.N)[0].pts
	var total := Roads.length(loop)
	var smp: Array = Roads.sample(loop, total * 0.3)
	var lane: Vector3 = smp[0] + Traffic.right_of(smp[1]) * Traffic.LANE + Vector3(0, 0.6, 0)
	main.enter_car()
	main.car.teleport(Transform3D(Basis(Vector3.UP.cross(smp[1]).normalized(), Vector3.UP, smp[1]), lane))
	main.car.toggle_camera()
	await frames(30)
	await shot("16_route40_strip")
	# Rain on the strip.
	Game.weather_override = "rain"
	Game._update_weather()
	await frames(60)
	await shot("17_rain")
	Game.weather_override = "snow"
	Game._update_weather()
	await frames(240)
	await shot("18_snow")
	Game.weather_override = ""
	Game.minute = 7 * 60.0
	var fog_day := 1
	while not Game.forecast(fog_day).fog or Game.forecast(fog_day).kind in ["rain", "storm", "snow"]:
		fog_day += 1
	Game.day = fog_day
	Game._update_weather()
	await frames(30)
	await shot("19_morning_fog")
	Game.day = 1
	Game.minute = 13 * 60.0
	Game.weather_override = "clear"
	Game._update_weather()
	main.car.toggle_camera()
	main.exit_car()
	# Inside the walk-up apartments: the stairwell.
	var w: Dictionary = main.town.walkups[0]
	var b: Node3D = w.node
	var fl: Array = w.flights[0]
	var bottom: Vector3 = b.to_global(fl[0])
	var top: Vector3 = b.to_global(fl[1])
	var fdir := top - bottom
	fdir.y = 0.0
	fdir = fdir.normalized()
	main.player.global_position = bottom - fdir * 3.0 + Vector3(0, 0.2, 0)
	main.player.yaw = atan2(-fdir.x, -fdir.z)
	main.player._model.rotation.y = atan2(fdir.x, fdir.z)
	main.player.pitch = -0.15
	await frames(20)
	await shot("20_apartment_stairs")
	# Carrying a pizza.
	main.player.global_position = main.town.spawn_point
	main.carry_preview = "pizza"
	main.player.yaw = main.player.facing() + 0.6
	main.player.pitch = -0.2
	await frames(20)
	await shot("21_carrying_pizza")
	main.carry_preview = ""
	main.player.set_carrying("")
	# Mid-jump, seen from the side.
	main.player.yaw = main.player.facing() + PI / 2.0
	main.player.pitch = -0.1
	await frames(10)
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	for i in 18:
		await get_tree().physics_frame
	# Freeze him mid-air: rendering here is slower than real time.
	get_tree().paused = true
	await shot("24_jump")
	get_tree().paused = false
	await frames(90)
	# The full map and the phone's Maps app, with a route to the Route 40 strip.
	var dest: Dictionary = main.town.places.filter(func(pl): return pl.name.begins_with("Chick"))[0]
	main.set_waypoint(dest.pos, dest.name)
	main.pause_menu.open_map()
	await frames(5)
	await shot("22_full_map")
	main.pause_menu.close()
	main.phone.open_app("maps")
	await frames(5)
	await shot("23_phone_map")
	main.phone.close()
	main.map_waypoint = {}
	Game.weather_override = ""
	Game.minute = 21 * 60.0
	main.player.global_position = main.town.spawn_point
	main.enter_car()
	await shot("07_night_drive")
	get_tree().quit()
