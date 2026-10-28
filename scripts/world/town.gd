extends Node3D
## Builds the town of "New Castlewood County" in code: a stylized, compressed take on
## New Castle County, DE. Downtown "Wilmingtown" in the middle, a Newark-style college
## strip to the west, suburbs, and a port/warehouse district to the east, all wrapped
## by the "I-95 Beltway". Every name is a parody.
##
## Layout: a 5x5 grid of blocks. Each block has two sides (facing the road to its
## north or south) with three 23 m lots per side. Buildings face their road.

const B := 90.0          # block pitch (road center to road center)
const N := 5             # blocks per side
const ROAD_W := 14.0
const WALK := 3.0
const RING := 60.0       # beltway distance outside the grid
const SLOT_W := (B - 20.0) / 3.0

const H_STREETS := ["Route 202", "Concord Pike", "4th St", "Pennsylvania Ave", "Lancaster Ave", "Route 40"]
const V_STREETS := ["Newerk Rd", "Kirkwood Hwy", "Delaware Ave", "Market St", "King St", "Christiana Rd"]

var main: Node = null
var addresses: Array = []
var restaurants: Array = []
var stores: Array = []
var station: Dictionary = {}
var places: Array = []
var homes := {}
var mechanic_bay: Transform3D
var spawn_point := Vector3.ZERO
var car_spawn := Transform3D.IDENTITY
var _street_lights: Array = []
var _rng := RandomNumberGenerator.new()

const HOUSE_COLORS := [Color(0.85, 0.82, 0.72), Color(0.62, 0.72, 0.8), Color(0.8, 0.66, 0.55),
	Color(0.7, 0.78, 0.62), Color(0.9, 0.9, 0.88), Color(0.75, 0.55, 0.5), Color(0.86, 0.78, 0.55)]
const ROOF_COLORS := [Color(0.3, 0.25, 0.22), Color(0.25, 0.28, 0.33), Color(0.45, 0.2, 0.15)]


func build() -> void:
	_rng.seed = 302   # same town every time
	_ground_and_roads()
	_blocks()
	_streetlights()
	_signs()


# --- Ground, roads, sidewalks ---------------------------------------------------

func _ground_and_roads() -> void:
	var size := N * B
	var center := size / 2.0
	Kit.box(self, Vector3(1600, 1, 1600), Vector3(center, -0.5, center), Kit.surf("grass"))
	var asphalt := Kit.surf("asphalt")
	var length := size + RING * 2.0 + 16.0
	for k in N + 1:
		var p := k * B
		Kit.box(self, Vector3(length, 0.04, ROAD_W), Vector3(center, 0.02, p), asphalt, false)
		Kit.box(self, Vector3(ROAD_W, 0.05, length), Vector3(p, 0.025, center), asphalt, false)
	# I-95 Beltway ring
	var hw := Kit.surf("asphalt", Color(0.85, 0.85, 0.88))
	for p in [-RING, size + RING]:
		Kit.box(self, Vector3(length, 0.045, 18.0), Vector3(center, 0.022, p), hw, false)
		Kit.box(self, Vector3(18.0, 0.05, length), Vector3(p, 0.027, center), hw, false)
	_road_markings(length)
	# Raised sidewalks with curbs around each block
	var concrete := Kit.surf("concrete")
	var curb := Kit.surf("concrete", Color(0.8, 0.8, 0.78))
	var inner := B - ROAD_W
	var sh := 0.12
	for bx in N:
		for bz in N:
			var cx := bx * B + B / 2.0
			var cz := bz * B + B / 2.0
			var off := inner / 2.0 - WALK / 2.0
			Kit.box(self, Vector3(inner, sh, WALK), Vector3(cx, sh / 2.0, cz - off), concrete)
			Kit.box(self, Vector3(inner, sh, WALK), Vector3(cx, sh / 2.0, cz + off), concrete)
			Kit.box(self, Vector3(WALK, sh, inner - 2.0 * WALK), Vector3(cx - off, sh / 2.0, cz), concrete)
			Kit.box(self, Vector3(WALK, sh, inner - 2.0 * WALK), Vector3(cx + off, sh / 2.0, cz), concrete)
			var co := inner / 2.0 + 0.1
			Kit.box(self, Vector3(inner + 0.4, sh + 0.03, 0.25), Vector3(cx, (sh + 0.03) / 2.0, cz - co), curb, false)
			Kit.box(self, Vector3(inner + 0.4, sh + 0.03, 0.25), Vector3(cx, (sh + 0.03) / 2.0, cz + co), curb, false)
			Kit.box(self, Vector3(0.25, sh + 0.03, inner + 0.4), Vector3(cx - co, (sh + 0.03) / 2.0, cz), curb, false)
			Kit.box(self, Vector3(0.25, sh + 0.03, inner + 0.4), Vector3(cx + co, (sh + 0.03) / 2.0, cz), curb, false)


## Double yellow center lines, white edge lines and zebra crosswalks (multimeshes).
func _road_markings(length: float) -> void:
	var yellow := []
	var white := []
	var zebra := []
	for k in N + 1:
		var p := k * B
		for j in N:
			var a := j * B + ROAD_W / 2.0 + 4.0
			var b := (j + 1) * B - ROAD_W / 2.0 - 4.0
			var mid := (a + b) / 2.0
			var seg := b - a
			for off in [-0.15, 0.15]:
				yellow.append(Transform3D(Basis.IDENTITY.scaled(Vector3(seg, 1, 1)), Vector3(mid, 0.06, p + off)))
				yellow.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1, seg)), Vector3(p + off, 0.065, mid)))
			for off in [-ROAD_W / 2.0 + 0.4, ROAD_W / 2.0 - 0.4]:
				white.append(Transform3D(Basis.IDENTITY.scaled(Vector3(seg, 1, 1)), Vector3(mid, 0.06, p + off)))
				white.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1, seg)), Vector3(p + off, 0.065, mid)))
	for kx in N + 1:
		for kz in N + 1:
			var c := Vector3(kx * B, 0.07, kz * B)
			var d := ROAD_W / 2.0 + 2.0
			for i in 7:
				var o := -ROAD_W / 2.0 + 1.0 + i * 2.0
				zebra.append(Transform3D(Basis.IDENTITY, c + Vector3(o, 0, d)))
				zebra.append(Transform3D(Basis.IDENTITY, c + Vector3(o, 0, -d)))
				zebra.append(Transform3D(Basis(Vector3.UP, PI / 2.0), c + Vector3(d, 0, o)))
				zebra.append(Transform3D(Basis(Vector3.UP, PI / 2.0), c + Vector3(-d, 0, o)))
	Kit.multibox(self, Vector3(1, 0.02, 0.12), yellow, Color(0.95, 0.75, 0.15))
	Kit.multibox(self, Vector3(1, 0.02, 0.14), white, Color(0.9, 0.9, 0.88))
	Kit.multibox(self, Vector3(0.9, 0.02, 3.0), zebra, Color(0.92, 0.92, 0.9))


