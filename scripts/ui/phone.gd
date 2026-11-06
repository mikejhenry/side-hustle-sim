class_name Phone
extends CanvasLayer
## The in-game smartphone. Gig apps, Bank (bills), Garage (car), Maps (GPS), Hail Yeah
## (taxi and bus), Wayfare (home goods), and Me (needs, saving).

var main: Node = null
var is_open := false
var current_app := ""

var _body: PanelContainer
var _screen: VBoxContainer
var _status: Label
var _live: Array = []         # [{node, fn}] refreshed 4x per second
var _dirty := false
var _tick := 0.0
var _heat_ahead := 0          # hot zone map preview: hours from now

const ICONS := {
	"yoober": "Y", "drift": "D", "doordish": "DD", "instacrate": "IC", "jungleflex": "JF",
	"bank": "$", "garage": "G", "maps": "M", "cab": "HY", "me": "Me", "wayfare": "W",
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
	Game.furniture_changed.connect(_mark_dirty)


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
	if id != current_app:
		_heat_ahead = 0
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
		"cab": _cab()
		"me": _me()
		"wayfare": _wayfare()
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
	apps.append(["cab", "Hail Yeah", Color(0.75, 0.6, 0.1)])
	apps.append(["me", "Me", Color(0.55, 0.35, 0.65)])
	apps.append(["wayfare", "Wayfare", WAYFARE_COLOR])
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
	if not Gigs.jobs.is_empty():
		_jobs_summary()


## Every job you're juggling, with buttons to point the GPS at one or open its app.
func _jobs_summary() -> void:
	var v := _card(Color(0.15, 0.2, 0.15))
	if Gigs.jobs.size() > 1:
		_lbl(v, "Juggling %d/%d jobs" % [Gigs.jobs.size(), GameData.MAX_JOBS], 15, Color(1, 0.85, 0.4))
	for j in Gigs.jobs:
		var jj: Dictionary = j
		var focused := is_same(jj, Gigs.job)
		_live_label(v, func(n):
			n.text = ("➤ " if is_same(jj, Gigs.job) else "") + Gigs.status_for(jj) + _due_text(jj), 14,
			Color.WHITE if focused else Color(0.8, 0.8, 0.85))
		if Gigs.jobs.size() > 1:
			var row := HBoxContainer.new()
			v.add_child(row)
			var id: String = jj.app
			if not focused:
				_btn(row, "Follow on GPS", func(): Gigs.focus(id), Color(0.2, 0.35, 0.6))
			_btn(row, "Open " + GameData.APPS[id].name, func(): open_app(id), GameData.APPS[id].color)


func _due_text(j: Dictionary) -> String:
	if j.kind == "flex":
		return ""
	var left := Gigs.minutes_left(j)
	return ("  (due in %d min)" % left) if left >= 0 else ("  (LATE %d min)" % -left)


func _gig_app(id: String) -> void:
	var a: Dictionary = GameData.APPS[id]
	_header(a.name, a.color, a.tagline)
	var top := _card()
	_live_label(top, func(n): n.text = "Rating: %.2f ★     %s" % [Gigs.ratings[id], Gigs.demand_label(id)], 15)
	_week_heatmap(top, id)
	var reason := Gigs.ineligible_reason(id)
	if reason != "":
		_lbl(top, reason, 14, Color(1, 0.5, 0.4))
	var on: bool = Gigs.online[id]
	_btn(top, "GO OFFLINE" if on else "GO ONLINE", func():
		Gigs.set_online(id, not on)
		_rebuild(), Color(0.6, 0.15, 0.15) if on else Color(0.1, 0.55, 0.25))

	var mine := Gigs.job_for_app(id)
	if not mine.is_empty():
		_job_card(id)
	var others: Array = Gigs.jobs.filter(func(j): return j.app != id)
	if not others.is_empty():
		var names := ", ".join(others.map(func(j): return GameData.APPS[j.app].name))
		_lbl(_screen, "Also running: %s (%d/%d jobs)" % [names, Gigs.jobs.size(), GameData.MAX_JOBS], 14, Color(1, 0.85, 0.4))

	for o in Gigs.offers:
		if o.app != id:
			continue
		_offer_card(o, a)
	if on and mine.is_empty() and not Gigs.offers.any(func(o): return o.app == id):
		var wait := "Looking for offers..." if a.kind != "flex" else "Blocks appear about 2.5 hours before they start (6AM, 10AM, 2PM, 6PM)."
		if a.kind != "flex" and Gigs.jobs.size() >= GameData.MAX_JOBS:
			wait = "No new offers while you're juggling %d jobs." % Gigs.jobs.size()
		elif a.kind == "ride" and not Gigs.job_for("ride").is_empty():
			wait = "No ride offers while you have another passenger."
		_lbl(_screen, wait, 14, Color(0.7, 0.7, 0.75))
	if a.kind != "flex":
		_hot_zones(id)


## Peak times for the week: one row per day, one square per hour, hotter colors are busier.
func _week_heatmap(parent: Node, id: String) -> void:
	_lbl(parent, "Peak times this week (midnight to midnight):", 12, Color(0.75, 0.75, 0.8))
	var grid := GridContainer.new()
	grid.columns = 25
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	parent.add_child(grid)
	var cells := []
	for wd in 7:
		var day := Label.new()
		day.text = GameData.DAY_NAMES[wd]
		day.custom_minimum_size = Vector2(30, 11)
		day.add_theme_font_size_override("font_size", 10)
		day.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		grid.add_child(day)
		for h in 24:
			var cell := ColorRect.new()
			cell.custom_minimum_size = Vector2(11, 11)
			var s := Gigs.surge(id, h, wd)
			if Gigs.app(id).kind == "ride" and Game.is_late_night(h):
				s *= GameData.LATE_NIGHT_SURGE    # bars-closing surge
			cell.set_meta("base", WorldMap.heat_color((s - 0.9) / 1.1))
			cell.set_meta("at", Vector2i(wd, h))
			cell.color = cell.get_meta("base")
			grid.add_child(cell)
			cells.append(cell)
	var axis := _lbl(parent, "        12a              6a              12p              6p", 10, Color(0.6, 0.6, 0.65))
	axis.autowrap_mode = TextServer.AUTOWRAP_OFF
	# The square for right now blinks white.
	var fn := func(_n):
		var now := Vector2i((Game.day - 1) % 7, Game.hour())
		var blink := int(Time.get_ticks_msec() / 500) % 2 == 0
		for c in cells:
			if is_instance_valid(c):
				c.color = Color.WHITE if (c.get_meta("at") == now and blink) else c.get_meta("base")
	fn.call(grid)
	_live.append({"node": grid, "fn": fn})
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 12)
	parent.add_child(legend)
	for k in [["quiet", 0.0], ["busy", 0.45], ["very busy", 0.9]]:
		var l := Label.new()
		l.text = "■ " + k[0]
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", WorldMap.heat_color(k[1]).lightened(0.15))
		legend.add_child(l)


