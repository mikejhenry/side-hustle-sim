class_name TrafficControl
extends Node3D
## Traffic lights at some intersections, red light cameras at a few of those, and speed
## cameras on some streets. AI traffic stops for red lights. Cameras mail you a ticket (no
## cop needed); a cop who sees you run a red light pulls you over. With the upgraded phone,
## cameras show on the minimap and you get a warning when you're heading toward one.

signal ran_red_light(pos: Vector3)

const LIGHTS := [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3), Vector2i(3, 3)]
const RED_CAMERAS := [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3)]
## Speed cameras: [from node, to node, fraction along the street]. One more is on the beltway.
const SPEED_CAMERAS := [[Vector2i(0, 1), Vector2i(1, 1), 0.5], [Vector2i(4, 0), Vector2i(4, 1), 0.55],
	[Vector2i(1, 4), Vector2i(2, 4), 0.45], [Vector2i(3, 0), Vector2i(4, 0), 0.5]]

const GREEN := 14.0
const YELLOW := 3.0
const ALL_RED := 1.5
const CYCLE := (GREEN + YELLOW + ALL_RED) * 2.0
const RED_GRACE := 0.4            # seconds into the red before a camera fires
const SPEED_CAM_SLACK := 10.0     # mph over the limit before a speed camera fires
const RED_FINE := 100.0
const SPEED_CAM_BASE := 80.0
const SPEED_CAM_PER_MPH := 6.0
const WARN_RANGE := 140.0

var town: Node = null
var main: Node = null
var cameras: Array = []           # {kind, pos, axis (Vector3, speed cams), node (red cams), marker, warned}
var _t := 0.0
var _lamps := {}                  # "ns_red" etc. -> StandardMaterial3D
var _shown := ""                  # last lamp state applied
var _inside := {}                 # light node -> player was inside the box last frame
var _cam_side := {}               # speed camera index -> which side of it the player was on


func build() -> void:
	for axis in ["ns", "ew"]:
		for col in ["red", "yellow", "green"]:
			var m := StandardMaterial3D.new()
			m.albedo_color = {"red": Color(1, 0.12, 0.08), "yellow": Color(1, 0.75, 0.1), "green": Color(0.2, 1, 0.35)}[col]
			m.emission_enabled = true
			m.emission = m.albedo_color
			_lamps["%s_%s" % [axis, col]] = m
	for n in LIGHTS:
		_build_light(n, n in RED_CAMERAS)
	for i in SPEED_CAMERAS.size():
		var spec: Array = SPEED_CAMERAS[i]
		var a: Vector3 = _node_pos(spec[0])
		var b: Vector3 = _node_pos(spec[1])
		_build_speed_camera(a.lerp(b, spec[2]), (b - a).normalized())
	# Beltway (west side).
	_build_speed_camera(Vector3(-town.RING, 0, town.B * 2.5), Vector3(0, 0, 1))
	_update_lamps(true)


func _node_pos(n: Vector2i) -> Vector3:
	return Vector3(n.x * town.B, 0, n.y * town.B)


# --- Lights ------------------------------------------------------------------------------

## "green", "yellow" or "red" for traffic moving along `axis` ("ns" = along Z, "ew" = along X).
func color(axis: String) -> String:
	var t := fmod(_t, CYCLE)
	var half := CYCLE / 2.0
	var mine := t if axis == "ns" else fmod(t + half, CYCLE)
	if mine < GREEN:
		return "green"
	if mine < GREEN + YELLOW:
		return "yellow"
	return "red"


## Seconds since this axis turned red (0 if it isn't red).
func red_for(axis: String) -> float:
	var t := fmod(_t, CYCLE)
	var mine := t if axis == "ns" else fmod(t + CYCLE / 2.0, CYCLE)
	return maxf(0.0, mine - GREEN - YELLOW) if mine >= GREEN + YELLOW else 0.0


static func axis_of(d: Vector2i) -> String:
	return "ew" if d.x != 0 else "ns"


func has_light(n: Vector2i) -> bool:
	return n in LIGHTS