func _streetlights() -> void:
	for kx in N + 1:
		for kz in N + 1:
			var p := Vector3(kx * B + ROAD_W / 2.0 + 1.0, 0, kz * B + ROAD_W / 2.0 + 1.0)
			Kit.cylinder(self, 0.12, 6.0, p + Vector3(0, 3, 0), Color(0.25, 0.25, 0.27))
			Kit.box(self, Vector3(1.6, 0.15, 0.4), p + Vector3(-0.7, 6.0, -0.7), Color(0.25, 0.25, 0.27), false)
			var l := OmniLight3D.new()
			l.position = p + Vector3(-1.5, 5.6, -1.5)
			l.omni_range = 24.0
			l.light_energy = 1.6
			l.light_color = Color(1.0, 0.85, 0.6)
			l.visible = false
			add_child(l)
			_street_lights.append(l)


func set_night(on: bool) -> void:
	for l in _street_lights:
		l.visible = on


func _signs() -> void:
	var s := Node3D.new()
	s.position = Vector3(B + 20, 0, 2 * B - 9.0)
	add_child(s)
	Kit.box(s, Vector3(7, 2.4, 0.3), Vector3(0, 2.2, 0), Color(0.1, 0.3, 0.55))
	Kit.label(s, "Welcome to\nNEW CASTLEWOOD COUNTY\nThe Firstish State", Vector3(0, 2.3, 0.2), 48)
	for p in [Vector3(-RING + 12, 0, -RING + 12), Vector3(N * B + RING - 12, 0, N * B + RING - 12)]:
		var g := Node3D.new()
		g.position = p
		add_child(g)
		Kit.box(g, Vector3(6, 1.6, 0.2), Vector3(0, 4, 0), Color(0.05, 0.4, 0.15))
		Kit.cylinder(g, 0.1, 4, Vector3(0, 2, -0.2), Color(0.4, 0.4, 0.4))
		var lb := Kit.label(g, "I-95 BELTWAY", Vector3(0, 4, 0.15), 72)
		lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y


# --- Lots ------------------------------------------------------------------------

## A lot's local frame: origin on the property line, +Z points out to the road, -Z into the lot.
func _lot(bx: int, bz: int, side: int, slot: int, span := 1) -> Node3D:
	var n := Node3D.new()
	var cx := bx * B + 10.0 + SLOT_W * (slot + span * 0.5)
	if side == 0:
		n.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(cx, 0, bz * B + 10.0))
	else:
		n.transform = Transform3D(Basis.IDENTITY, Vector3(cx, 0, (bz + 1) * B - 10.0))
	add_child(n)
	return n


func _street(bz: int, side: int) -> String:
	return H_STREETS[bz + side]


func _number(bx: int, side: int, slot: int) -> int:
	return 100 * (bx + 1) + slot * 20 + 2 + side


## Curb point (in the lane in front of the lot) where a car would stop.
func _curb(lot: Node3D) -> Vector3:
	return lot.to_global(Vector3(0, 0, WALK + 3.0))


func _register_address(lot: Node3D, addr_name: String, door_local: Vector3) -> Dictionary:
	var addr := {"name": addr_name, "door": lot.to_global(door_local), "curb": _curb(lot)}
	addresses.append(addr)
	Kit.interactable(lot, door_local + Vector3(0, 1, 0), 2.4,
		func(): return Gigs.door_prompt(addr),
		func(): Gigs.door_action(addr))
	return addr


func _place(place_name: String, lot: Node3D, door_local: Vector3) -> Dictionary:
	var p := {"name": place_name, "door": lot.to_global(door_local), "curb": _curb(lot), "pos": lot.to_global(door_local)}
	places.append(p)
	return p


# --- Block plan --------------------------------------------------------------------

func _blocks() -> void:
	for bx in N:
		for bz in N:
			_block(bx, bz)


