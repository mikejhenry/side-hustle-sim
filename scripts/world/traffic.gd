class_name Traffic
extends Node3D
## AI traffic. Cars drive the street grid in the right-hand lane, pick a random turn at each
## intersection, slow down for corners, and brake for anything ahead of them (you, your car,
## or other traffic). They are kinematic bodies, so you can still crash into them.
##
## A few of them are police. A cop only notices you when you're inside its field of view
## (ahead and to the sides, not behind) with a clear line of sight. Speeding or crashing in
## front of one starts a chase: it follows the GPS route to you, lights flashing, until you
## stop (ticket) or get far enough away for long enough (escaped).

signal chase_started(reason: String)
signal chase_ended(result: String)

const COUNT := 14
const COP_COUNT := 3
const SIGHT_RANGE := 55.0     # meters a cop can see
const SIGHT_COS := 0.3        # field of view: about 145 degrees wide
const CHASE_SPEED := 23.0     # ~51 mph
const LANE := 3.5          # lane center, meters right of the road center line
const HALF := 9.0          # where the intersection box starts, meters from its center
const CRUISE := 11.0       # ~25 mph
const TURN_SPEED := 5.0
const ACCEL := 3.0
const BRAKE := 9.0
const LOOK_AHEAD := 16.0
const PAINT := [Color(0.75, 0.77, 0.8), Color(0.1, 0.1, 0.12), Color(0.85, 0.85, 0.86),
	Color(0.55, 0.08, 0.08), Color(0.12, 0.22, 0.45), Color(0.3, 0.32, 0.3), Color(0.8, 0.7, 0.5),
	Color(0.15, 0.35, 0.2)]

var town: Node = null
var main: Node = null
var cars: Array = []
var cops: Array = []
var police_enabled := true
var chaser: AICar = null       # the cop chasing you, if any
var chase_reason := ""
var chase_time := 0.0
var _excess_mph := 0.0         # worst speeding seen by the cop who started the chase
var _speeding_seen := 0.0      # seconds a cop has watched you speed
var _stopped_time := 0.0
var _lost_time := 0.0
var _grace := 0.0              # after a ticket, cops leave you alone for a bit
var _rng := RandomNumberGenerator.new()


func build() -> void:
	_rng.seed = 911
	var avoid: Vector3 = main.actor_position() if main else Vector3.ZERO
	var tries := 0
	while cars.size() < COUNT and tries < 400:
		tries += 1
		var node := Vector2i(_rng.randi_range(0, town.N), _rng.randi_range(0, town.N))
		var dirs := _exits(node, Vector2i.ZERO)
		var d: Vector2i = dirs[_rng.randi() % dirs.size()]
		var car := AICar.new()
		car.traffic = self
		add_child(car)
		car.setup(_random_data(), node, d, _rng.randf_range(0.1, 0.8))
		if car.global_position.distance_to(avoid) < 30.0 or _too_close(car):
			cars.erase(car)
			car.queue_free()
			continue
		cars.append(car)
	_spawn_cops(avoid)
	if main and main.car:
		main.car.crashed.connect(_on_player_crash)


func _spawn_cops(avoid: Vector3) -> void:
	var tries := 0
	while cops.size() < COP_COUNT and tries < 300:
		tries += 1
		var node := Vector2i(_rng.randi_range(0, town.N), _rng.randi_range(0, town.N))
		var dirs := _exits(node, Vector2i.ZERO)
		var d: Vector2i = dirs[_rng.randi() % dirs.size()]
		var car := AICar.new()
		car.traffic = self
		car.is_cop = true
		add_child(car)
		var data := {"size": Vector3(1.85, 0.75, 4.6), "color": Color(0.08, 0.09, 0.12)}
		if ResourceLoader.exists("res://assets/quaternius/Cop.fbx"):
			data = {"size": Vector3(2.0, 1.4, 4.4), "model": "Cop"}
		car.setup(data, node, d, _rng.randf_range(0.1, 0.8))
		if car.global_position.distance_to(avoid) < 70.0 or _too_close(car):
			car.queue_free()
			continue
		cars.append(car)
		cops.append(car)


