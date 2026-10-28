extends SceneTree
## Renders the jump as a strip of 8 moments (side view on the bottom row, front on top):
## godot --path . -s res://tests/jump_strip.gd -- out.png [speed]
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
	var args := OS.get_cmdline_user_args()
	var speed := float(args[1]) if args.size() > 1 else 4.0
	var times := [0.1, 0.25, 0.45, 0.65, 0.85, 0.97, 1.1, 1.3]
	for row in 2:
		for i in times.size():
			var h := Humanoid.create("Casual2")
			var holder := Node3D.new()
			root3d.add_child(holder)
			holder.add_child(h)
			holder.rotation.y = PI / 2.0 if row == 0 else 0.0
			# Run up to the jump, then simulate it to this moment.
			var dt := 1.0 / 60.0
			for k in 60:
				h.animate(dt, speed)
			var t := 0.0
			var vy := 4.5
			var y := 0.0
			var on_floor := false
			while t < times[i]:
				if not on_floor:
					vy -= 9.8 * dt
					y += vy * dt
					if y <= 0.0:
						y = 0.0
						vy = 0.0
						on_floor = true
				h.animate(dt, speed if on_floor else 0.0, "", not on_floor, vy)
				t += dt
			holder.position = Vector3(i * 1.3, y + row * 2.6, 0)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.4
	cam.position = Vector3(4.55, 2.5, 10)
	root3d.add_child(cam)
	cam.current = true
	for i in 10:
		await process_frame
	get_root().get_texture().get_image().save_png(args[0])
	quit()