## Map of where this app's orders come from, with an hour-ahead preview.
func _hot_zones(id: String) -> void:
	var v := _card()
	var h := Game.hour() + _heat_ahead
	_lbl(v, "Hot zones %s" % ("right now" if _heat_ahead == 0 else "at " + Game.time_string(fmod(h * 60.0, 1440.0))), 15, Color(1, 0.75, 0.4))
	var m := WorldMap.new()
	m.main = main
	m.show_street_names = false
	m.heat_app = id
	m.heat_hour = h
	m.custom_minimum_size = Vector2(0, 220)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.place_picked.connect(func(p): _pick_place(p))
	v.add_child(m)
	var best := Gigs.hottest(id, h)
	if not best.is_empty():
		var r: Rect2 = Gigs.cell_rect(best.cell)
		var center := Vector3(r.get_center().x, 0, r.get_center().y)
		var here: Vector3 = main.actor_position()
		_lbl(v, "Hottest: %s (%.1f mi away). Hot zones pay up to +%d%% and send more offers." % [
			best.label, Gigs._miles(here, center), roundi((Gigs.zone_mult(1.0) - 1.0) * 100.0)], 12, Color(0.85, 0.85, 0.9))
	var ev := Gigs.hot_event(id, Game.day + floori(h / 24.0))
	if not ev.is_empty():
		_lbl(v, "Today: %s, %s to %s." % [ev.label, Game.time_string(ev.start * 60.0), Game.time_string(fmod(ev.end * 60.0, 1440.0))], 12, Color(1, 0.6, 0.5))
	var row := HBoxContainer.new()
	v.add_child(row)
	for ahead in [0, 1, 2, 3]:
		var a: int = ahead
		var b := _btn(row, "Now" if a == 0 else "+%dh" % a, func():
			_heat_ahead = a
			_rebuild(), Color(0.45, 0.3, 0.15) if a == _heat_ahead else Color(0.2, 0.2, 0.24))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _offer_card(o: Dictionary, _a: Dictionary) -> void:
	var v := _card(Color(0.12, 0.18, 0.14))
	_lbl(v, "$%.2f" % o.pay, 30, Color(0.5, 1, 0.6))
	match o.kind:
		"ride":
			_lbl(v, "%s • %.1f mi trip • pickup %.1f mi away%s" % [o.passenger, o.miles, o.pickup_miles,
				" • %s surge +$%.2f" % [Game.weather_text(), o.weather_pay] if o.get("weather_pay", 0.0) > 0.0 else ""], 14)
			_lbl(v, "From: %s\nTo: %s" % [o.pickup.name, o.dropoff.name], 13, Color(0.85, 0.85, 0.9))
			if o.get("night_pay", 0.0) > 0.0:
				_lbl(v, "Late-night surge +$%.2f%s" % [o.night_pay, " • Rider may be rowdy" if o.get("rowdy", false) else ""], 13, Color(0.75, 0.6, 1.0))
		"food":
			_lbl(v, "%.1f mi total • incl. $%.0f tip%s%s" % [o.miles, o.tip, " • Peak Pay +$%.2f" % o.peak_pay if o.peak_pay > 0 else "",
				" • %s boost +$%.2f" % [Game.weather_text(), o.weather_pay] if o.get("weather_pay", 0.0) > 0.0 else ""], 14)
			_lbl(v, "Pickup: %s\nDeliver: %s" % [o.restaurant.name, o.customer.name], 13, Color(0.85, 0.85, 0.9))
		"grocery":
			_lbl(v, "%d items • %.1f mi • incl. $%.0f tip%s" % [o.items.size(), o.miles, o.tip,
				" • %s boost +$%.2f" % [Game.weather_text(), o.weather_pay] if o.get("weather_pay", 0.0) > 0.0 else ""], 14)
			_lbl(v, "Shop: %s\nDeliver: %s" % [o.store.name, o.customer.name], 13, Color(0.85, 0.85, 0.9))
		"flex":
			_lbl(v, "Block %s - %s • %d packages" % [Game.abs_time_string(o.start), Game.time_string(fmod(o.end, 1440.0)), o.packages], 14)
			_lbl(v, "Station: Jungle Flex DNC9 (east side, near the port)", 13, Color(0.85, 0.85, 0.9))
	if o.get("zone_pay", 0.0) > 0.0:
		_lbl(v, "🔥 Hot zone +$%.2f" % o.zone_pay, 13, Color(1, 0.6, 0.3))
	if o.kind != "flex":
		_lbl(v, "Due by %s" % Game.abs_time_string(o.deadline), 12, Color(0.8, 0.8, 0.85))
	_live_label(v, func(n): n.text = "Expires in %d min" % maxi(0, int(o.expires - Game.total_minutes())), 12, Color(1, 0.8, 0.4))
	var block := Gigs.accept_block_reason(o)
	if block != "":
		_lbl(v, block, 12, Color(1, 0.6, 0.45))
	elif not Gigs.jobs.is_empty():
		_lbl(v, "⚠ Stacking with %d other job(s). Late deliveries cost a late fee and stars." % Gigs.jobs.size(), 12, Color(1, 0.8, 0.4))
	var row := HBoxContainer.new()
	v.add_child(row)
	var acc := _btn(row, "  ACCEPT  ", func(): Gigs.accept(o.id), Color(0.1, 0.55, 0.25))
	acc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acc.disabled = block != ""
	_btn(row, "Decline", func(): Gigs.decline(o.id), Color(0.35, 0.2, 0.2))