func _too_close(car: Node3D) -> bool:
	for c in cars:
		if c != car and c.global_position.distance_to(car.global_position) < 12.0:
			return true
	return false


## Quaternius car models (CC0) used for part of the traffic when the files are present.
const QUATERNIUS_CARS := ["NormalCar1", "NormalCar2", "SUV", "SportsCar", "Taxi"]


func _random_data() -> Dictionary:
	var keys: Array = GameData.CARS.keys()
	var base: Dictionary = GameData.CARS[keys[_rng.randi() % keys.size()]]
	var data := {"size": base.size, "color": PAINT[_rng.randi() % PAINT.size()]}
	var have := []
	for n in QUATERNIUS_CARS:
		if ResourceLoader.exists("res://assets/quaternius/%s.fbx" % n):
			have.append(n)
	# These models make up about half the traffic.
	if not have.is_empty() and _rng.randf() < 0.5:
		data["model"] = have[_rng.randi() % have.size()]
		data["size"] = Vector3(2.0, 1.4, 4.4)
	return data


func node_pos(n: Vector2i) -> Vector3:
	return Vector3(n.x * town.B, 0, n.y * town.B)


## Directions you can leave an intersection by, never straight back the way you came.
func _exits(n: Vector2i, came: Vector2i) -> Array:
	var out := []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var m: Vector2i = n + d
		if m.x < 0 or m.y < 0 or m.x > town.N or m.y > town.N:
			continue
		if d == -came and came != Vector2i.ZERO:
			continue
		out.append(d)
	return out


func pick_exit(n: Vector2i, came: Vector2i) -> Vector2i:
	var opts := _exits(n, came)
	if opts.is_empty():
		return -came
	# Going straight is a bit more common than turning.
	if came in opts and _rng.randf() < 0.45:
		return came
	return opts[_rng.randi() % opts.size()]


## Things a car must not drive into, as [position, is_ai_car]: you, your car, other traffic.
func obstacles(except: Node) -> Array:
	var out := []
	if main:
		out.append([main.car.global_position, false])
		if not main.is_driving():
			out.append([main.player.global_position, false])
	for c in cars:
		if c != except:
			out.append([c.global_position, true])
	return out


static func right_of(d: Vector3) -> Vector3:
	return Vector3(-d.z, 0, d.x)


## Speed limit in mph where you are: 30 in town, 45 on the beltway around it.
func speed_limit(p: Vector3) -> float:
	var size: float = town.N * town.B
	var inside := p.x > -20.0 and p.z > -20.0 and p.x < size + 20.0 and p.z < size + 20.0
	return GameData.SPEED_LIMIT if inside else GameData.BELTWAY_LIMIT


# --- Police ----------------------------------------------------------------------------

## True when this cop can see `target`: in range, inside its field of view, nothing in between.
func cop_sees(cop: Node3D, target: Vector3, ignore: Array) -> bool:
	var rel := target - cop.global_position
	rel.y = 0.0
	var dist := rel.length()
	if dist > SIGHT_RANGE or dist < 0.1:
		return false
	if rel.normalized().dot(cop.global_basis.z) < SIGHT_COS:
		return false
	var q := PhysicsRayQueryParameters3D.create(cop.global_position + Vector3(0, 1.4, 0), target + Vector3(0, 1.0, 0))
	q.exclude = ignore
	return cop.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _physics_process(delta: float) -> void:
	if main == null or not police_enabled:
		return
	_grace = maxf(0.0, _grace - delta)
	if chaser:
		_update_chase(delta)
		return
	if _grace > 0.0 or not main.is_driving():
		_speeding_seen = 0.0
		return
	var car: Node3D = main.car
	var over: float = main.car.speed_mph() - speed_limit(car.global_position)
	if over < GameData.TICKET_SLACK:
		_speeding_seen = maxf(0.0, _speeding_seen - delta)
		return
	for cop in cops:
		if cop.mode == "patrol" and cop_sees(cop, car.global_position, [cop.get_rid(), main.car.get_rid()]):
			_speeding_seen += delta
			_excess_mph = maxf(_excess_mph, over)
			# A short look is enough, but not a single frame.
			if _speeding_seen > 0.4:
				start_chase(cop, "speeding (%d in a %d)" % [int(main.car.speed_mph()), int(speed_limit(car.global_position))])
			return