func _block(bx: int, bz: int) -> void:
	var key := Vector2i(bx, bz)
	match key:
		Vector2i(2, 0):
			_apartments(_lot(bx, bz, 0, 0, 3), "Brandywine Apartments", 5, _number(bx, 0, 0), _street(bz, 0))
			_apartments(_lot(bx, bz, 1, 0, 3), "Brandywine Apartments II", 4, _number(bx, 1, 0), _street(bz, 1))
		Vector2i(0, 1):
			_apartments(_lot(bx, bz, 0, 0, 2), "Campus Edge Apartments", 4, _number(bx, 0, 0), _street(bz, 0), 2)
			_house_row(bx, bz, 0, [2])
			_house_row(bx, bz, 1, [0, 1, 2])
		Vector2i(1, 1):
			_house_row(bx, bz, 0, [0, 1, 2])
			_laundromat(_lot(bx, bz, 1, 0))
			var l := _lot(bx, bz, 1, 1)
			_home(l, "room", "Dottie's Boarding House", Vector3(14, 4.5, 12), Color(0.72, 0.5, 0.42), 6.0)
			spawn_point = l.to_global(Vector3(0, 1, 2.0))
			car_spawn = Transform3D(Basis(Vector3.UP, -PI / 2.0), _curb(l) + Vector3(0, 0.8, -0.5))
			_house_row(bx, bz, 1, [2])
		Vector2i(2, 1):
			_park(bx, bz)
		Vector2i(3, 1):
			_house_row(bx, bz, 0, [0, 1, 2])
			_home(_lot(bx, bz, 1, 0, 2), "studio", "Maple Court Apartments", Vector3(18, 5, 12), Color(0.55, 0.6, 0.68), 4.0, 3)
			_restaurant(_lot(bx, bz, 1, 2), "Bean Scene Coffee", Color(0.45, 0.3, 0.2))
		Vector2i(4, 1):
			_apartments(_lot(bx, bz, 0, 0, 3), "Riverfront Lofts", 6, _number(bx, 0, 0), _street(bz, 0))
			_home(_lot(bx, bz, 1, 0, 2), "twobr", "Lakeview Towers", Vector3(18, 5, 12), Color(0.82, 0.8, 0.75), 4.0, 6)
			_house_row(bx, bz, 1, [2])
		Vector2i(0, 2):
			_campus(_lot(bx, bz, 0, 0, 3))
			_apartments(_lot(bx, bz, 1, 0, 2), "Blue Chicken Student Housing", 3, _number(bx, 1, 0), _street(bz, 1), 2)
			_restaurant(_lot(bx, bz, 1, 2), "Grotty Pizza", Color(0.15, 0.45, 0.25))
		Vector2i(1, 2):
			_grocery(_lot(bx, bz, 0, 0, 2), "Ackme Market", Color(0.85, 0.2, 0.2))
			_restaurant(_lot(bx, bz, 0, 2), "Capritoni's", Color(0.75, 0.15, 0.15))
			_gas_station(_lot(bx, bz, 1, 0, 2))
			_house_row(bx, bz, 1, [2])
		Vector2i(2, 2):
			_restaurant(_lot(bx, bz, 0, 0), "Burger Barn", Color(0.7, 0.35, 0.15))
			_restaurant(_lot(bx, bz, 0, 1), "Taco Loco", Color(0.9, 0.6, 0.15))
			_restaurant(_lot(bx, bz, 0, 2), "Wok This Way", Color(0.65, 0.1, 0.1))
			_restaurant(_lot(bx, bz, 1, 0), "Sunny Side Diner", Color(0.3, 0.6, 0.75))
			_restaurant(_lot(bx, bz, 1, 1), "Cluckin' Good", Color(0.85, 0.75, 0.2))
			_restaurant(_lot(bx, bz, 1, 2), "Noodle Nirvana", Color(0.5, 0.25, 0.55))
		Vector2i(3, 2):
			_grocery(_lot(bx, bz, 0, 0, 2), "ShopWrite", Color(0.15, 0.35, 0.7))
			_house_row(bx, bz, 0, [2])
			_apartments(_lot(bx, bz, 1, 0, 3), "Christiana Commons", 4, _number(bx, 1, 0), _street(bz, 1))
		Vector2i(1, 3):
			_apartments(_lot(bx, bz, 0, 0, 3), "Wilmingtown Towers", 7, _number(bx, 0, 0), _street(bz, 0))
			_house_row(bx, bz, 1, [0, 1, 2])
		Vector2i(2, 3):
			_house_row(bx, bz, 0, [0, 1, 2])
			_mechanic(_lot(bx, bz, 1, 0))
			_dealership(_lot(bx, bz, 1, 1, 2))
		Vector2i(4, 3):
			_house_row(bx, bz, 0, [0, 1, 2])
			_warehouse(_lot(bx, bz, 1, 0, 3))
		Vector2i(4, 4):
			_house_row(bx, bz, 0, [0, 2])
			_home(_lot(bx, bz, 0, 1), "house", "Your Future House", Vector3(16, 5, 13), Color(0.92, 0.92, 0.88), 8.0)
			_house_row(bx, bz, 1, [0, 1, 2])
		_:
			_house_row(bx, bz, 0, [0, 1, 2])
			_house_row(bx, bz, 1, [0, 1, 2])


# --- Residential ------------------------------------------------------------------

func _house_row(bx: int, bz: int, side: int, slots: Array) -> void:
	for s in slots:
		_house(_lot(bx, bz, side, s), "%d %s" % [_number(bx, side, s), _street(bz, side)])


func _house(lot: Node3D, addr_name: String) -> void:
	var w := _rng.randf_range(9.0, 12.0)
	var d := _rng.randf_range(8.0, 10.0)
	var h := _rng.randf_range(3.4, 3.9)
	var setback := _rng.randf_range(8.0, 12.0)
	var color: Color = HOUSE_COLORS[_rng.randi() % HOUSE_COLORS.size()]
	var trim := Color(0.95, 0.94, 0.9)
	var brick_house := _rng.randf() < 0.3
	var walls := Kit.surf("brick") if brick_house else Kit.surf("siding", color)
	var hb := Node3D.new()
	hb.position = Vector3(0, 0, -(setback + d / 2.0))
	lot.add_child(hb)
	Kit.box(hb, Vector3(w + 0.2, 0.5, d + 0.2), Vector3(0, 0.25, 0), Kit.surf("concrete", Color(0.75, 0.75, 0.75)))
	Kit.box(hb, Vector3(w, h, d), Vector3(0, 0.5 + h / 2.0, 0), walls)
	# Gable roof made from two sloped shingle slabs
	var roof_mat := Kit.surf("shingles", ROOF_COLORS[_rng.randi() % ROOF_COLORS.size()])
	var pitch := 0.55
	var half_d := d / 2.0 + 0.5
	var slab_len := half_d / cos(pitch)
	var top := 0.5 + h
	for sz in [-1.0, 1.0]:
		var r := Kit.box(hb, Vector3(w + 0.8, 0.18, slab_len), Vector3(0, top + half_d * tan(pitch) / 2.0, sz * half_d / 2.0), roof_mat, false)
		r.rotation.x = sz * pitch
	# Gable ends
	var gable := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(d, half_d * tan(pitch) - 0.1, w - 0.05)
	gable.mesh = pm
	gable.material_override = walls
	gable.rotation.y = PI / 2.0
	gable.position = Vector3(0, top + pm.size.y / 2.0, 0)
	hb.add_child(gable)
	if _rng.randf() < 0.6:
		Kit.box(hb, Vector3(0.9, 2.4, 0.9), Vector3(w * 0.3, top + 1.0, -d * 0.2), Kit.surf("brick"), false)
	# Front: door, porch, windows with trim and shutters
	var fz := d / 2.0
	Kit.box(hb, Vector3(1.1, 2.2, 0.12), Vector3(0, 0.5 + 1.1, fz + 0.06), Kit.surf("wood", Color(0.7, 0.45, 0.3)), false)
	Kit.box(hb, Vector3(1.4, 0.15, 0.18), Vector3(0, 0.5 + 2.25, fz + 0.08), trim, false)
	Kit.box(hb, Vector3(3.6, 0.3, 2.0), Vector3(0, 0.35, fz + 1.0), Kit.surf("wood", Color(0.85, 0.8, 0.75)))
	Kit.box(hb, Vector3(3.8, 0.12, 2.2), Vector3(0, 0.5 + 2.7, fz + 1.0), roof_mat, false)
	for sx in [-1.6, 1.6]:
		Kit.cylinder(hb, 0.08, 2.5, Vector3(sx, 0.5 + 1.35, fz + 1.9), trim, false)
	for sx in [-1.0, 1.0]:
		var wx: float = sx * w * 0.3
		Kit.box(hb, Vector3(1.5, 1.3, 0.06), Vector3(wx, 0.5 + 1.75, fz + 0.03), Kit.glass(), false)
		Kit.box(hb, Vector3(1.7, 0.12, 0.12), Vector3(wx, 0.5 + 2.45, fz + 0.06), trim, false)
		Kit.box(hb, Vector3(1.8, 0.1, 0.22), Vector3(wx, 0.5 + 1.05, fz + 0.1), trim, false)
		Kit.box(hb, Vector3(0.06, 1.3, 0.08), Vector3(wx, 0.5 + 1.75, fz + 0.07), trim, false)
		for side in [-1.0, 1.0]:
			Kit.box(hb, Vector3(0.45, 1.4, 0.06), Vector3(wx + side * 1.0, 0.5 + 1.75, fz + 0.05), color.darkened(0.45), false)
	# Side windows
	for sx in [-1.0, 1.0]:
		Kit.box(hb, Vector3(0.06, 1.2, 1.4), Vector3(sx * (w / 2.0 + 0.03), 0.5 + 1.8, 0), Kit.glass(), false)
	Kit.label(hb, addr_name.split(" ")[0], Vector3(0.95, 0.5 + 2.3, fz + 0.1), 40, Color(0.1, 0.1, 0.1))
	# Garage on some houses
	if _rng.randf() < 0.5:
		var g := Node3D.new()
		g.position = Vector3(w / 2.0 + 2.3, 0, 0.5)
		hb.add_child(g)
		Kit.box(g, Vector3(4.2, 3.0, 6.5), Vector3(0, 1.5, 0), walls)
		Kit.box(g, Vector3(4.6, 0.25, 7.0), Vector3(0, 3.1, 0), roof_mat, false)
		Kit.box(g, Vector3(3.2, 2.3, 0.08), Vector3(0, 1.15, 3.27), Color(0.92, 0.92, 0.9), false)
	# Front walk, driveway, landscaping
	Kit.box(lot, Vector3(1.4, 0.05, setback + 0.2), Vector3(0, 0.035, -setback / 2.0), Kit.surf("concrete"), false)
	Kit.box(lot, Vector3(3.2, 0.05, setback + 0.5), Vector3(w / 2.0 + 2.3, 0.034, -setback / 2.0), Kit.surf("concrete", Color(0.75, 0.75, 0.75)), false)
	for i in 3:
		Kit.bush(lot, Vector3(-w / 2.0 + 0.8 + i * 1.3, 0, -setback + 0.6))
	if _rng.randf() < 0.8:
		_tree(lot, Vector3(-w / 2.0 - 2.5, 0, -setback / 2.0 + 1.0))
	# Mailbox
	Kit.cylinder(lot, 0.05, 1.0, Vector3(1.3, 0.5, -0.6), Color(0.2, 0.2, 0.2), false)
	Kit.box(lot, Vector3(0.25, 0.25, 0.45), Vector3(1.3, 1.1, -0.6), Color(0.15, 0.2, 0.35), false)
	_register_address(lot, addr_name, Vector3(0, 0, -setback + 1.0))


