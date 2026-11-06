class_name Radio
extends Node
## The car radio: four parody music stations and a talk station, all synthesized (see Music).
## Stations play "live": tune away and back and the song has moved on. Every so often the
## music ducks for the DJ, an ad, or a traffic and weather update. Voices are babble, and
## what they say is shown as a caption (HUD and the radio's display).
##
## The radio plays only while you sit in the car. The station is remembered in settings.

signal changed      # station, power or caption changed

const STATIONS := [
	{"freq": "88.3", "name": "Castlewood Public Radio", "short": "CPR", "style": "talk",
		"host": "Morgan Whitfield", "pitch": 115.0, "formant": 1.0},
	{"freq": "93.7", "name": "The Hustle", "short": "HUSTLE", "style": "hiphop",
		"host": "DJ Lil' Overtime", "pitch": 98.0, "formant": 0.92},
	{"freq": "97.5", "name": "The Breeze", "short": "BREEZE", "style": "jazz",
		"host": "Velvet Valerie", "pitch": 185.0, "formant": 1.12},
	{"freq": "99.9", "name": "Night Drive", "short": "NIGHT DRV", "style": "synthwave",
		"host": "Max Overdrive", "pitch": 125.0, "formant": 1.0},
	{"freq": "104.5", "name": "The Pickup", "short": "KOUNTRY", "style": "country",
		"host": "Cousin Dale", "pitch": 105.0, "formant": 0.95},
]

const SONGS := {
	"hiphop": ["\"Five Stars for Effort\" by Lil' Deductible", "\"Surge Pricing\" by Big Tip Energy",
		"\"Mileage Log\" by MC Write-Off", "\"No Tip Blues\" by Young Mileage", "\"Side Piece of the Pie\" by Lil' Overdraft"],
	"jazz": ["\"Autumn in Wilmingtown\" by the Brandywine Quartet", "\"Take the Beltway\" by the Duke of Elkton",
		"\"Kind of Broke\" by The Odometers", "\"Smooth Commute\" by Saxophone Steve"],
	"synthwave": ["\"Neon Overpass\" by Turbo Lease", "\"Midnight Delivery\" by Neon Pothole",
		"\"Red Light Camera\" by The Midnight Shift", "\"Chrome Hubcaps\" by Lease Option"],
	"country": ["\"My Truck Got Repossessed (And So Did My Heart)\" by Dusty Tailgate",
		"\"Gas Station Roses\" by Lurleen Pickett", "\"Five-Star Cowboy\" by Hank Overdrawn",
		"\"Mama Don't Let Your Babies Grow Up to Be Gig Workers\" by the Mud Flap Boys"],
}

const ADS := [
	["Honest Al's Used Cars", "Come on down to Honest Al's! Every car has a story, and most of them are true! Trade-ins welcome, questions discouraged."],
	["DriveThyme Auto Finance", "Bad credit? No credit? Ex-credit? DriveThyme Auto Finance says yes! Only 23.9% APR. What's APR? Don't worry about it."],
	["Lube & Tube", "When did you last change your oil? If you said 'what oil', come to Lube & Tube. We'll check your tires too. Bald is not a look."],
	["WahWah Market", "WahWah! Gas, hoagies, and coffee strong enough to drive for you. Open 24 hours, because neither are you."],
	["Pear uPhone 16 Pro", "The Pear uPhone 16 Pro. Better battery. A map that shows you the cops. Pear: think different, pay more."],
	["Yoober", "Drive with Yoober! Be your own boss. Set your own hours. Hours not included. Car not included. Boss not included."],
	["Christiana Maul", "The Christiana Maul, off Route 40. Tax-free shopping, and parking that builds character."],
	["Cash Kings", "Need money before payday? Cash Kings payday loans! It's like borrowing from your future self, who hates you."],
	["Hustle Juice", "Hustle Juice energy drink. Four hundred percent of your daily anxiety. Now in Blue Raspberry Regret."],
	["Dottie's Boarding House", "Dottie's Boarding House. Rooms by the month, a shared bathroom, and Dottie. Mostly Dottie."],
	["Maple Court Apartments", "Tired of sharing a bathroom? Maple Court studios. Your own toilet. Live the dream."],
	["Slumber Lumber Mattress", "Sleeping in your car again? Slumber Lumber mattresses: the only thing in your life that supports you."],
]

