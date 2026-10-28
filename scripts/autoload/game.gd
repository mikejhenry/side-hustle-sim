extends Node
## Global game state (autoload "Game"): clock, money, needs, bills, car condition, housing, saving.

signal money_changed(amount: float)
signal notified(text: String, kind: String)
signal hour_changed(hour: int)
signal day_changed(day: int)
signal minutes_advanced(minutes: float)
signal car_changed
signal home_changed
signal slept(hours: float)
signal bladder_accident
signal bills_changed

const SAVE_PATH := "user://savegame.json"

var money: float
var day: int
var minute: float          # minutes since midnight
var hunger: float          # 100 = full, 0 = starving
var bladder: float         # 0 = empty, 100 = accident
var energy: float          # 100 = rested, 0 = pass out
var phone_battery: float
var phone_service := true
var home_id := "room"
var evicted := false
var fridge_meals := 0
var phone_pro := false       # upgraded phone: shows police on the minimap, slower battery drain

var car_id := "rustwagon"
var fuel: float
var oil_life: float
var tire_tread: float
var engine_health: float
var odometer: float

var bills: Array = []
var loan := {}              # car loan: {lender, car, payment, left}; empty when none
var transactions: Array = []
var stats := {}

var time_multiplier := 1.0
var time_paused := false
var in_car := false
var sleeping := false

var _warned := {}
var _bill_seq := 0
var _passing_out := false


func _ready() -> void:
	# Keeps reading input while paused (gamepad detection); the clock checks for pause itself.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_options()
	new_game()


func new_game() -> void:
	money = GameData.START_MONEY
	day = 1
	minute = GameData.START_HOUR * 60.0
	hunger = 65.0
	bladder = 25.0
	energy = 85.0
	phone_battery = 75.0
	phone_service = true
	home_id = "room"
	evicted = false
	fridge_meals = 1
	phone_pro = false
	car_id = "rustwagon"
	var c: Dictionary = car()
	fuel = c.tank * 0.4
	oil_life = 14.0
	tire_tread = 32.0
	engine_health = 82.0
	odometer = c.odometer
	bills = []
	loan = {}
	transactions = []
	stats = {"earned": 0.0, "spent": 0.0, "jobs": 0, "miles": 0.0}
	_warned = {}
	_generate_bills(day)
	money_changed.emit(money)
	car_changed.emit()
	home_changed.emit()


func _process(delta: float) -> void:
	if time_paused or sleeping or get_tree().paused:
		return
	advance(delta * time_multiplier / GameData.REAL_SECONDS_PER_GAME_MINUTE)


# --- Clock --------------------------------------------------------------------

func hour() -> int:
	return int(minute / 60.0)


func total_minutes() -> float:
	return (day - 1) * 1440.0 + minute


func weekday() -> String:
	return GameData.DAY_NAMES[(day - 1) % 7]


func time_string(m: float = -1.0) -> String:
	if m < 0.0:
		m = minute
	m = fmod(m, 1440.0)
	var h := int(m / 60.0)
	var mm := int(m) % 60
	var suffix := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, mm, suffix]


func abs_time_string(abs_minutes: float) -> String:
	var d := int(abs_minutes / 1440.0) + 1
	var prefix := "" if d == day else ("Tomorrow " if d == day + 1 else "Day %d " % d)
	return prefix + time_string(fmod(abs_minutes, 1440.0))


func is_night() -> bool:
	return hour() < 6 or hour() >= 20


func advance(mins: float, is_sleeping := false, quality := 1.0) -> void:
	var remaining := mins
	while remaining > 0.0:
		var step := minf(remaining, 5.0)
		remaining -= step
		_step(step, is_sleeping, quality)


func _step(m: float, is_sleeping: bool, quality: float) -> void:
	var old_hour := hour()
	minute += m
	if minute >= 1440.0:
		minute -= 1440.0
		day += 1
		day_changed.emit(day)
		if (day - 1) % GameData.BILL_CYCLE_DAYS == 0:
			_generate_bills(day)
	_update_needs(m, is_sleeping, quality)
	_update_weather()
	if hour() != old_hour:
		hour_changed.emit(hour())
		if hour() == GameData.BILL_HOUR:
			process_bills()
	minutes_advanced.emit(m)


