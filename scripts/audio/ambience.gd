class_name Ambience
extends Node
## Background sound that changes with where you are and the time of day. The town is split
## into districts (downtown, campus, the park, suburbs, the port, the beltway, the Route 40
## strip), and each mixes a few looping layers: city rumble, crowd chatter, songbirds,
## crickets at night, port machinery, highway roar and wind. Moving between districts
## crossfades smoothly. Everything is quieter from inside the car or a building.
##
## Like Sfx, every sound is synthesized in code (no audio files). The loops take a moment
## to build, so that happens on a worker thread at startup.

const RATE := 22050
const LAYERS := ["city", "crowd", "birds", "crickets", "port", "highway", "wind"]
const GAIN_DB := {"city": -17.0, "crowd": -20.0, "birds": -19.0, "crickets": -24.0, "port": -16.0,
	"highway": -15.0, "wind": -24.0}

## Daytime mix for each district (0..1 per layer). Night and weather adjust it.
const MIX := {
	"downtown": {"city": 1.0, "crowd": 0.6, "birds": 0.1, "wind": 0.15},
	"campus": {"city": 0.3, "crowd": 0.85, "birds": 0.45, "wind": 0.2},
	"park": {"city": 0.25, "crowd": 0.2, "birds": 1.0, "wind": 0.45},
	"suburbs": {"city": 0.15, "birds": 0.75, "wind": 0.35},
	"port": {"city": 0.25, "port": 1.0, "wind": 0.5},
	"highway": {"highway": 1.0, "wind": 0.35},
	"strip": {"city": 0.7, "crowd": 0.35, "highway": 0.35, "wind": 0.2},
	"outskirts": {"city": 0.1, "birds": 0.5, "wind": 0.6, "highway": 0.2},
}
const NAMES := {"downtown": "Downtown Wilmingtown", "campus": "University of Delawhere", "park": "Rodknee Square",
	"suburbs": "the suburbs", "port": "the port district", "highway": "the I-95 Beltway", "strip": "the Route 40 strip",
	"outskirts": "the edge of town"}

static var _cache := {}

var town: Node = null
var main: Node = null
var district := "suburbs"
var weights := {}            # layer -> current 0..1 (smoothed)
var indoors := false
var _players := {}
var _task := -1
var _built := {}
var _roof_t := 0.0


## A cached one-shot or loop by name (also used for the pigeons' flutter).
static func stream(sound_name: String) -> AudioStreamWAV:
	if not _cache.has(sound_name):
		_cache[sound_name] = _build(sound_name)
	return _cache[sound_name]


func _ready() -> void:
	for l in LAYERS:
		weights[l] = 0.0
	var missing := LAYERS.filter(func(l): return not _cache.has(l))
	if missing.is_empty():
		_start_players()
	else:
		_task = WorkerThreadPool.add_task(func():
			for l in missing:
				_built[l] = _build(l))


func ready_to_play() -> bool:
	return not _players.is_empty()