func _job_card(id: String) -> void:
	var j := Gigs.job_for_app(id)
	var v := _card(Color(0.12, 0.15, 0.22))
	_lbl(v, "ACTIVE JOB  •  $%.2f" % j.pay, 18, Color(0.6, 0.85, 1))
	_live_label(v, func(n): n.text = Gigs.status_for(j), 14)
	if j.kind != "flex":
		_live_label(v, func(n):
			var left := Gigs.minutes_left(j)
			if left >= 0:
				n.text = "Due in %d min" % left
			else:
				n.text = "LATE by %d min  •  late fee so far -$%.2f" % [-left, Gigs.late_fee(j, j.pay)], 13, Color(1, 0.8, 0.4))
	if not is_same(j, Gigs.job):
		_btn(v, "Follow this job on GPS", func(): Gigs.focus(id), Color(0.2, 0.35, 0.6))
	match j.stage:
		"to_pickup":
			_live_button(v, "ARRIVED: START TRIP", func(): Gigs.start_trip(), func(): return Gigs.can_start_trip(), Color(0.1, 0.5, 0.25))
			_lbl(v, "Stop at the pickup beacon in your car to start.", 12, Color(0.7, 0.7, 0.75))
		"to_dropoff":
			_live_button(v, "COMPLETE TRIP", func(): Gigs.end_trip(), func(): return Gigs.can_end_trip(), Color(0.1, 0.5, 0.25))
			_lbl(v, "Passenger: %s. Drive smoothly, crashes cost stars." % j.passenger, 12, Color(0.7, 0.7, 0.75))
		"confirm_photo":
			_live_button(v, "TAKE DROP-OFF PHOTO  📷", func(): Gigs.confirm_photo(id), func(): return Gigs.can_take_photo(id), Color(0.1, 0.5, 0.25))
			_lbl(v, "Stand by the door to take the photo.", 12, Color(0.7, 0.7, 0.75))
		"to_station":
			_live_button(v, "SCAN PACKAGES", func(): Gigs.scan_packages(), func(): return Gigs.can_scan(), Color(0.1, 0.5, 0.25))
			_lbl(v, "Drive into the station's loading zone. Scanning opens 30 min before the block.", 12, Color(0.7, 0.7, 0.75))
		"delivering":
			if not j.get("photo_due", {}).is_empty():
				_live_button(v, "TAKE DROP-OFF PHOTO  📷", func(): Gigs.confirm_package_photo(), func(): return Gigs.can_take_photo(id), Color(0.1, 0.5, 0.25))
				_lbl(v, "Package left at %s. Stand by the door to take the photo." % j.photo_due.name, 12, Color(0.7, 0.7, 0.75))
			for s in j.stops:
				_lbl(v, "📦 " + s.name, 13)
	if j.kind == "grocery":
		var list := _card(Color(0.1, 0.18, 0.12))
		_lbl(list, "Shopping list for %s:" % j.customer_name, 14, Color(1, 0.85, 0.4))
		for item in j.items:
			var done: bool = item in j.picked
			_lbl(list, ("✔ " if done else "☐ ") + item, 15, Color(0.5, 1, 0.5) if done else Color.WHITE)
	_btn(v, "Cancel job (hurts rating)", func(): Gigs.cancel_job(id), Color(0.3, 0.15, 0.15))