# --- Weather ----------------------------------------------------------------------
# Each day gets its own forecast, worked out from the day number (so it never needs
# saving): mostly clear or cloudy, with a spell of rain, a storm or snow on some days, and
# morning fog on others. Bad weather means more and better-paid delivery offers.

signal weather_changed(kind: String)

const WEATHER_NAMES := {"clear": "Clear", "cloudy": "Cloudy", "rain": "Rain", "storm": "Thunderstorm", "snow": "Snow"}
var weather := "clear"          # what's falling (or not) right now
var weather_amount := 0.0       # 0..1, eases in and out
var fog := 0.0                  # 0..1 morning fog
var weather_override := ""      # tests and the dev cheat force a kind


## Today's plan: {kind, start, end (hours), fog (bool)}.
func forecast(for_day := -1) -> Dictionary:
	if for_day < 0:
		for_day = day
	var rng := RandomNumberGenerator.new()
	rng.seed = for_day * 7919 + 13
	var r := rng.randf()
	var kind := "clear"
	if r > 0.42:
		kind = "cloudy"
	if r > 0.6:
		kind = "rain"
	if r > 0.8:
		kind = "storm"
	if r > 0.88:
		kind = "snow"
	var start := rng.randf_range(5.0, 16.0)
	var length := rng.randf_range(3.0, 9.0)
	return {"kind": kind, "start": start, "end": start + length, "fog": rng.randf() < 0.35}


func _update_weather() -> void:
	var f := forecast()
	var h := minute / 60.0
	var kind: String = f.kind
	var target := 0.0
	if kind in ["rain", "storm", "snow"]:
		# Eases in over half an hour and out again; cloudy outside the spell.
		target = clampf(minf(h - f.start, f.end - h) * 2.0, 0.0, 1.0)
		if target <= 0.0:
			kind = "cloudy"
	elif kind == "cloudy":
		target = 1.0
	if weather_override != "":
		kind = weather_override
		target = 1.0
	weather_amount = target
	if kind != weather:
		var old := weather
		weather = kind
		weather_changed.emit(kind)
		if kind in ["rain", "storm", "snow"]:
			notify("Weather: %s. Delivery pay is up %d%% while it lasts. Roads are slippery." % [
				WEATHER_NAMES[kind].to_lower(), roundi((weather_boost("food") - 1.0) * 100.0)], "warn")
		elif old in ["rain", "storm", "snow"]:
			notify("The %s has stopped." % WEATHER_NAMES[old].to_lower(), "info")
	# Morning fog, thickest around 6-8 AM.
	fog = 0.0
	if f.fog and weather_override == "":
		fog = clampf(minf(h - 4.5, 9.5 - h), 0.0, 1.0)


## Pay multiplier from the weather for an app kind: food delivery gets the most,
## Jungle Flex barely anything.
func weather_boost(kind: String) -> float:
	var table := {
		"food": {"rain": 1.3, "storm": 1.45, "snow": 1.5},
		"grocery": {"rain": 1.2, "storm": 1.3, "snow": 1.35},
		"ride": {"rain": 1.25, "storm": 1.35, "snow": 1.4},
		"flex": {"rain": 1.04, "storm": 1.06, "snow": 1.08},
	}
	var b: float = table.get(kind, {}).get(weather, 1.0)
	var fog_b := 1.05 if kind in ["food", "ride"] else 1.0
	return lerpf(1.0, b, weather_amount) * lerpf(1.0, fog_b, fog)


func weather_text() -> String:
	var t: String = WEATHER_NAMES.get(weather, "Clear")
	if fog > 0.3:
		t = "Fog" if weather in ["clear", "cloudy"] else t + ", fog"
	return t


# --- Needs ----------------------------------------------------------------------

