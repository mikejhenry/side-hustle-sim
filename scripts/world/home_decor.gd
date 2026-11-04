class_name HomeDecor
extends Node3D
## Furniture you own, shown in the home you live in, and the mode for placing it.
## Placing: a see-through copy follows a spot in front of you (green = fits, red = blocked).
## [E] puts it down, [R] turns it, [Esc] cancels. Positions are saved in the home's own
## coordinates (see Game.furniture).

var main: Node = null
var town: Node = null

var placing := false
var _uid := -1
var _id := ""
var _rot := 0
var _valid := false
var _blocked_reason := ""
var _local := Vector3.ZERO
var _ghost: Node3D = null
var _ghost_mat: StandardMaterial3D


func _ready() -> void:
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45)
	Game.furniture_changed.connect(rebuild)
	Game.home_changed.connect(rebuild)
	rebuild()


# --- Showing what you own ----------------------------------------------------------

func rebuild() -> void:
	if town == null:
		return
	for hid in town.homes:
		var root: Node3D = town.homes[hid].furniture_root
		for c in root.get_children():
			root.remove_child(c)
			c.queue_free()
	if Game.home_id == "" or not town.homes.has(Game.home_id):
		return
	var home: Dictionary = town.homes[Game.home_id]
	for f in Game.placed_furniture():
		if placing and int(f.uid) == _uid:
			continue   # the one you're moving is shown as the see-through copy instead
		_spawn_piece(home.furniture_root, f)
	_spawn_boxes(home)


func _spawn_piece(root: Node3D, f: Dictionary) -> void:
	var info: Dictionary = GameData.FURNITURE[f.id]
	var piece := Node3D.new()
	piece.position = Vector3(f.x, 0, f.z)
	piece.rotation.y = int(f.rot) * PI / 2.0
	root.add_child(piece)
	build_model(piece, f.id)
	var size: Vector3 = info.size
	if size.y > 0.1:
		Kit.collider(piece, Vector3(size.x, size.y, size.z), Vector3(0, size.y / 2.0, 0))
	var uid := int(f.uid)
	Kit.interactable(piece, Vector3(0, 1, 0), maxf(size.x, size.z) / 2.0 + 1.3,
		func(): return _piece_prompt(uid),
		func(): _piece_menu(uid))


func _spawn_boxes(home: Dictionary) -> void:
	var boxed := Game.boxed_furniture()
	if boxed.is_empty():
		return
	var root: Node3D = home.furniture_root
	var spot: Vector3 = home.box_spot
	for i in mini(boxed.size(), 3):
		var p := spot + Vector3(0.15 * (i % 2), i * 0.42, 0.1 * i)
		if ResourceLoader.exists("res://assets/models/cardboard_box_01/cardboard_box_01.gltf"):
			Kit.prop(root, "cardboard_box_01", p, 0.3 * i, "", 1.0, "", 35.0)
		else:
			Kit.box(root, Vector3(0.6, 0.42, 0.5), p + Vector3(0, 0.21, 0), Color(0.72, 0.56, 0.38), false)
	Kit.label(root, "WAYFARE", spot + Vector3(0, 0.55 + 0.42 * mini(boxed.size(), 3), 0), 28, Color(0.85, 0.65, 1.0), true)
	Kit.interactable(root, spot + Vector3(0, 1, 0), 1.8,
		func():
			var b := Game.boxed_furniture()
			if b.is_empty():
				return ""
			var more: String = "  (+%d more)" % (b.size() - 1) if b.size() > 1 else ""
			return "Unbox and place: %s%s" % [GameData.FURNITURE[b[0].id].name, more],
		func(): _boxes_menu())


func _boxes_menu() -> void:
	var opts := []
	for f in Game.boxed_furniture():
		var uid := int(f.uid)
		var info: Dictionary = GameData.FURNITURE[f.id]
		opts.append({"text": "Place: " + info.name, "cb": func(): begin(uid)})
		opts.append({"text": "   Sell it for $%.0f" % Game.furniture_resale(f.id), "cb": func(): Game.sell_furniture(uid)})
	main.hud.show_menu("Wayfare boxes. Space used: %d / %d pieces" % [Game.placed_furniture().size(), Game.home_space()], opts)


