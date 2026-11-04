extends Node
## Story (autoload "Story"): milestones, daily and weekly challenges, text messages from the
## recurring characters, Cousin Ray's IOU for the Punta, and the regulars who show up in gig
## offers. The words live in StoryData.

signal changed                      # anything the Hustle Hub or Texts apps show
signal message_received(msg: Dictionary)
signal milestone_reached(m: Dictionary)
signal challenge_completed(c: Dictionary)

var milestones_done := {}           # id -> day reached
var ray_paid := 0.0
var ray_last_day := 1               # last day you sent Ray money (or he nagged)
var messages: Array = []            # newest first: {from, text, time, read}
var beats_sent := {}                # index in StoryData.BEATS -> true
var daily: Array = []
var daily_day := 0
var weekly: Array = []
var weekly_start := 0
var gig_earned := 0.0
var npc_visits := {}                # regular's id -> times served
var _dottie_warned := {}            # rent bill id -> true
var _last_miles := 0.0
var _last_car := ""
var _oil_changed := false


func _ready() -> void:
	reset()
	Game.minutes_advanced.connect(_on_minutes)
	Game.day_changed.connect(_on_day)
	Game.car_changed.connect(_on_car_changed)
	Game.home_changed.connect(_check_milestones)
	Game.bill_paid.connect(_on_bill_paid)
	Gigs.job_completed.connect(_on_job_completed)
	Gigs.job_changed.connect(_on_job_changed)


func reset() -> void:
	milestones_done = {}
	ray_paid = 0.0
	ray_last_day = Game.day
	messages = []
	beats_sent = {}
	daily = []
	daily_day = 0
	weekly = []
	weekly_start = 0
	gig_earned = 0.0
	npc_visits = {}
	_dottie_warned = {}
	_last_miles = float(Game.stats.get("miles", 0.0))
	_last_car = Game.car_id
	_oil_changed = false
	_refresh_challenges()
	changed.emit()


# --- Messages ---------------------------------------------------------------------------

func npc_name(id: String) -> String:
	return StoryData.NPCS.get(id, {}).get("name", id)


func text(from: String, body: String) -> void:
	var msg := {"from": from, "text": body, "time": "Day %d %s" % [Game.day, Game.time_string()], "read": false}
	messages.push_front(msg)
	if messages.size() > 40:
		messages.pop_back()
	Game.notify("💬 %s: %s" % [npc_name(from), body], "info")
	message_received.emit(msg)
	changed.emit()


func unread() -> int:
	return messages.filter(func(m): return not m.read).size()


func mark_read(notify_apps := true) -> void:
	if unread() == 0:
		return
	for m in messages:
		m.read = true
	if notify_apps:
		changed.emit()


func _send_beats() -> void:
	var now := Game.total_minutes()
	for i in StoryData.BEATS.size():
		if beats_sent.has(i):
			continue
		var b: Array = StoryData.BEATS[i]
		if now >= (b[0] - 1) * 1440.0 + b[1] * 60.0:
			beats_sent[i] = true
			text(b[2], b[3])


# --- Cousin Ray's IOU -------------------------------------------------------------------

func ray_left() -> float:
	return maxf(0.0, StoryData.RAY_DEBT - ray_paid)


func pay_ray(amount: float) -> bool:
	amount = minf(amount, ray_left())
	if amount <= 0.0 or not Game.spend(amount, "IOU: Cousin Ray (Punta)"):
		return false
	ray_paid += amount
	ray_last_day = Game.day
	if ray_left() > 0.0:
		text("ray", ["Got the $%d! Only $%d to go. You're a legend, cuz.",
			"$%d received. Buying myself a celebratory sub. $%d left.",
			"Ayy $%d! Mom says you're the responsible one now. $%d to go."].pick_random() % [int(amount), int(ray_left())])
	_check_milestones()
	changed.emit()
	return true


# --- Milestones -------------------------------------------------------------------------

func milestone_done(id: String) -> bool:
	return milestones_done.has(id)


## The first milestone you haven't reached yet, or {} when you've done them all.
func current_milestone() -> Dictionary:
	for m in StoryData.MILESTONES:
		if not milestones_done.has(m.id):
			return m
	return {}


