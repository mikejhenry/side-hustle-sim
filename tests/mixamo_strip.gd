extends SceneTree
## Renders the Mixamo player in a few states (side view): idle, walk, run, carry, and the jump.
## godot --path . -s res://tests/mixamo_strip.gd -- out.png
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
	# [speed, carry, airborne seconds into a jump (-1 = on the ground), time after landing]
	var states := [[0.0, "", -1.0], [4.2, "", -1.0], [7.5, "", -1.0], [4.2, "front", -1.0], [0.0, "front", -1.0],
		[4.0, "", 0.1], [4.0, "", 0.45], [4.0, "", 0.8], [4.0, "", 1.05]]
	var rigs := []
	for i in states.size():
		var r := MixamoRig.create_rig()
		var holder := Node3D.new()
		root3d.add_child(holder)
		holder.add_child(r)
		holder.rotation.y = PI / 2.0
		holder.position = Vector3(i * 1.3, 0, 0)
		rigs.append(r)
	var dt := 1.0 / 60.0
	for f in 150:
		for i in states.size():
			var st: Array = states[i]
			var r: MixamoRig = rigs[i]
			var t := f * dt
			var start := 150 * dt
			var air := false
			var vy := 0.0
			if st[2] >= 0.0 and t > start - st[2] and t < start - st[2] + 0.92:
				air = true
				vy = 4.5 - 9.8 * (t - (start - st[2]))
			r.animate(dt, st[0], st[1], air, vy)
		await process_frame
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.0
	cam.position = Vector3(5.2, 1.0, 10)
	root3d.add_child(cam)
	cam.current = true
	for i in 5:
		await process_frame
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
