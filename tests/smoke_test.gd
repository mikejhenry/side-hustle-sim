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
	# Keep the same cars and open roads through the older tests; _city_life_tests covers both.
	main.traffic.auto_density = false
	main.construction.clear()
	await frames(30)
	var town = main.town
	print("World")
	check(town.addresses.size() > 60, "addresses: %d" % town.addresses.size())
	check(town.restaurants.size() == 19, "restaurants: %d" % town.restaurants.size())
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
		# On the grid, or out on the curved Churchmans Loop.
		var curved: bool = tr.cars[i]._legs[0].size() > 6
		if minf(fx, 90.0 - fx) < 7.5 or minf(fz, 90.0 - fz) < 7.5 or curved:
			on_road += 1
	# Some will be waiting at lights or in the rush-hour crawl.
	check(moved >= tr.cars.size() * 0.8, "traffic moves (%d/%d)" % [moved, tr.cars.size()])
	check(on_road == tr.cars.size(), "traffic stays on roads (%d/%d)" % [on_road, tr.cars.size()])
	# Park the player's car in front of a traffic car: it must stop short of it (and honk).
	var ai: Node3D = tr.cars[0]
	for c in tr.cars:
		if not c.is_cop and c._legs[0][5] and c._legs[0].size() <= 6 and float(c._legs[0][3]) - c._s > 40.0:
			ai = c
			break
	var honks0: int = tr.honks
	var block := ai.global_position + ai.global_basis.z * 13.0
	main.car.teleport(Transform3D(ai.global_basis, block + Vector3(0, 0.5, 0)))
	# Stand nearby, so you'd hear the honking.
	var p_home: Vector3 = main.player.global_position
	main.player.global_position = block + Traffic.right_of(ai.global_basis.z) * 8.0 + Vector3(0, 0.5, 0)
	# It may be waiting at a red light first, so give it time to roll up and stop.
	for i in 900:
		await get_tree().physics_frame
		if i > 240 and ai.speed < 0.1:
			break
	var gap_now: float = ai.global_position.distance_to(main.car.global_position)
	check(ai.speed < 0.5 and gap_now > 4.0, "traffic stops for your car (gap %.1f m, speed %.1f)" % [gap_now, ai.speed])
	for i in 300:
		await get_tree().physics_frame
		if tr.honks > honks0:
			break
	check(tr.honks > honks0, "the driver behind you honks")
	main.player.global_position = p_home
	main.car.teleport(main.town.car_spawn)
	await _police_tests(tr)
	await _ui_tests()
	await _pedestrian_tests()
	await _light_tests(tr)
	await _strip_tests()
	await _weather_tests()
	await _driving_feel_tests()
	await _map_tests()
	await _jump_tests()
	await _city_life_tests()
	await _day_night_tests()

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
	await frames(3)
	var held: String = main.player.carrying()
	check(held in ["food_bag", "pizza"], "carrying the order (%s)" % held)
	var held_node: Node3D = main.player._carry_nodes[0] if not main.player._carry_nodes.is_empty() else null
	var palm: Vector3 = main.player._human.palm("R") if main.player._human else Vector3.ZERO
	check(held_node != null and (main.player._human == null or held_node.global_position.distance_to(palm) < 0.35), "order is in his hand")
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
	await frames(3)
	check(main.player.carrying() == "grocery", "carrying grocery bags")
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
			check(not Gigs.job.photo_due.is_empty(), "package waits for a photo")
			Gigs.confirm_package_photo()
			if Gigs.job.get("stops", []).size() == n:
				break
		check(Gigs.job.is_empty(), "block complete")

	await _multi_app_tests()

	print("Needs, bills, sleep")
	Game.bladder = 50.0
	Game.use_restroom()
	check(Game.bladder < 2.0, "restroom works")
	var d0: int = Game.day
	Game.money = 5000.0
	Game.sleep(10.0, 1.0)
	check(Game.energy > 50.0, "sleep restores energy (%.0f)" % Game.energy)
	check(GameData.BILL_CYCLE_DAYS == 30, "bills are monthly")
	Game.advance(1440.0 * GameData.BILL_CYCLE_DAYS)
	check(Game.day >= d0 + GameData.BILL_CYCLE_DAYS, "a month passed")
	check(Game.unpaid_bills().all(func(b): return b.due_day > Game.day or b.paid), "bills auto-paid")
	Game.money = 0.0
	Game.advance(1440.0 * (GameData.BILL_CYCLE_DAYS + GameData.EVICTION_GRACE_DAYS + 1))
	check(Game.evicted, "evicted after not paying rent")
	check(not Game.phone_service, "phone suspended after not paying")

	print("Financing")
	Game.money = 40000.0
	var terms: Dictionary = Game.finance_terms("passit")
	check(terms.total > float(GameData.CARS.passit.price), "financing costs more than cash ($%.0f vs $%.0f)" % [terms.total, GameData.CARS.passit.price])
	check(Game.finance_car("passit") and Game.car_id == "passit" and not Game.loan.is_empty(), "financed a car")
	check(not Game.buy_car("civil"), "can't trade in a car you still owe on")
	Game.money = 0.0
	# The first payment is billed at the start of the next cycle and due at its end.
	Game.advance(1440.0 * (GameData.BILL_CYCLE_DAYS * 2 + GameData.REPO_GRACE_DAYS + 1))
	check(Game.car_id == "rustwagon" and Game.loan.is_empty(), "car repossessed after a missed payment")
	Game.money = 40000.0
	check(Game.finance_car("pious"), "financed again")
	var payoff: float = Game.loan_payoff()
	check(payoff > 0.0 and Game.pay_off_loan() and Game.loan.is_empty() and Game.car_id == "pious", "paid off loan ($%.0f)" % payoff)

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
	await _polish_tests()

	await frames(10)
	print("\n%s: %d failure(s)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _light_tests(tr: Traffic) -> void:
	print("Traffic lights and cameras")
	var tc: TrafficControl = main.traffic_control
	check(tc.cameras.size() >= 6, "cameras: %d" % tc.cameras.size())
	tc.set_physics_process(false)
	tc._t = 25.0   # north-south red, east-west green
	tc._update_lamps(true)
	check(tc.color("ns") == "red" and tc.color("ew") == "green", "light cycle")
	check(tc.must_stop(Vector2i(2, 2), Vector2i(0, 1), 20.0) and not tc.must_stop(Vector2i(2, 2), Vector2i(1, 0), 20.0), "who stops at a light")
	# An AI car heading south toward the light at (2, 2) stops before the intersection.
	var ai: Traffic.AICar = tr.cars[1]
	# Clear the street (other cars, people in the crosswalk) so nothing else stops it.
	main.pedestrians.process_mode = Node.PROCESS_MODE_DISABLED
	for p in main.pedestrians.people:
		p.crossing = false
	for c in tr.cars.duplicate():
		if c != ai and not c.is_cop and c.global_position.distance_to(Vector3(2, 0, 1.5) * main.town.B) < 70.0:
			tr.cars.erase(c)
			tr._park(c)
	ai._legs.clear()
	ai._node_from = Vector2i(2, 1)
	ai._dir = Vector2i(0, 1)
	ai._queue_straight()
	ai._s = 15.0
	ai.speed = 8.0
	for i in 720:
		await get_tree().physics_frame
		if i > 300 and ai.speed < 0.3:
			break
	var stop_z: float = 2 * main.town.B - Traffic.HALF
	check(ai.speed < 0.5 and ai.global_position.z < stop_z, "AI car stops at a red light (%.1f m short, speed %.1f, braking for %s)" % [stop_z - ai.global_position.z, ai.speed, ai.blocker])
	tc._t = 2.0    # north-south green
	tc._update_lamps(true)
	for i in 240:
		await get_tree().physics_frame
	check(ai.global_position.z > stop_z or ai._dir != Vector2i(0, 1), "AI car goes on green")
	main.pedestrians.process_mode = Node.PROCESS_MODE_INHERIT
	# Red light camera: drive into a red at (2, 2) heading south.
	tc._t = 25.0
	var c := Vector3(2 * main.town.B, 0, 2 * main.town.B)
	var bills0 := Game.unpaid_bills().size()
	tc._inside.clear()
	tc._check_red_lights(c + Vector3(-3.5, 0, -14), Vector3(0, 0, 12))
	tc._check_red_lights(c + Vector3(-3.5, 0, -6), Vector3(0, 0, 12))
	check(Game.unpaid_bills().size() == bills0 + 1, "red light camera mails a ticket")
	tc._check_red_lights(c + Vector3(-3.5, 0, -2), Vector3(0, 0, 12))
	check(Game.unpaid_bills().size() == bills0 + 1, "only one ticket per red light")
	# Speed camera: pass it at 60 mph.
	var cam: Dictionary = tc.cameras.filter(func(x): return x.kind == "speed")[0]
	var along: Vector3 = cam.axis
	var lane: Vector3 = cam.pos + Traffic.right_of(along) * Traffic.LANE
	tc._cam_side.clear()
	tc._check_speed_cameras(lane - along * 5.0, along * 27.0)
	tc._check_speed_cameras(lane + along * 5.0, along * 27.0)
	check(Game.unpaid_bills().size() == bills0 + 2, "speed camera mails a ticket")
	tc._check_speed_cameras(lane - along * 5.0 + Vector3(0, 0, 0.01), along * 12.0)
	tc._check_speed_cameras(lane + along * 5.0, along * 12.0)
	check(Game.unpaid_bills().size() == bills0 + 2, "no ticket under the limit")
	# Markers only with the upgraded phone.
	var had := Game.phone_pro
	Game.phone_pro = false
	tc.set_physics_process(true)
	await get_tree().physics_frame
	var hidden: bool = not cam.marker.visible
	Game.phone_pro = true
	await get_tree().physics_frame
	check(hidden and cam.marker.visible, "cameras show on the map with the upgraded phone")
	Game.phone_pro = had
	for b in Game.bills:
		if b.kind == "ticket":
			b.paid = true
	# Prompts follow the device you're using.
	Game.using_pad = false
	var kb := Game.key("interact")
	Game.using_pad = true
	var pad := Game.key("interact")
	Game.using_pad = false
	check(kb == "E" and pad == "X", "prompts switch between keyboard and gamepad")


func _police_tests(tr: Traffic) -> void:
	print("Police")
	check(tr.cops.size() == Traffic.COP_COUNT, "police cars: %d" % tr.cops.size())
	var car = main.car
	main.enter_car()
	await frames(5)
	check(car.mirrors_visible(), "mirrors on in first person")
	await frames(3)
	check(car._mirror_glass.size() == 3 and car._mirror_glass[0][1].get_shader_parameter("tint") == Color.WHITE, "mirror glass in the car shows the picture")
	Game.mirror_mode = 1
	await frames(10)
	check(main.hud._mirrors.rear.visible and main.hud._mirrors.left.visible, "HUD shows mirrors")
	check(car.mirror_texture("rear") != null, "rearview has a texture")
	car.toggle_camera()
	await frames(2)
	check(not main.hud._mirrors.rear.visible, "mirrors hidden in chase camera")
	car.toggle_camera()
	# Out of the car and back in (what Mike did after a delivery): mirrors come back.
	main.exit_car()
	await frames(5)
	main.enter_car()
	await frames(5)
	check(main.hud._mirrors.rear.visible and car._mirror_glass[0][1].get_shader_parameter("tint") == Color.WHITE, "mirrors back after getting out and in")
	Game.mirror_mode = 0
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


func _strip_tests() -> void:
	print("Route 40 strip, curved road, apartments")
	var town = main.town
	var mcd: Dictionary = town.restaurants.filter(func(r): return r.name == "Sub Way Out")[0]
	check(mcd.door.x > town.N * town.B + town.RING, "Sub Way Out is past the beltway")
	var gps: GPS = main.gps
	gps.update(Vector3(225, 0, 90), Vector3(1, 0, 0), mcd.curb, "Sub Way Out", true)
	check("Churchmans Loop" in gps._names, "GPS routes onto the curved road (%s)" % gps.instruction)
	var curved := 0
	for i in range(1, gps.route.size() - 1):
		var d1 := (gps.route[i] - gps.route[i - 1]).normalized()
		var d2 := (gps.route[i + 1] - gps.route[i]).normalized()
		if d1.dot(d2) < 0.9999 and d1.dot(d2) > 0.9:
			curved += 1
	check(curved > 5, "route follows the curve (%d bends)" % curved)
	# An AI car put on the loop drives it and comes out at the other end.
	var tr: Traffic = main.traffic
	var ai: Traffic.AICar = tr.cars[2]
	ai._legs.clear()
	ai._node_from = Vector2i(town.N, 1)
	ai._dir = Vector2i(1, 0)
	ai._queue_straight()
	ai._s = 0.0
	ai.speed = 10.0
	var far_x := 0.0
	var off_road := 0.0
	for i in 5400:
		await get_tree().physics_frame
		far_x = maxf(far_x, ai.global_position.x)
		var q: Dictionary = gps._snap(ai.global_position)
		off_road = maxf(off_road, q.point.distance_to(Vector3(ai.global_position.x, 0, ai.global_position.z)))
		if ai._legs[0].size() <= 6 and far_x > 650.0:
			break
	check(far_x > 650.0, "AI car drives the loop (reached x=%.0f)" % far_x)
	check(off_road < 6.0, "AI car stays in its lane (max %.1f m off center)" % off_road)
	check(ai.global_position.distance_to(Vector3(town.N * town.B, 0, 3 * town.B)) < 15.0, "AI car comes back in on Pennsylvania Ave (%s)" % str(ai.global_position))
	# Apartments: upstairs doors, elevator, stairs you can walk up.
	var upstairs: Array = town.addresses.filter(func(a): return a.has("floor"))
	check(upstairs.size() == 12, "upstairs apartments: %d" % upstairs.size())
	var w: Dictionary = town.walkups[0]
	var b: Node3D = w.node
	var p: Player = main.player
	var fl: Array = w.flights[0]
	var bottom: Vector3 = b.to_global(fl[0])
	var top: Vector3 = b.to_global(fl[1])
	var dir := (top - bottom)
	dir.y = 0.0
	dir = dir.normalized()
	p.global_position = bottom - dir * 1.5 + Vector3(0, 0.2, 0)
	p.velocity = Vector3.ZERO
	p.yaw = atan2(-dir.x, -dir.z)
	await frames(5)
	Input.action_press("move_forward")
	for i in 240:
		await get_tree().physics_frame
		if p.global_position.y > top.y - 0.2:
			break
	Input.action_release("move_forward")
	check(p.global_position.y > top.y - 0.4, "walked up the stairs to floor 2 (y %.1f, need %.1f)" % [p.global_position.y, top.y])
	# Elevator from the lobby to the top floor.
	var el = null
	for n in get_tree().get_nodes_in_group("interactable"):
		if b.is_ancestor_of(n) and "elevator (floor 1)" in n.get_prompt():
			el = n
	check(el != null, "lobby elevator")
	var top_y: float = b.global_position.y + (w.floors - 1) * StripDistrict.FLOOR_H
	if el:
		el.use()
		await frames(2)
		var btn = null
		for c in main.hud._menu_list.get_children():
			if c is Button and c.text == "Floor %d" % w.floors:
				btn = c
		check(btn != null, "elevator offers floor %d" % w.floors)
		if btn:
			btn.pressed.emit()
		await frames(30)
	check(p.global_position.y > top_y - 0.3 and p.is_on_floor(), "elevator to the top floor (y %.1f)" % p.global_position.y)
	p.global_position = main.town.spawn_point
	await frames(5)


func _weather_tests() -> void:
	print("Weather")
	var kinds := {}
	var foggy := 0
	for d in range(1, 61):
		var f: Dictionary = Game.forecast(d)
		kinds[f.kind] = true
		if f.fog:
			foggy += 1
	check(kinds.has("rain") and kinds.has("snow") and kinds.has("clear") and foggy > 5, "60-day forecast has variety (%s, %d foggy mornings)" % [str(kinds.keys()), foggy])
	var grip0: float = Game.grip_factor()
	Game.weather_override = "rain"
	Game._update_weather()
	await frames(5)
	check(Game.weather == "rain" and main.weather_fx._rain.emitting, "rain falls")
	var food: float = Game.weather_boost("food")
	var flex: float = Game.weather_boost("flex")
	check(food > Game.weather_boost("grocery") and Game.weather_boost("grocery") > flex and flex > 1.0, "rain pay boost: food %.2fx, flex %.2fx" % [food, flex])
	check(Game.grip_factor() < grip0, "wet roads have less grip")
	Gigs.set_online("doordish", true)
	Gigs._make_offer("doordish")
	var o: Dictionary = Gigs.offers.back()
	check(o.get("weather_pay", 0.0) > 0.0, "food offer includes a rain boost ($%.2f)" % o.get("weather_pay", 0.0))
	Gigs.decline(o.id)
	Gigs.set_online("doordish", false)
	Game.weather_override = "snow"
	Game._update_weather()
	await frames(5)
	check(main.weather_fx._snow.emitting and not main.weather_fx._rain.emitting and main.env.fog_enabled, "snow falls, with haze")
	Game.weather_override = "clear"
	Game._update_weather()
	await frames(5)
	check(not main.weather_fx._snow.emitting and Game.weather_boost("food") == 1.0, "clear again")
	Game.weather_override = ""
	Game._update_weather()


# --- Driving feel: weather grip, signals, wipers, dashboard, radio, GPS mount --------------

const TEST_ROAD := Vector3(182.0, 0.6, 60.0)   # a straight stretch heading +Z


func _place_test_car(car, speed: float) -> void:
	car.teleport(Transform3D(Basis.IDENTITY, TEST_ROAD))
	await frames(20)
	car.linear_velocity = car.global_basis.z * speed
	await frames(1)


## Distance to stop from 20 m/s with full brakes.
func _stopping_distance(car) -> float:
	await _place_test_car(car, 20.0)
	var from: Vector3 = car.global_position
	Input.action_press("move_back")
	var n := 0
	while car.linear_velocity.dot(car.global_basis.z) > 0.5 and n < 600:
		await frames(1)
		n += 1
	Input.action_release("move_back")
	return Vector2(car.global_position.x - from.x, car.global_position.z - from.z).length()


## Largest sideways slide during a hard turn on the gas.
func _turn_slip(car) -> float:
	await _place_test_car(car, 14.0)
	Input.action_press("move_forward")
	Input.action_press("move_left")
	var most := 0.0
	for i in 90:
		await frames(1)
		most = maxf(most, car.slip_speed)
	Input.action_release("move_left")
	Input.action_release("move_forward")
	return most


func _driving_feel_tests() -> void:
	print("Driving feel")
	var car: Car = main.car
	var d: Dashboard = car.dash
	main.traffic.process_mode = Node.PROCESS_MODE_DISABLED
	main.pedestrians.process_mode = Node.PROCESS_MODE_DISABLED
	Game.using_pad = false
	main.enter_car()
	var tread := Game.tire_tread
	Game.tire_tread = 100.0
	Game.weather_override = "clear"
	Game._update_weather()
	var dry_stop: float = await _stopping_distance(car)
	var dry_slip: float = await _turn_slip(car)
	Game.weather_override = "snow"
	Game._update_weather()
	Game.weather_amount = 1.0
	var snow_stop: float = await _stopping_distance(car)
	var snow_slip: float = await _turn_slip(car)
	print("  stopping from 45 mph: dry %.1f m, snow %.1f m; slide in a hard turn: dry %.1f m/s, snow %.1f m/s" % [dry_stop, snow_stop, dry_slip, snow_slip])
	check(snow_stop > dry_stop * 1.2, "snow takes longer to stop")
	check(snow_slip > dry_slip, "the car slides more on snow")
	check(car.global_basis.y.y > 0.8, "still upright after sliding")
	# Rain: worn tires hydroplane at speed through standing water; slow and new tires don't.
	Game.weather_override = "storm"
	Game._update_weather()
	Game.weather_amount = 1.0
	check(car.hydroplane_mph() > 30.0, "new tires hydroplane only above %.0f mph" % car.hydroplane_mph())
	await _place_test_car(car, 13.0)
	var hydro := false
	for i in 180:
		car.linear_velocity = car.global_basis.z * 13.0
		await frames(1)
		hydro = hydro or car.hydroplaning > 0.0
	check(not hydro, "no hydroplaning at 29 mph on new tires")
	Game.tire_tread = 10.0
	await _place_test_car(car, 22.0)
	for i in 240:
		car.linear_velocity = car.global_basis.z * 22.0
		await frames(1)
		hydro = hydro or car.hydroplaning > 0.0
	check(hydro, "bald tires hydroplane at 49 mph in a storm (above %.0f mph)" % car.hydroplane_mph())
	check(car.hydroplane_risk(), "the HUD warns about hydroplaning")
	Game.tire_tread = 100.0
	car.hydroplaning = 0.0

	# Wipers: drops build up on the glass, the wipers clear them.
	Game.weather_override = "rain"
	Game._update_weather()
	Game.weather_amount = 1.0
	var ws: Windshield = main.hud.windshield
	ws.drops.clear()
	if d.wiper_mode != 0:
		d.wiper_mode = 0
	await _place_test_car(car, 0.0)
	await frames(180)
	var wet: float = ws.coverage()
	d.cycle_wipers()
	var wiped := 0.0
	for i in 240:
		await frames(1)
		wiped += ws.coverage() / 240.0
	print("  windshield: %.0f%% covered, %.0f%% on average with the wipers on" % [wet * 100.0, wiped * 100.0])
	check(wet > 0.2 and wiped < wet * 0.8, "rain covers the windshield and the wipers clear it")
	d.wiper_mode = 2
	d.cycle_wipers()
	check(d.wiper_mode == 0, "wipers: off, on, fast, off")

	# Turn signals: blink, and cancel themselves after the turn.
	Game.weather_override = "clear"
	Game._update_weather()
	d.set_signal("left")
	check(d.signal_dir == "left" and d.blink_on, "left signal on")
	var toggled := false
	for i in 40:
		await frames(1)
		toggled = toggled or not d.blink_on
	check(toggled, "signal blinks")
	await _place_test_car(car, 7.0)
	Input.action_press("move_left")
	Input.action_press("move_forward")
	await frames(90)
	Input.action_release("move_left")
	Input.action_release("move_forward")
	check(d.signal_dir == "left", "signal stays on through the turn")
	await frames(60)
	check(d.signal_dir == "", "signal cancels after the turn")
	d.set_signal("right")
	d.set_signal("right")
	check(d.signal_dir == "", "pressing the same signal again cancels it")
	d.cycle_signal()
	d.cycle_signal()
	check(d.signal_dir == "right", "D-pad cycles left, right")
	d.cycle_signal()
	d.toggle_hazards()
	check(d.hazards, "hazards on")
	d.toggle_hazards()

	# Dashboard: look at a control and press interact.
	await _place_test_car(car, 0.0)
	var r: Radio = car.radio
	r.set_station(1)
	var target: Interactable = null
	for it in d._controls:
		if it.get_prompt().begins_with("Radio: next"):
			target = it
	check(target != null, "dashboard has a next-station button")
	var local: Vector3 = car.to_local(target.global_position) - car.fp_camera.position
	local = local.normalized()
	car._look_yaw = atan2(local.x, local.z)
	car._look_pitch = asin(local.y)
	await frames(3)
	await get_tree().process_frame
	check(d.focused == target, "looking at the button focuses it")
	check(main.hud._prompt.text.contains("Radio: next station"), "prompt names the control: %s" % main.hud._prompt.text)
	main._current.use()
	check(r.station == 2, "the button changes the station (now %s)" % r.display_text())
	car._look_yaw = 0.0
	car._look_pitch = -0.08
	await frames(3)
	await get_tree().process_frame
	check(d.focused == null, "looking at the road focuses nothing")

	# Radio: music renders on a worker thread, then plays; DJs and ads talk over it.
	var waited := 0
	while not r.is_ready(r.current().style) and waited < 900:
		await get_tree().process_frame
		waited += 1
	check(r.is_ready(r.current().style), "station music is ready (%s)" % r.current().style)
	await get_tree().process_frame
	await get_tree().process_frame
	check(r._music.playing, "radio plays while driving")
	r._next_segment = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	check(r.caption != "" and main.hud._radio_panel.visible, "DJ / ad caption shows: %s: %s" % [r.caption_who, r.caption])
	for i in Radio.STATIONS.size() + 1:
		r.next_station()
	check(r.power, "radio cycles through every station and off, then back on")
	r.toggle_power()
	check(not r.power, "radio off")
	await get_tree().process_frame
	check(not r._music.playing, "silent when off")
	r.toggle_power()
	main.exit_car()
	await get_tree().process_frame
	check(not r._music.playing, "radio stops when you get out")

	# GPS mount.
	check(d.phone_screen != null and d.gps_mount, "phone is on the GPS mount")
	main.traffic.process_mode = Node.PROCESS_MODE_INHERIT
	main.pedestrians.process_mode = Node.PROCESS_MODE_INHERIT
	Game.weather_override = ""
	Game._update_weather()
	Game.tire_tread = tread
	main.car.teleport(main.town.car_spawn)
	await frames(10)


func _pedestrian_tests() -> void:
	print("Pedestrians")
	var peds: Pedestrians = main.pedestrians
	check(peds.people.size() == Pedestrians.COUNT, "pedestrians: %d" % peds.people.size())
	# Midday: most people are out, strolling or on their way somewhere.
	var m0: float = Game.minute
	Game.minute = 12 * 60.0 + 10.0
	for p in peds.people:
		p.refresh(true)
	var out: Array = peds.people.filter(func(p): return p.state != "inside")
	check(out.size() >= peds.people.size() / 2, "people are out at lunchtime (%d/%d)" % [out.size(), peds.people.size()])
	var start: Array = out.map(func(p): return p.global_position)
	await frames(180)
	var moved := 0
	var on_walk := 0
	for i in out.size():
		var p: Vector3 = out[i].global_position
		if p.distance_to(start[i]) > 1.0 or out[i].state == "inside":
			moved += 1
		var fx := fposmod(p.x, 90.0)
		var fz := fposmod(p.z, 90.0)
		# On a sidewalk (or the short path between it and a door).
		var walk := absf(minf(fx, 90.0 - fx) - Pedestrians.INSET) < 0.6 or absf(minf(fz, 90.0 - fz) - Pedestrians.INSET) < 0.6
		if walk or out[i].state == "inside" or _near_door_path(p, out[i]._in_door) or _near_door_path(p, out[i].activity.get("door", {})):
			on_walk += 1
	check(moved >= out.size() - 4, "pedestrians walk (%d/%d)" % [moved, out.size()])
	check(on_walk == out.size(), "pedestrians stay on sidewalks (%d/%d)" % [on_walk, out.size()])
	Game.minute = m0


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
	check(not tut.active and Tutorial.is_done(), "tutorial skipped")
	# Someone who finished an older version of the tour sees the new one again.
	var cfg := ConfigFile.new()
	cfg.load(Tutorial.SETTINGS_PATH)
	cfg.set_value("tutorial", "version", Tutorial.VERSION - 1)
	cfg.save(Tutorial.SETTINGS_PATH)
	check(not Tutorial.is_done(), "updated tutorial shows again")
	tut.finish(true)
	await _gamepad_phone_test()


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		Input.parse_input_event(e)
		await frames(3)


## Drive the phone with only the gamepad: Y opens it, D-pad moves, A picks, B backs out.
func _gamepad_phone_test() -> void:
	print("Gamepad menus")
	if main.phone.is_open:
		main.phone.close()
	# Start from keyboard/mouse, so the first gamepad press is also the one that opens the phone.
	Game.using_pad = false
	await _pad(JOY_BUTTON_Y)
	await frames(5)
	check(main.phone.is_open, "Y opens the phone")
	var f = get_viewport().gui_get_focus_owner()
	check(f != null, "phone focuses a button (%s)" % (f.text if f is Button else str(f)))
	var screen0: String = main.phone.current_app
	await _pad(JOY_BUTTON_DPAD_DOWN)
	var f2 = get_viewport().gui_get_focus_owner()
	check(f2 != null and f2 != f, "D-pad moves focus (%s)" % (f2.text if f2 is Button else str(f2)))
	await _pad(JOY_BUTTON_A)
	await frames(5)
	var screen1: String = main.phone.current_app
	check(screen1 != screen0, "A opens the focused app (%s -> %s)" % [screen0, screen1])
	check(get_viewport().gui_get_focus_owner() != null, "app screen has focus")
	await _pad(JOY_BUTTON_B)
	await frames(5)
	var screen2: String = main.phone.current_app
	check(screen2 == screen0 or not main.phone.is_open, "B goes back (%s)" % screen2)
	if main.phone.is_open:
		main.phone.close()
	await _pad(JOY_BUTTON_START)
	await frames(5)
	check(main.pause_menu.is_open, "Start opens the pause menu")
	await _pad(JOY_BUTTON_A)
	await frames(5)
	check(not main.pause_menu.is_open and not get_tree().paused, "A picks Resume")
	Game.using_pad = false


## Teleports the player next to the closest interactable whose prompt contains `text`
## (searching within `radius` of `near_pos`) and uses it.
func _multi_app_tests() -> void:
	print("Multi-apping")
	Game.minute = 12 * 60.0
	for id in ["doordish", "instacrate", "yoober", "drift"]:
		Gigs.set_online(id, true)
	Gigs.offers.clear()
	for id in ["doordish", "instacrate", "yoober", "drift"]:
		Gigs._make_offer(id)
	var by_app := {}
	for o in Gigs.offers:
		by_app[o.app] = o
	Gigs.accept(by_app.doordish.id)
	Gigs.accept(by_app.instacrate.id)
	check(Gigs.jobs.size() == 2 and Gigs.job.app == "doordish", "two apps at once, GPS stays on the first")
	check("Instacrate" in Gigs.others_text(), "HUD lists the other job: %s" % Gigs.others_text())
	check(Gigs.accept_block_reason(by_app.yoober) == "", "a third app is allowed")
	Gigs.accept(by_app.yoober.id)
	check(Gigs.jobs.size() == 3, "three jobs at once")
	check(Gigs.accept_block_reason(by_app.drift) != "", "no second passenger or fourth job")
	Gigs._make_offer("doordish")
	check(Gigs.accept_block_reason(Gigs.offers.back()) != "", "one job per app")
	Gigs.focus("instacrate")
	check(Gigs.job.app == "instacrate" and Gigs.target().label.begins_with("Shop"), "focus moves the GPS")
	Gigs.focus("doordish")
	# World objects work for a job the GPS isn't following.
	var g: Dictionary = Gigs.job_for("grocery")
	for item in g.items:
		await _use_nearest_with("Grab " + item, g.store.door, 40.0)
	check(g.stage == "checkout", "shopped for Instacrate while following DoorDish")
	var f: Dictionary = Gigs.job_for("food")
	await _use_nearest_with("Pick up DoorDish", f.restaurant.door, 15.0)
	check(f.stage == "to_customer", "picked up the DoorDish order")
	f.deadline = Game.total_minutes() - 20.0
	var fee := Gigs.late_fee(f, f.pay)
	check(fee > 0.0 and fee <= f.pay * GameData.LATE_FEE_MAX, "late fee $%.2f" % fee)
	await _use_nearest_with("Leave", f.customer.door, 4.0)
	var money0 := Game.money
	var pay0: float = f.pay
	Gigs.confirm_photo("doordish")
	check(Gigs.job_for("food").is_empty() and Game.money - money0 < pay0, "late delivery paid less ($%.2f of $%.2f)" % [Game.money - money0, pay0])
	check(not Gigs.job.is_empty() and Gigs.job.app != "doordish", "GPS moves on to the next job")
	Gigs.cancel_job("instacrate")
	Gigs.cancel_job("yoober")
	check(Gigs.jobs.is_empty() and Gigs.job.is_empty(), "all jobs cleared")
	for id in ["doordish", "instacrate", "yoober", "drift"]:
		Gigs.set_online(id, false)

	print("Peak heatmaps")
	var hm: Dictionary = Gigs.heat_map("doordish")
	var ok := hm.size() > 4
	var top := 0.0
	for k in hm:
		ok = ok and hm[k] >= 0.0 and hm[k] <= 1.0
		top = maxf(top, hm[k])
	check(ok and is_equal_approx(top, 1.0), "heat map: %d squares, 0..1" % hm.size())
	check(not Gigs.hottest("yoober", 8).is_empty() and not Gigs.hottest("yoober", 23).is_empty(), "hottest zone morning and night")
	check(Gigs.heat_map("yoober", 30).size() == hm.size(), "heat map previews into tomorrow")
	check(Gigs.zone_mult(1.0) > 1.2 and is_equal_approx(Gigs.zone_mult(0.1), 1.0), "hot zones pay more")
	check(Gigs.surge("yoober", 12, 5) > Gigs.surge("yoober", 12, 0), "Saturday busier than Monday")
	main.phone.open_app("doordish")
	await frames(3)
	main.phone.open_app("yoober")
	await frames(3)
	main.phone.close()


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
	for i in 15:
		if main._current == best:
			break
		await frames(1)
	var cur: String = "nothing"
	if main._current:
		cur = "'%s' at %s" % [main._current.get_prompt(), main._current.global_position]
	check(main._current == best, "main picks '%s' at %s (picked %s, player at %s)" % [best.get_prompt(), best.global_position, cur, main.player.global_position])
	best.use()
	await frames(2)


func _map_tests() -> void:
	print("Map")
	var kinds := {}
	for p in main.town.places:
		kinds[p.get("kind", "")] = true
	check(not kinds.has("") and kinds.has("food") and kinds.has("gas") and kinds.has("flex") and kinds.has("restroom"),
		"every place has a map icon (%s)" % str(kinds.keys()))
	main.map_waypoint = {}
	print("  window ", get_viewport().get_visible_rect().size)
	get_window().size = Vector2i(1600, 900)
	main.pause_menu.open_map()
	await frames(3)
	var view: WorldMap = main.pause_menu._map_view
	check(get_tree().paused and main.pause_menu._map.visible and view.size.x > 400, "G opens the full map (%dx%d)" % [view.size.x, view.size.y])
	var gas: Dictionary = main.town.places.filter(func(p): return p.kind == "gas")[0]
	var at := view.to_map(gas.pos)
	check(Rect2(Vector2.ZERO, view.size).has_point(at), "gas station icon is on the map")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = at
	view._gui_input(click)
	await frames(2)
	check(main.map_waypoint.get("label", "") == gas.name and main.gps.route.size() > 1, "clicking an icon sets the GPS and draws a route while paused")
	var back := InputEventAction.new()
	back.action = "back"
	back.pressed = true
	Input.parse_input_event(back)
	await frames(3)
	check(not main.pause_menu.is_open and not get_tree().paused, "Back closes the map and resumes")
	main.phone.open_app("maps")
	await frames(3)
	var phone_maps: Array = main.phone._screen.find_children("*", "WorldMap", true, false)
	check(phone_maps.size() == 1 and phone_maps[0].size.y >= 280, "phone Maps app shows the map")
	main.phone.close()
	main.map_waypoint = {}
	main.refresh_gps()


func _jump_tests() -> void:
	print("Jump")
	if main.is_driving():
		main.exit_car()
	var p: Player = main.player
	p.global_position = main.town.spawn_point + Vector3(0, 0.2, 0)
	await frames(30)
	var h: Humanoid = p._human
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	var peak_air := 0.0
	for i in 30:
		await get_tree().physics_frame
		peak_air = maxf(peak_air, h._air)
	check(peak_air > 0.9, "jumping goes into the split-leg pose (%.2f)" % peak_air)
	var landed := false
	for i in 120:
		await get_tree().physics_frame
		if p.is_on_floor() and h._land > 0.0:
			landed = true
			break
	check(landed, "landing bends the knees")
	await frames(60)
	check(h._air < 0.05, "back to normal after landing")


## On the short walk between a door and the sidewalk in front of it.
func _near_door_path(p: Vector3, door: Dictionary) -> bool:
	if door.is_empty():
		return false
	var q := Geometry3D.get_closest_point_to_segment(Vector3(p.x, 0, p.z), door.pos, door.walk)
	return q.distance_to(Vector3(p.x, 0, p.z)) < 0.6


func _city_life_tests() -> void:
	print("City life")
	var peds: Pedestrians = main.pedestrians
	var tr: Traffic = main.traffic
	var town = main.town
	var m0: float = Game.minute
	# Routines: a plan that leaves home, goes places, and comes back.
	var p0: Pedestrians.Walker = peds.people[0]
	var plan: Array = peds.plan_for(p0, Game.day)
	var homes: Array = plan.filter(func(e): return e.do == "home")
	var visits: Array = plan.filter(func(e): return e.do == "visit")
	check(homes.size() >= 2 and visits.size() >= 2, "%s's day: %s" % [p0.role, ", ".join(plan.map(func(e): return "%s %s" % [Game.time_string(e.at), e.do]))])
	Game.minute = 3 * 60.0
	for p in peds.people:
		p.refresh(true)
	var night_out: int = peds.outside_count()
	Game.minute = 17 * 60.0 + 30.0
	for p in peds.people:
		p.refresh(true)
	var rush_out: int = peds.outside_count()
	check(night_out <= 8 and rush_out > night_out * 2, "streets empty out at night (%d out at 3 AM, %d at 5:30 PM)" % [night_out, rush_out])
	# Walking between blocks crosses at the crosswalks, and cars stop for people in them.
	var r: Array = peds.route(peds.corner(Vector2i(1, 1), 0), peds.corner(Vector2i(3, 1), 2))
	var crossings: Array = r.filter(func(w): return w.cross)
	check(crossings.size() >= 2, "a walk across town crosses %d streets" % crossings.size())
	var walker: Pedestrians.Walker = peds.people.filter(func(p): return p.state != "inside")[0]
	walker.crossing = true
	var obs: Array = tr.obstacles(null).filter(func(o): return o[1] == "ped")
	check(obs.size() >= 1, "traffic sees people in the crosswalk")
	walker.crossing = false
	# Someone told to visit a door walks there and goes inside.
	var door: Dictionary = peds._food[0]
	walker.global_position = peds.corner(door.block, 0)
	walker.activity = {"do": "visit", "door": door, "stay": 30.0, "at": Game.minute}
	walker.state = "stroll"
	walker._start(walker.activity)
	walker.speed = 6.0
	for i in 1800:
		await get_tree().physics_frame
		if walker.state == "inside":
			break
	check(walker.state == "inside" and not walker.visible, "walked to %s and went in" % town.places.filter(func(pl): return Vector3(pl.door.x, 0, pl.door.z).distance_to(door.pos) < 0.5)[0].name)
	walker.speed = 1.4

	# Traffic follows the clock.
	tr.auto_density = true
	Game.minute = 3 * 60.0
	tr.rebalance()
	var night_cars: int = tr.civilians()
	Game.minute = 8 * 60.0
	tr.rebalance()
	var rush_cars: int = tr.civilians()
	check(rush_cars > night_cars * 2 and tr.rush_hour(), "rush hour traffic: %d cars at 8 AM, %d at 3 AM" % [rush_cars, night_cars])
	Game.minute = 13 * 60.0
	tr.rebalance()
	tr.auto_density = false
	await frames(5)

	# Road work: closed roads are fenced off, routed around, and left out of AI turns.
	var works: Construction = main.construction
	works.pick_for_day(Game.day)
	check(works.sites.size() == Construction.PER_DAY, "road work today: %d closures" % works.sites.size())
	var site: Dictionary = works.sites[0]
	var gps: GPS = main.gps
	var pa: Vector3 = works._pos(site.a)
	var pb: Vector3 = works._pos(site.b)
	var along: Vector3 = (pb - pa).normalized()
	var side := Vector3(-along.z, 0, along.x)
	gps.update(pa - along * 3.0 + side * 3.5, along, pb + along * 3.0 + side * 3.5, "Test", true)
	var mid: Vector3 = (pa + pb) / 2.0
	var through := false
	for q in gps.route:
		if Vector3(q.x, 0, q.z).distance_to(mid) < 20.0:
			through = true
	check(not through and gps.route.size() > 2, "GPS detours around the closed road (%d points)" % gps.route.size())
	check(not site.b - site.a in tr._exits(site.a, Vector2i.ZERO), "traffic won't turn into the closed road")
	var q := PhysicsRayQueryParameters3D.create(pa + along * 4.0 + Vector3(0, 0.6, 0), mid + Vector3(0, 0.6, 0))
	q.exclude = [main.car.get_rid(), main.player.get_rid()]
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(q)
	check(not hit.is_empty() and hit.position.distance_to(pa) < Construction.END_GAP + 1.5, "barricade blocks the road")
	var day0: Array = works.closures()
	works.pick_for_day(Game.day + 1)
	check(works.closures() != day0, "different road work tomorrow")
	works.clear()
	gps.set_closed([])

	# Parked cars sit in the parking lane, clear of traffic and intersections.
	var pc: ParkedCars = main.parked_cars
	var bad := 0
	for c in pc.cars:
		var p: Vector3 = c.global_position
		var fx := fposmod(p.x, 90.0)
		var off := minf(fx, 90.0 - fx)
		var fz := fposmod(p.z, 90.0)
		if absf(off - ParkedCars.OFFSET) > 0.2 or minf(fz, 90.0 - fz) < Traffic.HALF + 4.0:
			bad += 1
	check(pc.cars.size() > 40 and bad == 0, "parked cars: %d (%d out of place)" % [pc.cars.size(), bad])

	# Birds scatter when you walk up, and roost at night.
	var birds: Birds = main.birds
	var f: Dictionary = birds.flocks[0]
	var pl: Player = main.player
	pl.global_position = f.home + Vector3(12, 0.3, 0)
	Game.minute = 12 * 60.0
	await frames(10)
	check(f.state == "ground" and f.birds[0].visible, "pigeons on the ground")
	var y0: float = f.birds[0].global_position.y
	pl.global_position = f.home + Vector3(2, 0.3, 0)
	await frames(60)
	check(f.state == "flying" and f.birds[0].global_position.y > y0 + 1.5, "pigeons fly off when you walk up")
	pl.global_position = f.home + Vector3(60, 0.3, 0)
	Game.minute = 23 * 60.0
	await frames(5)
	check(f.state == "ground" and not f.birds[0].visible, "birds roost at night")
	Game.minute = 12 * 60.0

	# District sounds.
	var amb: Ambience = main.ambience
	var B: float = town.B
	check(amb.district_at(Vector3(2.5 * B, 0, 2.5 * B)) == "downtown" and amb.district_at(Vector3(4.5 * B, 0, 4.5 * B)) == "port" \
		and amb.district_at(Vector3(2.5 * B, 0, 1.5 * B)) == "park" and amb.district_at(Vector3(-town.RING, 0, 2 * B)) == "highway" \
		and amb.district_at(Vector3(0.5 * B, 0, 1.5 * B)) == "campus", "districts")
	var park_day: Dictionary = amb.mix_at(Vector3(2.5 * B, 0, 1.5 * B), 12 * 60.0)
	var park_night: Dictionary = amb.mix_at(Vector3(2.5 * B, 0, 1.5 * B), 23 * 60.0)
	var port: Dictionary = amb.mix_at(Vector3(4.5 * B, 0, 4.5 * B), 12 * 60.0)
	var downtown: Dictionary = amb.mix_at(Vector3(2.5 * B, 0, 2.5 * B), 12 * 60.0)
	check(park_day.birds > 0.5 and park_night.birds < 0.05 and park_night.crickets > 0.5, "park: birds by day, crickets at night")
	check(port.port > 0.6 and downtown.city > 0.6 and downtown.get("port", 0.0) < 0.1, "port machinery, downtown traffic")
	for i in 600:
		await get_tree().physics_frame
		if amb.ready_to_play():
			break
	check(amb.ready_to_play() and amb._players.size() == Ambience.LAYERS.size(), "ambience loops built")
	pl.global_position = town.spawn_point
	Game.minute = m0
func _day_night_tests() -> void:
	print("Day and night")
	var saved_min: float = Game.minute
	var saved_day: int = Game.day
	var saved_car: String = Game.car_id
	var tr: Traffic = main.traffic
	Game.day = 1   # a Monday
	Game.minute = 12 * 60.0
	await frames(5)
	check(Game.daylight() == 1.0 and not Game.lights_on(), "noon is full daylight")
	check(not main.town._street_lights[0].visible, "streetlights off at noon")
	Game.minute = 18 * 60.0 + 20.0
	check(Game.lights_on(), "lights come on at dusk (6:20 PM, daylight %.2f)" % Game.daylight())
	Game.minute = 21 * 60.0
	await frames(5)
	check(main.town._street_lights[0].visible, "streetlights on at night")
	check(Kit.lit_glass("shop").emission_energy_multiplier > 0.4 and Kit.lit_glass("home").emission_energy_multiplier > 0.4, "shop and house windows glow")
	check(tr.night and tr.cars[0]._night.visible, "traffic has headlights on")
	if main.is_driving():
		main.exit_car()
	main.enter_car()
	check(main.car.headlights_on, "your headlights come on at night")
	main.exit_car()
	# Rush hour: busiest at 8 AM and 5 PM on weekdays, nearly empty at 3 AM, calmer on weekends.
	check(Game.is_rush_hour(8) and Game.is_rush_hour(17) and not Game.is_rush_hour(13), "rush hours 8 AM and 5 PM")
	Game.minute = 3 * 60.0
	var night_n := tr.target_count()
	Game.minute = 8 * 60.0
	var rush_n := tr.target_count()
	Game.day = 6   # Saturday
	var weekend_n := tr.target_count()
	Game.day = 1
	check(rush_n > weekend_n and weekend_n > night_n, "traffic: %d cars at rush hour, %d on a weekend morning, %d at 3 AM" % [rush_n, weekend_n, night_n])
	# The traffic manager adds and removes cars out of sight to match.
	tr.auto_density = true
	main.player.global_position = main.town.spawn_point
	Game.minute = 3 * 60.0
	for i in 40:
		tr._density_t = 0.0
		tr._update_density(0.1)
	check(tr.civilians() == night_n, "late night thins traffic to %d cars (%d in reserve)" % [tr.civilians(), tr.reserve.size()])
	Game.minute = 8 * 60.0
	for i in 60:
		tr._density_t = 0.0
		tr._update_density(0.1)
	check(tr.civilians() >= rush_n - 2, "rush hour fills the roads back up (%d cars)" % tr.civilians())
	var hidden_ok := true
	for c in tr.cars:
		hidden_ok = hidden_ok and c.visible
	for c in tr.reserve:
		hidden_ok = hidden_ok and not c.visible
	check(hidden_ok, "only cars on the road are shown")
	tr.auto_density = false
	# Late-night rides: surge pay and rowdy riders.
	Game.car_id = "civil"
	Game.minute = 23 * 60.0
	Gigs.set_online("yoober", true)
	Gigs._make_offer("yoober")
	var o: Dictionary = Gigs.offers.back()
	check(o.get("night_pay", 0.0) > 0.0, "11 PM ride includes a late-night surge (+$%.2f)" % o.get("night_pay", 0.0))
	Gigs.decline(o.id)
	Game.minute = 13 * 60.0
	Gigs._make_offer("yoober")
	o = Gigs.offers.back()
	check(o.get("night_pay", 0.0) == 0.0 and not o.get("rowdy", false), "no late-night surge or rowdy riders at 1 PM")
	Gigs.decline(o.id)
	Gigs.set_online("yoober", false)
	check(Gigs.rowdy_outcome(0.1).tip > 0.0 and Gigs.rowdy_outcome(0.5).has("clean_minutes") and Gigs.rowdy_outcome(0.7).stars < 0.0, "rowdy riders: big tips, messes, bad ratings")
	Game.minute = saved_min
	Game.day = saved_day
	Game.car_id = saved_car
	await frames(5)


func _polish_tests() -> void:
	print("Save slots")
	var keep := FileAccess.get_file_as_bytes(Game.slot_path(3)) if Game.has_save(3) else PackedByteArray()
	Game.money = 1234.0
	Game.save_game(3)
	check(Game.slot_info(3).money == 1234.0 and Game.current_slot == 3, "saved to slot 3 (%s)" % Game.slot_summary(3))
	check(Game.latest_slot() == 3, "slot 3 is the latest save")
	Game.money = 5.0
	main.load_game(3)
	check(Game.money == 1234.0, "loaded slot 3")
	Game.delete_save(3)
	check(not Game.has_save(3) and Game.slot_summary(3) == "Empty", "deleted slot 3")
	if not keep.is_empty():
		var f := FileAccess.open(Game.slot_path(3), FileAccess.WRITE)
		f.store_buffer(keep)
		f.close()
	Game.current_slot = 1

	print("Taxi and bus")
	var tr: Transit = main.transit
	check(tr.stops.size() == 8, "bus stops: %d" % tr.stops.size())
	if main.driving:
		main.exit_car()
	Gigs.reset_jobs()
	Game.phone_service = true
	Game.phone_battery = 80.0
	Game.minute = 10 * 60.0
	Game.energy = 90.0
	Game.hunger = 90.0
	Game.bladder = 10.0
	Game.money = 500.0
	main.player.global_position = main.town.spawn_point
	await frames(5)
	check(tr.blocked_reason() == "", "can ride when on foot with no job ('%s')" % tr.blocked_reason())
	var place: Dictionary = main.town.restaurants[0]
	var dest := tr.drop_point(place)
	var q := tr.taxi_quote(dest)
	var t0 := Game.total_minutes()
	check(tr.ride_taxi(dest, place.name), "called a cab ($%.2f, %d min)" % [q.fare, q.minutes])
	await frames(150)
	check(main.player.global_position.distance_to(dest) < 2.0, "taxi dropped you at %s" % place.name)
	check(absf(Game.money - (500.0 - q.fare)) < 0.01, "taxi fare charged")
	check(Game.total_minutes() - t0 >= q.minutes - 0.01, "taxi ride took %d min" % int(Game.total_minutes() - t0))
	main.enter_car()
	check(tr.blocked_reason() != "" and not tr.ride_taxi(dest, "x"), "no taxi while driving")
	main.exit_car()
	var a: Dictionary = tr.stops[0]
	var b: Dictionary = tr.stops[5]
	main.player.global_position = a.pos + Vector3(0, 0.6, 0)
	await frames(5)
	check(tr.at_stop() == a, "standing at %s" % a.name)
	var money := Game.money
	check(tr.ride_bus(a, b), "rode the bus")
	await frames(150)
	check(main.player.global_position.distance_to(b.pos) < 2.0 and absf(money - Game.money - GameData.BUS_FARE) < 0.01, "bus dropped you at %s" % b.short)
	Game.minute = 60.0
	check(tr.bus_wait() < 0.0 and not tr.ride_bus(b, a), "no buses at 1 AM")
	Game.minute = 10 * 60.0
	main.drop_pin(Vector3(200, 0, 130))
	check(str(main.map_waypoint.get("label", "")).begins_with("Pin on"), "dropped a map pin (%s)" % main.map_waypoint.get("label", ""))
	main.map_waypoint = {}

	print("Settings and screen effects")
	Game.invert_y = true
	check(Game.look_y_sign() == -1.0, "invert look")
	Game.invert_y = false
	var fov: float = Game.fov
	Game.fov = 90.0
	main.apply_view_settings()
	check(main.player.camera.fov == 90.0 and main.car.fp_camera.fov == 98.0, "field of view applies")
	Game.fov = fov
	main.apply_view_settings()
	Game.energy = 4.0
	Game.hunger = 3.0
	Game.bladder = 95.0
	await frames(5)
	check(main.needs_fx._rect.visible, "screen effects show when tired and hungry")
	Game.screen_fx = 0.0
	await frames(2)
	check(not main.needs_fx._rect.visible, "screen effects can be turned off")
	Game.screen_fx = 1.0
	Game.energy = 90.0
	Game.hunger = 90.0
	Game.bladder = 10.0
	await frames(2)
	check(not main.needs_fx._rect.visible, "no effects when your needs are fine")

	print("New game")
	main.new_game()
	check(Game.day == 1 and Game.money == GameData.START_MONEY and Game.car_id == "rustwagon", "new game resets")
	check(main.player.global_position.distance_to(main.town.spawn_point) < 1.0, "new game puts you at Dottie's")