func _apartments(lot: Node3D, apt_name: String, floors: int, number: int, street: String, span := 3) -> void:
	var w := SLOT_W * span - 6.0
	var d := 16.0
	var h := floors * 3.2
	var setback := 6.0
	var b := Node3D.new()
	b.position = Vector3(0, 0, -(setback + d / 2.0))
	lot.add_child(b)
	var walls := Kit.surf("brick") if floors % 2 == 0 else Kit.surf("stucco", Color(0.82, 0.78, 0.7))
	Kit.box(b, Vector3(w, h, d), Vector3(0, h / 2.0, 0), walls)
	var panes := []
	var sills := []
	var n := int(w / 3.2)
	for f in floors:
		for i in n:
			var x := -w / 2.0 + (i + 0.5) * w / n
			if f == 0 and absf(x) < 2.5:
				continue
			panes.append(Transform3D(Basis.IDENTITY, Vector3(x, 1.7 + f * 3.2, d / 2.0 + 0.03)))
			sills.append(Transform3D(Basis.IDENTITY, Vector3(x, 1.0 + f * 3.2, d / 2.0 + 0.08)))
	Kit.multibox(b, Vector3(1.6, 1.5, 0.06), panes, Kit.glass())
	Kit.multibox(b, Vector3(1.9, 0.12, 0.2), sills, Color(0.88, 0.86, 0.82))
	Kit.box(b, Vector3(2.4, 2.6, 0.15), Vector3(0, 1.3, d / 2.0 + 0.08), Kit.glass(), false)
	Kit.box(b, Vector3(4.0, 0.25, 2.0), Vector3(0, 3.0, d / 2.0 + 1.0), Color(0.15, 0.25, 0.35), false)
	Kit.box(b, Vector3(w + 0.4, 0.6, d + 0.4), Vector3(0, h + 0.3, 0), Kit.surf("concrete", Color(0.7, 0.7, 0.7)))
	Kit.box(b, Vector3(w - 1.0, 0.1, d - 1.0), Vector3(0, h + 0.62, 0), Kit.surf("gravel"), false)
	Kit.label(b, apt_name, Vector3(0, 3.5, d / 2.0 + 0.12), 72, Color(1, 0.95, 0.8))
	Kit.box(lot, Vector3(2.0, 0.05, setback + 0.2), Vector3(0, 0.035, -setback / 2.0), Kit.surf("concrete"), false)
	for x in [-6.0, -4.0, 4.0, 6.0]:
		Kit.bush(lot, Vector3(x, 0, -setback + 0.8))
	_register_address(lot, "%s (%d %s)" % [apt_name, number, street], Vector3(0, 0, -setback + 1.0))


func _tree(parent: Node3D, pos: Vector3) -> void:
	var tint := Color(0.3 + _rng.randf() * 0.1, 0.48 + _rng.randf() * 0.15, 0.2 + _rng.randf() * 0.08)
	Kit.tree(parent, pos, _rng.randf_range(0.8, 1.25), tint)