func _milestone_met(id: String) -> bool:
	match id:
		"first_gig": return int(Game.stats.get("jobs", 0)) >= 1
		"gas_money": return gig_earned >= 250.0
		"oil": return _oil_changed
		"rent": return milestones_done.has("rent") or Game.home_id not in ["room", ""]
		"pay_ray": return ray_left() <= 0.0
		"new_car": return int(Game.car().year) >= 2011
		"move_out": return Game.home_id not in ["room", ""]
		"own_car": return Game.car_id != "rustwagon" and Game.loan.is_empty() and ray_left() <= 0.0
		"five_figures": return gig_earned >= 10000.0
		"dream_house": return Game.home_id == "house"
	return false


func _check_milestones() -> void:
	for m in StoryData.MILESTONES:
		if not milestones_done.has(m.id) and _milestone_met(m.id):
			_reach(m)


func _reach(m: Dictionary) -> void:
	milestones_done[m.id] = Game.day
	Game.notify("🏆 Milestone: %s!" % m.title, "good")
	if m.reward > 0.0:
		Game.earn(m.reward, "Gift from %s" % npc_name(m.from))
	text(m.from, m.text + (" (+$%d)" % int(m.reward) if m.reward > 0.0 else ""))
	if m.id == "dream_house":
		Game.notify("You made it: from a rented room to a house with a yard. Keep hustling as long as you like!", "good")
	milestone_reached.emit(m)
	changed.emit()


## One line for the HUD when you're not on a job: what to work toward next.
func objective_text() -> String:
	var m := current_milestone()
	if m.is_empty():
		return ""
	if m.id == "pay_ray":
		return "Goal: %s ($%d left to Ray)" % [m.title, int(ray_left())]
	return "Goal: %s" % m.title


# --- Challenges -------------------------------------------------------------------------

func _refresh_challenges() -> void:
	if daily_day != Game.day:
		daily_day = Game.day
		daily = _pick(StoryData.DAILY, StoryData.DAILY_COUNT)
	var week_start := Game.day - (Game.day - 1) % 7
	if weekly_start != week_start:
		weekly_start = week_start
		weekly = _pick(StoryData.WEEKLY, StoryData.WEEKLY_COUNT)


func _pick(templates: Array, count: int) -> Array:
	var pool := templates.filter(func(t):
		if t.type == "weather":
			return Game.forecast().kind in ["rain", "storm", "snow"]
		if t.type == "regulars":
			return npc_visits.size() > 0 or milestones_done.has("first_gig")
		return true)
	pool.shuffle()
	var out := []
	for t in pool.slice(0, count):
		var n := randi_range(t.n[0], t.n[1])
		if t.type == "earn":
			n = int(snappedf(n, 10.0))
		var c := {"type": t.type, "title": t.title, "n": n, "progress": 0.0, "done": false, "seen": []}
		if t.type == "app_jobs":
			c.app = _pick_app()
			c.text = t.text % [n, GameData.APPS[c.app].name]
		else:
			c.text = t.text % n
		c.reward = maxf(5.0, snappedf(n * t.reward_per, 5.0))
		out.append(c)
	return out


func _pick_app() -> String:
	var ok := GameData.APP_ORDER.filter(func(id):
		var a: Dictionary = GameData.APPS[id]
		return a.kind != "flex" and int(Game.car().year) >= int(a.get("min_year", 0)))
	return ok.pick_random() if not ok.is_empty() else "doordish"


func _count(type: String, amount: float, info := {}) -> void:
	for c in daily + weekly:
		if c.done or c.type != type:
			continue
		if type == "app_jobs" and c.app != info.get("app", ""):
			continue
		if type == "apps":
			if info.app in c.seen:
				continue
			c.seen.append(info.app)
		c.progress = minf(float(c.n), c.progress + amount)
		if c.progress >= c.n:
			c.done = true
			Game.earn(c.reward, "Hustle Hub challenge: %s" % c.title)
			Game.notify("✅ Challenge complete: %s (+$%d)" % [c.text, int(c.reward)], "money")
			challenge_completed.emit(c)
	changed.emit()


func _on_job_completed(job: Dictionary, pay: float, stars: float) -> void:
	gig_earned += pay
	var now := Game.total_minutes()
	var on_time: bool = now <= float(job.get("end", job.get("deadline", now)))
	_count("jobs", 1.0)
	_count("app_jobs", 1.0, {"app": job.app})
	_count("apps", 1.0, {"app": job.app})
	_count("earn", pay)
	if Gigs.surge(job.app) > 1.0:
		_count("peak", 1.0)
	if on_time:
		_count("on_time", 1.0)
	if stars >= 4.95:
		_count("five_star", 1.0)
	if Game.weather in ["rain", "storm", "snow"] and Game.weather_amount > 0.3:
		_count("weather", 1.0)
	var npc: String = job.get("npc", "")
	if npc != "":
		_regular_done(npc, on_time)
	_check_milestones()