func _bank() -> void:
	_header("First Statewide Bank", Color(0.15, 0.4, 0.2), "Totally not a payday lender.")
	var v := _card()
	_live_label(v, func(n): n.text = "Balance: $%.2f" % Game.money, 22, Color(0.5, 1, 0.6))
	_lbl(v, "Earned so far: $%.2f   Jobs: %d" % [Game.stats.earned, Game.stats.jobs], 13, Color(0.8, 0.8, 0.85))
	var bills := _card()
	_lbl(bills, "Bills (due monthly, auto-pay at 9 AM)", 15, Color(1, 0.85, 0.5))
	if not Game.loan.is_empty():
		_lbl(bills, "Car loan: $%.2f a month, %d more payments (%s)" % [Game.loan.payment, int(Game.loan.left), Game.loan.lender], 13, Color(1, 0.75, 0.5))
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
	_header("Maps", Color(0.2, 0.45, 0.75), "Tap an icon or a place to set your GPS. Full map: %s." % Game.key("map"))
	var m := WorldMap.new()
	m.main = main
	m.show_street_names = false
	m.custom_minimum_size = Vector2(0, 280)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.place_picked.connect(func(p): _pick_place(p))
	m.point_picked.connect(func(at):
		main.drop_pin(at)
		_rebuild())
	m.clear_requested.connect(func():
		main.map_waypoint = {}
		main.refresh_gps()
		_rebuild())
	_screen.add_child(m)
	var key := _card()
	WorldMap.legend(key, 2, 11)
	if not main.map_waypoint.is_empty():
		_btn(_screen, "Clear route (%s)" % main.map_waypoint.label, func():
			main.map_waypoint = {}
			main.refresh_gps()
			_rebuild(), Color(0.4, 0.2, 0.2))
	var here: Vector3 = main.actor_position()
	for kind in WorldMap.KINDS:
		var group: Array = m.places().filter(func(p): return p.get("kind", "") == kind)
		if group.is_empty():
			continue
		group.sort_custom(func(a, b): return here.distance_to(a.pos) < here.distance_to(b.pos))
		var k: Array = WorldMap.KINDS[kind]
		_lbl(_screen, "%s  %s" % [k[1], k[0]], 14, k[2])
		for p in group:
			var place: Dictionary = p
			var b := _btn(_screen, "%s   %.1f mi" % [place.name, here.distance_to(place.pos) / GameData.METERS_PER_MILE], func(): _pick_place(place))
			b.add_theme_font_size_override("font_size", 13)


