extends SceneTree
## Renders a car from GameData.CARS from four sides: godot --path . -s res://tests/car_view.gd -- out.png <car id>
func _init():
	await process_frame
	var args := OS.get_cmdline_user_args()
	var root := Node3D.new()
	get_root().add_child(root)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.8, 0.6, 0)
	root.add_child(light)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.6, 0.7, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.7)
	we.environment = env
	root.add_child(we)
	var data: Dictionary = GameData.CARS[args[1] if args.size() > 1 else "rustwagon"]
	for i in 4:
		var c := CarModel.build(data, false, true)
		c.rotation.y = i * PI / 2.0
		c.position = Vector3((i - 1.5) * 5.0, 0, 0)
		root.add_child(c)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 10)
	ground.mesh = pm
	root.add_child(ground)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 4, 13)
	cam.rotation.x = -0.3
	root.add_child(cam)
	cam.current = true
	for i in 6:
		await process_frame
	get_root().get_texture().get_image().save_png(args[0])
	quit()