## Should a car `left` meters from the stop line, heading in `d`, stop for node `n`?
func must_stop(n: Vector2i, d: Vector2i, left: float) -> bool:
	if not has_light(n):
		return false
	var c := color(axis_of(d))
	# Too close to stop safely on yellow: keep going.
	return c == "red" or (c == "yellow" and left > 9.0)


func _build_light(n: Vector2i, camera: bool) -> void:
	var c := _node_pos(n)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var m: Vector2i = n - d
		if m.x < 0 or m.y < 0 or m.x > town.N or m.y > town.N:
			continue
		var d3 := Vector3(d.x, 0, d.y)
		var r := Traffic.right_of(d3)
		var base := c - d3 * (Traffic.HALF + 1.5)
		var pole_pos: Vector3 = base + r * (town.ROAD_W / 2.0 + 1.3)
		var dark := Color(0.12, 0.13, 0.12)
		Kit.cylinder(self, 0.13, 5.6, pole_pos + Vector3(0, 2.8, 0), dark)
		# Arm out over the lane, head facing oncoming traffic.
		var arm_len: float = town.ROAD_W / 2.0 + 1.3 - Traffic.LANE
		var arm := Kit.box(self, Vector3(0.1, 0.1, arm_len), base + r * (Traffic.LANE + arm_len / 2.0) + Vector3(0, 5.5, 0), dark, false)
		arm.look_at(arm.global_position + d3, Vector3.UP)
		arm.rotate_y(PI / 2.0)
		var head := Node3D.new()
		add_child(head)
		head.position = base + r * Traffic.LANE + Vector3(0, 4.9, 0)
		head.look_at(head.position + d3, Vector3.UP)   # -Z toward... faces along travel, lamps on +Z side
		Kit.box(head, Vector3(0.4, 1.15, 0.3), Vector3.ZERO, dark, false)
		var axis := axis_of(d)
		var cols := ["red", "yellow", "green"]
		for i in 3:
			Kit.sphere(head, 0.13, Vector3(0, 0.36 - i * 0.36, 0.14), _lamps["%s_%s" % [axis, cols[i]]])
		if camera:
			Kit.box(self, Vector3(0.35, 0.3, 0.55), pole_pos + Vector3(0, 4.2, 0) - d3 * 0.3, Color(0.2, 0.2, 0.22), false)
			Kit.label(self, "PHOTO\nENFORCED", pole_pos + Vector3(0, 2.6, 0) - d3 * 0.2, 28, Color(1, 1, 1), true)
	if camera:
		cameras.append({"kind": "red", "pos": c, "node": n, "marker": _marker(c, "RED\nCAM"), "warned": false})


func _update_lamps(force := false) -> void:
	var state := "%s/%s" % [color("ns"), color("ew")]
	if state == _shown and not force:
		return
	_shown = state
	for axis in ["ns", "ew"]:
		var on := color(axis)
		for col in ["red", "yellow", "green"]:
			var m: StandardMaterial3D = _lamps["%s_%s" % [axis, col]]
			m.emission_energy_multiplier = 3.0 if col == on else 0.0
			m.albedo_color = m.emission if col == on else m.emission.darkened(0.75)


# --- Speed cameras ---------------------------------------------------------------------

func _build_speed_camera(pos: Vector3, along: Vector3) -> void:
	var r := Traffic.right_of(along)
	var side: Vector3 = pos + r * (town.ROAD_W / 2.0 + 1.5)
	Kit.cylinder(self, 0.1, 3.2, side + Vector3(0, 1.6, 0), Color(0.6, 0.6, 0.62))
	var cam := Kit.box(self, Vector3(0.45, 0.4, 0.7), side + Vector3(0, 3.3, 0), Color(0.85, 0.75, 0.15), false)
	cam.look_at(cam.global_position - along, Vector3.UP)
	Kit.box(self, Vector3(1.0, 0.7, 0.05), side + Vector3(0, 2.1, 0) - along * 0.15, Color(1, 1, 1), false)
	var plate := Kit.label(self, "SPEED\nPHOTO\nENFORCED", side + Vector3(0, 2.1, 0) - along * 0.2, 22, Color(0.05, 0.05, 0.05))
	plate.look_at(plate.global_position + along, Vector3.UP)
	plate.outline_size = 0
	cameras.append({"kind": "speed", "pos": pos, "axis": along, "marker": _marker(pos, "SPEED\nCAM"), "warned": false})