func _update_needs(m: float, is_sleeping: bool, quality: float) -> void:
	var sleep_mult := 0.4 if is_sleeping else 1.0
	hunger = maxf(0.0, hunger - GameData.HUNGER_DRAIN * m * sleep_mult)
	bladder = minf(100.0, bladder + GameData.BLADDER_FILL * m * (0.3 if is_sleeping else 1.0))
	if is_sleeping:
		energy = minf(100.0, energy + GameData.SLEEP_GAIN * quality * m)
	else:
		var drain := GameData.ENERGY_DRAIN
		if hunger <= 0.0:
			drain *= GameData.STARVING_ENERGY_MULT
		energy = maxf(0.0, energy - drain * m)

	# Phone battery: charges in the car or while sleeping at home.
	if in_car or (is_sleeping and home_id != ""):
		phone_battery = minf(100.0, phone_battery + GameData.PHONE_CHARGE * m)
	else:
		var online: bool = Gigs.any_online()
		var drain: float = GameData.PHONE_DRAIN_ONLINE if online else GameData.PHONE_DRAIN_IDLE
		phone_battery = maxf(0.0, phone_battery - drain * (0.6 if phone_pro else 1.0) * m)

	_threshold_warn("hungry", hunger < 25.0, "You're getting hungry. Grab some food.", "warn")
	_threshold_warn("starving", hunger <= 0.0, "You're starving! Your energy is draining fast.", "bad")
	_threshold_warn("bladder", bladder > 75.0, "You really need to pee. Find a restroom!", "warn")
	_threshold_warn("tired", energy < 20.0, "You're exhausted. Find somewhere to sleep.", "warn")
	_threshold_warn("battery", phone_battery < 15.0, "Phone battery low. Charge it in your car.", "warn")

	if bladder >= 100.0:
		bladder = 0.0
		hunger = maxf(0.0, hunger)
		var cost := minf(money, GameData.BLADDER_ACCIDENT_COST)
		money -= cost
		_log("Emergency pants + dry cleaning", -cost)
		money_changed.emit(money)
		notify("You had an accident... That cost $%.0f in new pants." % cost, "bad")
		bladder_accident.emit()
	if energy <= 0.0 and not is_sleeping and not _passing_out:
		_passing_out = true
		notify("You passed out from exhaustion!", "bad")
		call_deferred("_pass_out")


func _pass_out() -> void:
	sleep(5.0, 0.5)
	_passing_out = false


func _threshold_warn(key: String, cond: bool, text: String, kind: String) -> void:
	if cond and not _warned.get(key, false):
		_warned[key] = true
		notify(text, kind)
	elif not cond:
		_warned[key] = false


func eat(label: String, hunger_gain: float, energy_gain := 0.0) -> void:
	hunger = minf(100.0, hunger + hunger_gain)
	energy = minf(100.0, energy + energy_gain)
	bladder = minf(99.0, bladder + 6.0)
	notify("You had: %s" % label, "good")


func use_restroom() -> void:
	bladder = 0.0
	advance(3.0)
	notify("Ahh. Much better.", "good")


func sleep(hours: float, quality: float) -> void:
	Gigs.go_offline_all()
	sleeping = true
	advance(hours * 60.0, true, quality)
	sleeping = false
	slept.emit(hours)


func hours_until(target_hour: int) -> float:
	var target := target_hour * 60.0
	var diff := target - minute
	if diff <= 0.0:
		diff += 1440.0
	return diff / 60.0


# --- Money ----------------------------------------------------------------------

func notify(text: String, kind := "info") -> void:
	notified.emit(text, kind)


func earn(amount: float, memo: String) -> void:
	money += amount
	stats.earned += amount
	_log(memo, amount)
	money_changed.emit(money)


func spend(amount: float, memo: String) -> bool:
	if money + 0.001 < amount:
		notify("Not enough money. You need $%.2f." % amount, "bad")
		return false
	money -= amount
	stats.spent += amount
	_log(memo, -amount)
	money_changed.emit(money)
	return true


func _log(memo: String, amount: float) -> void:
	transactions.push_front({"memo": memo, "amount": amount, "time": "%s %s" % [weekday(), time_string()]})
	if transactions.size() > 30:
		transactions.pop_back()


## Traffic ticket: paid on the spot when you can afford it, otherwise it becomes a bill.
func ticket(reason: String, amount: float) -> void:
	stats["tickets"] = int(stats.get("tickets", 0)) + 1
	if money >= amount:
		spend(amount, "Ticket: " + reason)
		notify("Ticket for %s: $%.0f, paid." % [reason, amount], "bad")
	else:
		_add_bill("Traffic ticket: " + reason, amount, day + GameData.TICKET_DUE_DAYS, "ticket")
		bills_changed.emit()
		notify("Ticket for %s: $%.0f. You can't cover it, so it's a bill due in %d days." % [reason, amount, GameData.TICKET_DUE_DAYS], "bad")