func _campus(lot: Node3D) -> void:
	var b := Node3D.new()
	b.position = Vector3(0, 0, -20)
	lot.add_child(b)
	Kit.box(b, Vector3(50, 12, 18), Vector3(0, 6, 0), Kit.surf("brick"))
	Kit.box(b, Vector3(10, 16, 10), Vector3(0, 8, 5), Kit.surf("brick", Color(1.05, 1.0, 0.95)))
	Kit.box(b, Vector3(11, 1.0, 11), Vector3(0, 16.5, 5), Color(0.9, 0.9, 0.88))
	for x in [-3.0, -1.0, 1.0, 3.0]:
		Kit.cylinder(b, 0.4, 7, Vector3(x, 3.5, 10.6), Color(0.95, 0.95, 0.92))
	Kit.label(b, "UNIVERSITY OF DELAWHERE", Vector3(0, 8.5, 10.1), 110, Color(1, 0.85, 0.3))
	Kit.label(b, "Home of the Fightin' Blue Chickens", Vector3(0, 7.2, 10.1), 56)
	for i in 4:
		_tree(lot, Vector3(-20 + i * 13, 0, -4))


func _park(bx: int, bz: int) -> void:
	var p := Node3D.new()
	p.position = Vector3(bx * B + B / 2.0, 0, bz * B + B / 2.0)
	add_child(p)
	Kit.box(p, Vector3(4, 0.05, 66), Vector3(0, 0.04, 0), Kit.surf("concrete", Color(0.95, 0.9, 0.82)), false)
	Kit.box(p, Vector3(66, 0.05, 4), Vector3(0, 0.041, 0), Kit.surf("concrete", Color(0.95, 0.9, 0.82)), false)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.1, 0.22, 0.28)
	water.metallic = 0.3
	water.roughness = 0.05
	Kit.box(p, Vector3(17, 0.3, 11), Vector3(18, 0.1, -18), Kit.surf("concrete"), false)
	Kit.box(p, Vector3(16, 0.32, 10), Vector3(18, 0.1, -18), water, false)
	Kit.box(p, Vector3(2, 1.2, 2), Vector3(0, 0.6, 0), Color(0.55, 0.55, 0.52))
	Kit.box(p, Vector3(0.8, 2.2, 0.8), Vector3(0, 2.3, 0), Color(0.3, 0.45, 0.35))
	Kit.label(p, "Caesar Rodknee\n(rode a horse, probably)", Vector3(0, 1.0, 1.05), 32)
	Kit.label(p, "RODKNEE SQUARE", Vector3(0, 4.2, 0), 96, Color(1, 1, 0.85), true)
	for i in 14:
		var a := i * TAU / 14.0
		_tree(p, Vector3(cos(a) * 26.0, 0, sin(a) * 26.0))
	for bpos in [Vector3(5, 0, 6), Vector3(-5, 0, -6), Vector3(6, 0, -5)]:
		Kit.box(p, Vector3(2.2, 0.08, 0.6), bpos + Vector3(0, 0.48, 0), Kit.surf("wood"))
		Kit.box(p, Vector3(2.2, 0.5, 0.08), bpos + Vector3(0, 0.8, -0.28), Kit.surf("wood"), false)
		for lx in [-0.9, 0.9]:
			Kit.box(p, Vector3(0.08, 0.45, 0.5), bpos + Vector3(lx, 0.22, 0), Color(0.15, 0.15, 0.15))
	# Public restroom
	var r := Node3D.new()
	r.position = Vector3(-20, 0, 20)
	p.add_child(r)
	var rb := Kit.hollow_building(r, Vector3(7, 3.4, 6), Kit.surf("brick"), Kit.surf("gravel"), 2.0, 2.6, null, false)
	rb.rotation.y = PI
	var rl := Kit.label(r, "PUBLIC RESTROOM", Vector3(0, 3.0, -3.15), 48)
	rl.rotation.y = PI
	_toilet(rb, Vector3(-1.8, 0, -1.6))
	_toilet(rb, Vector3(1.8, 0, -1.6))
	places.append({"name": "Rodknee Square (public restroom)", "pos": r.global_position + Vector3(0, 0, -4.5), "door": r.global_position})


# --- Businesses -----------------------------------------------------------------------

func _shop(lot: Node3D, shop_name: String, size: Vector3, color: Color, setback := 3.0,
		door_w := 2.6, door_h := 3.0) -> Node3D:
	var holder := Node3D.new()
	holder.position = Vector3(0, 0, -(setback + size.z / 2.0))
	lot.add_child(holder)
	var walls: Material
	if shop_name.hash() % 3 == 0:
		walls = Kit.surf("brick")
	else:
		walls = Kit.surf("stucco", color.lerp(Color(0.9, 0.88, 0.82), 0.55))
	var b := Kit.hollow_building(holder, size, walls, Kit.surf("gravel"), door_w, door_h)
	var fz := size.z / 2.0
	# Sign board in the brand color
	var sign_w := minf(size.x - 2.0, 12.0)
	Kit.box(b, Vector3(sign_w, 1.2, 0.2), Vector3(0, size.y - 0.9, fz + 0.2), color.darkened(0.35), false)
	Kit.box(b, Vector3(sign_w + 0.2, 0.08, 0.3), Vector3(0, size.y - 0.26, fz + 0.2), Color(0.9, 0.9, 0.9), false)
	Kit.label(b, shop_name, Vector3(0, size.y - 0.9, fz + 0.32), 120, Color(1, 0.97, 0.85))
	# Striped awning over the storefront
	if door_h <= 3.2 and size.y >= 4.0:
		var aw := Kit.box(b, Vector3(size.x - 1.0, 0.08, 1.6), Vector3(0, door_h + 0.35, fz + 0.75), color, false)
		aw.rotation.x = 0.35
		Kit.box(b, Vector3(size.x - 1.0, 0.25, 0.04), Vector3(0, door_h + 0.02, fz + 1.5), color.darkened(0.2), false)
	Kit.box(lot, Vector3(door_w + 1.0, 0.05, setback + 0.2), Vector3(0, 0.036, -setback / 2.0), Kit.surf("concrete"), false)
	return b


func _counter(b: Node3D, pos: Vector3, width: float, color := Color(0.5, 0.35, 0.25)) -> void:
	Kit.box(b, Vector3(width, 1.05, 0.8), pos + Vector3(0, 0.525, 0), color)
	Kit.box(b, Vector3(width + 0.1, 0.06, 0.9), pos + Vector3(0, 1.08, 0), Color(0.85, 0.85, 0.82))


func _toilet(b: Node3D, pos: Vector3, home_id := "") -> void:
	Kit.box(b, Vector3(0.5, 0.45, 0.7), pos + Vector3(0, 0.225, 0), Color(0.95, 0.95, 0.97))
	Kit.box(b, Vector3(0.55, 0.7, 0.2), pos + Vector3(0, 0.6, -0.4), Color(0.95, 0.95, 0.97))
	Kit.label(b, "WC", pos + Vector3(0, 2.2, -0.45), 40, Color(0.7, 0.85, 1.0))
	Kit.interactable(b, pos + Vector3(0, 1, 0.6), 1.8,
		func():
			if home_id != "" and Game.home_id != home_id:
				return ""
			return "Use the restroom",
		func(): Game.use_restroom())