func _pick_place(place: Dictionary) -> void:
	main.set_waypoint(place.pos, place.name)
	main.map_waypoint["drop"] = main.transit.drop_point(place)
	_rebuild()


## Hail Yeah: call a cab to anywhere on the map, or check the bus.
func _cab() -> void:
	var tr: Transit = main.transit
	_header(GameData.TAXI_NAME, Color(0.75, 0.6, 0.1), "Hail yeah, we'll take you there. $%.2f + $%.2f/mi (more from 11 PM to 5 AM). Your car stays put." % [GameData.TAXI_BASE, GameData.TAXI_PER_MILE])
	var why := tr.blocked_reason()
	if why != "":
		var c := _card(Color(0.3, 0.15, 0.1))
		_lbl(c, why, 15, Color(1, 0.85, 0.6))
	var here: Vector3 = main.actor_position()
	var targets: Array = []
	if not main.map_waypoint.is_empty():
		var wp: Dictionary = main.map_waypoint
		targets.append({"name": "GPS: " + wp.label, "drop": wp.get("drop", wp.pos)})
	var m := WorldMap.new()
	m.main = main
	var ps: Array = m.places()
	m.free()
	for kind in ["car", "home"]:
		for p in ps.filter(func(p): return p.get("kind", "") == kind):
			targets.append({"name": p.name, "drop": tr.drop_point(p)})
	var rest: Array = ps.filter(func(p): return not p.get("kind", "") in ["car", "home", "bus", "restroom"])
	rest.sort_custom(func(a, b): return here.distance_to(a.pos) < here.distance_to(b.pos))
	for p in rest:
		targets.append({"name": p.name, "drop": tr.drop_point(p)})
	_lbl(_screen, "Where to?", 16)
	for t in targets:
		var dest: Dictionary = t
		var q := tr.taxi_quote(dest.drop)
		if q.miles < 0.25:
			continue
		var b := _live_button(_screen, "%s\n$%.2f  ·  %d min" % [dest.name, q.fare, q.minutes],
			func(): tr.ride_taxi(dest.drop, dest.name),
			func(): return why == "" and Game.money >= q.fare, Color(0.22, 0.2, 0.14))
		b.add_theme_font_size_override("font_size", 13)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bus := _card(Color(0.25, 0.12, 0.2))
	_lbl(bus, "Bus: %s" % GameData.BUS_NAME, 16, Color(1, 0.8, 0.9))
	var stop := tr.nearest_stop(here)
	var wait := tr.bus_wait()
	_lbl(bus, "$%.2f a ride between bus stops (B on the map). Every %d min, %d AM to midnight." % [GameData.BUS_FARE, GameData.BUS_EVERY, GameData.BUS_FIRST_HOUR], 12, Color(0.85, 0.8, 0.85))
	if wait < 0.0:
		_lbl(bus, "No buses running right now.", 13, Color(1, 0.7, 0.6))
	if not stop.is_empty():
		var near: Dictionary = stop
		var mi := here.distance_to(near.pos) / GameData.METERS_PER_MILE
		var sb: Button
		if tr.at_stop() == near:
			sb = _btn(bus, "Ride from %s" % near.short, func():
				close()
				tr.bus_menu(near), Color(0.45, 0.2, 0.35))
		else:
			sb = _btn(bus, "GPS to the nearest stop: %s (%.1f mi)" % [near.short, mi], func():
				main.set_waypoint(near.pos, near.name)
				_rebuild(), Color(0.45, 0.2, 0.35))
		sb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _me() -> void:
	_header("Me", Color(0.55, 0.35, 0.65), "Self-care is a side hustle too.")
	var v := _card()
	_live_label(v, func(n):
		n.text = "Hunger: %d%%   Bladder: %d%%   Energy: %d%%" % [Game.hunger, Game.bladder, Game.energy], 15)
	var home := Game.home()
	_lbl(v, "Home: %s" % ("%s (%s)" % [home.name, home.area] if not home.is_empty() else "None (sleeping in your car)"), 14)
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
	_btn(sv, "Save game (%s)" % Game.slot_name(Game.current_slot), func():
		Game.save_game()
		_rebuild())
	_btn(sv, "Load latest save", func(): main.load_game(Game.latest_slot()))
	_lbl(sv, "More slots in the pause menu (%s)." % Game.key("pause"), 12, Color(0.75, 0.75, 0.8))