## Camera ticket: no cop, it arrives in the mail as a bill.
func mail_ticket(reason: String, amount: float) -> void:
	stats["tickets"] = int(stats.get("tickets", 0)) + 1
	_add_bill("Camera ticket: " + reason, amount, day + GameData.TICKET_DUE_DAYS, "ticket")
	bills_changed.emit()
	notify("📸 Flash! Ticket in the mail for %s: $%.0f, due in %d days (Bank app)." % [reason, amount, GameData.TICKET_DUE_DAYS], "bad")


func buy_phone_upgrade() -> bool:
	if phone_pro:
		return false
	if not spend(GameData.PHONE_PRO_PRICE, GameData.PHONE_PRO_NAME):
		return false
	phone_pro = true
	notify("New %s! Police now show on your map, and the battery lasts longer." % GameData.PHONE_PRO_NAME, "good")
	return true


# --- Bills ----------------------------------------------------------------------

func _generate_bills(start_day: int) -> void:
	var due := start_day + GameData.BILL_CYCLE_DAYS - 1
	if home_id != "":
		_add_bill("Rent: " + home().short, home().rent, due, "rent")
	_add_bill("Phone plan (TalkMore Wireless)", GameData.PHONE_BILL, due, "phone")
	_add_bill("Car insurance (GEICKO)", car().insurance, due, "insurance")
	if not loan.is_empty() and int(loan.left) > 0:
		_add_bill("Car loan (%s, %d left)" % [loan.lender, int(loan.left) - 1], float(loan.payment), due, "loan")
		loan.left = int(loan.left) - 1
		if loan.left <= 0:
			loan = {}
	bills_changed.emit()


func _add_bill(bill_name: String, amount: float, due_day: int, kind: String) -> void:
	_bill_seq += 1
	bills.append({"id": _bill_seq, "name": bill_name, "amount": amount, "due_day": due_day,
		"kind": kind, "paid": false, "overdue": false})


func unpaid_bills() -> Array:
	var out := bills.filter(func(b): return not b.paid)
	out.sort_custom(func(a, b): return a.due_day < b.due_day)
	return out


func pay_bill(bill_id: int) -> bool:
	for b in bills:
		if b.id == bill_id and not b.paid:
			if spend(b.amount, "Bill: " + b.name):
				b.paid = true
				if b.kind == "phone" and not phone_service:
					phone_service = true
					notify("Phone service restored.", "good")
				bills_changed.emit()
				return true
	return false


func process_bills() -> void:
	for b in bills:
		if b.paid or b.due_day > day:
			continue
		if money >= b.amount:
			pay_bill(b.id)
			notify("Auto-paid %s ($%.2f)" % [b.name, b.amount], "info")
		elif not b.overdue:
			b.overdue = true
			b.amount += GameData.LATE_FEE
			notify("Couldn't pay %s! Late fee added. Pay it in the Bank app." % b.name, "bad")
	for b in bills:
		if b.paid:
			continue
		if b.kind == "rent" and day - b.due_day >= GameData.EVICTION_GRACE_DAYS and not evicted:
			_evict()
		if b.kind == "loan" and day - b.due_day >= GameData.REPO_GRACE_DAYS:
			_repossess()
		if b.kind == "phone" and day - b.due_day >= 1 and phone_service:
			phone_service = false
			Gigs.go_offline_all()
			notify("Phone service suspended for non-payment. Gig apps won't work!", "bad")
	# Keep the list short.
	bills = bills.filter(func(b): return not b.paid or b.due_day >= day - 6)
	bills_changed.emit()


func _evict() -> void:
	evicted = true
	home_id = ""
	for b in bills:
		if b.kind == "rent" and not b.paid:
			b.paid = true
			b.name += " (sent to collections)"
	notify("You've been EVICTED. You'll have to sleep in your car until you sign a new lease.", "bad")
	home_changed.emit()