## Minimap badge (render layer 2), only shown with the upgraded phone.
func _marker(pos: Vector3, text: String) -> Node3D:
	var m := Node3D.new()
	add_child(m)
	m.position = Vector3(pos.x, 98.5, pos.z)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 5.0
	cm.bottom_radius = 5.0
	cm.height = 0.5
	cm.radial_segments = 6
	disc.mesh = cm
	disc.material_override = Kit.mat(Color(1, 0.4, 0.05), 0.5)
	disc.layers = 2
	m.add_child(disc)
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.06
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position.y = 1.0
	l.layers = 2
	m.add_child(l)
	m.visible = false
	return m


# --- Player checks -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	_update_lamps()
	if main == null:
		return
	for cam in cameras:
		cam.marker.visible = Game.phone_pro
	if not main.is_driving():
		return
	var car: Node3D = main.car
	var p: Vector3 = car.global_position
	var v: Vector3 = car.linear_velocity
	v.y = 0.0
	_check_red_lights(p, v)
	_check_speed_cameras(p, v)
	if Game.phone_pro:
		_warn(p, v)


func _check_red_lights(p: Vector3, v: Vector3) -> void:
	for n in LIGHTS:
		var rel := p - _node_pos(n)
		var inside := absf(rel.x) < Traffic.HALF - 1.0 and absf(rel.z) < Traffic.HALF - 1.0
		var was: bool = _inside.get(n, false)
		_inside[n] = inside
		if not inside or was or v.length() < 2.0:
			continue
		var axis := "ew" if absf(v.x) > absf(v.z) else "ns"
		if red_for(axis) <= RED_GRACE:
			continue
		ran_red_light.emit(p)
		if n in RED_CAMERAS:
			_camera_ticket("running a red light (camera)", RED_FINE)


func _check_speed_cameras(p: Vector3, v: Vector3) -> void:
	for i in cameras.size():
		var cam: Dictionary = cameras[i]
		if cam.kind != "speed":
			continue
		var rel: Vector3 = p - cam.pos
		rel.y = 0.0
		var along: Vector3 = cam.axis
		var s := signf(rel.dot(along))
		var near := absf(rel.dot(Traffic.right_of(along))) < 12.0 and absf(rel.dot(along)) < 20.0
		var prev: float = _cam_side.get(i, s)
		_cam_side[i] = s
		if not near or s == prev or s == 0.0:
			continue
		var mph := v.length() * 2.237
		var limit: float = main.traffic.speed_limit(p) if main.traffic else GameData.SPEED_LIMIT
		if mph > limit + SPEED_CAM_SLACK:
			_camera_ticket("speeding, %d in a %d (camera)" % [int(mph), int(limit)],
				SPEED_CAM_BASE + SPEED_CAM_PER_MPH * roundf(mph - limit))


func _camera_ticket(reason: String, amount: float) -> void:
	Game.mail_ticket(reason, amount)
	Sfx.play(self, "shutter", -2.0)
	if main and main.hud:
		main.hud.flash()


## Upgraded phone: "camera ahead" warning once per approach.
func _warn(p: Vector3, v: Vector3) -> void:
	for cam in cameras:
		var rel: Vector3 = cam.pos - p
		rel.y = 0.0
		var d := rel.length()
		if d > WARN_RANGE * 1.5:
			cam.warned = false
		elif not cam.warned and d < WARN_RANGE and v.length() > 3.0 and rel.normalized().dot(v.normalized()) > 0.7:
			cam.warned = true
			if cam.kind == "speed":
				Game.notify("Wayz: speed camera ahead, %d m. Limit %d." % [int(d), int(main.traffic.speed_limit(cam.pos))], "warn")
			else:
				Game.notify("Wayz: red light camera ahead, %d m." % int(d), "warn")
