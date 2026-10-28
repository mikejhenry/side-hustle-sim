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
	add_child(main)
	await frames(30)
	# The software GL renderer used in CI over-brightens shadowed scenes; real GPUs are fine.
	if "--no-shadows" in args:
		main.sun.shadow_enabled = false
	Game.minute = 10 * 60.0
	await shot("01_walking")
	main.enter_car()
	await shot("02_driving_first_person")
	main.car.toggle_camera()
	await shot("03_driving_chase")
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
	Game.minute = 21 * 60.0
	main.player.global_position = main.town.spawn_point
	main.enter_car()
	await shot("07_night_drive")
	get_tree().quit()