## Missed car payments: the lender takes the car. You're left with a beat-up Rustwagon from
## their back lot, and the rest of the loan goes to collections.
func _repossess() -> void:
	var lost: String = car().name
	for b in bills:
		if b.kind == "loan" and not b.paid:
			b.paid = true
			b.name += " (sent to collections)"
	loan = {}
	car_id = "rustwagon"
	var c := car()
	fuel = c.tank * 0.25
	oil_life = 30.0
	tire_tread = 30.0
	engine_health = 60.0
	odometer = c.odometer
	notify("Your %s was REPOSSESSED for missed payments. %s left you a beat-up Rustwagon." % [lost, GameData.FINANCE_NAME], "bad")
	car_changed.emit()


# --- Housing ---------------------------------------------------------------------

func home() -> Dictionary:
	return GameData.HOMES.get(home_id, {})


func sign_lease(id: String) -> bool:
	var h: Dictionary = GameData.HOMES[id]
	var move_in: float = h.deposit + h.rent
	if not spend(move_in, "Move-in: " + h.short):
		return false
	home_id = id
	evicted = false
	# The first cycle's rent was paid at move-in; drop other unpaid upcoming rent.
	for b in bills:
		if b.kind == "rent" and not b.paid and not b.overdue:
			b.paid = true
			b.name += " (lease ended)"
	notify("Welcome home! You moved into the " + h.name + ".", "good")
	home_changed.emit()
	bills_changed.emit()
	return true


# --- Car --------------------------------------------------------------------------

func car() -> Dictionary:
	return GameData.CARS[car_id]


func add_distance(meters: float, hard := 0.0) -> void:
	var miles := meters / GameData.METERS_PER_MILE
	if miles <= 0.0:
		return
	var c := car()
	odometer += miles
	stats.miles += miles
	fuel = maxf(0.0, fuel - miles / c.mpg)
	oil_life = maxf(0.0, oil_life - miles * GameData.OIL_PER_MILE)
	tire_tread = maxf(0.0, tire_tread - miles * GameData.TIRE_PER_MILE * (1.0 + hard))
	if oil_life <= 0.0:
		engine_health = maxf(0.0, engine_health - miles * GameData.ENGINE_DAMAGE_NO_OIL)
	_threshold_warn("oil", oil_life < 10.0, "Oil change overdue! Visit Lube & Tube before the engine suffers.", "warn")
	_threshold_warn("noil", oil_life <= 0.0, "Your engine is running without good oil. It's getting damaged!", "bad")
	_threshold_warn("tires", tire_tread < 15.0, "Your tires are bald. Grip is poor, replace them soon.", "warn")
	_threshold_warn("fuel", fuel < c.tank * 0.12, "Fuel is low. Find a gas station.", "warn")
	_threshold_warn("nofuel", fuel <= 0.0, "Out of gas! Call a tow from the Garage app or walk to Gas-N-Go.", "bad")


func damage_engine(amount: float) -> void:
	engine_health = maxf(0.0, engine_health - amount)


func engine_factor() -> float:
	if fuel <= 0.0:
		return 0.0
	var f := 0.35 + 0.65 * engine_health / 100.0
	if oil_life <= 0.0:
		f *= 0.8
	return f


func grip_factor() -> float:
	var tires := 0.55 + 0.45 * tire_tread / 100.0
	# Wet roads cost some grip, snow a lot (worse with bald tires).
	var wet := {"rain": 0.85, "storm": 0.78, "snow": 0.6}.get(weather, 1.0) as float
	return tires * lerpf(1.0, wet, weather_amount)


func refuel(gallons: float) -> bool:
	var cost := gallons * GameData.GAS_PRICE
	if spend(cost, "Gas-N-Go: %.1f gal" % gallons):
		fuel = minf(car().tank, fuel + gallons)
		notify("Filled up %.1f gallons for $%.2f" % [gallons, cost], "good")
		car_changed.emit()
		return true
	return false


func oil_change() -> bool:
	if spend(GameData.OIL_CHANGE_PRICE, "Lube & Tube: oil change"):
		oil_life = 100.0
		notify("Fresh oil. Your engine thanks you.", "good")
		car_changed.emit()
		return true
	return false


