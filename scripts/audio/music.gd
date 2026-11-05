class_name Music
extends RefCounted
## Radio music and DJ voices, synthesized in code (no audio files). Each station style is an
## 8-bar loop built from simple instruments: drums from noise and sine sweeps, plucked strings
## (Karplus-Strong), an FM electric piano, filtered saws and squares, and sine bass. Voices are
## "babble": syllables from a buzzing source through vowel formant filters, so a DJ sounds like
## someone talking on the radio without real words (the words are shown as captions).
##
## Rendering takes a second or two per style, so Radio runs these on a worker thread.

const RATE := Sfx.RATE


static func midi(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


## Renders a station style to a looping AudioStreamWAV.
static func render(style: String) -> AudioStreamWAV:
	var s := _Song.new()
	match style:
		"hiphop": _hiphop(s)
		"country": _country(s)
		"synthwave": _synthwave(s)
		"jazz": _jazz(s)
		_: _talk_bed(s)
	return Sfx._wav(s.finish(), true)


## A voice clip of babble, about `seconds` long. pitch is the speaking pitch in Hz, formant
## scales the vowel formants (higher for smaller voices), seed picks the syllables.
static func babble(pitch: float, formant: float, seconds: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# Vowel formants (F1, F2) in Hz.
	var vowels := [[750.0, 1250.0], [500.0, 1850.0], [320.0, 2250.0], [520.0, 950.0], [350.0, 820.0], [650.0, 1600.0]]
	var i := int(0.05 * RATE)
	var phase := 0.0
	var word_left := rng.randi_range(2, 4)
	var f1 := _Reson.new()
	var f2 := _Reson.new()
	var f3 := _Reson.new()
	f3.set_band(2600.0 * formant, 260.0)
	while i < n - int(0.3 * RATE):
		var syl := int(rng.randf_range(0.09, 0.19) * RATE)
		var v: Array = vowels[rng.randi() % vowels.size()]
		f1.set_band(v[0] * formant, 110.0)
		f2.set_band(v[1] * formant, 160.0)
		var p0 := pitch * rng.randf_range(0.9, 1.15)
		var p1 := p0 * rng.randf_range(0.88, 1.08)
		var cons := int(rng.randf_range(0.0, 0.035) * RATE)
		for k in syl:
			var t := float(k) / syl
			var f0 := lerpf(p0, p1, t)
			phase = fmod(phase + f0 / RATE, 1.0)
			var src := (phase * 2.0 - 1.0) * 0.6
			if k < cons:
				src = rng.randf_range(-1.0, 1.0) * 0.5      # a consonant: a puff of noise
			var env := minf(1.0, t * 12.0) * minf(1.0, (1.0 - t) * 6.0)
			var y := f1.step(src) * 1.0 + f2.step(src) * 0.6 + f3.step(src) * 0.25
			out[i + k] += y * env * 0.5
		i += syl
		word_left -= 1
		if word_left <= 0:
			word_left = rng.randi_range(1, 4)
			i += int(rng.randf_range(0.06, 0.16) * RATE)
			if rng.randf() < 0.15:
				i += int(0.3 * RATE)      # end of a sentence
	# Radio voice: a touch of grit, then normalise.
	var peak := 0.001
	for k in n:
		out[k] = tanh(out[k] * 2.5)
		peak = maxf(peak, absf(out[k]))
	for k in n:
		out[k] = out[k] / peak * 0.7
	return Sfx._wav(out, false)


# --- Styles ----------------------------------------------------------------------------

## "The Hustle" 93.7: laid-back boom bap. 88 BPM, A minor.
static func _hiphop(s: _Song) -> void:
	s.setup(88.0, 8, 1)
	var chords := [[57, 60, 64], [53, 57, 60], [50, 53, 57], [52, 56, 59]]   # Am F Dm E
	var rng := RandomNumberGenerator.new()
	rng.seed = 937
	for bar in 8:
		var ch: Array = chords[bar % 4]
		var b0 := s.bar_t(bar)
		for st in [0, 7, 10]:
			s.kick(b0 + s.step(st), 0.9)
		for st in [4, 12]:
			s.snare(b0 + s.step(st), 0.55, 0.12)
		for st in 16:
			if st % 2 == 0 or rng.randf() < 0.25:
				s.hat(b0 + s.step(st), 0.16 if st % 4 == 2 else 0.1, 0.03)
		# 808-style bass on the kicks.
		for st in [0, 7, 10]:
			s.tone(b0 + s.step(st), s.step(3), midi(ch[0] - 24), 0.5, "sine", 0.005, 4.0)
		s.pad(b0, s.bar_len, ch, 0.07, 900.0)
		# A sparse bell motif.
		for st in [2, 6, 11, 14]:
			if rng.randf() < 0.55:
				var m: int = ch[rng.randi() % 3] + 12
				s.epiano(b0 + s.step(st), 0.6, midi(m), 0.12)


## "Kountry 104.5 The Pickup": boom-chick and a picked lead. 112 BPM, G major.
static func _country(s: _Song) -> void:
	s.setup(112.0, 8, 2)
	var chords := [[55, 59, 62], [60, 64, 67], [62, 66, 69], [55, 59, 62]]   # G C D G
	var scale := [55, 57, 59, 62, 64, 67, 69, 71, 74]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1045
	var note := 4
	for bar in 8:
		var ch: Array = chords[bar % 4]
		var b0 := s.bar_t(bar)
		for beat in 4:
			var t := b0 + s.step(beat * 4)
			if beat % 2 == 0:
				s.kick(t, 0.45)
				# Bass alternates root and fifth.
				s.pluck(t, midi(ch[0] - 12 + (0 if beat == 0 else 7)), 0.55, 0.6, 0.996)
			else:
				s.snare(t, 0.22, 0.08)
				for k in 3:
					s.pluck(t + k * 0.012, midi(ch[k]), 0.25, 0.35, 0.993)
		# Picked lead: a wandering pentatonic line of eighth notes.
		for e in 8:
			if rng.randf() < 0.7:
				note = clampi(note + rng.randi_range(-2, 2), 0, scale.size() - 1)
				s.pluck(b0 + s.step(e * 2), midi(scale[note] + 12), 0.28, 0.4, 0.995)


## "Night Drive 99.9": synthwave arpeggios. 100 BPM, A minor.
static func _synthwave(s: _Song) -> void:
	s.setup(100.0, 8, 3)
	var chords := [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]   # Am F C G
	for bar in 8:
		var ch: Array = chords[bar % 4]
		var b0 := s.bar_t(bar)
		for beat in 4:
			s.kick(b0 + s.step(beat * 4), 0.75)
			s.hat(b0 + s.step(beat * 4 + 2), 0.12, 0.05)
		for st in [4, 12]:
			s.snare(b0 + s.step(st), 0.45, 0.3)
		for e in 8:
			s.tone(b0 + s.step(e * 2), s.step(2) * 0.9, midi(ch[0] - 24), 0.3, "saw", 0.004, 6.0, 500.0)
		var arp := [ch[0], ch[1], ch[2], ch[0] + 12, ch[2], ch[1], ch[0] + 12, ch[1] + 12]
		for st in 16:
			s.tone(b0 + s.step(st), s.step(1) * 0.8, midi(arp[st % arp.size()] + 12), 0.09, "square", 0.002, 8.0, 2200.0)
		s.pad(b0, s.bar_len, ch, 0.08, 1400.0)


## "Smooth 97.5 The Breeze": electric piano and walking bass. 84 BPM, C major ii-V-I-VI.
static func _jazz(s: _Song) -> void:
	s.setup(84.0, 8, 4)
	var chords := [[50, 53, 57, 60], [55, 59, 62, 65], [48, 52, 55, 59], [57, 61, 64, 67]]   # Dm7 G7 Cmaj7 A7
	var rng := RandomNumberGenerator.new()
	rng.seed = 975
	for bar in 8:
		var ch: Array = chords[bar % 4]
		var nxt: Array = chords[(bar + 1) % 4]
		var b0 := s.bar_t(bar)
		# Swung ride.
		for beat in 4:
			s.hat(b0 + s.step(beat * 4), 0.09, 0.12)
			if beat % 2 == 1:
				s.hat(b0 + s.step(beat * 4 + 3), 0.06, 0.06)
		s.kick(b0, 0.3)
		s.snare(b0 + s.step(12), 0.12, 0.1)
		# Walking bass: root, a chord tone, another, then a step into the next chord.
		var walk := [ch[0], ch[1 + rng.randi() % 2], ch[2], nxt[0] + (1 if rng.randf() < 0.5 else -1)]
		for beat in 4:
			s.tone(b0 + s.step(beat * 4), s.step(4) * 0.95, midi(walk[beat] - 24), 0.42, "sine", 0.01, 2.5)
		for t in [0.0, s.step(6)]:
			for m in ch:
				s.epiano(b0 + t, 1.6, midi(m), 0.07)
		if rng.randf() < 0.7:
			s.epiano(b0 + s.step(10), 0.8, midi(ch[3] + 12), 0.08)


## The talk station's quiet bed: a soft pad under the voices.
static func _talk_bed(s: _Song) -> void:
	s.setup(70.0, 4, 5)
	var chords := [[48, 55, 64], [53, 57, 64], [50, 57, 65], [48, 55, 64]]
	for bar in 4:
		s.pad(s.bar_t(bar), s.bar_len, chords[bar], 0.035, 700.0)


# --- Building blocks ----------------------------------------------------------------------

class _Song:
	var buf := PackedFloat32Array()
	var n := 0
	var bar_len := 2.0
	var rng := RandomNumberGenerator.new()

	func setup(bpm: float, bars: int, seed_value: int) -> void:
		bar_len = 240.0 / bpm
		n = int(bar_len * bars * RATE)
		buf.resize(n)
		buf.fill(0.0)
		rng.seed = seed_value

	func bar_t(bar: int) -> float:
		return bar * bar_len

	func step(st: float) -> float:
		return st * bar_len / 16.0

	## Adds a sample, wrapping round the loop so tails carry over the seam.
	func _add(i: int, v: float) -> void:
		buf[i % n] += v

	func tone(t: float, dur: float, f: float, vol: float, wave: String, attack: float, decay: float, cutoff := 0.0) -> void:
		var start := int(t * RATE)
		var len := int((dur + 0.08) * RATE)
		var ph := 0.0
		var lp := 0.0
		var a := 1.0 - exp(-TAU * cutoff / RATE) if cutoff > 0.0 else 1.0
		for k in len:
			var u := float(k) / RATE
			ph = fmod(ph + f / RATE, 1.0)
			var w := 0.0
			match wave:
				"sine": w = sin(TAU * ph)
				"saw": w = ph * 2.0 - 1.0
				"square": w = 1.0 if ph < 0.5 else -1.0
			lp += (w - lp) * a
			var env := minf(1.0, u / attack) * exp(-u * decay)
			if u > dur:
				env *= maxf(0.0, 1.0 - (u - dur) / 0.08)
			_add(start + k, lp * env * vol)

	## A soft chord pad: detuned filtered saws with a slow swell.
	func pad(t: float, dur: float, notes: Array, vol: float, cutoff: float) -> void:
		var start := int(t * RATE)
		var len := int(dur * RATE)
		var a := 1.0 - exp(-TAU * cutoff / RATE)
		for m in notes:
			var f := Music.midi(m)
			var p1 := 0.0
			var p2 := 0.37
			var lp := 0.0
			for k in len:
				var u := float(k) / len
				p1 = fmod(p1 + f / RATE, 1.0)
				p2 = fmod(p2 + f * 1.004 / RATE, 1.0)
				lp += ((p1 + p2) - 1.0 - lp) * a
				var env := minf(1.0, u * 6.0) * minf(1.0, (1.0 - u) * 10.0)
				_add(start + k, lp * env * vol)

	## FM electric piano / bell.
	func epiano(t: float, dur: float, f: float, vol: float) -> void:
		var start := int(t * RATE)
		var len := int(dur * RATE)
		for k in len:
			var u := float(k) / RATE
			var mod := 1.6 * exp(-u * 6.0) * sin(TAU * f * u)
			var env := minf(1.0, u * 300.0) * exp(-u * 2.8)
			_add(start + k, sin(TAU * f * u + mod) * env * vol)

	## Karplus-Strong plucked string.
	func pluck(t: float, f: float, vol: float, dur: float, damp: float) -> void:
		var start := int(t * RATE)
		var period := maxi(2, int(RATE / f))
		var ring := PackedFloat32Array()
		ring.resize(period)
		for k in period:
			ring[k] = rng.randf_range(-1.0, 1.0)
		var len := int(dur * RATE)
		var idx := 0
		for k in len:
			var nxt := (idx + 1) % period
			var v := ring[idx]
			ring[idx] = (v + ring[nxt]) * 0.5 * damp
			idx = nxt
			var env := minf(1.0, (1.0 - float(k) / len) * 8.0)
			_add(start + k, v * env * vol)

	func kick(t: float, vol: float) -> void:
		var start := int(t * RATE)
		var len := int(0.35 * RATE)
		var ph := 0.0
		for k in len:
			var u := float(k) / RATE
			ph += TAU * (45.0 + 90.0 * exp(-u * 30.0)) / RATE
			_add(start + k, sin(ph) * exp(-u * 9.0) * vol)

	func snare(t: float, vol: float, decay_s: float) -> void:
		var start := int(t * RATE)
		var len := int((decay_s * 4.0 + 0.05) * RATE)
		var prev := 0.0
		for k in len:
			var u := float(k) / RATE
			var nz := rng.randf_range(-1.0, 1.0)
			var hp := nz - prev * 0.7
			prev = nz
			var body := sin(TAU * 185.0 * u) * exp(-u * 30.0) * 0.5
			_add(start + k, (hp * 0.6 * exp(-u / decay_s) + body) * vol)

	func hat(t: float, vol: float, decay_s: float) -> void:
		var start := int(t * RATE)
		var len := int(decay_s * 5.0 * RATE)
		var prev := 0.0
		for k in len:
			var u := float(k) / RATE
			var nz := rng.randf_range(-1.0, 1.0)
			_add(start + k, (nz - prev) * 0.5 * exp(-u / decay_s) * vol)
			prev = nz

	func finish() -> PackedFloat32Array:
		# Gentle limiter so the loudest hits don't clip.
		var peak := 0.001
		for k in n:
			peak = maxf(peak, absf(buf[k]))
		var g := 0.8 / peak
		for k in n:
			buf[k] = tanh(buf[k] * g * 1.2) * 0.85
		return buf


## Two-pole resonant band-pass filter (for vowel formants).
class _Reson:
	var a1 := 0.0
	var a2 := 0.0
	var gain := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func set_band(freq: float, bw: float) -> void:
		var r := exp(-PI * bw / RATE)
		a1 = 2.0 * r * cos(TAU * freq / RATE)
		a2 = -r * r
		gain = 1.0 - r

	func step(x: float) -> float:
		var y := gain * x + a1 * y1 + a2 * y2
		y2 = y1
		y1 = y
		return y * 4.0
