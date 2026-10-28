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
	Game.minute = 21 * 60.0
	main.player.global_position = main.town.spawn_point
	main.enter_car()
	await shot("07_night_drive")
	get_tree().quit()