func _start_players() -> void:
	for l in LAYERS:
		var p := AudioStreamPlayer.new()
		p.stream = stream(l)
		p.volume_db = -80.0
		add_child(p)
		# Start each loop somewhere different so layers don't line up.
		p.play(randf() * 3.0)
		_players[l] = p


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _process(delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		for l in _built:
			_cache[l] = _built[l]
		_start_players()
	if main == null or town == null:
		return
	var p: Vector3 = main.actor_position()
	district = district_at(p)
	_roof_t -= delta
	if _roof_t <= 0.0:
		_roof_t = 0.5
		indoors = _under_roof()
	var target := mix_at(p, Game.minute, Game.weather if Game.weather_amount > 0.3 else "clear")
	var muffle := 1.0
	if main.is_driving():
		muffle = 0.45
	elif indoors:
		muffle = 0.3
	for l in LAYERS:
		weights[l] = move_toward(weights[l], target.get(l, 0.0) * muffle, delta * 0.6)
		if _players.has(l):
			var w: float = weights[l]
			_players[l].volume_db = GAIN_DB[l] + linear_to_db(w) if w > 0.005 else -80.0


func district_name() -> String:
	return NAMES.get(district, district)


func district_at(p: Vector3) -> String:
	var B: float = town.B
	var N: int = town.N
	var size := N * B
	var lo: float = -town.RING
	var hi: float = size + town.RING
	if p.x > hi + 15.0:
		return "strip"
	var near_ring := ((absf(p.x - lo) < 14.0 or absf(p.x - hi) < 14.0) and p.z > lo - 14.0 and p.z < hi + 14.0) \
		or ((absf(p.z - lo) < 14.0 or absf(p.z - hi) < 14.0) and p.x > lo - 14.0 and p.x < hi + 14.0)
	if near_ring:
		return "highway"
	if p.x < -8.0 or p.z < -8.0 or p.x > size + 8.0 or p.z > size + 8.0:
		return "outskirts"
	var b := Vector2i(clampi(floori(p.x / B), 0, N - 1), clampi(floori(p.z / B), 0, N - 1))
	if b == Vector2i(2, 1):
		return "park"
	if b.x == 0 and b.y in [1, 2]:
		return "campus"
	if b.x == 4 and b.y >= 3:
		return "port"
	if b.x >= 1 and b.x <= 3 and b.y >= 2 and b.y <= 3:
		return "downtown"
	return "suburbs"


## The layer mix for a spot, time and weather. Averages a few nearby points so district
## edges blend instead of switching.
func mix_at(p: Vector3, minute: float, weather := "clear") -> Dictionary:
	var out := {}
	var pts := [p, p + Vector3(25, 0, 0), p + Vector3(-25, 0, 0), p + Vector3(0, 0, 25), p + Vector3(0, 0, -25)]
	for q in pts:
		var m: Dictionary = MIX[district_at(q)]
		for l in m:
			out[l] = out.get(l, 0.0) + m[l] / pts.size()
	# Day (1) to night (0), easing through dawn and dusk.
	var h := minute / 60.0
	var day := clampf(minf(h - 5.0, 21.0 - h), 0.0, 1.0)
	var birds: float = out.get("birds", 0.0)
	out["birds"] = birds * day * (1.4 if h > 5.0 and h < 8.0 else 1.0)   # dawn chorus
	out["crickets"] = (birds + 0.2) * (1.0 - day)
	out["crowd"] = out.get("crowd", 0.0) * lerpf(0.25, 1.0, day)
	out["city"] = out.get("city", 0.0) * lerpf(0.55, 1.0, day)
	out["port"] = out.get("port", 0.0) * lerpf(0.6, 1.0, day)
	if weather in ["rain", "storm", "snow"]:
		out["birds"] *= 0.15
		out["crickets"] *= 0.2
		out["crowd"] *= 0.5
		out["wind"] = out.get("wind", 0.0) + 0.3
	for l in out:
		out[l] = clampf(out[l], 0.0, 1.0)
	return out


## Something solid overhead: you're in a building (or under the gas station canopy).
func _under_roof() -> bool:
	if main.is_driving() or not main.player.is_inside_tree():
		return false
	var from: Vector3 = main.player.global_position + Vector3(0, 1.8, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 12, 0))
	q.exclude = [main.player.get_rid()]
	return not main.player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- Synthesis ---------------------------------------------------------------------------

static func _build(sound_name: String) -> AudioStreamWAV:
	match sound_name:
		"city": return _wav(_city(), true)
		"crowd": return _wav(_crowd(), true)
		"birds": return _wav(_birds(), true)
		"crickets": return _wav(_crickets(), true)
		"port": return _wav(_port(), true)
		"highway": return _wav(_highway(), true)
		"wind": return _wav(_wind(), true)
		"flutter": return _wav(_flutter(), false)
	return _wav(PackedFloat32Array([0.0]), false)


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## `raw` holds n + fade samples; the tail is crossfaded into the head so it loops cleanly.
static func _loop(raw: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var fade := raw.size() - n
	var out := raw.slice(0, n)
	for i in fade:
		var k := float(i) / fade
		out[i] = raw[i] * k + raw[n + i] * (1.0 - k)
	return out


static func _buf(seconds: float, fade := 0.5) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(RATE * (seconds + fade)))
	return b