func _restaurant(lot: Node3D, rname: String, color: Color) -> void:
	var size := Vector3(16, 5, 14)
	var b := _shop(lot, rname, size, color)
	var cz := -size.z / 2.0 + 4.0
	_counter(b, Vector3(0, 0, cz), 9.0)
	Kit.box(b, Vector3(14, 3.0, 0.2), Vector3(0, 1.5, cz - 1.6), Color(0.75, 0.75, 0.78))
	Kit.label(b, "ORDER HERE", Vector3(-2.5, 2.6, cz - 1.45), 80, Color(1, 1, 0.6))
	Kit.label(b, "MOBILE PICKUP", Vector3(2.8, 2.6, cz - 1.45), 80, Color(0.6, 1, 0.7))
	for i in 3:
		Kit.box(b, Vector3(0.5, 0.35, 0.4), Vector3(2.0 + i * 0.7, 1.28, cz), Color(0.7, 0.55, 0.35), false)
	for t in [Vector3(-4, 0, 2), Vector3(4, 0, 2), Vector3(-4, 0, 5), Vector3(4, 0, 5)]:
		Kit.box(b, Vector3(1.4, 0.8, 1.4), t + Vector3(0, 0.4, 0), Color(0.6, 0.45, 0.3))
	var menu: Array = GameData.RESTAURANTS.get(rname, [])
	Kit.interactable(b, Vector3(-2.5, 1, cz + 1.1), 2.0,
		func(): return "Order food" if not menu.is_empty() else "",
		func(): _food_menu(rname, menu))
	Kit.interactable(b, Vector3(2.8, 1, cz + 1.1), 2.0,
		func():
			var j := Gigs.job
			if j.get("kind", "") == "food" and j.stage == "to_restaurant" and j.restaurant.name == rname:
				return "Pick up DoorDish order #%d for %s" % [j.order_no, j.customer_name]
			return "",
		func(): Gigs.pick_up_food())
	_toilet(b, Vector3(size.x / 2.0 - 1.4, 0, -size.z / 2.0 + 1.0))
	var p := _place(rname, lot, Vector3(0, 0, -2.0))
	restaurants.append({"name": rname, "door": p.door, "curb": p.curb})


func _food_menu(title: String, items: Array) -> void:
	var opts := []
	for it in items:
		var cb := func():
			if Game.spend(it[1], title + ": " + it[0]):
				Game.eat(it[0], it[2], it[3])
		opts.append({"text": "%s   $%.2f" % [it[0], it[1]], "cb": cb})
	main.hud.show_menu(title, opts)


func _grocery(lot: Node3D, sname: String, color: Color) -> void:
	var size := Vector3(40, 6, 28)
	var b := _shop(lot, sname, size, color, 3.0, 4.0, 3.2)
	var items: Array = GameData.GROCERY_ITEMS
	var idx := 0
	for row in 3:
		var z := -9.0 + row * 6.0
		Kit.box(b, Vector3(22, 2.0, 1.2), Vector3(4, 1.0, z), Color(0.82, 0.82, 0.8))
		for face in [-1.0, 1.0]:
			for k in 3:
				if idx >= items.size():
					break
				var item: String = items[idx]
				idx += 1
				var x := -4.0 + k * 8.0
				var pos := Vector3(x, 0, z + face * 1.1)
				Kit.box(b, Vector3(2.5, 0.5, 0.15), Vector3(x, 1.6, z + face * 0.62), Color(_rng.randf(), _rng.randf(), _rng.randf()).lerp(Color.WHITE, 0.3), false)
				Kit.label(b, item, pos + Vector3(0, 2.3, 0), 64, Color(1, 1, 0.8), true)
				Kit.interactable(b, pos + Vector3(0, 1, 0), 1.6,
					func():
						var j := Gigs.job
						if j.get("kind", "") == "grocery" and j.stage in ["to_store", "shopping"] \
								and j.store.name == sname and item in j.items and not item in j.picked:
							return "Grab %s for %s" % [item, j.customer_name]
						return "",
					func(): Gigs.grab_item(item))
	# Registers near the front-left
	var rz := size.z / 2.0 - 5.0
	_counter(b, Vector3(-14, 0, rz), 3.0, Color(0.3, 0.3, 0.35))
	_counter(b, Vector3(-8, 0, rz), 3.0, Color(0.3, 0.3, 0.35))
	Kit.label(b, "INSTACRATE\nCHECKOUT", Vector3(-14, 2.6, rz), 44, Color(1, 0.8, 0.3), true)
	Kit.label(b, "REGISTER", Vector3(-8, 2.6, rz), 44, Color.WHITE, true)
	Kit.interactable(b, Vector3(-14, 1, rz - 1.0), 2.0,
		func():
			var j := Gigs.job
			if j.get("kind", "") == "grocery" and j.stage == "checkout" and j.store.name == sname:
				return "Check out %s's order" % j.customer_name
			return "",
		func(): Gigs.checkout())
	Kit.interactable(b, Vector3(-8, 1, rz - 1.0), 2.0,
		func():
			if Game.home_id == "":
				return ""
			return "Buy groceries for home ($%.0f, %d meals)" % [GameData.HOME_GROCERIES_PRICE, GameData.HOME_GROCERIES_MEALS],
		func():
			if Game.spend(GameData.HOME_GROCERIES_PRICE, sname + ": groceries"):
				Game.fridge_meals += GameData.HOME_GROCERIES_MEALS
				Game.notify("Groceries bought. They're in your fridge at home.", "good"))
	_toilet(b, Vector3(-size.x / 2.0 + 1.5, 0, -size.z / 2.0 + 1.0))
	var p := _place(sname, lot, Vector3(0, 0, -2.0))
	stores.append({"name": sname, "door": p.door, "curb": p.curb, "items": items})


