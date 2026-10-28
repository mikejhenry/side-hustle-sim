class_name Phone
extends CanvasLayer
## The in-game smartphone. Gig apps, Bank (bills), Garage (car), Maps (GPS), and Me (needs).

var main: Node = null
var is_open := false
var current_app := ""

var _body: PanelContainer
var _screen: VBoxContainer
var _status: Label
var _live: Array = []         # [{node, fn}] refreshed 4x per second
var _dirty := false
var _tick := 0.0

const ICONS := {
	"yoober": "Y", "drift": "D", "doordish": "DD", "instacrate": "IC", "jungleflex": "JF",
	"bank": "$", "garage": "G", "maps": "M", "me": "Me",
}


func _ready() -> void:
	layer = 5
	_body = PanelContainer.new()
	_body.anchor_left = 1.0
	_body.anchor_right = 1.0
	_body.anchor_top = 1.0
	_body.anchor_bottom = 1.0
	_body.offset_left = -400
	_body.offset_right = -24
	_body.offset_top = -700
	_body.offset_bottom = -24
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.06, 0.06, 0.07)
	frame.set_corner_radius_all(30)
	frame.border_color = Color(0.25, 0.25, 0.28)
	frame.set_border_width_all(4)
	frame.content_margin_left = 14
	frame.content_margin_right = 14
	frame.content_margin_top = 14
	frame.content_margin_bottom = 20
	_body.add_theme_stylebox_override("panel", frame)
	add_child(_body)
	var col := VBoxContainer.new()
	_body.add_child(col)
	_status = _lbl(col, "", 13, Color(0.8, 0.8, 0.85))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	col.add_child(scroll)
	_screen = VBoxContainer.new()
	_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen.add_theme_constant_override("separation", 8)
	scroll.add_child(_screen)
	var home_btn := _btn(col, "( Home )", func(): open_app(""))
	home_btn.add_theme_font_size_override("font_size", 14)
	_body.visible = false

	Gigs.offers_changed.connect(_mark_dirty)
	Gigs.job_changed.connect(_mark_dirty)
	Game.bills_changed.connect(_mark_dirty)
	Game.home_changed.connect(_mark_dirty)
	Game.car_changed.connect(_mark_dirty)


func _mark_dirty() -> void:
	_dirty = true


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	is_open = true
	_body.visible = true
	_rebuild()
	if main:
		main.on_phone_toggled(true)


func close() -> void:
	is_open = false
	_body.visible = false
	if main:
		main.on_phone_toggled(false)


func open_app(id: String) -> void:
	current_app = id
	if not is_open:
		open()
	else:
		_rebuild()


func _process(delta: float) -> void:
	if not is_open:
		return
	_tick += delta
	if _dirty:
		_dirty = false
		_rebuild()
	if _tick >= 0.25:
		_tick = 0.0
		_status.text = "%s     %s     %d%%%s" % [Game.time_string(), "TalkMore 5G" if Game.phone_service else "NO SERVICE",
			int(Game.phone_battery), " (charging)" if Game.in_car else ""]
		for l in _live:
			if is_instance_valid(l.node):
				l.fn.call(l.node)


# --- Widgets ------------------------------------------------------------------