const TALK_LINES := [
	"Welcome back to Mornings Considered, where we consider whether it is still morning.",
	"Our guest today argues the gig economy is just the economy now. Let's take some calls.",
	"Caller, you're on the air. ... Caller? He's in a drive-thru. We'll come back to him.",
	"It's pledge week! For just twelve dollars a month you get a tote bag, and the feeling of having a tote bag.",
	"A new study finds that drivers who say 'one more order' say it, on average, eleven more times.",
	"Today on Car Chat: what's that noise? Our experts agree: it's probably fine. It is not fine.",
	"Up next, an hour of quiet jazz while our producer looks for his keys.",
	"And now, a poem by a delivery driver: 'Leave it at the door. Photo. Next order. Next order.'",
]

var station := 1                 # index into STATIONS
var power := true
var caption := ""                # what's being said right now ("" during music)
var caption_who := ""
var active := false              # true while you sit in the car

var _music: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _streams := {}               # style -> AudioStreamWAV
var _tasks := {}                 # style -> WorkerThreadPool task id
var _results := {}               # style -> AudioStreamWAV, filled by the worker
var _mutex := Mutex.new()
var _voices := {}                # station index -> [AudioStreamWAV]
var _offsets := {}               # style -> start offset, so stations aren't in sync
var _next_segment := 12.0
var _segment_left := 0.0
var _song_idx := {}
var _ad_idx := 0
var _talk_idx := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_music = AudioStreamPlayer.new()
	_music.volume_db = -9.0
	add_child(_music)
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = -11.0
	add_child(_voice)
	for i in STATIONS.size():
		_offsets[STATIONS[i].style] = _rng.randf_range(0.0, 20.0)
	station = clampi(Game.radio_station, 0, STATIONS.size() - 1)
	power = Game.radio_on
	_prepare(STATIONS[station].style)


func _exit_tree() -> void:
	for style in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[style])
	_tasks.clear()


func current() -> Dictionary:
	return STATIONS[station]


## "93.7 The Hustle", or "Radio off".
func display_text() -> String:
	if not power:
		return "Radio off"
	var s := current()
	return "%s %s" % [s.freq, s.name]


## Turns on, steps through the stations, then off, then back to the first.
func next_station() -> void:
	if not power:
		power = true
		station = 0
	elif station == STATIONS.size() - 1:
		power = false
	else:
		station += 1
	_tuned()


func prev_station() -> void:
	if not power:
		power = true
		station = STATIONS.size() - 1
	elif station == 0:
		power = false
	else:
		station -= 1
	_tuned()


func toggle_power() -> void:
	power = not power
	_tuned()


func set_station(i: int) -> void:
	power = true
	station = clampi(i, 0, STATIONS.size() - 1)
	_tuned()


func _tuned() -> void:
	Game.radio_station = station
	Game.radio_on = power
	Game.save_options()
	_end_segment()
	_music.stop()
	if active:
		Sfx.play(self, "static", -14.0)
	if power:
		_prepare(current().style)
		_next_segment = _rng.randf_range(6.0, 14.0) if current().style != "talk" else 1.5
	changed.emit()


## Starts building a style's loop on a worker thread (once).
func _prepare(style: String) -> void:
	if _streams.has(style) or _tasks.has(style):
		return
	_tasks[style] = WorkerThreadPool.add_task(func():
		var w := Music.render(style)
		_mutex.lock()
		_results[style] = w
		_mutex.unlock())


func is_ready(style: String) -> bool:
	return _streams.has(style)


func _collect() -> void:
	for style in _tasks.keys():
		if WorkerThreadPool.is_task_completed(_tasks[style]):
			WorkerThreadPool.wait_for_task_completion(_tasks[style])
			_tasks.erase(style)
			_mutex.lock()
			_streams[style] = _results[style]
			_results.erase(style)
			_mutex.unlock()


func _voice_clip(i: int) -> AudioStreamWAV:
	if not _voices.has(i):
		var s: Dictionary = STATIONS[i]
		var clips := []
		for k in 3:
			clips.append(Music.babble(s.pitch, s.formant, 6.0, i * 31 + k))
		_voices[i] = clips
	var arr: Array = _voices[i]
	return arr[_rng.randi() % arr.size()]


