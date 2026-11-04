class_name StoryScreens
extends RefCounted
## Phone screens for the story: the Hustle Hub app (milestones, daily and weekly challenges,
## Ray's IOU) and the Texts app. Built with the phone's own widgets.

const HUB_COLOR := Color(0.85, 0.55, 0.1)
const TEXTS_COLOR := Color(0.2, 0.65, 0.35)


static func hub(phone: Phone) -> void:
	phone._header("Hustle Hub", HUB_COLOR, "Goals, challenges and the people who believe in you.")

	var cur := Story.current_milestone()
	var goal := phone._card(Color(0.2, 0.15, 0.08))
	if cur.is_empty():
		phone._lbl(goal, "🏡 You did it: every milestone reached.", 17, Color(1, 0.9, 0.5))
	else:
		phone._lbl(goal, "NEXT GOAL", 12, Color(1, 0.8, 0.45))
		phone._lbl(goal, cur.title, 20, Color.WHITE)
		phone._lbl(goal, cur.goal, 13, Color(0.85, 0.85, 0.9))

	# Cousin Ray's IOU for the Punta.
	var ray := phone._card()
	if Story.ray_left() > 0.0:
		phone._live_label(ray, func(n): n.text = "Cousin Ray's IOU: $%d of $%d left" % [int(Story.ray_left()), int(StoryData.RAY_DEBT)], 15, Color(1, 0.8, 0.5))
		_bar(ray, func(): return Story.ray_paid / StoryData.RAY_DEBT, Color(1, 0.7, 0.3))
		var row := HBoxContainer.new()
		ray.add_child(row)
		for amt in StoryData.RAY_PAYMENTS:
			var a: float = amt
			phone._live_button(row, "Send $%d" % int(a), func(): Story.pay_ray(a),
				func(): return Game.money >= minf(a, Story.ray_left()) and Story.ray_left() > 0.0, Color(0.5, 0.35, 0.1))
		phone._live_button(ray, "Pay it all off", func(): Story.pay_ray(Story.ray_left()),
			func(): return Game.money >= Story.ray_left() and Story.ray_left() > 0.0, Color(0.45, 0.3, 0.1))
	else:
		phone._lbl(ray, "Cousin Ray: paid in full. The Punta's yours. ✔", 14, Color(0.5, 1, 0.6))

	_challenges(phone, "Today's challenges", "Reset at midnight", Story.daily)
	var left := 7 - (Game.day - Story.weekly_start)
	_challenges(phone, "This week", "Resets in %d day%s" % [left, "" if left == 1 else "s"], Story.weekly)

	var ms := phone._card()
	phone._lbl(ms, "Milestones  (%d/%d)" % [Story.milestones_done.size(), StoryData.MILESTONES.size()], 15, Color(1, 0.85, 0.5))
	for m in StoryData.MILESTONES:
		var done := Story.milestone_done(m.id)
		phone._lbl(ms, ("✔ " if done else "☐ ") + m.title, 15, Color(0.5, 1, 0.6) if done else Color.WHITE)
		if not done:
			phone._lbl(ms, "    " + m.goal, 12, Color(0.7, 0.7, 0.75))

	var regs := phone._card()
	phone._lbl(regs, "Your regulars", 15, Color(0.8, 0.8, 0.85))
	var any := false
	for id in StoryData.NPCS:
		var npc: Dictionary = StoryData.NPCS[id]
		if npc.kind == "contact" or not Story.npc_visits.has(id):
			continue
		any = true
		var where := ""
		if npc.kind == "customer":
			where = " • lives at %s" % Story.regular_address(id).get("name", "?")
		phone._lbl(regs, "%s: served %d time%s%s" % [npc.name, Story.npc_visits[id], "" if Story.npc_visits[id] == 1 else "s", where], 13, npc.color)
	if not any:
		phone._lbl(regs, "Keep working. Some customers order again and again.", 12, Color(0.7, 0.7, 0.75))
	phone._btn(phone._screen, "Replay the story intro", func():
		phone.close()
		phone.main.play_intro(), Color(0.25, 0.22, 0.3))


static func _challenges(phone: Phone, title: String, sub: String, list: Array) -> void:
	var v := phone._card(Color(0.12, 0.15, 0.2))
	phone._lbl(v, title, 15, Color(0.6, 0.85, 1))
	phone._lbl(v, sub, 11, Color(0.65, 0.7, 0.75))
	if list.is_empty():
		phone._lbl(v, "Nothing yet.", 13, Color(0.7, 0.7, 0.75))
	for c in list:
		var ch: Dictionary = c
		phone._live_label(v, func(n):
			var prog := ("$%d/$%d" if ch.type == "earn" else "%d/%d") % [int(ch.progress), int(ch.n)]
			n.text = "%s %s  •  %s  •  $%d" % ["✔" if ch.done else "☐", ch.text, "done" if ch.done else prog, int(ch.reward)]
			n.add_theme_color_override("font_color", Color(0.5, 1, 0.6) if ch.done else Color.WHITE), 13)
		_bar(v, func(): return ch.progress / maxf(1.0, float(ch.n)), Color(0.3, 0.75, 1))


static func _bar(parent: Node, frac: Callable, color: Color) -> void:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	bar.value = frac.call()
	parent.add_child(bar)


static func texts(phone: Phone) -> void:
	phone._header("Texts", TEXTS_COLOR, "%d conversation%s" % [_senders().size(), "" if _senders().size() == 1 else "s"])
	if Story.messages.is_empty():
		phone._lbl(phone._screen, "No messages yet.", 14, Color(0.7, 0.7, 0.75))
	for m in Story.messages:
		var npc: Dictionary = StoryData.NPCS.get(m.from, {})
		var v := phone._card(Color(0.12, 0.17, 0.13) if not m.read else Color(0.13, 0.13, 0.16))
		phone._lbl(v, "%s%s   %s" % ["● " if not m.read else "", npc.get("name", m.from), m.time], 12, npc.get("color", Color.WHITE))
		phone._lbl(v, m.text, 14)
	# Read once you've seen them (the home screen badge updates next time it opens).
	Story.mark_read(false)


static func _senders() -> Array:
	var out := []
	for m in Story.messages:
		if not m.from in out:
			out.append(m.from)
	return out