func _piece_prompt(uid: int) -> String:
	if placing:
		return ""
	var f := Game.furniture_item(uid)
	if f.is_empty():
		return ""
	var info: Dictionary = GameData.FURNITURE[f.id]
	match info.kind:
		"bed":
			return "Sleep in the %s (quality %d%%)" % [info.name, roundi(Game.bed_quality(f.id) * 100.0)]
		"kitchen":
			if Game.fridge_meals <= 0:
				return "%s: fridge is empty (buy groceries)" % info.name
			return "Cook: %s (%d meals left)" % [GameData.KITCHEN_MEALS[Game.kitchen_tier()][0], Game.fridge_meals]
		"coffee":
			return "Brew coffee ($%.2f)" % GameData.HOME_COFFEE_PRICE
	return "Rearrange: " + info.name


func _piece_menu(uid: int) -> void:
	var f := Game.furniture_item(uid)
	if f.is_empty():
		return
	var info: Dictionary = GameData.FURNITURE[f.id]
	var arrange := [
		{"text": "Move it", "cb": func(): begin(uid)},
		{"text": "Box it up", "cb": func(): Game.box_up_furniture(uid)},
		{"text": "Sell it for $%.0f" % Game.furniture_resale(f.id), "cb": func(): Game.sell_furniture(uid)},
	]
	match info.kind:
		"bed":
			main.sleep_menu(Game.bed_quality(f.id), arrange, info.name)
			return
		"kitchen":
			arrange.push_front({"text": "Cook and eat (%d meals left)" % Game.fridge_meals,
				"cb": func(): Game.eat_at_home(), "disabled": Game.fridge_meals <= 0})
		"coffee":
			arrange.push_front({"text": "Brew a cup ($%.2f, +18 energy)" % GameData.HOME_COFFEE_PRICE,
				"cb": func(): Game.brew_coffee(), "disabled": Game.money < GameData.HOME_COFFEE_PRICE})
	var title: String = info.name
	if info.kind == "decor":
		title += "  (+%d comfort)" % int(info.comfort)
	main.hud.show_menu(title, arrange)


# --- Placing -------------------------------------------------------------------------

## Starts placing a piece you own (boxed up, or already placed here to move it).
func begin(uid: int) -> bool:
	var f := Game.furniture_item(uid)
	if f.is_empty():
		return false
	if Game.home_id == "" or not town.homes.has(Game.home_id):
		main.hud.toast("You need a home to put furniture in.", "warn")
		return false
	if main.is_driving() or not is_inside_home():
		main.hud.toast("Go inside your home to place furniture.", "warn")
		return false
	if f.home != Game.home_id and Game.placed_furniture().size() >= Game.home_space():
		main.hud.toast("No room left here (%d pieces max). Box something up or move somewhere bigger." % Game.home_space(), "warn")
		return false
	if placing:
		cancel()
	if main.phone.is_open:
		main.phone.close()
	placing = true
	_uid = uid
	_id = f.id
	_rot = int(f.rot) if f.home == Game.home_id else 0
	var home: Dictionary = town.homes[Game.home_id]
	_ghost = Node3D.new()
	home.building.add_child(_ghost)
	build_model(_ghost, _id, false)
	for n in _ghost.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		gi.material_override = _ghost_mat
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rebuild()
	_update_ghost()
	return true


func cancel() -> void:
	if not placing:
		return
	placing = false
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	rebuild()


func _confirm() -> void:
	if not _valid:
		main.hud.toast("It doesn't fit there: %s." % _blocked_reason, "warn")
		return
	var uid := _uid
	var x := _local.x
	var z := _local.z
	var rot := _rot
	placing = false
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	if Game.place_furniture(uid, x, z, rot):
		Sfx.play(main, "ping", -10.0)
	else:
		rebuild()


func prompt_text() -> String:
	var info: Dictionary = GameData.FURNITURE.get(_id, {})
	var what: String = "Place the %s" % info.get("name", "item") if _valid else "Blocked: %s" % _blocked_reason
	return "%s     [%s] Turn it     [%s] Cancel" % [what, Game.key("reset_car"), Game.key("back")]


func _unhandled_input(event: InputEvent) -> void:
	if not placing or main.hud.menu_open:
		return
	if event.is_action_pressed("interact"):
		_confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_car"):
		_rot = (_rot + 1) % 4
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if placing:
		_update_ghost()


func is_inside_home() -> bool:
	if Game.home_id == "" or not town.homes.has(Game.home_id) or main.is_driving():
		return false
	var home: Dictionary = town.homes[Game.home_id]
	var lp: Vector3 = home.building.to_local(main.player.global_position)
	var half: Vector2 = home.half
	return absf(lp.x) < half.x and absf(lp.z) < half.y and lp.y < 3.0