# --- Regulars ---------------------------------------------------------------------------

## Called by Gigs for each new offer: sometimes it's one of your regulars instead of a
## stranger. Pemberton always orders to the same house, so the trip is re-measured.
func decorate_offer(o: Dictionary) -> void:
	if not milestones_done.has("first_gig") or Gigs.town == null:
		return
	var id := ""
	if o.kind in ["food", "grocery"]:
		id = "pemberton"
	elif o.kind == "ride":
		id = "darnell"
	if id == "" or _regular_busy(id):
		return
	# Better odds until you've met them, so they show up early on.
	var chance := StoryData.NPC_CHANCE if npc_visits.has(id) else StoryData.NPC_CHANCE * 2.0
	if randf() >= chance:
		return
	var npc: Dictionary = StoryData.NPCS[id]
	o.npc = id
	if id == "darnell":
		o.passenger = npc.name
		return
	var home := regular_address(id)
	if home.is_empty():
		return
	var src: Dictionary = o.restaurant if o.kind == "food" else o.store
	var delta: float = Gigs._miles(src.curb, home.curb) - Gigs._miles(src.curb, o.customer.curb)
	o.customer = home
	o.customer_name = npc.name
	o.miles = snappedf(maxf(0.1, o.miles + delta), 0.1)
	o.pay = snappedf(maxf(o.pay + Gigs.app(o.app).per_mile * delta, 3.0), 0.01)
	o.deadline += maxf(-10.0, delta * 9.0)


## A regular's home address (always the same one).
func regular_address(id: String) -> Dictionary:
	var addrs: Array = Gigs.town.addresses if Gigs.town else []
	if addrs.is_empty():
		return {}
	var s: int = StoryData.NPCS[id].get("address_seed", 0)
	return addrs[(s * 13 + 5) % addrs.size()]


func _regular_busy(id: String) -> bool:
	if Gigs.job.get("npc", "") == id:
		return true
	return Gigs.offers.any(func(x): return x.get("npc", "") == id)


func _on_job_changed() -> void:
	var j := Gigs.job
	var id: String = j.get("npc", "")
	if id == "" or j.get("npc_greeted", false):
		return
	# Darnell talks once he's in the car; Pemberton texts when you accept his order.
	if id == "darnell" and j.stage != "to_dropoff":
		return
	j.npc_greeted = true
	var npc: Dictionary = StoryData.NPCS[id]
	if not npc_visits.has(id):
		if id == "pemberton":
			text(id, npc.first)
		else:
			Game.notify(npc.first, "info")
	elif id == "pemberton":
		Game.notify("It's Mr. Pemberton again. His note: \"Do NOT ring the bell. Knock twice. Softly.\"", "info")
	else:
		Game.notify("Darnell waves. \"My driver! Same playlist?\"", "info")


func _regular_done(id: String, on_time: bool) -> void:
	var npc: Dictionary = StoryData.NPCS[id]
	npc_visits[id] = int(npc_visits.get(id, 0)) + 1
	_count("regulars", 1.0)
	if on_time:
		var bonus: int = npc.bonus
		Game.earn(bonus, "Tip: %s" % npc.name)
		gig_earned += bonus
		Game.notify(npc.on_time.pick_random() % bonus, "money")
	else:
		Game.notify(npc.late.pick_random(), "warn")
	if npc_visits[id] == 5:
		text(id, "You've been my driver five times now. I told my whole building about you." if id == "darnell"
			else "Five deliveries without catastrophe. I've added you to my will. (I have not.) Keep it up.")


# --- Ticking ----------------------------------------------------------------------------

func _on_minutes(_m: float) -> void:
	var miles := float(Game.stats.get("miles", 0.0))
	if miles > _last_miles:
		_count_miles(miles - _last_miles)
	_last_miles = miles
	_send_beats()
	_check_milestones()


