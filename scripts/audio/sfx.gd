class_name Sfx
extends RefCounted
## Sound effects synthesized in code at startup (no audio files): engine loop, horn, police
## siren, phone pings, crash, and a quiet town ambience. Each is a small 16-bit mono
## AudioStreamWAV, built once and cached.

const RATE := 22050

static var _cache := {}


static func get_stream(sound_name: String) -> AudioStreamWAV:
	if not _cache.has(sound_name):
		_cache[sound_name] = _build(sound_name)
	return _cache[sound_name]


## A one-shot non-positional player that frees itself when done.
static func play(parent: Node, sound_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = get_stream(sound_name)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


static func _build(sound_name: String) -> AudioStreamWAV:
	match sound_name:
		"engine": return _wav(_engine(), true)
		"siren": return _wav(_siren(), true)
		"horn": return _wav(_horn(), false)
		"ping": return _wav(_chime([880.0, 1318.5], 0.11), false)
		"money": return _wav(_chime([1046.5, 1318.5, 1568.0], 0.08), false)
		"bad": return _wav(_chime([392.0, 311.1], 0.14), false)
		"crash": return _wav(_crash(), false)
		"ambience": return _wav(_ambience(), true)
		"shutter": return _wav(_shutter(), false)
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


## Low four-cylinder rumble: a 30 Hz firing pulse with harmonics. Exactly 15 cycles per loop,
## so it loops without clicks; pitch_scale follows the revs.
static func _engine() -> PackedFloat32Array:
	var n := int(RATE * 0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var noise := 0.0
	for i in n:
		var t := float(i) / RATE
		var ph := TAU * 30.0 * t
		var s := 0.5 * sin(ph) + 0.32 * sin(2.0 * ph + 0.4) + 0.22 * sin(3.0 * ph + 1.1) \
			+ 0.16 * sin(4.0 * ph + 0.3) + 0.08 * sin(6.0 * ph + 2.0)
		# Each firing gets a little rough edge.
		var pulse := pow(maxf(0.0, sin(ph * 2.0)), 6.0)
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.15)
		out[i] = (s * 0.55 + pulse * noise * 0.35) * 0.8
	return out


## American "wail": the pitch sweeps up and down, scaled so the loop ends on a whole cycle.
static func _siren() -> PackedFloat32Array:
	var n := RATE * 2
	var freqs := PackedFloat32Array()
	freqs.resize(n)
	var total := 0.0
	for i in n:
		var t := float(i) / n
		freqs[i] = 700.0 + 700.0 * (0.5 - 0.5 * cos(TAU * t))
		total += freqs[i] / RATE
	var k := roundf(total) / total
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		ph += TAU * freqs[i] * k / RATE
		# Slightly square tone, like a speaker horn.
		out[i] = clampf(sin(ph) * 1.6, -1.0, 1.0) * 0.45
	return out


static func _horn() -> PackedFloat32Array:
	var n := int(RATE * 0.45)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t * 60.0) * minf(1.0, (0.45 - t) * 30.0)
		var s := 0.0
		for f in [415.0, 520.0]:
			var ph: float = TAU * f * t
			s += sin(ph) + 0.33 * sin(3.0 * ph) + 0.2 * sin(5.0 * ph)
		out[i] = clampf(s * 0.5, -1.0, 1.0) * env * 0.5
	return out


static func _chime(notes: Array, spacing: float) -> PackedFloat32Array:
	var n := int(RATE * (spacing * notes.size() + 0.35))
	var out := PackedFloat32Array()
	out.resize(n)
	for j in notes.size():
		var start := int(spacing * j * RATE)
		var f: float = notes[j]
		for i in range(start, n):
			var t := float(i - start) / RATE
			out[i] += (sin(TAU * f * t) + 0.25 * sin(TAU * f * 2.0 * t)) * exp(-t * 9.0) * minf(1.0, t * 400.0) * 0.4
	return out


static func _crash() -> PackedFloat32Array:
	var n := int(RATE * 0.7)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.25)
		var thump := sin(TAU * 55.0 * t) * exp(-t * 12.0)
		var rattle := rng.randf_range(-1.0, 1.0) * exp(-t * 5.0) * 0.25 * (1.0 if fmod(t, 0.06) < 0.03 else 0.4)
		out[i] = clampf((lp * exp(-t * 6.0) + thump + rattle) * 0.7, -1.0, 1.0)
	return out


## Camera shutter: two quick mechanical clicks.
static func _shutter() -> PackedFloat32Array:
	var n := int(RATE * 0.25)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for start in [0.0, 0.11]:
			var u: float = t - start
			if u >= 0.0:
				s += (rng.randf_range(-1.0, 1.0) * 0.7 + sin(TAU * 2400.0 * u) * 0.3) * exp(-u * 90.0)
		out[i] = clampf(s, -1.0, 1.0) * 0.8
	return out


## Soft, distant town noise: filtered noise with a slow swell. The loop is crossfaded.
static func _ambience() -> PackedFloat32Array:
	var n := RATE * 4
	var raw := PackedFloat32Array()
	raw.resize(n + int(RATE * 0.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var a := 0.0
	var b := 0.0
	for i in raw.size():
		a = lerpf(a, rng.randf_range(-1.0, 1.0), 0.02)
		b = lerpf(b, a, 0.1)
		raw[i] = b * (0.8 + 0.2 * sin(TAU * float(i) / raw.size()))
	var out := PackedFloat32Array()
	out.resize(n)
	var fade := int(RATE * 0.5)
	for i in n:
		out[i] = raw[i]
		if i < fade:
			var w := float(i) / fade
			out[i] = raw[i] * w + raw[n + i] * (1.0 - w)
		out[i] *= 2.2
	return out