func replace_tires() -> bool:
	if spend(car().tires, "Lube & Tube: new tires"):
		tire_tread = 100.0
		notify("New tires installed. Grippy!", "good")
		car_changed.emit()
		return true
	return false


func repair_cost() -> float:
	return roundf((100.0 - engine_health) * GameData.ENGINE_REPAIR_PER_PCT)


func repair_engine() -> bool:
	if spend(repair_cost(), "Lube & Tube: engine repair"):
		engine_health = 100.0
		notify("Engine repaired.", "good")
		car_changed.emit()
		return true
	return false


func trade_in_value() -> float:
	return roundf(car().trade_in * (0.5 + 0.5 * engine_health / 100.0))


func buy_car(id: String) -> bool:
	var c: Dictionary = GameData.CARS[id]
	if not loan.is_empty():
		notify("Pay off your %s loan before trading in this car." % loan.lender, "bad")
		return false
	var cost: float = maxf(0.0, c.price - trade_in_value())
	if not spend(cost, "Honest Al's: " + c.name):
		return false
	_take_delivery(id)
	notify("You bought a %s! Insurance changes next bill cycle." % c.name, "good")
	return true


## Financing terms for a car: {price, down, due_now, financed, payment, total}.
## Your trade-in goes toward the down payment first, then the loan.
func finance_terms(id: String) -> Dictionary:
	var c: Dictionary = GameData.CARS[id]
	var price := roundf(float(c.price) * GameData.FINANCE_MARKUP)
	var down := roundf(price * GameData.FINANCE_DOWN)
	var trade := trade_in_value()
	var due_now := maxf(0.0, down - trade)
	var financed := price - down - maxf(0.0, trade - down)
	var r := GameData.FINANCE_APR / 12.0
	var n := GameData.FINANCE_MONTHS
	var payment := snappedf(financed * r / (1.0 - pow(1.0 + r, -n)), 0.01)
	return {"price": price, "down": down, "due_now": due_now, "financed": financed,
		"payment": payment, "total": due_now + trade + payment * n}


func finance_car(id: String) -> bool:
	if not loan.is_empty():
		notify("You already have a car loan. Pay it off first.", "bad")
		return false
	var t := finance_terms(id)
	if not spend(t.due_now, "%s down payment" % GameData.FINANCE_NAME):
		return false
	_take_delivery(id)
	loan = {"lender": GameData.FINANCE_NAME, "car": id, "payment": t.payment, "left": GameData.FINANCE_MONTHS}
	notify("Drove off in a %s! $%.2f a month for %d months, starting next bill cycle. Miss a payment and they take it." % [
		car().name, t.payment, GameData.FINANCE_MONTHS], "good")
	bills_changed.emit()
	return true


## Pay the rest of the loan in one go (no discount for paying early).
func loan_payoff() -> float:
	var pending := 0.0
	for b in bills:
		if b.kind == "loan" and not b.paid:
			pending += b.amount
	return pending + (float(loan.payment) * int(loan.left) if not loan.is_empty() else 0.0)


func pay_off_loan() -> bool:
	var amount := loan_payoff()
	if amount <= 0.0:
		return false
	if not spend(amount, "%s loan payoff" % GameData.FINANCE_NAME):
		return false
	for b in bills:
		if b.kind == "loan" and not b.paid:
			b.paid = true
	loan = {}
	notify("Loan paid off. The car is all yours.", "good")
	bills_changed.emit()
	return true


func _take_delivery(id: String) -> void:
	var c: Dictionary = GameData.CARS[id]
	car_id = id
	fuel = c.tank * 0.5
	oil_life = 100.0
	tire_tread = 100.0
	engine_health = 100.0
	odometer = c.odometer
	car_changed.emit()


# --- Save / load --------------------------------------------------------------------