func _lbl(parent: Node, text: String, size := 16, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	parent.add_child(l)
	return l


func _btn(parent: Node, text: String, cb: Callable, color := Color(0.2, 0.2, 0.24)) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = color.lightened(0.12) if state == "hover" else (color.darkened(0.3) if state == "disabled" else color)
		if state == "focus":
			# Gamepad highlight: outline only, drawn over the normal look.
			s.draw_center = false
			s.set_border_width_all(3)
			s.border_color = Color(1, 0.85, 0.3)
		s.set_corner_radius_all(10)
		s.content_margin_top = 8
		s.content_margin_bottom = 8
		s.content_margin_left = 10
		s.content_margin_right = 10
		b.add_theme_stylebox_override(state, s)
	parent.add_child(b)
	return b


func _card(color := Color(0.13, 0.13, 0.16)) -> VBoxContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(12)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", s)
	_screen.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	return v


func _live_label(parent: Node, fn: Callable, size := 15, color := Color.WHITE) -> Label:
	var l := _lbl(parent, "", size, color)
	fn.call(l)
	_live.append({"node": l, "fn": fn})
	return l


func _live_button(parent: Node, text: String, cb: Callable, enabled_fn: Callable, color: Color) -> Button:
	var b := _btn(parent, text, cb, color)
	var fn := func(n): n.disabled = not enabled_fn.call()
	fn.call(b)
	_live.append({"node": b, "fn": fn})
	return b


func _header(title: String, color: Color, sub := "") -> void:
	var v := _card(color)
	_lbl(v, title, 24, Color.WHITE)
	if sub != "":
		_lbl(v, sub, 13, Color(1, 1, 1, 0.8))


# --- Screens ------------------------------------------------------------------

func _rebuild() -> void:
	# Keep the gamepad highlight on the same button when the screen refreshes.
	var focus_index := 0
	var focused := get_viewport().gui_get_focus_owner()
	if focused and _body.is_ancestor_of(focused):
		focus_index = _body.find_children("*", "BaseButton", true, false).filter(
			func(b): return b.is_visible_in_tree() and not b.disabled).find(focused)
	_build_screen()
	Game.pad_focus.call_deferred(_body, maxi(focus_index, 0))


func _build_screen() -> void:
	for c in _screen.get_children():
		_screen.remove_child(c)
		c.queue_free()
	_live.clear()
	if not Game.phone_service and current_app in GameData.APPS:
		_header("No Service", Color(0.4, 0.1, 0.1), "Pay your phone bill in the Bank app.")
		return
	if Game.phone_battery <= 0.0:
		_header("Battery dead", Color(0.2, 0.2, 0.2), "Sit in your car to charge.")
		return
	match current_app:
		"": _home()
		"bank": _bank()
		"garage": _garage()
		"maps": _maps()
		"me": _me()
		_: _gig_app(current_app)


func _home() -> void:
	_lbl(_screen, "  " + Game.time_string(), 40)
	_lbl(_screen, "  %s, Day %d" % [Game.weekday(), Game.day], 16, Color(0.8, 0.8, 0.85))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_screen.add_child(grid)
	var apps := []
	for id in GameData.APP_ORDER:
		var a: Dictionary = GameData.APPS[id]
		apps.append([id, a.name, a.color])
	apps.append(["bank", "Bank", Color(0.15, 0.4, 0.2)])
	apps.append(["garage", "Garage", Color(0.35, 0.35, 0.4)])
	apps.append(["maps", "Maps", Color(0.2, 0.45, 0.75)])
	apps.append(["me", "Me", Color(0.55, 0.35, 0.65)])
	for a in apps:
		var id: String = a[0]
		var label: String = "%s\n%s" % [ICONS[id], a[1]]
		if Gigs.online.get(id, false):
			label += " •"
		var b := _btn(grid, label, func(): open_app(id), a[2])
		b.custom_minimum_size = Vector2(98, 84)
		b.add_theme_font_size_override("font_size", 14)
	if not Gigs.offers.is_empty():
		_lbl(_screen, "%d pending offer(s)!" % Gigs.offers.size(), 16, Color(0.5, 1, 0.6))
	if not Gigs.job.is_empty():
		var v := _card(Color(0.15, 0.2, 0.15))
		_live_label(v, func(n): n.text = Gigs.status_text(), 14)


func _gig_app(id: String) -> void:
	var a: Dictionary = GameData.APPS[id]
	_header(a.name, a.color, a.tagline)
	var top := _card()
	_live_label(top, func(n): n.text = "Rating: %.2f ★     %s" % [Gigs.ratings[id], Gigs.demand_label(id)], 15)
	_demand_chart(top, id)
	var reason := Gigs.ineligible_reason(id)
	if reason != "":
		_lbl(top, reason, 14, Color(1, 0.5, 0.4))
	var on: bool = Gigs.online[id]
	_btn(top, "GO OFFLINE" if on else "GO ONLINE", func():
		Gigs.set_online(id, not on)
		_rebuild(), Color(0.6, 0.15, 0.15) if on else Color(0.1, 0.55, 0.25))

	if not Gigs.job.is_empty() and Gigs.job.app == id:
		_job_card(id)
	elif not Gigs.job.is_empty():
		_lbl(_screen, "You're busy with a %s job." % GameData.APPS[Gigs.job.app].name, 14, Color(1, 0.85, 0.4))

	for o in Gigs.offers:
		if o.app != id:
			continue
		_offer_card(o, a)
	if on and Gigs.job.is_empty() and not Gigs.offers.any(func(o): return o.app == id):
		_lbl(_screen, "Looking for offers..." if a.kind != "flex" else "Blocks appear about 2.5 hours before they start (6AM, 10AM, 2PM, 6PM).", 14, Color(0.7, 0.7, 0.75))


func _demand_chart(parent: Node, id: String) -> void:
	_lbl(parent, "Peak times today (hour 0-23):", 12, Color(0.75, 0.75, 0.8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.custom_minimum_size.y = 40
	parent.add_child(row)
	for h in 24:
		var s := Gigs.surge(id, h)
		var holder := VBoxContainer.new()
		holder.alignment = BoxContainer.ALIGNMENT_END
		holder.custom_minimum_size = Vector2(10, 40)
		row.add_child(holder)
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(10, 10.0 + (s - 1.0) * 30.0)
		bar.color = Color(1, 0.55, 0.15) if s > 1.0 else Color(0.35, 0.35, 0.4)
		holder.add_child(bar)
		var fn := func(n): n.color = Color(0.3, 1, 0.4) if Game.hour() == h else (Color(1, 0.55, 0.15) if s > 1.0 else Color(0.35, 0.35, 0.4))
		_live.append({"node": bar, "fn": fn})


func _offer_card(o: Dictionary, _a: Dictionary) -> void:
	var v := _card(Color(0.12, 0.18, 0.14))
	_lbl(v, "$%.2f" % o.pay, 30, Color(0.5, 1, 0.6))
	match o.kind:
		"ride":
			_lbl(v, "%s • %.1f mi trip • pickup %.1f mi away" % [o.passenger, o.miles, o.pickup_miles], 14)
			_lbl(v, "From: %s\nTo: %s" % [o.pickup.name, o.dropoff.name], 13, Color(0.85, 0.85, 0.9))
		"food":
			_lbl(v, "%.1f mi total • incl. $%.0f tip%s" % [o.miles, o.tip, " • Peak Pay +$%.2f" % o.peak_pay if o.peak_pay > 0 else ""], 14)
			_lbl(v, "Pickup: %s\nDeliver: %s" % [o.restaurant.name, o.customer.name], 13, Color(0.85, 0.85, 0.9))
		"grocery":
			_lbl(v, "%d items • %.1f mi • incl. $%.0f tip" % [o.items.size(), o.miles, o.tip], 14)
			_lbl(v, "Shop: %s\nDeliver: %s" % [o.store.name, o.customer.name], 13, Color(0.85, 0.85, 0.9))
		"flex":
			_lbl(v, "Block %s - %s • %d packages" % [Game.abs_time_string(o.start), Game.time_string(fmod(o.end, 1440.0)), o.packages], 14)
			_lbl(v, "Station: Jungle Flex DNC9 (east side, near the port)", 13, Color(0.85, 0.85, 0.9))
	_live_label(v, func(n): n.text = "Expires in %d min" % maxi(0, int(o.expires - Game.total_minutes())), 12, Color(1, 0.8, 0.4))
	var row := HBoxContainer.new()
	v.add_child(row)
	var acc := _btn(row, "  ACCEPT  ", func(): Gigs.accept(o.id), Color(0.1, 0.55, 0.25))
	acc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acc.disabled = not Gigs.job.is_empty()
	_btn(row, "Decline", func(): Gigs.decline(o.id), Color(0.35, 0.2, 0.2))


func _job_card(_id: String) -> void:
	var j := Gigs.job
	var v := _card(Color(0.12, 0.15, 0.22))
	_lbl(v, "ACTIVE JOB  •  $%.2f" % j.pay, 18, Color(0.6, 0.85, 1))
	_live_label(v, func(n): n.text = Gigs.status_text(), 14)
	if j.kind != "flex":
		_live_label(v, func(n):
			var left := int(Gigs.job.get("deadline", 0.0) - Game.total_minutes()) if not Gigs.job.is_empty() else 0
			n.text = ("Due in %d min" % left) if left >= 0 else ("LATE by %d min" % -left), 13, Color(1, 0.8, 0.4))
	match j.stage:
		"to_pickup":
			_live_button(v, "ARRIVED: START TRIP", func(): Gigs.start_trip(), func(): return Gigs.can_start_trip(), Color(0.1, 0.5, 0.25))
			_lbl(v, "Stop at the pickup beacon in your car to start.", 12, Color(0.7, 0.7, 0.75))
		"to_dropoff":
			_live_button(v, "COMPLETE TRIP", func(): Gigs.end_trip(), func(): return Gigs.can_end_trip(), Color(0.1, 0.5, 0.25))
			_lbl(v, "Passenger: %s. Drive smoothly, crashes cost stars." % j.passenger, 12, Color(0.7, 0.7, 0.75))
		"confirm_photo":
			_btn(v, "TAKE DROP-OFF PHOTO  📷", func(): Gigs.confirm_photo(), Color(0.1, 0.5, 0.25))
		"to_station":
			_live_button(v, "SCAN PACKAGES", func(): Gigs.scan_packages(), func(): return Gigs.can_scan(), Color(0.1, 0.5, 0.25))
			_lbl(v, "Drive into the station's loading zone. Scanning opens 30 min before the block.", 12, Color(0.7, 0.7, 0.75))
		"delivering":
			for s in j.stops:
				_lbl(v, "📦 " + s.name, 13)
	if j.kind == "grocery":
		var list := _card(Color(0.1, 0.18, 0.12))
		_lbl(list, "Shopping list for %s:" % j.customer_name, 14, Color(1, 0.85, 0.4))
		for item in j.items:
			var done: bool = item in j.picked
			_lbl(list, ("✔ " if done else "☐ ") + item, 15, Color(0.5, 1, 0.5) if done else Color.WHITE)
	_btn(v, "Cancel job (hurts rating)", func(): Gigs.cancel_job(), Color(0.3, 0.15, 0.15))


func _bank() -> void:
	_header("First Statewide Bank", Color(0.15, 0.4, 0.2), "Totally not a payday lender.")
	var v := _card()
	_live_label(v, func(n): n.text = "Balance: $%.2f" % Game.money, 22, Color(0.5, 1, 0.6))
	_lbl(v, "Earned so far: $%.2f   Jobs: %d" % [Game.stats.earned, Game.stats.jobs], 13, Color(0.8, 0.8, 0.85))
	var bills := _card()
	_lbl(bills, "Bills (due every %d days, auto-pay at 9 AM)" % GameData.BILL_CYCLE_DAYS, 15, Color(1, 0.85, 0.5))
	var unpaid := Game.unpaid_bills()
	if unpaid.is_empty():
		_lbl(bills, "All paid up!", 14, Color(0.5, 1, 0.6))
	for b in unpaid:
		var days: int = b.due_day - Game.day
		var when := "OVERDUE" if b.overdue else ("due today" if days <= 0 else "due Day %d" % b.due_day)
		var row := HBoxContainer.new()
		bills.add_child(row)
		var l := _lbl(row, "%s\n$%.2f  •  %s" % [b.name, b.amount, when], 13, Color(1, 0.5, 0.4) if b.overdue else Color.WHITE)
		l.custom_minimum_size.x = 220
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bid: int = b.id
		_btn(row, "Pay", func(): Game.pay_bill(bid), Color(0.15, 0.45, 0.25))
	var tx := _card()
	_lbl(tx, "Recent activity", 15, Color(0.8, 0.8, 0.85))
	for t in Game.transactions.slice(0, 10):
		_lbl(tx, "%s  %s$%.2f  %s" % [t.time, "+" if t.amount >= 0 else "-", absf(t.amount), t.memo], 12,
			Color(0.5, 1, 0.6) if t.amount >= 0 else Color(1, 0.7, 0.6))


func _garage() -> void:
	var c := Game.car()
	_header("Garage", Color(0.35, 0.35, 0.4), c.name)
	var v := _card()
	_live_label(v, func(n):
		n.text = "Odometer: %s mi\nFuel: %.1f / %.0f gal\nOil life: %d%%\nTire tread: %d%%\nEngine health: %d%%\nMPG: %d   Comfort: %d%%" % [
			int(Game.odometer), Game.fuel, Game.car().tank, Game.oil_life, Game.tire_tread, Game.engine_health,
			Game.car().mpg, Game.car().comfort * 100], 15)
	_lbl(v, "Oil changes and tires at Lube & Tube (south side). Gas at WahWah.", 12, Color(0.75, 0.75, 0.8))
	var tow := _card()
	_lbl(tow, "Stuck or out of gas? Tow to Lube & Tube for $%.0f (adds 1 gallon)." % GameData.TOW_PRICE, 13)
	_btn(tow, "Call a tow truck", func(): main.call_tow(), Color(0.5, 0.35, 0.1))


func _maps() -> void:
	_header("Maps", Color(0.2, 0.45, 0.75), "Tap a place to set a GPS beacon.")
	if not main.map_waypoint.is_empty():
		_btn(_screen, "Clear route (%s)" % main.map_waypoint.label, func():
			main.map_waypoint = {}
			_rebuild(), Color(0.4, 0.2, 0.2))
	if Game.home_id != "" and main.town.homes.has(Game.home_id):
		var hd: Dictionary = main.town.homes[Game.home_id]
		_btn(_screen, "🏠 Home", func(): main.set_waypoint(hd.door, "Home"), Color(0.35, 0.25, 0.45))
	for p in main.town.places:
		var place: Dictionary = p
		_btn(_screen, place.name, func(): main.set_waypoint(place.pos, place.name))


func _me() -> void:
	_header("Me", Color(0.55, 0.35, 0.65), "Self-care is a side hustle too.")
	var v := _card()
	_live_label(v, func(n):
		n.text = "Hunger: %d%%   Bladder: %d%%   Energy: %d%%" % [Game.hunger, Game.bladder, Game.energy], 15)
	var home := Game.home()
	_lbl(v, "Home: %s" % (home.name if not home.is_empty() else "None (sleeping in your car)"), 14)
	_lbl(v, "Car: %s" % Game.car().name, 14)
	var naps := _card()
	_lbl(naps, "Sleep in your car (poor quality). Must be parked.", 13, Color(0.8, 0.8, 0.85))
	_live_button(naps, "Nap in car (2 hours)", func(): main.sleep_in_car(2.0), func(): return main.is_driving() and main.car_speed() < 1.0, Color(0.3, 0.25, 0.45))
	_live_button(naps, "Sleep in car until 6 AM", func(): main.sleep_in_car(Game.hours_until(6)), func(): return main.is_driving() and main.car_speed() < 1.0, Color(0.3, 0.25, 0.45))
	var up := _card(Color(0.16, 0.14, 0.2))
	if Game.phone_pro:
		_lbl(up, "📱 %s" % GameData.PHONE_PRO_NAME, 16, Color(0.8, 0.9, 1))
		_lbl(up, "Police near you show on your map as blue COP badges (red when they're after you). Battery lasts 40% longer.", 12, Color(0.75, 0.75, 0.8))
	else:
		_lbl(up, "Upgrade: %s" % GameData.PHONE_PRO_NAME, 16, Color(0.8, 0.9, 1))
		_lbl(up, "Comes with Wayz Pro: police near you show up on your map. Bigger battery too.", 12, Color(0.75, 0.75, 0.8))
		_live_button(up, "Buy for $%.0f" % GameData.PHONE_PRO_PRICE, func():
			if Game.buy_phone_upgrade():
				_rebuild(), func(): return Game.money >= GameData.PHONE_PRO_PRICE, Color(0.25, 0.35, 0.6))
	var sv := _card()
	_btn(sv, "Save game (F5)", func(): Game.save_game())
	_btn(sv, "Load game (F9)", func(): main.load_game())
