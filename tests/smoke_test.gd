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
	add_child(main)
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
	await frames(30)
	check(Gigs.can_start_trip(), "can start trip at pickup")
	Gigs.start_trip()
	car.teleport(Transform3D(Basis.IDENTITY, Gigs.job.dropoff.curb + Vector3(0, 0.8, 0)))
	await frames(30)
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
		await frames(10)
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