func _gas_station(lot: Node3D) -> void:
	var sname := "WahWah"
	# Canopy and pumps
	Kit.box(lot, Vector3(18, 0.5, 11), Vector3(0, 5.2, -9), Color(0.95, 0.85, 0.2), false)
	Kit.label(lot, "WahWah", Vector3(0, 5.2, -3.4), 120, Color(0.75, 0.1, 0.1))
	for x in [-8.0, 8.0]:
		for z in [-13.0, -5.0]:
			Kit.cylinder(lot, 0.25, 5.0, Vector3(x, 2.5, z), Color(0.9, 0.9, 0.9))
	for x in [-4.0, 4.0]:
		var pump_pos := Vector3(x, 0, -9)
		Kit.box(lot, Vector3(1.0, 0.25, 4.0), pump_pos + Vector3(0, 0.12, 0), Color(0.6, 0.6, 0.6))
		Kit.box(lot, Vector3(0.7, 1.7, 0.6), pump_pos + Vector3(0, 1.0, 0), Color(0.8, 0.15, 0.1))
		var gpos := lot.to_global(pump_pos)
		Kit.interactable(lot, pump_pos + Vector3(0, 1, 0), 3.2,
			func():
				if main == null or main.car.global_position.distance_to(gpos) > 7.0:
					return "Park your car next to the pump to fill up"
				var need: float = Game.car().tank - Game.fuel
				if need < 0.1:
					return "Tank is full"
				return "Fill up: %.1f gal  ($%.2f)" % [need, need * GameData.GAS_PRICE],
			func():
				if main.car.global_position.distance_to(gpos) > 7.0:
					return
				var need: float = Game.car().tank - Game.fuel
				var afford: float = Game.money / GameData.GAS_PRICE
				var gal := minf(need, afford)
				if gal < 0.1:
					Game.notify("You can't afford any gas.", "bad")
					return
				Game.refuel(gal))
	# Mini mart
	var b := _shop(lot, "WahWah Market", Vector3(14, 4, 10), Color(0.9, 0.9, 0.85), 20.0)
	_counter(b, Vector3(0, 0, -2.5), 6.0)
	Kit.label(b, "Hoagies  Coffee  Snacks", Vector3(0, 2.8, -4.7), 44, Color(0.75, 0.1, 0.1))
	Kit.interactable(b, Vector3(0, 1, -1.4), 2.0,
		func(): return "Buy snacks & coffee",
		func(): _food_menu("WahWah Market", GameData.GAS_STATION_MENU))
	_toilet(b, Vector3(5.5, 0, -3.8))
	_place("WahWah (gas & snacks)", lot, Vector3(0, 0, -2.0))


func _laundromat(lot: Node3D) -> void:
	var b := _shop(lot, "Suds City Laundromat", Vector3(14, 4, 12), Color(0.55, 0.75, 0.85))
	for i in 4:
		Kit.box(b, Vector3(1.0, 1.0, 0.9), Vector3(-4.5 + i * 3.0, 0.5, -4.5), Color(0.95, 0.95, 0.95))


func _mechanic(lot: Node3D) -> void:
	var size := Vector3(17, 6, 16)
	var b := _shop(lot, "Lube & Tube", size, Color(0.35, 0.35, 0.4), 4.0, 7.5, 4.6)
	Kit.box(b, Vector3(7, 0.04, 9), Vector3(0, 0.05, -1), Color(0.9, 0.75, 0.1), false)
	Kit.label(b, "SERVICE BAY", Vector3(0, 3.8, -7.85), 64, Color(1, 0.9, 0.3))
	_counter(b, Vector3(-6.2, 0, -5), 2.6)
	Kit.interactable(b, Vector3(-5.8, 1, -3.8), 2.2,
		func(): return "Talk to the mechanic",
		func(): _mechanic_menu())
	_toilet(b, Vector3(6.8, 0, -7))
	mechanic_bay = Transform3D(lot.global_transform.basis, b.to_global(Vector3(0, 1.0, -1)))
	_place("Lube & Tube (mechanic)", lot, Vector3(0, 0, -3.0))


func _mechanic_menu() -> void:
	var near_car: bool = main.car.global_position.distance_to(mechanic_bay.origin) < 30.0
	var opts := []
	if not near_car:
		opts.append({"text": "(Bring your car to the shop first)", "cb": func(): pass, "disabled": true})
	opts.append({"text": "Oil change  $%.0f   (oil life %d%%)" % [GameData.OIL_CHANGE_PRICE, Game.oil_life],
		"cb": func(): Game.oil_change(), "disabled": not near_car})
	opts.append({"text": "New tires  $%.0f   (tread %d%%)" % [Game.car().tires, Game.tire_tread],
		"cb": func(): Game.replace_tires(), "disabled": not near_car})
	var rc := Game.repair_cost()
	opts.append({"text": "Engine repair  $%.0f   (health %d%%)" % [rc, Game.engine_health],
		"cb": func(): Game.repair_engine(), "disabled": not near_car or rc <= 0.0})
	main.hud.show_menu("Lube & Tube: \"What're we doin' today?\"", opts)


func _dealership(lot: Node3D) -> void:
	var b := _shop(lot, "Honest Al's Used Cars", Vector3(12, 4, 9), Color(0.85, 0.85, 0.9), 22.0)
	Kit.box(lot, Vector3(40, 0.05, 18), Vector3(0, 0.04, -10), Color(0.3, 0.3, 0.32), false)
	var i := 0
	for id in GameData.CAR_ORDER:
		if id == "rustwagon":
			continue
		var c: Dictionary = GameData.CARS[id]
		var pos := Vector3(-15 + i * 10, 0, -10)
		i += 1
		var car_node := Node3D.new()
		car_node.position = pos
		car_node.rotation.y = 0.5
		lot.add_child(car_node)
		car_node.add_child(CarModel.build(c, false, true))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.8, 1.0, 4.3)
		cs.shape = bs
		cs.position.y = 0.8
		var sb := StaticBody3D.new()
		sb.add_child(cs)
		car_node.add_child(sb)
		Kit.label(lot, "%s\n$%s" % [c.name, c.price], pos + Vector3(0, 2.8, 0), 40, Color(1, 1, 0.7), true)
	Kit.label(lot, "WE FINANCE NOBODY!", Vector3(0, 3.5, -20), 72, Color(1, 0.3, 0.3), true)
	_counter(b, Vector3(0, 0, -2.0), 4.0)
	Kit.interactable(b, Vector3(0, 1, -0.8), 2.2,
		func(): return "Talk to Honest Al",
		func(): _dealer_menu())
	_place("Honest Al's Used Cars", lot, Vector3(0, 0, -21.0))


func _dealer_menu() -> void:
	var opts := []
	var trade := Game.trade_in_value()
	for id in GameData.CAR_ORDER:
		if id == Game.car_id:
			continue
		var c: Dictionary = GameData.CARS[id]
		if c.price == 0:
			continue
		var cost: float = maxf(0.0, c.price - trade)
		opts.append({"text": "%s  $%d  (you pay $%d after trade-in)" % [c.name, c.price, cost],
			"cb": func(): Game.buy_car(id), "disabled": Game.money < cost})
	main.hud.show_menu("Honest Al: \"Your %s? I'll give you $%d for it.\"" % [Game.car().name, trade], opts)