func save_game() -> void:
	var data := {
		"money": money, "day": day, "minute": minute, "hunger": hunger, "bladder": bladder,
		"energy": energy, "phone_battery": phone_battery, "phone_service": phone_service,
		"home_id": home_id, "evicted": evicted, "fridge_meals": fridge_meals,
		"car_id": car_id, "fuel": fuel, "oil_life": oil_life, "tire_tread": tire_tread,
		"engine_health": engine_health, "odometer": odometer, "bills": bills,
		"transactions": transactions, "stats": stats, "bill_seq": _bill_seq,
		"ratings": Gigs.ratings, "phone_pro": phone_pro, "loan": loan,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		notify("Game saved.", "info")


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_game() -> bool:
	if not has_save():
		notify("No save found.", "warn")
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		notify("Save file is corrupted.", "bad")
		return false
	for key in ["money", "minute", "hunger", "bladder", "energy", "phone_battery", "fuel",
			"oil_life", "tire_tread", "engine_health", "odometer"]:
		set(key, float(data.get(key, get(key))))
	day = int(data.get("day", 1))
	phone_service = bool(data.get("phone_service", true))
	home_id = str(data.get("home_id", "room"))
	evicted = bool(data.get("evicted", false))
	fridge_meals = int(data.get("fridge_meals", 0))
	phone_pro = bool(data.get("phone_pro", false))
	loan = data.get("loan", {})
	if not loan.is_empty():
		loan.left = int(loan.left)
	car_id = str(data.get("car_id", "rustwagon"))
	bills = data.get("bills", [])
	for b in bills:
		b.id = int(b.id)
		b.due_day = int(b.due_day)
	transactions = data.get("transactions", [])
	stats = data.get("stats", stats)
	_bill_seq = int(data.get("bill_seq", 0))
	var r = data.get("ratings", {})
	for k in r:
		Gigs.ratings[k] = float(r[k])
	Gigs.reset_jobs()
	money_changed.emit(money)
	car_changed.emit()
	home_changed.emit()
	bills_changed.emit()
	notify("Game loaded.", "info")
	return true


# --- Input map (set up in code so project.godot stays readable) -------------------

func _setup_input() -> void:
	# Keyboard keys, then gamepad buttons and stick/trigger directions (Xbox layout names).
	_bind("move_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("move_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("throttle", [], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_bind("brake_reverse", [], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_bind("look_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_bind("look_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_bind("look_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_bind("look_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_pad_menus()
	_bind("sprint", [KEY_SHIFT], [JOY_BUTTON_LEFT_STICK])
	_bind("jump", [KEY_SPACE], [JOY_BUTTON_A])
	_bind("handbrake", [KEY_SPACE], [JOY_BUTTON_A])
	_bind("interact", [KEY_E], [JOY_BUTTON_X])
	_bind("phone", [KEY_TAB, KEY_P], [JOY_BUTTON_Y])
	_bind("back", [], [JOY_BUTTON_B])
	_bind("horn", [KEY_H], [JOY_BUTTON_RIGHT_STICK])
	_bind("reset_car", [KEY_R], [JOY_BUTTON_DPAD_DOWN])
	_bind("headlights", [KEY_L], [JOY_BUTTON_RIGHT_SHOULDER])
	_bind("camera_toggle", [KEY_C], [JOY_BUTTON_LEFT_SHOULDER])
	_bind("mirrors", [KEY_M], [JOY_BUTTON_DPAD_UP])
	_bind("help", [KEY_F1], [JOY_BUTTON_BACK])
	_bind("save_game", [KEY_F5])
	_bind("load_game", [KEY_F9])
	_bind("time_warp", [KEY_F7])
	_bind("cheat_money", [KEY_F8])
	_bind("cheat_weather", [KEY_F6])
	_bind("graphics", [KEY_F3])
	_bind("pause", [KEY_ESCAPE], [JOY_BUTTON_START])


func _bind(action: String, keys: Array, buttons: Array = [], axes: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)
	for a in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[0]
		jm.axis_value = a[1]
		InputMap.action_add_event(action, jm)


# --- Gamepad / keyboard detection ---------------------------------------------------
# Menus get a highlighted (focused) button only while you're using a gamepad, so the
# keyboard's Space and Enter never press a phone button by accident.

var using_pad := false

## On-screen names of controls: [keyboard, gamepad]. Prompts use key() so they always name
## whichever device you touched last.
const KEY_NAMES := {
	"interact": ["E", "X"], "phone": ["Tab", "Y"], "pause": ["Esc", "Start"], "back": ["Esc", "B"],
	"help": ["F1", "Back"], "mirrors": ["M", "D-pad up"], "camera_toggle": ["C", "LB"],
	"headlights": ["L", "RB"], "horn": ["H", "R3"], "reset_car": ["R", "D-pad down"],
	"handbrake": ["Space", "A"], "sprint": ["Shift", "L3"], "jump": ["Space", "A"],
	"gas": ["W", "RT"], "brake": ["S", "LT"], "move": ["WASD", "the left stick"],
	"look": ["the mouse", "the right stick"], "graphics": ["F3", "the pause menu"],
	"save_game": ["F5", "the pause menu"], "load_game": ["F9", "the pause menu"],
}


## Right-stick look with a response curve: small pushes make small, slow turns, so it pans
## like a head instead of snapping. (The 0.25 deadzone is applied by get_vector.)
func look_stick() -> Vector2:
	var v := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var m := v.length()
	if m < 0.001:
		return Vector2.ZERO
	return v / m * pow(minf(m, 1.0), 1.8)


func key(action: String) -> String:
	var names: Array = KEY_NAMES.get(action, [action, action])
	return names[1] if using_pad else names[0]


# --- Options (saved in user://settings.cfg, separate from save games) -----------------

const SETTINGS_PATH := "user://settings.cfg"
var volume := 0.8           # master volume 0..1
var mouse_sens := 1.0       # multiplier
var pad_sens := 1.0         # right-stick look speed multiplier
var mirror_mode := 0        # 0 = mirrors in the car, 1 = car + screen overlays, 2 = off


func load_options() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		volume = float(cfg.get_value("options", "volume", volume))
		mouse_sens = float(cfg.get_value("options", "mouse_sens", mouse_sens))
		pad_sens = float(cfg.get_value("options", "pad_sens", pad_sens))
		mirror_mode = int(cfg.get_value("options", "mirror_mode", mirror_mode))
	apply_volume()


func save_options() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("options", "volume", volume)
	cfg.set_value("options", "mouse_sens", mouse_sens)
	cfg.set_value("options", "pad_sens", pad_sens)
	cfg.set_value("options", "mirror_mode", mirror_mode)
	cfg.save(SETTINGS_PATH)


func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)


func _input(event: InputEvent) -> void:
	track_device(event)


## Menus on the gamepad: A picks the highlighted option, B backs out. Godot's defaults don't
## include A, and they put Y on "select", which would press a button while closing the phone.
func _pad_menus() -> void:
	for e in InputMap.action_get_events("ui_select"):
		if e is InputEventJoypadButton:
			InputMap.action_erase_event("ui_select", e)
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		if not InputMap.action_get_events(pair[0]).any(func(e): return e is InputEventJoypadButton and e.button_index == pair[1]):
			var ev := InputEventJoypadButton.new()
			ev.button_index = pair[1]
			InputMap.action_add_event(pair[0], ev)


## Notes whether you're on the gamepad or keyboard/mouse. Main calls this too, because it
## handles some buttons (like opening the phone) before this autoload sees them.
func track_device(event: InputEvent) -> void:
	var vp := get_viewport()
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		using_pad = true
		# A menu is open but nothing is highlighted yet: highlight its first option, so the
		# D-pad and A work right away.
		if vp and vp.gui_get_focus_owner() == null and is_instance_valid(_focus_root) \
				and _focus_root.is_visible_in_tree():
			pad_focus.call_deferred(_focus_root)
	elif event is InputEventKey or event is InputEventMouseButton:
		if using_pad:
			using_pad = false
		if vp and vp.gui_get_focus_owner() and event is InputEventKey:
			vp.gui_release_focus()


var _focus_root: Node = null

## Focus the first enabled button under `root` when a gamepad is in use. Also remembers
## `root` as the open menu, so switching to the gamepad later can still highlight it.
func pad_focus(root: Node, index := 0) -> void:
	if root == null:
		return
	_focus_root = root
	if not using_pad:
		return
	var buttons := root.find_children("*", "Control", true, false).filter(
		func(b): return b.is_visible_in_tree() and ((b is BaseButton and not b.disabled) or b is Slider))
	if buttons.is_empty():
		return
	(buttons[clampi(index, 0, buttons.size() - 1)] as Control).grab_focus()