func _on_player_crash(_strength: float) -> void:
	if chaser or _grace > 0.0 or not police_enabled or not main.is_driving():
		return
	for cop in cops:
		if cop.mode == "patrol" and cop_sees(cop, main.car.global_position, [cop.get_rid(), main.car.get_rid()]):
			start_chase(cop, "reckless driving")
			return


## A cop who sees you run a red light pulls you over (cameras are handled separately).
func on_ran_red_light(p: Vector3) -> void:
	if chaser or _grace > 0.0 or not police_enabled or not main.is_driving():
		return
	for cop in cops:
		if cop.mode == "patrol" and cop_sees(cop, p, [cop.get_rid(), main.car.get_rid()]):
			start_chase(cop, "running a red light")
			return


func start_chase(cop: AICar, reason: String) -> void:
	chaser = cop
	chase_reason = reason
	chase_time = 0.0
	_stopped_time = 0.0
	_lost_time = 0.0
	_speeding_seen = 0.0
	cop.begin_chase()
	Game.notify("Police lights behind you! Pull over and stop.", "bad")
	chase_started.emit(reason)


func _update_chase(delta: float) -> void:
	chase_time += delta
	var target: Vector3 = main.actor_position()
	var dist := chaser.global_position.distance_to(target)
	var stopped: bool = not main.is_driving() or main.car.speed_mph() < 3.0
	if dist < 20.0 and stopped:
		_stopped_time += delta
		if _stopped_time > 2.0:
			_write_ticket()
			return
	else:
		_stopped_time = 0.0
	var sees := cop_sees(chaser, target, [chaser.get_rid(), main.car.get_rid()]) or dist < 25.0
	if dist > 160.0 or (not sees and dist > 90.0):
		_lost_time += delta
		if _lost_time > 8.0:
			_end_chase("escaped")
			Game.notify("You lost the cops. For now.", "warn")
	else:
		_lost_time = 0.0


func _write_ticket() -> void:
	var fine: float
	if chase_reason == "reckless driving":
		fine = GameData.RECKLESS_FINE
	elif chase_reason == "running a red light":
		fine = GameData.RED_LIGHT_FINE
	else:
		fine = GameData.TICKET_BASE + GameData.TICKET_PER_MPH * roundf(_excess_mph)
	var reason := chase_reason
	if chase_time > 25.0:
		fine += GameData.EVADING_FINE
		reason += " + failure to stop"
	Game.advance(10.0)
	Game.ticket(reason, fine)
	_grace = 45.0
	_end_chase("ticket")


func _end_chase(result: String) -> void:
	if chaser:
		chaser.end_chase()
	chaser = null
	_excess_mph = 0.0
	chase_ended.emit(result)


## Nearest lane start for a cop to rejoin traffic from: [node, direction, point].
func lane_entry(p: Vector3) -> Array:
	var n := Vector2i(clampi(roundi(p.x / town.B), 0, town.N), clampi(roundi(p.z / town.B), 0, town.N))
	var best: Array = []
	var best_d := INF
	for d in _exits(n, Vector2i.ZERO):
		var d3 := Vector3(d.x, 0, d.y)
		var q := node_pos(n) + d3 * HALF + right_of(d3) * LANE
		var dist := q.distance_to(p)
		if dist < best_d:
			best_d = dist
			best = [n, d, q]
	return best