func _warehouse(lot: Node3D) -> void:
	var size := Vector3(56, 9, 26)
	var b := _shop(lot, "JUNGLE FLEX DELIVERY STATION  DNC9", size, Color(0.55, 0.6, 0.62), 4.0, 10.0, 6.0)
	for x in [-22.0, -14.0, 14.0, 22.0]:
		for z in [-8.0, 0.0]:
			Kit.box(b, Vector3(5, 4, 1.5), Vector3(x, 2, z), Color(0.2, 0.35, 0.6))
			for k in 3:
				Kit.box(b, Vector3(0.8, 0.6, 0.6), Vector3(x - 1.5 + k * 1.5, 4.3, z), Color(0.75, 0.6, 0.4), false)
	Kit.box(b, Vector3(18, 0.9, 1.4), Vector3(0, 0.45, -10), Color(0.3, 0.3, 0.3))
	Kit.box(b, Vector3(10, 0.03, 10), Vector3(0, 0.05, 1), Color(0.95, 0.8, 0.1), false)
	Kit.label(b, "LOADING ZONE: SCAN WITH APP", Vector3(0, 4.5, -4), 72, Color(1, 0.85, 0.2), true)
	var load_point := b.to_global(Vector3(0, 0, 1))
	Kit.interactable(b, Vector3(0, 1, 1), 7.0,
		func():
			if Gigs.job.get("kind", "") == "flex" and Gigs.job.stage == "to_station":
				return "Open Jungle Flex app to scan packages"
			return "",
		func(): main.phone.open_app("jungleflex"), true)
	_toilet(b, Vector3(26, 0, -11.5))
	var p := _place("Jungle Flex Station (DNC9)", lot, Vector3(0, 0, -3.0))
	station = {"name": p.name, "door": load_point, "curb": p.curb, "load_point": load_point}


# --- Homes ---------------------------------------------------------------------------

func _home(lot: Node3D, id: String, bname: String, size: Vector3, color: Color, setback: float, tower_floors := 0) -> void:
	var b := _shop(lot, bname, size, color, setback)
	if tower_floors > 0:
		var tower_d := 13.0
		var t := Node3D.new()
		t.position = Vector3(0, 0, -(setback + size.z + tower_d / 2.0))
		lot.add_child(t)
		Kit.box(t, Vector3(size.x + 4, tower_floors * 3.2, tower_d), Vector3(0, tower_floors * 1.6, 0), color.darkened(0.1))
		for f in tower_floors:
			Kit.box(t, Vector3(size.x + 2, 1.1, 0.08), Vector3(0, 6.0 + f * 3.2, tower_d / 2.0 + 0.05), Color(0.3, 0.42, 0.55), false)
	var h: Dictionary = GameData.HOMES[id]
	var hw := size.x / 2.0
	var hd := size.z / 2.0
	# Bed
	Kit.box(b, Vector3(2.0, 0.55, 3.0), Vector3(-hw + 1.6, 0.275, -hd + 2.0), Color(0.35, 0.3, 0.6))
	Kit.box(b, Vector3(1.8, 0.2, 0.6), Vector3(-hw + 1.6, 0.65, -hd + 0.9), Color(0.95, 0.95, 0.95))
	Kit.interactable(b, Vector3(-hw + 1.6, 1, -hd + 3.5), 2.0,
		func(): return "Sleep" if Game.home_id == id else "",
		func(): main.sleep_menu(h.sleep_quality))
	_toilet(b, Vector3(hw - 1.2, 0, -hd + 1.0), id)
	# Fridge
	Kit.box(b, Vector3(0.9, 1.9, 0.8), Vector3(hw - 0.8, 0.95, 0.5), Color(0.92, 0.92, 0.95))
	Kit.interactable(b, Vector3(hw - 1.8, 1, 0.5), 1.8,
		func():
			if Game.home_id != id:
				return ""
			if Game.fridge_meals <= 0:
				return "Fridge is empty (buy groceries at a store register)"
			return "Eat from fridge (%d meals left)" % Game.fridge_meals,
		func():
			if Game.home_id == id and Game.fridge_meals > 0:
				Game.fridge_meals -= 1
				Game.eat("a home-cooked meal", 50.0))
	# Couch / TV for flavor
	Kit.box(b, Vector3(2.6, 0.7, 0.9), Vector3(0, 0.35, -hd + 1.0), Color(0.45, 0.3, 0.25))
	# Leasing desk by the door
	Kit.box(b, Vector3(1.4, 1.0, 0.7), Vector3(-hw + 1.4, 0.5, hd - 2.0), Color(0.5, 0.4, 0.3))
	Kit.label(b, "LEASING", Vector3(-hw + 1.4, 1.6, hd - 2.0), 36, Color(1, 1, 0.7), true)
	Kit.interactable(b, Vector3(-hw + 1.4, 1, hd - 3.0), 2.0,
		func(): return "Your lease: %s ($%.0f per %d days)" % [h.short, h.rent, GameData.BILL_CYCLE_DAYS] if Game.home_id == id else "Lease info: " + h.short,
		func(): _lease_menu(id))
	var p := _place(h.short + " (housing)", lot, Vector3(0, 0, -setback + 1.0))
	homes[id] = {"door": p.door, "curb": p.curb,
		"inside": b.to_global(Vector3(0, 1, hd - 3.0)),
		"parking": Transform3D(lot.global_transform.basis * Basis(Vector3.UP, PI / 2.0), _curb(lot) + Vector3(0, 0.8, 0))}


func _lease_menu(id: String) -> void:
	var h: Dictionary = GameData.HOMES[id]
	var opts := []
	if Game.home_id == id:
		opts.append({"text": "You live here. Rent is $%.0f every %d days." % [h.rent, GameData.BILL_CYCLE_DAYS], "cb": func(): pass, "disabled": true})
	else:
		var move_in: float = h.deposit + h.rent
		opts.append({"text": "Sign lease: $%.0f deposit + $%.0f first rent" % [h.deposit, h.rent],
			"cb": func(): Game.sign_lease(id), "disabled": Game.money < move_in})
	main.hud.show_menu("%s\nRent $%.0f / %d days  |  Sleep quality %d%%" % [h.name, h.rent, GameData.BILL_CYCLE_DAYS, h.sleep_quality * 100], opts)
