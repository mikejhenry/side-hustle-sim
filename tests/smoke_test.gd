extends Node
## Headless smoke test: godot --headless --path . res://tests/smoke_test.tscn
## Boots the game, drives the car, and runs one job from every app end to end.

var main: Node
var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.auto_tutorial = false
	add_child(main)
	main.traffic.police_enabled = false
	await frames(30)
	var town = main.town
	print("World")
	check(town.addresses.size() > 60, "addresses: %d" % town.addresses.size())
	check(town.restaurants.size() == 9, "restaurants: %d" % town.restaurants.size())
	check(town.stores.size() == 2, "stores: %d" % town.stores.size())
	check(not town.station.is_empty(), "flex station exists")
	check(town.homes.size() == 4, "homes: %d" % town.homes.size())
	print("  interactables: %d" % get_tree().get_nodes_in_group("interactable").size())
	for n in get_tree().get_nodes_in_group("interactable"):
		n.get_prompt()

	print("Driving")
	var car = main.car
	await frames(60)
	check(car.global_position.y > -0.3 and car.global_position.y < 2.0, "car rests on ground (y=%.2f)" % car.global_position.y)
	main.enter_car()
	check(main.is_driving(), "entered car")
	var start: Vector3 = car.global_position
	Input.action_press("move_forward")
	await frames(240)
	Input.action_release("move_forward")
	var v: Vector3 = car.linear_velocity
	var fwd: float = v.dot(car.global_basis.z)
	print("  after 4s throttle: speed %.1f m/s (%.0f mph), forward component %.1f" % [v.length(), v.length() * 2.237, fwd])
	check(fwd > 8.0, "car accelerates forward")
	check(car.global_basis.y.y > 0.9, "car stays upright")
	Input.action_press("move_forward")
	await frames(120)
	print("  top-ish speed: %.1f m/s (%.0f mph)" % [car.linear_velocity.length(), car.speed_mph()])
	Input.action_press("move_left")
	await frames(120)
	Input.action_release("move_left")
	Input.action_release("move_forward")
	check(car.global_basis.y.y > 0.8, "hard turn at speed doesn't flip the car (up=%.2f)" % car.global_basis.y.y)
	var t0 := Time.get_ticks_msec()
	Input.action_press("move_back")
	var brake_frames := 0
	while car.linear_velocity.dot(car.global_basis.z) > 1.0 and brake_frames < 600:
		await frames(1)
		brake_frames += 1
	Input.action_release("move_back")
	print("  braking took %.1f s" % (brake_frames / 60.0))
	await frames(60)
	print("  after braking: speed %.2f m/s, upright %.2f, moved %.0f m" % [car.linear_velocity.length(), car.global_basis.y.y, car.global_position.distance_to(start)])
	check(car.linear_velocity.length() < 3.0, "car brakes to a stop")
	check(Game.odometer > GameData.CARS.rustwagon.odometer, "odometer advanced")
	main.exit_car()
	check(not main.is_driving(), "exited car")

	print("Traffic")
	var tr: Traffic = main.traffic
	check(tr.cars.size() >= 10, "traffic cars: %d" % tr.cars.size())
	var start_pos: Array = []
	for c in tr.cars:
		start_pos.append(c.global_position)
	for i in 240:
		await get_tree().physics_frame
	var moved := 0
	var on_road := 0
	for i in tr.cars.size():
		var p: Vector3 = tr.cars[i].global_position
		if p.distance_to(start_pos[i]) > 5.0:
			moved += 1
		var fx := fposmod(p.x, 90.0)
		var fz := fposmod(p.z, 90.0)
		if minf(fx, 90.0 - fx) < 7.5 or minf(fz, 90.0 - fz) < 7.5:
			on_road += 1
	check(moved >= tr.cars.size() - 3, "traffic moves (%d/%d)" % [moved, tr.cars.size()])
	check(on_road == tr.cars.size(), "traffic stays on roads (%d/%d)" % [on_road, tr.cars.size()])
	# Park the player's car in front of a traffic car: it must stop short of it.
	var ai: Node3D = tr.cars[0]
	var block := ai.global_position + ai.global_basis.z * 13.0
	main.car.teleport(Transform3D(ai.global_basis, block + Vector3(0, 0.5, 0)))
	for i in 240:
		await get_tree().physics_frame
	var gap_now: float = ai.global_position.distance_to(main.car.global_position)
	check(ai.speed < 0.5 and gap_now > 4.0, "traffic stops for your car (gap %.1f m, speed %.1f)" % [gap_now, ai.speed])
	main.car.teleport(main.town.car_spawn)
	await _police_tests(tr)
	await _ui_tests()
	await _pedestrian_tests()

	print("Phone screens")
	for app in ["", "yoober", "drift", "doordish", "instacrate", "jungleflex", "bank", "garage", "maps", "me"]:
		main.phone.open_app(app)
		await frames(2)
	main.phone.close()
	check(true, "all phone screens built")

	print("DoorDish job")
	Gigs.set_online("doordish", true)
	Gigs._make_offer("doordish")
	var o: Dictionary = Gigs.offers.back()
	var money0: float = Game.money
	Gigs.accept(o.id)
	check(Gigs.job.stage == "to_restaurant", "accepted, heading to restaurant")
	check(not Gigs.target().is_empty(), "GPS target set")
	await frames(30)
	var gps: GPS = main.gps
	check(gps.route.size() >= 2 and gps.instruction != "", "turn-by-turn: %s, %s" % [gps.instruction, gps.distance_text])
	# Route from one corner of the grid to the other must turn once.
	gps.update(Vector3(5, 0, 2), Vector3(1, 0, 0), Vector3(360, 0, 268), "Test", true)
	check(gps.turn in ["left", "right"] and gps.instruction.begins_with("Turn"), "corner route: %s (%s)" % [gps.instruction, gps.turn])
	gps.update(Vector3(5, 0, 2), Vector3(-1, 0, 0), Vector3(360, 0, 268), "Test", true)
	check(gps.turn == "uturn", "u-turn when facing away")
	await _use_nearest_with("Pick up DoorDish", Gigs.job.restaurant.door, 15.0)
	check(Gigs.job.get("stage", "") == "to_customer", "picked up food")
	await _use_nearest_with("Leave", Gigs.job.customer.door, 4.0)
	check(Gigs.job.get("stage", "") == "confirm_photo", "left at door")
	Gigs.confirm_photo()
	check(Gigs.job.is_empty() and Game.money > money0, "paid $%.2f" % (Game.money - money0))

	print("Instacrate job")
	Gigs.set_online("instacrate", true)
	Gigs._make_offer("instacrate")
	o = Gigs.offers.filter(func(x): return x.app == "instacrate").back()
	Gigs.accept(o.id)
	for item in o.items:
		await _use_nearest_with("Grab " + item, Gigs.job.store.door, 40.0)
	check(Gigs.job.get("stage", "") == "checkout", "all items grabbed")
	await _use_nearest_with("Check out", Gigs.job.store.door, 25.0)
	check(Gigs.job.get("stage", "") == "to_customer", "checked out")
	await _use_nearest_with("Leave", Gigs.job.customer.door, 4.0)
	Gigs.confirm_photo()
	check(Gigs.job.is_empty(), "grocery delivered")

	print("Yoober ride")
	check(Gigs.ineligible_reason("yoober") != "", "rustwagon is not eligible for rides")
	Game.car_id = "civil"
	check(Gigs.ineligible_reason("yoober") == "", "civil is eligible")
	Gigs.set_online("yoober", true)
	Gigs._make_offer("yoober")
	o = Gigs.offers.filter(func(x): return x.app == "yoober").back()
	Gigs.accept(o.id)
	car.teleport(Transform3D(Basis.IDENTITY, Gigs.job.pickup.curb + Vector3(0, 0.8, 0)))
	main.enter_car()
	await frames(60)
	check(Gigs.can_start_trip(), "can start trip at pickup")
	Gigs.start_trip()
	car.teleport(Transform3D(Basis.IDENTITY, Gigs.job.dropoff.curb + Vector3(0, 0.8, 0)))
	await frames(60)
	check(Gigs.can_end_trip(), "can end trip at dropoff")
	money0 = Game.money
	Gigs.end_trip()
	check(Gigs.job.is_empty() and Game.money > money0, "ride paid $%.2f" % (Game.money - money0))
	main.exit_car()

	print("Jungle Flex block")
	Gigs.set_online("jungleflex", true)
	Game.minute = 8 * 60.0
	Gigs._tick_minute()
	var blocks: Array = Gigs.offers.filter(func(x): return x.app == "jungleflex")
	check(blocks.size() > 0, "block offered")
	if blocks.size() > 0:
		Gigs.accept(blocks[0].id)
		Game.minute = 9 * 60.0 + 45.0
		car.teleport(Transform3D(Basis.IDENTITY, town.station.load_point + Vector3(0, 0.8, 0)))
		main.enter_car()
		await frames(60)
		check(Gigs.can_scan(), "can scan at station")
		Gigs.scan_packages()
		main.exit_car()
		while Gigs.job.get("stage", "") == "delivering":
			var t: Dictionary = Gigs.target()
			var n: int = Gigs.job.stops.size()
			await _use_nearest_with("Deliver", t.pos, 4.0)
			if Gigs.job.get("stops", []).size() == n:
				break
		check(Gigs.job.is_empty(), "block complete")

	print("Needs, bills, sleep")
	Game.bladder = 50.0
	Game.use_restroom()
	check(Game.bladder < 2.0, "restroom works")
	var d0: int = Game.day
	Game.money = 5000.0
	Game.sleep(10.0, 1.0)
	check(Game.energy > 50.0, "sleep restores energy (%.0f)" % Game.energy)
	Game.advance(1440.0 * 3)
	check(Game.day >= d0 + 3, "3 days passed")
	check(Game.unpaid_bills().all(func(b): return b.due_day > Game.day or b.paid), "bills auto-paid")
	Game.money = 0.0
	Game.advance(1440.0 * 6)
	check(Game.evicted, "evicted after not paying rent")
	check(not Game.phone_service, "phone suspended after not paying")

	print("Shops")
	Game.money = 40000.0
	check(Game.oil_change() and Game.oil_life == 100.0, "oil change")
	check(Game.replace_tires(), "tires")
	check(Game.buy_car("voltz") and Game.car_id == "voltz", "bought a car")
	check(Game.sign_lease("house") and Game.home_id == "house", "signed a lease")
	Game.save_game()
	Game.money = 1.0
	main.load_game()
	check(Game.money > 1000.0, "save/load round trip")

	await frames(10)
	print("\n%s: %d failure(s)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _police_tests(tr: Traffic) -> void:
	print("Police")
	check(tr.cops.size() == Traffic.COP_COUNT, "police cars: %d" % tr.cops.size())
	var car = main.car
	main.enter_car()
	await frames(5)
	check(car.mirrors_visible(), "mirrors on in first person")
	await frames(10)
	check(main.hud._mirrors.rear.visible and main.hud._mirrors.left.visible, "HUD shows mirrors")
	check(car.mirror_texture("rear") != null, "rearview has a texture")
	car.toggle_camera()
	await frames(2)
	check(not main.hud._mirrors.rear.visible, "mirrors hidden in chase camera")
	car.toggle_camera()
	tr.police_enabled = true
	var cop = tr.cops[0]
	var fwd: Vector3 = cop.global_basis.z
	# Speeding behind the cop: it can't see you.
	await _speed_past(car, cop.global_position - fwd * 22.0, -fwd, 30)
	check(tr.chaser == null, "cop doesn't see you speeding behind it")
	# Speeding in front of it: chase.
	fwd = cop.global_basis.z
	await _speed_past(car, cop.global_position + fwd * 22.0, fwd, 45)
	check(tr.chaser == cop, "cop sees you speeding in front of it and gives chase (%s)" % tr.chase_reason)
	check(main.hud._police.visible, "HUD shows the pull-over alert")
	var tickets0: int = int(Game.stats.get("tickets", 0))
	var money0: float = Game.money
	var bills0: int = Game.unpaid_bills().size()
	car.linear_velocity = Vector3.ZERO
	var waited := 0
	while tr.chaser != null and waited < 900:
		await frames(1)
		waited += 1
	print("  cop reached you in %.1f s, %.1f m away" % [waited / 60.0, cop.global_position.distance_to(car.global_position)])
	check(int(Game.stats.get("tickets", 0)) == tickets0 + 1, "pulling over gets you a ticket")
	check(Game.money < money0 or Game.unpaid_bills().size() > bills0, "ticket costs money ($%.2f -> $%.2f)" % [money0, Game.money])
	check(cop.mode == "return", "cop heads back to patrol")
	var back := 0
	while cop.mode != "patrol" and back < 1200:
		await frames(1)
		back += 1
	check(cop.mode == "patrol", "cop rejoins traffic (%.1f s)" % (back / 60.0))
	tr.police_enabled = false
	main.car.teleport(main.town.car_spawn)
	await frames(3)
	main.exit_car()
	# Phone upgrade shows police on the minimap.
	check(not cop.marker.visible, "no cop markers with the stock phone")
	Game.money += 500.0
	check(Game.buy_phone_upgrade() and Game.phone_pro, "bought the phone upgrade")
	await frames(2)
	check(cop.marker.visible and cop.marker.get_child(0).layers == 2, "cop markers on the minimap")


func _speed_past(car, pos: Vector3, dir: Vector3, n: int) -> void:
	car.teleport(Transform3D(Basis.looking_at(-dir, Vector3.UP), pos + Vector3(0, 0.6, 0)))
	for i in n:
		car.linear_velocity = dir * 20.0
		await frames(1)


func _pedestrian_tests() -> void:
	print("Pedestrians")
	var peds: Pedestrians = main.pedestrians
	check(peds.people.size() == Pedestrians.COUNT, "pedestrians: %d" % peds.people.size())
	var start: Array = peds.people.map(func(p): return p.global_position)
	await frames(180)
	var moved := 0
	var on_walk := 0
	for i in peds.people.size():
		var p: Vector3 = peds.people[i].global_position
		if p.distance_to(start[i]) > 1.0:
			moved += 1
		var fx := fposmod(p.x, 90.0)
		var fz := fposmod(p.z, 90.0)
		if absf(minf(fx, 90.0 - fx) - Pedestrians.INSET) < 0.6 or absf(minf(fz, 90.0 - fz) - Pedestrians.INSET) < 0.6:
			on_walk += 1
	check(moved >= peds.people.size() - 4, "pedestrians walk (%d/%d)" % [moved, peds.people.size()])
	check(on_walk == peds.people.size(), "pedestrians stay on sidewalks (%d/%d)" % [on_walk, peds.people.size()])


func _ui_tests() -> void:
	print("Pause menu and tutorial")
	main.pause_menu.open()
	check(get_tree().paused and main.pause_menu.is_open, "pause menu pauses the game")
	main.pause_menu.close()
	check(not get_tree().paused, "resume")
	check(InputMap.action_get_events("interact").any(func(e): return e is InputEventJoypadButton), "gamepad bound")
	main.pause_menu.open()
	main.pause_menu._show_settings(true)
	check(main.pause_menu._settings.visible, "settings panel opens")
	main.pause_menu.close()
	check(Sfx.get_stream("siren").get_length() > 1.0 and Sfx.get_stream("engine").loop_mode == AudioStreamWAV.LOOP_FORWARD, "sounds synthesized")
	var tut: Tutorial = main.tutorial
	main.start_tutorial()
	check(tut.active and tut.step == 0, "tutorial starts")
	main.player.global_position += Vector3(6, 0, 0)
	await frames(45)
	check(tut.step == 1, "tutorial: walking done")
	main.phone.open()
	await frames(45)
	check(tut.step == 2, "tutorial: phone opened")
	main.phone.close()
	await frames(45)
	check(tut.step == 3 and not tut.target().is_empty(), "tutorial: heading to the car")
	for i in range(3, tut._steps.size()):
		tut._go(i)
		check(tut._body.text != "", "tutorial step %d: %s" % [i + 1, tut._steps[i].title])
		if i >= 4 and i <= 10:
			check(not tut.target().is_empty(), "  has a GPS target: %s" % tut.target().get("label", ""))
	tut.finish(true)
	check(not tut.active, "tutorial skipped")


## Teleports the player next to the closest interactable whose prompt contains `text`
## (searching within `radius` of `near_pos`) and uses it.
func _use_nearest_with(text: String, near_pos: Vector3, radius: float) -> void:
	var best = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("interactable"):
		var d: float = n.global_position.distance_to(near_pos)
		if d < radius + 50.0 and d < best_d and text in n.get_prompt():
			best = n
			best_d = d
	if best == null:
		print("  (no interactable with '%s' near %s)" % [text, near_pos])
		return
	main.player.global_position = best.global_position - Vector3(0, 0.9, 0)
	await frames(3)
	check(main._current == best, "main picks '%s'" % best.get_prompt())
	best.use()
	await frames(2)