# --- Wayfare: home goods ---------------------------------------------------------------

const WAYFARE_COLOR := Color(0.45, 0.22, 0.55)


func _wayfare() -> void:
	_header("Wayfare", WAYFARE_COLOR, "Furniture that arrives in one more box than you expected.")
	var home := Game.home()
	var v := _card(Color(0.17, 0.13, 0.2))
	if home.is_empty():
		_lbl(v, "No address on file. Sign a lease to get deliveries.", 14, Color(1, 0.75, 0.6))
	else:
		_lbl(v, "%s  ·  %s" % [home.short, home.area], 15)
		_live_label(v, func(n):
			n.text = "Best bed: %d%% sleep quality\n%s: %d meals per grocery run ($%.2f a meal)\nComfort: %d (+%d%% sleep)     Space: %d / %d pieces" % [
				roundi(Game.best_bed_quality() * 100.0), GameData.KITCHEN_NAMES[Game.kitchen_tier()], Game.grocery_meals(),
				GameData.HOME_GROCERIES_PRICE / Game.grocery_meals(), Game.comfort(), roundi(Game.comfort_bonus() * 100.0),
				Game.placed_furniture().size(), Game.home_space()], 13, Color(0.85, 0.82, 0.9))
	# What you own and where it is.
	var boxed := Game.boxed_furniture()
	var placed := Game.placed_furniture()
	if not boxed.is_empty() or not placed.is_empty():
		var mine := _card()
		_lbl(mine, "Your stuff", 16)
		for f in boxed:
			var uid := int(f.uid)
			var row := HBoxContainer.new()
			mine.add_child(row)
			var l := _lbl(row, "📦 " + GameData.FURNITURE[f.id].name, 13)
			l.custom_minimum_size.x = 170
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_live_button(row, "Place", func(): main.decor.begin(uid), func(): return main.decor.is_inside_home(), WAYFARE_COLOR)
		if not boxed.is_empty():
			_lbl(mine, "Boxes wait by your front door. Go inside to place them.", 12, Color(0.75, 0.75, 0.8))
		for f in placed:
			_lbl(mine, "✓ " + GameData.FURNITURE[f.id].name, 13, Color(0.7, 0.9, 0.7))
		if not placed.is_empty():
			_lbl(mine, "Walk up to a piece at home to move, box or sell it.", 12, Color(0.75, 0.75, 0.8))
	# Catalog
	var sections := [["bed", "Beds"], ["kitchen", "Kitchen"], ["coffee", "Kitchen"], ["decor", "Decor"]]
	var last_title := ""
	var card: VBoxContainer = null
	for sec in sections:
		if sec[1] != last_title:
			last_title = sec[1]
			card = _card()
			_lbl(card, last_title, 16)
		for id in GameData.FURNITURE_ORDER:
			var info: Dictionary = GameData.FURNITURE[id]
			if info.kind != sec[0]:
				continue
			_lbl(card, "%s  $%.0f" % [info.name, info.price], 14, Color(1, 0.92, 0.75))
			_lbl(card, "%s  %s" % [_furniture_effect(id), info.blurb], 12, Color(0.78, 0.78, 0.82))
			var item_id: String = id
			_live_button(card, "Buy", func(): Game.buy_furniture(item_id),
				func(): return Game.home_id != "" and Game.money >= float(GameData.FURNITURE[item_id].price), WAYFARE_COLOR)


func _furniture_effect(id: String) -> String:
	var info: Dictionary = GameData.FURNITURE[id]
	match info.kind:
		"bed":
			return "Sleep x%.2f." % info.sleep
		"kitchen":
			return "%s: +%d meals per grocery run, bigger meals." % [GameData.KITCHEN_NAMES[info.kitchen], GameData.KITCHEN_EXTRA_MEALS[info.kitchen]]
		"coffee":
			return "+18 energy per cup."
	return "+%d comfort." % info.comfort