func _process(delta: float) -> void:
	_collect()
	var on := active and power
	if not on:
		if _music.playing:
			_music.stop()
		if _voice.playing:
			_voice.stop()
		return
	var style: String = current().style
	var stream: AudioStreamWAV = _streams.get(style)
	if stream and not _music.playing:
		_music.stream = stream
		var length := stream.get_length()
		_music.play(fmod(Time.get_ticks_msec() / 1000.0 + _offsets[style], length))
	# DJ breaks, ads and news.
	if _segment_left > 0.0:
		_segment_left -= delta
		if _segment_left <= 0.0:
			_end_segment()
	else:
		_next_segment -= delta
		if _next_segment <= 0.0:
			_start_segment()
	var duck := -26.0 if _segment_left > 0.0 else (-14.0 if style == "talk" else -9.0)
	_music.volume_db = lerpf(_music.volume_db, duck, clampf(delta * 5.0, 0.0, 1.0))


## Picks and starts the next spoken segment on this station.
func _start_segment() -> void:
	var s := current()
	var who: String = s.host
	var text := ""
	var voice_station := station
	var roll := _rng.randf()
	if s.style == "talk":
		if roll < 0.25:
			text = _news_line()
			who = "CPR News"
		elif roll < 0.4:
			var ad: Array = ADS[_ad_idx % ADS.size()]
			_ad_idx += 1
			who = "Sponsor: " + ad[0]
			text = ad[1]
			voice_station = (station + 2) % STATIONS.size()
		else:
			text = TALK_LINES[_talk_idx % TALK_LINES.size()]
			_talk_idx += 1
	elif roll < 0.45:
		text = _dj_line(s)
	elif roll < 0.8:
		var ad: Array = ADS[_ad_idx % ADS.size()]
		_ad_idx += 1
		who = ad[0]
		text = ad[1]
		voice_station = (station + 1 + _rng.randi() % (STATIONS.size() - 1)) % STATIONS.size()
		Sfx.play(self, "money", -14.0)     # the ad jingle
	else:
		text = _news_line()
		who = "%s traffic & weather" % s.freq
	caption = text
	caption_who = who
	_segment_left = clampf(text.length() * 0.06, 4.0, 11.0)
	_voice.stream = _voice_clip(voice_station)
	_voice.play()
	changed.emit()


func _end_segment() -> void:
	_segment_left = 0.0
	if _voice.playing:
		_voice.stop()
	if caption != "":
		caption = ""
		caption_who = ""
		changed.emit()
	if power:
		var talk: bool = current().style == "talk"
		_next_segment = _rng.randf_range(2.0, 5.0) if talk else _rng.randf_range(35.0, 70.0)


## The DJ talks between songs: a back-announce plus something useful (peak times, weather).
func _dj_line(s: Dictionary) -> String:
	var songs: Array = SONGS.get(s.style, [])
	var i: int = _song_idx.get(s.style, _rng.randi() % maxi(songs.size(), 1))
	_song_idx[s.style] = i + 1
	var intro := ""
	if not songs.is_empty():
		intro = "That was %s. " % songs[i % songs.size()]
	return intro + _tip_line() + " %s, %s %s." % [s.host, s.freq, s.name]


## A useful bit for gig workers: which app is busiest now, or what the weather is paying.
func _tip_line() -> String:
	var boost := Game.weather_boost("food")
	if boost > 1.05:
		return "It's %s out there, so DoorDish is paying about %d%% extra. Drive careful, the roads are slick." % [
			Game.weather_text().to_lower(), roundi((boost - 1.0) * 100.0)]
	var best := ""
	var best_s := 1.0
	for id in GameData.APPS:
		var sv := Gigs.surge(id)
		if sv > best_s:
			best_s = sv
			best = id
	if best != "":
		return "%s is busy right now, %.1fx demand. Go get that bag." % [GameData.APPS[best].name, best_s]
	return "It's %s on %s and nobody's ordering anything. Grab a hoagie at WahWah, gas is $%.2f." % [
		Game.time_string(), Game.weekday(), GameData.GAS_PRICE]


func _news_line() -> String:
	var w := Game.weather_text()
	var road := "Traffic is moving on the I-95 Beltway"
	if Game.weather in ["rain", "storm"]:
		road = "Standing water on the beltway: slow down, bald tires will hydroplane"
	elif Game.weather == "snow":
		road = "Snow on all roads: leave extra room to stop, and go easy on the gas in the turns"
	elif Game.fog > 0.3:
		road = "Thick fog this morning, so headlights on"
	return "Traffic and weather on the nines. %s. Right now it's %s at %s. Speed cameras are watching, and so is your mother." % [road, w.to_lower(), Game.time_string()]
