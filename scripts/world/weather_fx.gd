class_name WeatherFX
extends Node3D
## Shows the weather from Game: rain and snow falling around the camera, darker overcast
## skies, fog, wet shiny roads, snow on the grass, lightning in storms, and the sound of rain.
## Light enough for the Compatibility renderer: two CPU particle systems that follow the
## camera, and tweaks to materials that already exist.

var main: Node = null
var _rain: CPUParticles3D
var _snow: CPUParticles3D
var _rain_sound: AudioStreamPlayer
var _wet := -1.0
var _snowy := -1.0
var _flash := 0.0
var _next_bolt := 8.0


func _ready() -> void:
	_rain = _particles(Vector2(0.03, 0.75), Color(0.75, 0.8, 0.9, 0.45), 900, 0.9)
	_rain.direction = Vector3(0.05, -1, 0)
	_rain.spread = 2.0
	_rain.initial_velocity_min = 24.0
	_rain.initial_velocity_max = 28.0
	_rain.gravity = Vector3.ZERO
	_rain.emission_box_extents = Vector3(22, 1, 22)
	_snow = _particles(Vector2(0.08, 0.08), Color(1, 1, 1, 0.9), 900, 7.0)
	_snow.direction = Vector3(0.2, -1, 0.1)
	_snow.spread = 25.0
	_snow.initial_velocity_min = 1.2
	_snow.initial_velocity_max = 2.2
	_snow.gravity = Vector3(0, -0.25, 0)
	_snow.emission_box_extents = Vector3(26, 2, 26)
	_rain_sound = AudioStreamPlayer.new()
	_rain_sound.stream = Sfx.get_stream("rain")
	_rain_sound.volume_db = -80.0
	add_child(_rain_sound)


func _particles(size: Vector2, color: Color, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	q.material = m
	p.mesh = q
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.layers = 4   # weather layer: the minimap camera skips it
	add_child(p)
	return p


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var amt := Game.weather_amount
	var raining := Game.weather in ["rain", "storm"] and amt > 0.02
	var snowing := Game.weather == "snow" and amt > 0.02
	var ahead := -cam.global_basis.z
	ahead.y = 0.0
	var at := cam.global_position + ahead.normalized() * 8.0
	_rain.global_position = at + Vector3(0, 14, 0)
	_snow.global_position = at + Vector3(0, 12, 0)
	var low: bool = main != null and main.low_graphics
	_set_amount(_rain, raining, 900.0 * clampf(amt * (1.0 if Game.weather == "storm" else 0.7), 0.1, 1.0) * (0.5 if low else 1.0))
	_set_amount(_snow, snowing, 900.0 * clampf(amt, 0.1, 1.0) * (0.5 if low else 1.0))
	# Rain sound.
	var vol := amt * (1.0 if Game.weather == "storm" else 0.7) if raining else 0.0
	if vol > 0.01:
		if not _rain_sound.playing:
			_rain_sound.play()
		_rain_sound.volume_db = linear_to_db(vol * 0.6)
	elif _rain_sound.playing:
		_rain_sound.stop()
	# Lightning now and then in a storm.
	_flash = maxf(0.0, _flash - delta * 3.0)
	if Game.weather == "storm" and amt > 0.5:
		_next_bolt -= delta
		if _next_bolt <= 0.0:
			_next_bolt = randf_range(9.0, 25.0)
			_flash = 1.0
			get_tree().create_timer(randf_range(0.6, 2.5)).timeout.connect(func(): Sfx.play(self, "thunder", -4.0))
	_update_surfaces()


## Changing a CPU particle count restarts the effect, so only do it in big steps.
func _set_amount(p: CPUParticles3D, on: bool, want: float) -> void:
	var n := maxi(50, int(snappedf(want, 100.0)))
	if on and p.amount != n:
		p.amount = n
	if p.emitting != on:
		p.emitting = on


## Called by main after it sets the sky for the time of day.
func apply_sky(sun: DirectionalLight3D, env: Environment, sky_mat: ProceduralSkyMaterial) -> void:
	var amt := Game.weather_amount
	var overcast: float = {"cloudy": 0.45, "rain": 0.8, "storm": 0.95, "snow": 0.7}.get(Game.weather, 0.0) * amt
	overcast = maxf(overcast, Game.fog * 0.5)
	sun.light_energy *= 1.0 - 0.7 * overcast
	var grey := Color(0.55, 0.57, 0.6)
	var lum := env.background_color.get_luminance()
	var g := grey * clampf(lum * 1.4, 0.03, 1.0)
	g.a = 1.0
	env.background_color = env.background_color.lerp(g, overcast)
	if sky_mat:
		var top_l := sky_mat.sky_top_color.get_luminance()
		var gt := grey * clampf(top_l * 1.6, 0.02, 1.0)
		gt.a = 1.0
		sky_mat.sky_top_color = sky_mat.sky_top_color.lerp(gt, overcast)
		sky_mat.sky_horizon_color = sky_mat.sky_horizon_color.lerp(g, overcast)
		sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	if _flash > 0.0:
		env.ambient_light_energy += _flash * 1.5
		env.background_color = env.background_color.lerp(Color(0.85, 0.88, 1.0), _flash * 0.6)
	# Fog: a light haze in rain and snow, thick on foggy mornings.
	var density := 0.0
	if Game.weather in ["rain", "storm"]:
		density += 0.006 * amt
	elif Game.weather == "snow":
		density += 0.009 * amt
	density += 0.022 * Game.fog
	env.fog_enabled = density > 0.0005
	env.fog_density = density
	env.fog_light_color = env.background_color.lerp(Color(0.7, 0.72, 0.75), 0.3)
	env.fog_light_energy = 1.0
	env.fog_sky_affect = 0.6


## Wet roads look shiny; snow whitens the grass. Only touches materials when it changes.
func _update_surfaces() -> void:
	var wet := Game.weather_amount if Game.weather in ["rain", "storm", "snow"] else 0.0
	wet = snappedf(wet, 0.05)
	if wet != _wet:
		_wet = wet
		for key in Kit._mats:
			if str(key).begins_with("surf|asphalt") or str(key).begins_with("surf|concrete"):
				var m: StandardMaterial3D = Kit._mats[key]
				if not m.has_meta("dry_rough"):
					m.set_meta("dry_rough", m.roughness)
					m.set_meta("dry_color", m.albedo_color)
				# Only roads get shiny: flat concrete roofs would flash in the sun from above.
				if str(key).begins_with("surf|asphalt"):
					m.roughness = lerpf(m.get_meta("dry_rough"), 0.3, wet)
				m.albedo_color = (m.get_meta("dry_color") as Color).darkened(0.25 * wet)
	var snowy := Game.weather_amount if Game.weather == "snow" else 0.0
	snowy = snappedf(snowy, 0.05)
	if snowy != _snowy:
		_snowy = snowy
		for key in Kit._mats:
			if str(key).begins_with("surf|grass") or str(key).begins_with("surf|gravel") or str(key).begins_with("surf|shingles"):
				var m: StandardMaterial3D = Kit._mats[key]
				if not m.has_meta("dry_color"):
					m.set_meta("dry_color", m.albedo_color)
					m.set_meta("dry_tex", m.albedo_texture)
				# The grass texture tints everything green, so a real snow cover drops it.
				var covered := snowy > 0.45
				m.albedo_texture = null if covered else m.get_meta("dry_tex")
				var snow_col := Color(0.88, 0.9, 0.94)
				m.albedo_color = snow_col if covered else (m.get_meta("dry_color") as Color).lerp(snow_col, 0.6 * snowy)