func _count_miles(d: float) -> void:
	# Miles tick in tiny steps; only refresh the apps once a whole mile has gone by.
	for c in daily + weekly:
		if c.type == "miles" and not c.done:
			var before := int(c.progress)
			c.progress = minf(float(c.n), c.progress + d)
			if c.progress >= c.n:
				c.done = true
				Game.earn(c.reward, "Hustle Hub challenge: %s" % c.title)
				Game.notify("✅ Challenge complete: %s (+$%d)" % [c.text, int(c.reward)], "money")
				challenge_completed.emit(c)
				changed.emit()
			elif int(c.progress) != before:
				changed.emit()


func _on_day(_d: int) -> void:
	_refresh_challenges()
	Game.notify("New daily challenges in the Hustle Hub app.", "info")
	# Ray checks in if you've gone quiet on the IOU.
	if ray_left() > 0.0 and Game.day - ray_last_day >= StoryData.RAY_NAG_DAYS:
		ray_last_day = Game.day
		text("ray", ["Hey cuz, just checking in on that Punta money. $%d left. No pressure. (Some pressure.)",
			"My landlord asked about my rent and I said \"my cousin's got me.\" $%d left. You got me, right?",
			"Saw a '95 Punta on the highway and got emotional. Anyway. $%d."].pick_random() % int(ray_left()))
	# Dottie gives you a heads-up when rent's close and your balance won't cover it.
	for b in Game.unpaid_bills():
		if b.kind != "rent" or _dottie_warned.has(b.id) or Game.home_id != "room":
			continue
		if b.due_day - Game.day <= 3 and Game.money < b.amount:
			_dottie_warned[b.id] = true
			text("dottie", "Hon, rent's due Day %d and it's $%d. I know it's tight. Pick up some extra shifts?" % [b.due_day, int(b.amount)])
	changed.emit()


func _on_car_changed() -> void:
	if Game.car_id == _last_car and Game.oil_life >= 99.9:
		_oil_changed = true
	if _last_car == "rustwagon" and Game.car_id != "rustwagon" and ray_left() > 0.0:
		text("ray", "You TRADED IN the Punta?? She had so much life left. You still owe me $%d, by the way." % int(ray_left()))
	_last_car = Game.car_id
	_check_milestones()


func _on_bill_paid(b: Dictionary) -> void:
	if b.kind == "rent" and not milestones_done.has("rent"):
		_reach(_milestone("rent"))


func _milestone(id: String) -> Dictionary:
	for m in StoryData.MILESTONES:
		if m.id == id:
			return m
	return {}


# --- Save / load ------------------------------------------------------------------------

func save_state() -> Dictionary:
	return {"milestones": milestones_done, "ray_paid": ray_paid, "ray_last_day": ray_last_day,
		"messages": messages, "beats": beats_sent.keys(), "daily": daily, "daily_day": daily_day,
		"weekly": weekly, "weekly_start": weekly_start, "gig_earned": gig_earned,
		"npc_visits": npc_visits, "dottie_warned": _dottie_warned.keys(), "oil": _oil_changed}


func load_state(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		# A save from before the story existed: skip the old beats instead of sending them
		# all at once, and count past earnings toward the money milestones.
		for i in StoryData.BEATS.size():
			if StoryData.BEATS[i][0] < Game.day:
				beats_sent[i] = true
		gig_earned = float(Game.stats.get("earned", 0.0))
		_check_milestones()
		changed.emit()
		return
	milestones_done = {}
	var ms: Dictionary = d.get("milestones", {})
	for k in ms:
		milestones_done[k] = int(ms[k])
	ray_paid = float(d.get("ray_paid", 0.0))
	ray_last_day = int(d.get("ray_last_day", Game.day))
	messages = d.get("messages", [])
	for i in d.get("beats", []):
		beats_sent[int(i)] = true
	daily = _ints(d.get("daily", []))
	daily_day = int(d.get("daily_day", 0))
	weekly = _ints(d.get("weekly", []))
	weekly_start = int(d.get("weekly_start", 0))
	gig_earned = float(d.get("gig_earned", 0.0))
	var nv: Dictionary = d.get("npc_visits", {})
	for k in nv:
		npc_visits[k] = int(nv[k])
	for i in d.get("dottie_warned", []):
		_dottie_warned[int(i)] = true
	_oil_changed = bool(d.get("oil", false))
	_refresh_challenges()
	changed.emit()


## JSON turns ints into floats; challenge targets read nicer as ints.
func _ints(list: Array) -> Array:
	for c in list:
		c.n = int(c.n)
		c.reward = float(c.reward)
	return list