func _extents(id: String, rot: int) -> Vector2:
	var s: Vector3 = GameData.FURNITURE[id].size
	return Vector2(s.z, s.x) / 2.0 if rot % 2 == 1 else Vector2(s.x, s.z) / 2.0


func _update_ghost() -> void:
	if not is_inside_home():
		main.hud.toast("You left home, so placing was cancelled.", "info")
		cancel()
		return
	var home: Dictionary = town.homes[Game.home_id]
	var b: Node3D = home.building
	var half: Vector2 = home.half
	var lp: Vector3 = b.to_local(main.player.global_position)
	var fwd: Vector3 = b.global_basis.inverse() * (Basis(Vector3.UP, main.player.yaw) * Vector3(0, 0, -1))
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
	var ext := _extents(_id, _rot)
	var t := lp + fwd * (0.9 + maxf(ext.x, ext.y))
	t = Vector3(snappedf(t.x, 0.25), 0, snappedf(t.z, 0.25))
	var wall := 0.35   # wall thickness plus a little gap
	t.x = clampf(t.x, -half.x + wall + ext.x, half.x - wall - ext.x)
	t.z = clampf(t.z, -half.y + wall + ext.y, half.y - wall - ext.y)
	_local = t
	_ghost.position = t
	_ghost.rotation.y = _rot * PI / 2.0
	_check_fit(home, lp)
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45) if _valid else Color(1.0, 0.25, 0.2, 0.45)


func _check_fit(home: Dictionary, player_local: Vector3) -> void:
	var ext := _extents(_id, _rot)
	var r := Rect2(Vector2(_local.x - ext.x, _local.z - ext.y), ext * 2.0)
	var is_rug: bool = GameData.FURNITURE[_id].size.y < 0.1
	_valid = false
	if r.grow(0.3).has_point(Vector2(player_local.x, player_local.z)) and not is_rug:
		_blocked_reason = "you're standing there"
		return
	for res in home.reserved:
		if r.intersects(res):
			_blocked_reason = "something's already there"
			return
	for f in Game.placed_furniture():
		if int(f.uid) == _uid:
			continue
		# Rugs go under things and other things go on rugs.
		var other_rug: bool = GameData.FURNITURE[f.id].size.y < 0.1
		if is_rug != other_rug:
			continue
		var e := _extents(f.id, int(f.rot))
		if r.intersects(Rect2(Vector2(f.x - e.x, f.z - e.y), e * 2.0)):
			_blocked_reason = "it bumps into your " + GameData.FURNITURE[f.id].name
			return
	_valid = true
	_blocked_reason = ""


# --- Models (simple shapes; origin on the floor at the center, front facing +Z) ----------

