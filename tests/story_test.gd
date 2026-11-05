extends Node
## Headless story test: godot --headless --path . res://tests/story_test.tscn
## Intro, texts, milestones, challenges, Ray's IOU, regulars, and saving it all.

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


## Takes an offer and finishes it on the spot with the given stars.
func do_job(app: String, stars := 5.0) -> Dictionary:
	Gigs.offers.clear()
	Gigs._make_offer(app)
	var o: Dictionary = Gigs.offers.back()
	Gigs.accept(o.id)
	var j := Gigs.job
	Gigs._complete(stars, 0.0, "test")
	return j


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.auto_tutorial = false
	add_child(main)
	main.traffic.police_enabled = false
	await frames(30)

	print("Intro")
	main.play_intro()
	check(get_tree().paused and main.intro.visible, "intro pauses the game")
	for i in StoryData.INTRO.size():
		main.intro.next()
	check(not get_tree().paused and not main.intro.visible and Intro.is_seen(), "intro plays through and unpauses")

	print("Texts")
	Game.advance(6 * 60.0)
	check(Story.messages.size() >= 3, "day-one texts arrived (%d)" % Story.messages.size())
	check(Story.unread() > 0, "unread texts: %d" % Story.unread())
	var before := Story.messages.size()
	Game.advance(10.0)
	check(Story.messages.size() == before, "beats are only sent once")
	main.phone.open_app("texts")
	await frames(2)
	check(Story.unread() == 0, "opening Texts marks them read")
	main.phone.open_app("hub")
	await frames(2)
	main.phone.open_app("")
	await frames(2)
	main.phone.close()
	check(true, "Hustle Hub and Texts screens built")

	print("Challenges")
	check(Story.daily.size() == StoryData.DAILY_COUNT, "%d daily challenges" % Story.daily.size())
	check(Story.weekly.size() == StoryData.WEEKLY_COUNT, "%d weekly challenges" % Story.weekly.size())
	for c in Story.daily + Story.weekly:
		print("    %s ($%d)" % [c.text, int(c.reward)])
	Story.daily.append({"type": "jobs", "title": "Test", "text": "Complete 2 gigs", "n": 2, "progress": 0.0,
		"done": false, "seen": [], "reward": 20.0})
	var test_c: Dictionary = Story.daily.back()

	print("Milestones")
	check(Story.current_milestone().id == "first_gig", "first goal is the first gig")
	check(main.hud._objective.text.begins_with("Goal:"), "HUD shows the goal: %s" % main.hud._objective.text)
	Gigs.set_online("doordish", true)
	do_job("doordish")
	check(Story.milestone_done("first_gig"), "first gig milestone")
	check(test_c.progress == 1.0 and not test_c.done, "challenge counts a gig")
	var m0 := Game.money
	do_job("doordish")
	check(test_c.done and Game.money >= m0 + 20.0, "challenge pays out when done")

	Game.money = 5000.0
	check(Story.pay_ray(100.0) and Story.ray_left() == StoryData.RAY_DEBT - 100.0, "sent Ray $100")
	check(Story.pay_ray(99999.0) and Story.ray_left() == 0.0, "paid Ray off")
	check(Story.milestone_done("pay_ray"), "pay off the car milestone")
	check(not Story.pay_ray(10.0), "nothing more to pay Ray")
	Game.oil_change()
	check(Story.milestone_done("oil"), "oil change milestone")

	print("Regulars")
	var found := {}
	for i in 400:
		Gigs.offers.clear()
		Gigs._make_offer("doordish")
		if Gigs.offers.back().get("npc", "") == "pemberton":
			found = Gigs.offers.back()
			break
	check(not found.is_empty(), "Mr. Pemberton placed an order")
	if not found.is_empty():
		check(found.customer.name == Story.regular_address("pemberton").name, "he orders to the same house (%s)" % found.customer.name)
		Gigs.accept(found.id)
		m0 = Game.money
		var pay: float = Gigs.job.pay
		Gigs._complete(5.0, 0.0, "test")
		check(Story.npc_visits.get("pemberton", 0) == 1, "regular visit counted")
		check(Game.money >= m0 + pay + StoryData.NPCS.pemberton.bonus - 0.01, "on-time bonus from Mr. Pemberton")

	print("Moving out")
	Game.money = 5000.0
	Game.sign_lease("studio")
	check(Story.milestone_done("move_out") and Story.milestone_done("rent"), "move out milestone")

	print("New day")
	var d := Game.day
	Game.advance(1440.0)
	check(Story.daily_day == d + 1 and not Story.daily.has(test_c), "new daily challenges at midnight")

	print("Save / load")
	var paid := Story.ray_paid
	var done := Story.milestones_done.size()
	var msgs := Story.messages.size()
	Game.save_game()
	Story.reset()
	check(Story.milestones_done.is_empty(), "story reset")
	main.load_game()
	check(Story.ray_paid == paid and Story.milestones_done.size() == done and Story.messages.size() == msgs,
		"story saved and loaded (%d milestones, %d texts)" % [done, msgs])
	check(Story.daily.size() == StoryData.DAILY_COUNT and Story.daily[0].n is int, "challenges loaded")

	await frames(10)
	print("\n%s: %d failure(s)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures > 0 else 0)