class AICar:
	extends AnimatableBody3D

	var traffic: Traffic
	var speed := 0.0
	var waited := 0.0
	var _creep := 0.0        # seconds left ignoring other AI cars (breaks intersection standoffs)
	var _node_from: Vector2i
	var _dir: Vector2i
	var _legs: Array = []     # each leg: [p0, control, p1, length, is_turn, is_road_segment]
	var _s := 0.0             # distance travelled along the current leg
	var _wheels: Array = []
	# Police only
	var is_cop := false
	var mode := "patrol"      # patrol (normal traffic), chase, return (driving back to a lane)
	var marker: Node3D        # minimap badge, shown with the upgraded phone
	var _path := PackedVector3Array()
	var _path_i := 0
	var _repath := 0.0
	var _rejoin: Array = []
	var _bar: Array = []      # [red material, blue material]
	var _flash: OmniLight3D
	var _flash_t := 0.0
	var _siren: AudioStreamPlayer3D

	func setup(data: Dictionary, node: Vector2i, d: Vector2i, start_frac: float) -> void:
		sync_to_physics = false
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var size: Vector3 = data.size
		box.size = Vector3(size.x, 1.2, size.z)
		col.shape = box
		col.position.y = 0.85
		add_child(col)
		var model: Node3D
		if data.has("model"):
			model = load("res://assets/quaternius/%s.fbx" % data.model).instantiate()
			model.scale = Vector3.ONE * 1.18
		else:
			model = CarModel.build(data, false, true)
		add_child(model)
		for c in model.get_children():
			if c.get_child_count() > 0 and c.get_child(0) is MeshInstance3D and (c.get_child(0) as MeshInstance3D).mesh is CylinderMesh:
				_wheels.append(c)
		_node_from = node
		_dir = d
		_queue_straight()
		_s = _legs[0][3] * start_frac
		_apply_pose()
		if is_cop:
			_build_police_gear(model)


	func _build_police_gear(model: Node3D) -> void:
		# Light bar on the roof, at the top of whichever model this is.
		var top := 1.5
		var inv := global_transform.affine_inverse()
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = inv * (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			top = maxf(top, box.end.y) if box.end.y < 3.0 else top
		for i in 2:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.9, 0.1, 0.1) if i == 0 else Color(0.1, 0.25, 1.0)
			m.emission_enabled = true
			m.emission = m.albedo_color
			m.emission_energy_multiplier = 0.3
			var bar := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.55, 0.14, 0.24)
			bar.mesh = bm
			bar.material_override = m
			bar.position = Vector3(0.3 if i == 0 else -0.3, top + 0.07, -0.2)
			add_child(bar)
			_bar.append(m)
		_flash = OmniLight3D.new()
		_flash.position = Vector3(0, top + 0.5, -0.2)
		_flash.omni_range = 10.0
		_flash.light_energy = 2.5
		_flash.visible = false
		add_child(_flash)
		_siren = AudioStreamPlayer3D.new()
		_siren.stream = Sfx.get_stream("siren")
		_siren.unit_size = 18.0
		_siren.max_distance = 300.0
		_siren.volume_db = -6.0
		_siren.position.y = top
		add_child(_siren)
		# Minimap badge (render layer 2 is only seen by the minimap camera).
		marker = Node3D.new()
		marker.top_level = true
		add_child(marker)
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 4.5
		cm.bottom_radius = 4.5
		cm.height = 0.5
		cm.radial_segments = 16
		disc.mesh = cm
		disc.material_override = Kit.mat(Color(0.15, 0.35, 1.0), 2.0)
		disc.layers = 2
		marker.add_child(disc)
		var lbl := Label3D.new()
		lbl.text = "COP"
		lbl.font_size = 64
		lbl.pixel_size = 0.06
		lbl.outline_size = 12
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0, 1.0, 0)
		lbl.layers = 2
		marker.add_child(lbl)

	func _update_police_gear(delta: float) -> void:
		marker.visible = Game.phone_pro
		marker.global_position = Vector3(global_position.x, 99.0, global_position.z)
		var chasing := mode == "chase"
		_flash.visible = chasing
		if chasing:
			_flash_t += delta
			var red := fmod(_flash_t, 0.5) < 0.25
			(_bar[0] as StandardMaterial3D).emission_energy_multiplier = 6.0 if red else 0.2
			(_bar[1] as StandardMaterial3D).emission_energy_multiplier = 0.2 if red else 6.0
			_flash.light_color = Color(1, 0.1, 0.1) if red else Color(0.2, 0.3, 1)
			var disc := marker.get_child(0) as MeshInstance3D
			disc.material_override = Kit.mat(Color(1, 0.1, 0.1) if red else Color(0.15, 0.35, 1.0), 2.0)

	func begin_chase() -> void:
		mode = "chase"
		_repath = 0.0
		_siren.play()

	func end_chase() -> void:
		mode = "return"
		_siren.stop()
		for i in 2:
			(_bar[i] as StandardMaterial3D).emission_energy_multiplier = 0.3
		(marker.get_child(0) as MeshInstance3D).material_override = Kit.mat(Color(0.15, 0.35, 1.0), 2.0)
		_rejoin = traffic.lane_entry(global_position)
		_path = traffic.main.gps._compute_route(global_position, _rejoin[2])
		_path_i = 1

	## Free driving (not on a lane): turn toward `aim` at a limited rate and move forward.
	func _steer_toward(aim: Vector3, want: float, delta: float) -> void:
		var to := aim - global_position
		to.y = 0.0
		var fwd := global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var ang := 0.0
		if to.length() > 0.5:
			ang = fwd.signed_angle_to(to.normalized(), Vector3.UP)
		var rate := 1.9 * clampf(speed / 5.0, 0.4, 1.0) * delta
		var yaw := atan2(fwd.x, fwd.z) + clampf(ang, -rate, rate)
		want *= clampf(1.0 - absf(ang) / 1.5, 0.3, 1.0)
		speed = move_toward(speed, want, (Traffic.ACCEL * 2.5 if want > speed else Traffic.BRAKE * 1.5) * delta)
		var nf := Vector3(sin(yaw), 0, cos(yaw))
		var pos := global_position + nf * speed * delta
		pos.y = 0.0
		global_transform = Transform3D(Basis(Vector3.UP.cross(nf).normalized(), Vector3.UP, nf), pos)

	func _next_path_point(reach: float) -> Vector3:
		while _path_i < _path.size() - 1 and global_position.distance_to(_path[_path_i]) < reach:
			_path_i += 1
		return _path[mini(_path_i, _path.size() - 1)]

	func _chase(delta: float) -> void:
		var target: Vector3 = traffic.main.actor_position()
		var dist := global_position.distance_to(target)
		_repath -= delta
		if _repath <= 0.0:
			_repath = 1.0
			_path = traffic.main.gps._compute_route(global_position, target)
			_path_i = 1
		var aim := target if dist < 30.0 else _next_path_point(7.0)
		# Pull up behind you and stop there.
		_steer_toward(aim, minf(Traffic.CHASE_SPEED, maxf(0.0, (dist - 9.0) * 1.2)), delta)

	func _return_to_lane(delta: float) -> void:
		var end: Vector3 = _rejoin[2]
		_creep = maxf(0.0, _creep - delta)
		var want := minf(Traffic.CRUISE, _gap_speed(Traffic.CRUISE))
		# Traffic queued at a light can block the way back; nudge past it.
		if speed < 0.3 and want < 0.5:
			waited += delta
			if waited > 3.0:
				_creep = 2.5
				waited = 0.0
		else:
			waited = 0.0
		if global_position.distance_to(end) < 3.0:
			_legs.clear()
			_node_from = _rejoin[0]
			_dir = _rejoin[1]
			_queue_straight()
			_s = 0.0
			mode = "patrol"
			_apply_pose()
			return
		_steer_toward(_next_path_point(5.0), want, delta)

	## Target speed after braking for anything in the lane ahead.
	func _gap_speed(target: float) -> float:
		var fwd := global_basis.z
		var right := Traffic.right_of(fwd)
		var gap := INF
		for o in traffic.obstacles(self):
			if o[1] and _creep > 0.0:
				continue
			var rel: Vector3 = o[0] - global_position
			rel.y = 0.0
			var ahead := rel.dot(fwd)
			if ahead > 0.0 and ahead < Traffic.LOOK_AHEAD and absf(rel.dot(right)) < 2.4:
				gap = minf(gap, ahead)
		if gap < INF:
			return minf(target, maxf(0.0, (gap - 6.5) * 1.2))
		return target

	func _queue_straight() -> void:
		var a := traffic.node_pos(_node_from)
		var d3 := Vector3(_dir.x, 0, _dir.y)
		var r := Traffic.right_of(d3)
		var b := traffic.node_pos(_node_from + _dir)
		var p0 := a + d3 * Traffic.HALF + r * Traffic.LANE
		var p1 := b - d3 * Traffic.HALF + r * Traffic.LANE
		_legs.append([p0, (p0 + p1) / 2.0, p1, p0.distance_to(p1), false, true])

	func _queue_turn() -> void:
		var n := _node_from + _dir
		var came := _dir
		var nd := traffic.pick_exit(n, came)
		var c := traffic.node_pos(n)
		var d1 := Vector3(came.x, 0, came.y)
		var d2 := Vector3(nd.x, 0, nd.y)
		var r1 := Traffic.right_of(d1)
		var r2 := Traffic.right_of(d2)
		var p0 := c - d1 * Traffic.HALF + r1 * Traffic.LANE
		var p1 := c + d2 * Traffic.HALF + r2 * Traffic.LANE
		var ctrl := (p0 + p1) / 2.0 if nd == came else c + (r1 + r2) * Traffic.LANE
		var length := p0.distance_to(ctrl) + ctrl.distance_to(p1)
		_legs.append([p0, ctrl, p1, length * 0.9, nd != came, false])
		_node_from = n
		_dir = nd

	func _point(leg: Array, t: float) -> Vector3:
		var p0: Vector3 = leg[0]
		var c: Vector3 = leg[1]
		var p1: Vector3 = leg[2]
		return p0.lerp(c, t).lerp(c.lerp(p1, t), t)

	func _apply_pose() -> void:
		var leg: Array = _legs[0]
		var t := clampf(_s / float(leg[3]), 0.0, 1.0)
		var p := _point(leg, t)
		var ahead := _point(leg, minf(t + 0.02, 1.0))
		var fwd := ahead - p
		if t >= 0.98:
			var p0: Vector3 = leg[0]
			var p1: Vector3 = leg[2]
			fwd = p1 - _point(leg, 0.96) if leg[4] else p1 - p0
		fwd.y = 0.0
		if fwd.length() < 0.001:
			fwd = Vector3(_dir.x, 0, _dir.y)
		fwd = fwd.normalized()
		# Car models face +Z.
		var basis := Basis(Vector3.UP.cross(fwd).normalized(), Vector3.UP, fwd)
		global_transform = Transform3D(basis, p)

	func _physics_process(delta: float) -> void:
		if is_cop:
			_update_police_gear(delta)
			if mode == "chase":
				_chase(delta)
				return
			if mode == "return":
				_return_to_lane(delta)
				return
		var leg: Array = _legs[0]
		var target := Traffic.TURN_SPEED if leg[4] else Traffic.CRUISE
		# Ease off before a corner.
		if not leg[4]:
			var left := float(leg[3]) - _s
			if left < 14.0:
				target = lerpf(Traffic.TURN_SPEED + 2.0, Traffic.CRUISE, left / 14.0)
		# Brake for anything ahead in our lane.
		_creep = maxf(0.0, _creep - delta)
		target = _gap_speed(target)
		# Stop for red lights (and yellows we can still stop for).
		if leg[5]:
			var to_line := float(leg[3]) - _s
			var tc: TrafficControl = traffic.main.traffic_control if traffic.main else null
			if tc and to_line < 45.0 and tc.must_stop(_node_from + _dir, _dir, to_line):
				# Brake smoothly so we stop about 2 m before the line.
				target = 0.0 if to_line < 2.0 else minf(target, sqrt(2.0 * Traffic.BRAKE * 0.7 * (to_line - 2.0)) + 0.3)
		if speed < 0.3 and target < 0.5:
			waited += delta
			# Two AI cars blocking each other would wait forever, so one creeps through.
			if waited > 4.0 + randf() * 2.0:
				_creep = 2.5
				waited = 0.0
		else:
			waited = 0.0
		var rate := Traffic.ACCEL if target > speed else Traffic.BRAKE
		speed = move_toward(speed, target, rate * delta)
		_s += speed * delta
		while _s >= float(_legs[0][3]):
			_s -= float(_legs[0][3])
			var done: Array = _legs.pop_front()
			# After a road segment comes an intersection, and after an intersection a road.
			if done[5]:
				_queue_turn()
			else:
				_queue_straight()
		_apply_pose()
		for w in _wheels:
			w.rotation.x += speed * delta / CarModel.WHEEL_R
