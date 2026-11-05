class_name NeedsFX
extends CanvasLayer
## Makes your needs felt on screen. Tired: the picture blurs and darkens at the edges, you
## start blinking slowly, and when you're nearly out the blinks get long and the view
## doubles. Hungry: colors drain, and your stomach growls now and then with a little
## wobble. Bladder nearly full: a yellow pulse at the edges and the odd shiver.
## Strength follows Settings > Screen effects (0 turns it off). Drawn under the HUD.

var main: Node = null

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float tired = 0.0;
uniform float hungry = 0.0;
uniform float bladder = 0.0;
uniform float blink = 0.0;
uniform float growl = 0.0;
uniform float shiver = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	// Stomach growl: a short wobble. Bladder shiver: a quick sideways shake.
	uv += vec2(sin(uv.y * 20.0 + TIME * 7.0), cos(uv.x * 16.0 + TIME * 6.0)) * 0.003 * growl;
	uv.x += sin(TIME * 70.0) * 0.004 * shiver;
	// Tired: soft blur that comes and goes, plus a drifting double image when it's bad.
	float blur = tired * (0.55 + 0.45 * sin(TIME * 0.8)) * 2.8;
	vec3 c = textureLod(screen_tex, uv, blur).rgb;
	float dbl = clamp(tired * 2.0 - 1.0, 0.0, 1.0);
	if (dbl > 0.0) {
		vec2 o = vec2(0.008 * sin(TIME * 0.6), 0.003 * cos(TIME * 0.45)) * dbl;
		c = mix(c, textureLod(screen_tex, uv + o, blur).rgb, 0.4 * dbl);
	}
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	// Hungry: colors drain out.
	c = mix(c, vec3(lum), hungry * 0.5);
	// Vignette.
	vec2 d = SCREEN_UV - 0.5;
	float r = length(d * vec2(1.35, 1.0));
	float vig = smoothstep(0.32, 0.85, r);
	c *= 1.0 - vig * clamp(tired * 0.65 + hungry * 0.3 + growl * 0.25, 0.0, 0.9);
	// Bladder: a warm yellow pulse creeping in from the edges.
	float pulse = 0.6 + 0.4 * sin(TIME * 3.5);
	c = mix(c, vec3(0.95, 0.8, 0.25) * (0.35 + lum), vig * bladder * 0.4 * pulse);
	// Eyelids: close from the top and bottom with a slight curve.
	float lid = blink * 0.52 * (1.0 - 0.18 * d.x * d.x * 4.0);
	float y = SCREEN_UV.y;
	float shut = max(1.0 - smoothstep(lid - 0.03, lid, y), 1.0 - smoothstep(lid - 0.03, lid, 1.0 - y));
	c *= 1.0 - shut;
	COLOR = vec4(c, 1.0);
}
"""

var _rect: ColorRect
var _mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _blink := 0.0           # 0 open .. 1 shut
var _blink_t := -1.0        # time into the current blink (-1 = not blinking)
var _blink_len := 0.5
var _next_blink := 6.0
var _growl := 0.0
var _next_growl := 20.0
var _shiver := 0.0
var _next_shiver := 8.0


func _ready() -> void:
	layer = 0     # over the 3D view, under the HUD (layer 1) and the phone
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)
	_rng.randomize()


## How strong each effect is right now (0..1), before the settings slider.
static func levels() -> Dictionary:
	return {
		"tired": clampf((30.0 - Game.energy) / 30.0, 0.0, 1.0),
		"hungry": clampf((25.0 - Game.hunger) / 25.0, 0.0, 1.0),
		"bladder": clampf((Game.bladder - 80.0) / 20.0, 0.0, 1.0),
	}


func _process(delta: float) -> void:
	var k := Game.screen_fx
	var lv := levels()
	var asleep: bool = Game.sleeping or (main != null and main.traveling)
	var any: bool = k > 0.01 and not asleep and (lv.tired > 0.0 or lv.hungry > 0.0 or lv.bladder > 0.0 or _growl > 0.0)
	_rect.visible = any
	if not any:
		_blink = 0.0
		_blink_t = -1.0
		return
	if get_tree().paused:
		return
	_update_blink(delta, lv.tired)
	_update_growl(delta, lv.hungry)
	_update_shiver(delta, lv.bladder)
	_mat.set_shader_parameter("tired", lv.tired * k)
	_mat.set_shader_parameter("hungry", lv.hungry * k)
	_mat.set_shader_parameter("bladder", lv.bladder * k)
	_mat.set_shader_parameter("blink", _blink * minf(k * 1.5, 1.0))
	_mat.set_shader_parameter("growl", _growl * k)
	_mat.set_shader_parameter("shiver", _shiver * k)


## Slow blinks once you're tired: more often and longer the more tired you are, and at the
## very end they're microsleeps.
func _update_blink(delta: float, tired: float) -> void:
	if _blink_t >= 0.0:
		_blink_t += delta
		var x: float = _blink_t / _blink_len
		# Close fast, hold, open slower.
		_blink = clampf(x / 0.25, 0.0, 1.0) if x < 0.25 else (1.0 if x < 0.55 else clampf(1.0 - (x - 0.55) / 0.45, 0.0, 1.0))
		if x >= 1.0:
			_blink_t = -1.0
			_blink = 0.0
		return
	if tired < 0.3:
		return
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink_t = 0.0
		_blink_len = lerpf(0.45, 1.6, tired)
		_next_blink = lerpf(9.0, 2.5, tired) * _rng.randf_range(0.7, 1.3)


func _update_growl(delta: float, hungry: float) -> void:
	_growl = maxf(0.0, _growl - delta / 1.6)
	if hungry <= 0.0:
		return
	_next_growl -= delta
	if _next_growl <= 0.0:
		_growl = 1.0
		_next_growl = lerpf(45.0, 15.0, hungry) * _rng.randf_range(0.7, 1.3)
		if main:
			Sfx.play(main, "growl", -4.0 + 4.0 * hungry, _rng.randf_range(0.85, 1.1))


func _update_shiver(delta: float, bladder: float) -> void:
	_shiver = maxf(0.0, _shiver - delta / 0.5)
	if bladder <= 0.0:
		return
	_next_shiver -= delta
	if _next_shiver <= 0.0:
		_shiver = 1.0
		_next_shiver = lerpf(14.0, 5.0, bladder) * _rng.randf_range(0.7, 1.3)