## Adds a decaying tone burst (a beep, a chirp, a clank partial) at `start` seconds.
static func _tone(buf: PackedFloat32Array, start: float, dur: float, f0: float, f1: float, amp: float, decay := 0.0) -> void:
	var a := int(start * RATE)
	var n := int(dur * RATE)
	var ph := 0.0
	for i in n:
		if a + i >= buf.size():
			return
		var t := float(i) / n
		ph += TAU * lerpf(f0, f1, t) / RATE
		var env := sin(PI * t) if decay <= 0.0 else exp(-t * decay) * minf(1.0, t * 80.0)
		buf[a + i] += sin(ph) * amp * env


## Distant traffic: a low rumble with slow swells and a far-off horn or two.
static func _city() -> PackedFloat32Array:
	var n := RATE * 8
	var raw := _buf(8.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	var a := 0.0
	var b := 0.0
	var c := 0.0
	for i in raw.size():
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		a = lerpf(a, w, 0.02)
		b = lerpf(b, a, 0.1)
		c = lerpf(c, w, 0.12)
		var swell := 0.75 + 0.25 * sin(TAU * t / 8.0) + 0.1 * sin(TAU * t * 0.37)
		raw[i] = b * 2.4 * swell + c * 0.12 * swell
	for h in [[1.6, 392.0], [5.3, 466.0]]:
		for f in [h[1], h[1] * 1.26]:
			_tone(raw, h[0], 0.35, f, f, 0.025)
			_tone(raw, h[0], 0.35, f * 3.0, f * 3.0, 0.008)
	return _loop(raw, n)


## Crowd murmur: several "voices", each a buzzing pitch shaped by a moving formant,
## spoken in syllables and phrases.
static func _crowd() -> PackedFloat32Array:
	var n := RATE * 7
	var raw := _buf(7.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 202
	for v in 6:
		var pitch := rng.randf_range(95.0, 230.0)
		var y1 := 0.0
		var y2 := 0.0
		var ph := 0.0
		var i := 0
		var amp := rng.randf_range(0.5, 1.0)
		while i < raw.size():
			# A phrase of a few syllables, then a pause.
			var syl := rng.randi_range(2, 7)
			for s in syl:
				var len_s := int(rng.randf_range(0.11, 0.26) * RATE)
				var f := rng.randf_range(350.0, 1300.0)
				var r := 0.985
				var a1 := 2.0 * r * cos(TAU * f / RATE)
				var a2 := r * r
				var p := pitch * rng.randf_range(0.9, 1.15)
				for k in len_s:
					if i >= raw.size():
						break
					ph = fmod(ph + p / RATE, 1.0)
					var src := (ph * 2.0 - 1.0) * 0.6 + rng.randf_range(-0.4, 0.4)
					var y := (1.0 - r) * src + a1 * y1 - a2 * y2
					y2 = y1
					y1 = y
					var env := sin(PI * float(k) / len_s)
					raw[i] += y * env * amp * 1.4
					i += 1
			i += int(rng.randf_range(0.3, 1.2) * RATE)
	return _loop(raw, n)


## Songbirds: quick falling tweets, two-note whistles and trills, near and far.
static func _birds() -> PackedFloat32Array:
	var n := RATE * 9
	var raw := _buf(9.0, 0.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var t := 0.2
	while t < 9.0:
		var amp := rng.randf_range(0.05, 0.22)
		match rng.randi() % 3:
			0:   # tweet-tweet-tweet
				var f := rng.randf_range(3200.0, 4800.0)
				for k in rng.randi_range(3, 6):
					_tone(raw, t + k * 0.12, 0.07, f, f * 0.7, amp)
				t += 0.8
			1:   # two-note whistle
				var f := rng.randf_range(2000.0, 2800.0)
				_tone(raw, t, 0.22, f, f * 1.05, amp)
				_tone(raw, t + 0.26, 0.3, f * 1.25, f * 1.2, amp)
				t += 0.7
			_:   # trill
				var f := rng.randf_range(3800.0, 5200.0)
				var dur := rng.randf_range(0.4, 0.8)
				var a := int(t * RATE)
				for i in int(dur * RATE):
					if a + i >= raw.size():
						break
					var u := float(i) / RATE
					var am := 0.5 + 0.5 * sin(TAU * 28.0 * u)
					raw[a + i] += sin(TAU * (f + 200.0 * sin(TAU * 28.0 * u)) * u) * am * amp * sin(PI * u / dur)
				t += dur + 0.2
		t += rng.randf_range(0.15, 1.1)
	return _loop(raw, n)


## Crickets: a few of them, each chirping three quick pulses at its own pitch and pace.
static func _crickets() -> PackedFloat32Array:
	var n := RATE * 6
	var raw := _buf(6.0, 0.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for c in [[4300.0, 0.62, 0.35], [4750.0, 0.71, 0.22], [3900.0, 0.83, 0.15], [5100.0, 0.55, 0.1]]:
		var t := rng.randf_range(0.0, 0.5)
		while t < 6.3:
			for k in 3:
				_tone(raw, t + k * 0.04, 0.018, c[0], c[0], c[2])
			t += c[1] * rng.randf_range(0.92, 1.08)
	var a := 0.0
	for i in raw.size():
		a = lerpf(a, rng.randf_range(-1.0, 1.0), 0.03)
		raw[i] += a * 0.25
	return _loop(raw, n)


## The port: a deep machinery hum, metal clanks, and a forklift backing up.
static func _port() -> PackedFloat32Array:
	var n := RATE * 10
	var raw := _buf(10.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 505
	var a := 0.0
	var b := 0.0
	for i in raw.size():
		var t := float(i) / RATE
		a = lerpf(a, rng.randf_range(-1.0, 1.0), 0.015)
		b = lerpf(b, a, 0.1)
		raw[i] = b * 2.0 + 0.12 * sin(TAU * 60.0 * t) + 0.06 * sin(TAU * 120.0 * t + 0.5)
	for t in [0.8, 3.1, 4.0, 7.2]:
		var amp := rng.randf_range(0.12, 0.25)
		for f in [210.0, 523.0, 1187.0, 2031.0]:
			_tone(raw, t, 0.7, f, f * 0.995, amp / (1.0 + f / 900.0), 7.0)
	var t2 := 5.0
	for k in 4:
		_tone(raw, t2 + k * 0.8, 0.4, 1100.0, 1100.0, 0.07)
	return _loop(raw, n)


## Highway: a steady roar with cars swishing past.
static func _highway() -> PackedFloat32Array:
	var n := RATE * 8
	var raw := _buf(8.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 606
	var passes := []
	for k in 9:
		passes.append([rng.randf_range(0.0, 8.5), rng.randf_range(0.5, 1.0), rng.randf_range(0.5, 1.1)])
	var a := 0.0
	var b := 0.0
	var c := 0.0
	for i in raw.size():
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		a = lerpf(a, w, 0.05)
		b = lerpf(b, a, 0.2)
		c = lerpf(c, w, 0.35)
		var swish := 0.0
		for p in passes:
			var d: float = (t - p[0]) / p[2]
			swish += p[1] * exp(-d * d * 4.0)
		raw[i] = b * 1.2 + c * 0.35 * swish + a * 0.5 * swish
	return _loop(raw, n)


## Wind: low noise in slow gusts.
static func _wind() -> PackedFloat32Array:
	var n := RATE * 8
	var raw := _buf(8.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 707
	var a := 0.0
	var b := 0.0
	for i in raw.size():
		var t := float(i) / RATE
		a = lerpf(a, rng.randf_range(-1.0, 1.0), 0.04)
		b = lerpf(b, a, 0.08)
		var gust := 0.55 + 0.3 * sin(TAU * t / 8.0) + 0.15 * sin(TAU * t * 0.61 + 1.0)
		raw[i] = b * 3.0 * gust
	return _loop(raw, n)


## Pigeons taking off: a burst of quick wing claps.
static func _flutter() -> PackedFloat32Array:
	var n := int(RATE * 1.4)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.3)
		# Wing beats about 9 a second, several birds slightly out of step.
		var beat := 0.0
		for k in 4:
			beat += pow(maxf(0.0, sin(TAU * (8.5 + k * 0.7) * t + k)), 8.0)
		out[i] = lp * beat * 0.5 * exp(-t * 1.6) * minf(1.0, t * 30.0)
	return out