static func build_model(p: Node3D, id: String, lit := true) -> void:
	var wood := Color(0.55, 0.4, 0.26)
	var dark_wood := Color(0.3, 0.2, 0.13)
	var white := Color(0.94, 0.94, 0.95)
	var black := Color(0.08, 0.08, 0.09)
	match id:
		"futon":
			Kit.box(p, Vector3(2.0, 0.25, 1.0), Vector3(0, 0.125, 0), wood, false)
			Kit.box(p, Vector3(1.9, 0.2, 0.85), Vector3(0, 0.35, 0.05), Color(0.25, 0.35, 0.55), false)
			Kit.box(p, Vector3(1.9, 0.45, 0.2), Vector3(0, 0.62, -0.38), Color(0.2, 0.28, 0.45), false)
		"queen_bed":
			Kit.box(p, Vector3(1.7, 0.35, 2.2), Vector3(0, 0.175, 0), dark_wood, false)
			Kit.box(p, Vector3(1.6, 0.22, 2.05), Vector3(0, 0.46, 0.05), white, false)
			Kit.box(p, Vector3(1.64, 0.06, 1.4), Vector3(0, 0.6, 0.35), Color(0.7, 0.3, 0.3), false)
			for x in [-0.38, 0.38]:
				Kit.box(p, Vector3(0.6, 0.14, 0.35), Vector3(x, 0.63, -0.75), white, false)
			Kit.box(p, Vector3(1.7, 1.0, 0.08), Vector3(0, 0.5, -1.06), dark_wood, false)
		"smart_bed":
			Kit.box(p, Vector3(1.9, 0.4, 2.3), Vector3(0, 0.2, 0), Color(0.3, 0.31, 0.34), false)
			Kit.box(p, Vector3(1.8, 0.28, 2.15), Vector3(0, 0.54, 0.05), Color(0.96, 0.96, 0.98), false)
			Kit.box(p, Vector3(1.84, 0.07, 1.5), Vector3(0, 0.71, 0.35), Color(0.12, 0.18, 0.35), false)
			for x in [-0.42, 0.42]:
				Kit.box(p, Vector3(0.68, 0.16, 0.38), Vector3(x, 0.75, -0.8), white, false)
			Kit.box(p, Vector3(1.9, 1.1, 0.15), Vector3(0, 0.55, -1.08), Color(0.35, 0.37, 0.4), false)
			Kit.box(p, Vector3(1.8, 0.03, 0.05), Vector3(0, 0.05, 1.13), Color(0.3, 0.85, 1.0), false, 2.0)
		"microwave":
			for y in [0.3, 0.85]:
				Kit.box(p, Vector3(0.7, 0.04, 0.5), Vector3(0, y, 0), Color(0.6, 0.6, 0.62), false)
			for sx in [-0.32, 0.32]:
				for sz in [-0.22, 0.22]:
					Kit.box(p, Vector3(0.03, 0.85, 0.03), Vector3(sx, 0.425, sz), Color(0.4, 0.4, 0.42), false)
			Kit.box(p, Vector3(0.55, 0.32, 0.4), Vector3(0, 1.03, 0), Color(0.12, 0.12, 0.13), false)
			Kit.box(p, Vector3(0.32, 0.2, 0.01), Vector3(-0.07, 1.03, 0.205), Color(0.2, 0.25, 0.3), false, 0.3)
			Kit.box(p, Vector3(0.12, 0.24, 0.01), Vector3(0.19, 1.03, 0.205), Color(0.5, 0.52, 0.55), false)
		"stove":
			Kit.box(p, Vector3(0.76, 0.9, 0.65), Vector3(0, 0.45, 0), white, false)
			Kit.box(p, Vector3(0.78, 0.03, 0.66), Vector3(0, 0.915, 0), black, false)
			for bx in [-0.18, 0.18]:
				for bz in [-0.15, 0.15]:
					Kit.cylinder(p, 0.09, 0.01, Vector3(bx, 0.935, bz), Color(0.2, 0.2, 0.2), false)
			Kit.box(p, Vector3(0.78, 0.2, 0.05), Vector3(0, 1.0, -0.31), white, false)
			Kit.box(p, Vector3(0.5, 0.3, 0.01), Vector3(0, 0.45, 0.33), Color(0.1, 0.1, 0.12), false)
			Kit.box(p, Vector3(0.55, 0.03, 0.04), Vector3(0, 0.72, 0.345), Color(0.8, 0.82, 0.85), false)
			Kit.cylinder(p, 0.1, 0.14, Vector3(0.18, 1.01, 0.15), Color(0.55, 0.56, 0.58), false)
		"coffee_maker":
			Kit.box(p, Vector3(0.7, 0.04, 0.5), Vector3(0, 0.75, 0), wood, false)
			for sx in [-0.32, 0.32]:
				for sz in [-0.21, 0.21]:
					Kit.box(p, Vector3(0.04, 0.73, 0.04), Vector3(sx, 0.365, sz), dark_wood, false)
			Kit.box(p, Vector3(0.22, 0.32, 0.22), Vector3(0, 0.93, -0.03), black, false)
			Kit.cylinder(p, 0.07, 0.12, Vector3(0, 0.83, 0.06), Color(0.3, 0.2, 0.12), false)
			Kit.cylinder(p, 0.04, 0.09, Vector3(0.2, 0.815, 0.08), Color(0.8, 0.15, 0.15), false)
		"couch":
			var fabric := Color(0.35, 0.42, 0.5)
			Kit.box(p, Vector3(2.2, 0.42, 0.95), Vector3(0, 0.21, 0), fabric, false)
			Kit.box(p, Vector3(1.84, 0.14, 0.72), Vector3(0, 0.49, 0.08), fabric.lightened(0.1), false)
			Kit.box(p, Vector3(2.2, 0.5, 0.22), Vector3(0, 0.65, -0.36), fabric.darkened(0.1), false)
			for x in [-1.01, 1.01]:
				Kit.box(p, Vector3(0.18, 0.62, 0.95), Vector3(x, 0.31, 0), fabric.darkened(0.1), false)
		"tv":
			Kit.box(p, Vector3(1.5, 0.5, 0.45), Vector3(0, 0.25, 0), dark_wood, false)
			Kit.box(p, Vector3(0.1, 0.12, 0.08), Vector3(0, 0.56, -0.05), black, false)
			Kit.box(p, Vector3(1.25, 0.72, 0.05), Vector3(0, 0.98, -0.05), Color(0.12, 0.17, 0.26), false, 0.6)
		"rug":
			Kit.box(p, Vector3(2.4, 0.02, 1.6), Vector3(0, 0.011, 0), Color(0.75, 0.6, 0.45), false)
			Kit.box(p, Vector3(2.1, 0.022, 1.3), Vector3(0, 0.012, 0), Color(0.55, 0.3, 0.25), false)
		"plant":
			Kit.cylinder(p, 0.2, 0.4, Vector3(0, 0.2, 0), Color(0.72, 0.4, 0.25), false)
			Kit.cylinder(p, 0.03, 0.6, Vector3(0, 0.7, 0), Color(0.4, 0.28, 0.15), false)
			Kit.sphere(p, 0.3, Vector3(0, 1.15, 0), Color(0.22, 0.48, 0.2))
			Kit.sphere(p, 0.22, Vector3(0.12, 1.35, 0.05), Color(0.26, 0.55, 0.22))
		"lamp":
			Kit.cylinder(p, 0.18, 0.04, Vector3(0, 0.02, 0), black, false)
			Kit.cylinder(p, 0.02, 1.6, Vector3(0, 0.82, 0), Color(0.75, 0.7, 0.55), false)
			Kit.box(p, Vector3(0.4, 0.28, 0.4), Vector3(0, 1.66, 0), Color(1.0, 0.92, 0.75), false, 1.2)
			if lit:
				var light := OmniLight3D.new()
				light.position = Vector3(0, 1.5, 0)
				light.omni_range = 4.0
				light.light_energy = 0.8
				light.light_color = Color(1.0, 0.82, 0.6)
				p.add_child(light)
		"bookshelf":
			for x in [-0.48, 0.48]:
				Kit.box(p, Vector3(0.04, 1.9, 0.35), Vector3(x, 0.95, 0), wood, false)
			Kit.box(p, Vector3(1.0, 1.9, 0.02), Vector3(0, 0.95, -0.165), wood.darkened(0.2), false)
			var colors := [Color(0.7, 0.2, 0.2), Color(0.2, 0.35, 0.6), Color(0.85, 0.75, 0.3), Color(0.25, 0.5, 0.3)]
			for i in 5:
				var y := 0.02 + i * 0.46
				Kit.box(p, Vector3(0.96, 0.03, 0.33), Vector3(0, y, 0), wood, false)
				if i < 4:
					for k in 4:
						var h := 0.22 + 0.04 * ((i + k) % 3)
						Kit.box(p, Vector3(0.16, h, 0.24), Vector3(-0.33 + k * 0.2, y + 0.015 + h / 2.0, 0.02), colors[(i + k) % 4], false)
		"desk":
			Kit.box(p, Vector3(1.4, 0.04, 0.7), Vector3(0, 0.75, -0.25), wood, false)
			for x in [-0.66, 0.66]:
				Kit.box(p, Vector3(0.05, 0.73, 0.65), Vector3(x, 0.365, -0.25), dark_wood, false)
			Kit.box(p, Vector3(0.6, 0.35, 0.03), Vector3(0, 1.05, -0.5), Color(0.1, 0.12, 0.18), false, 0.5)
			Kit.box(p, Vector3(0.06, 0.25, 0.06), Vector3(0, 0.88, -0.52), black, false)
			Kit.cylinder(p, 0.03, 0.42, Vector3(0, 0.22, 0.3), black, false)
			Kit.box(p, Vector3(0.5, 0.1, 0.5), Vector3(0, 0.48, 0.3), Color(0.75, 0.12, 0.12), false)
			Kit.box(p, Vector3(0.5, 0.7, 0.08), Vector3(0, 0.88, 0.55), Color(0.12, 0.12, 0.12), false)
		"art":
			Kit.box(p, Vector3(0.05, 1.2, 0.05), Vector3(0, 0.6, -0.12), dark_wood, false)
			for x in [-0.28, 0.28]:
				Kit.box(p, Vector3(0.04, 0.9, 0.04), Vector3(x, 0.45, 0.08), dark_wood, false)
			Kit.box(p, Vector3(0.7, 0.9, 0.04), Vector3(0, 1.05, 0), dark_wood, false)
			Kit.box(p, Vector3(0.6, 0.8, 0.01), Vector3(0, 1.05, 0.025), Color(0.95, 0.9, 0.8), false)
			Kit.label(p, "Live\nLaugh\nHustle", Vector3(0, 1.05, 0.035), 26, Color(0.25, 0.2, 0.18))
