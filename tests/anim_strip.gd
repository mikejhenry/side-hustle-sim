extends SceneTree
## Renders the walk cycle as a strip (front row and side row, 8 phases):
## godot --path . -s res://tests/anim_strip.gd -- out.png <move 0..1.8> [zoom]
func _init():
	await process_frame
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.8, 0.6, 0)
	root3d.add_child(light)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.6, 0.7, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	we.environment = env
	root3d.add_child(we)
	var m := float(OS.get_cmdline_user_args()[1]) if OS.get_cmdline_user_args().size() > 1 else 1.0
	for i in 8:
		var h := Humanoid.create("Casual2")
		root3d.add_child(h)
		var holder := Node3D.new()
		root3d.add_child(holder)
		h.reparent(holder)
		holder.position = Vector3(i * 1.3, 0, 0)
		holder.rotation.y = PI / 2.0   # face +X: side view from +Z camera... walking to the right
		h._apply(i * TAU / 8.0, m, 0.0, 0.0)
		# front view row
		var h2 := Humanoid.create("Casual2")
		var holder2 := Node3D.new()
		root3d.add_child(holder2)
		holder2.add_child(h2)
		holder2.position = Vector3(i * 1.3, 2.3, 0)
		h2._apply(i * TAU / 8.0, m, 0.0, 0.0)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.8
	cam.position = Vector3(4.55, 2.2, 10)
	root3d.add_child(cam)
	cam.current = true
	if OS.get_cmdline_user_args().size() > 2:
		cam.size = 1.2
		cam.position = Vector3(0.0, 2.3 + 0.85, 10)
	for i in 10:
		await process_frame
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
