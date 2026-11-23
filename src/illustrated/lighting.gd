extends Node2D
## Day / night for Version C, all engine lighting (art carries no light pools):
## CanvasModulate ambient, warm shadow-casting PointLight2D practicals from
## HousePlan.LIGHTS (the bathroom one flickers by summed sines), small unshaded
## glows on the fixtures, the abandoned car's hazard lights, the player's
## lights, the strength of the soft "sun" shadows and a screen-space grade
## (desaturation, vignette, paper grain). One blend factor drives everything.

const Art := preload("res://src/illustrated/ill_art.gd")

const DAY_AMBIENT := Color(0.79, 0.81, 0.86)
const NIGHT_AMBIENT := Color(0.15, 0.18, 0.3)
## kind -> [color, energy, radius m]
const PRACTICAL := {
	"floor_lamp": [Color(1.0, 0.74, 0.46), 1.25, 4.6],
	"table_lamp": [Color(1.0, 0.7, 0.44), 1.1, 3.4],
	"hood": [Color(1.0, 0.84, 0.62), 1.0, 3.6],
	"ceiling": [Color(0.82, 0.9, 1.0), 1.15, 4.2],
	"bare_bulb": [Color(1.0, 0.82, 0.5), 1.25, 5.0],
}
const GRADE_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float desat = 0.15;
uniform float vignette = 0.35;
uniform vec3 tint = vec3(1.0);
uniform float grain = 0.03;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desat) * tint;
	vec2 q = (SCREEN_UV - 0.5) * vec2(1.25, 1.0);
	c *= 1.0 - vignette * smoothstep(0.2, 0.78, length(q));
	float paper = (hash(floor(FRAGCOORD.xy)) - 0.5) * 0.6 + (vnoise(FRAGCOORD.xy / 6.0) - 0.5);
	c *= 1.0 + paper * grain;
	COLOR = vec4(c, 1.0);
}
"""

var night := false
var amount := 0.0                    ## 0 day .. 1 night (tweened)
var modulate_node: CanvasModulate
var shadow_group: CanvasItem
var player
var lights: Array = []               ## [{light, base, flicker, phase, glow}]
var hazards: Array[PointLight2D] = []
var _grade: ShaderMaterial
var _t := 0.0
var _tween: Tween


func build(p_shadow_group: CanvasItem, p_player) -> void:
	shadow_group = p_shadow_group
	player = p_player
	modulate_node = CanvasModulate.new()
	modulate_node.color = DAY_AMBIENT
	add_child(modulate_node)
	var soft := Art.tex("light_soft")
	for d in HousePlan.LIGHTS:
		if not d["night_on"] or not PRACTICAL.has(d["kind"]):
			continue
		var spec: Array = PRACTICAL[d["kind"]]
		var l := PointLight2D.new()
		l.texture = soft
		l.position = Art.w(d["pos"])
		l.color = spec[0]
		l.texture_scale = spec[2] / 4.0
		l.energy = 0.0
		l.enabled = false
		l.shadow_enabled = true
		l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		l.shadow_filter_smooth = 2.0
		l.shadow_color = Color(0, 0, 0, 0.85)
		add_child(l)
		var g := Sprite2D.new()
		g.texture = soft
		g.position = l.position
		var gk := Art.m(0.55) / 512.0
		g.scale = Vector2(gk, gk)
		g.modulate = Color(spec[0].r, spec[0].g, spec[0].b, 0.0)
		g.material = Art.additive()
		g.z_index = Art.Z_OVERHEAD + 1
		g.z_as_relative = false
		add_child(g)
		lights.append({"light": l, "base": spec[1], "flicker": d["flicker"], "phase": randf() * 10.0, "glow": g})
	# the abandoned car's hazard lights keep blinking, day and night
	for f in HousePlan.PROPS:
		if f["type"] != "car":
			continue
		var r: Rect2 = f["rect"]
		for corner in [Vector2(r.position.x + 0.15, r.position.y + 0.1), Vector2(r.end.x - 0.15, r.position.y + 0.1),
				Vector2(r.position.x + 0.15, r.end.y - 0.1), Vector2(r.end.x - 0.15, r.end.y - 0.1)]:
			var h := PointLight2D.new()
			h.texture = soft
			h.position = Art.w(corner)
			h.color = Color(1.0, 0.55, 0.15)
			h.texture_scale = 0.28
			h.energy = 0.0
			add_child(h)
			hazards.append(h)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRADE_SHADER
	_grade.shader = sh
	rect.material = _grade
	layer.add_child(rect)
	_apply()


func set_night(n: bool, instant := false) -> void:
	night = n
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if instant:
		amount = 1.0 if n else 0.0
		_apply()
		return
	_tween = create_tween()
	_tween.tween_property(self, "amount", 1.0 if n else 0.0, 0.55).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	_t += delta
	_apply()


func _apply() -> void:
	var k := amount
	modulate_node.color = DAY_AMBIENT.lerp(NIGHT_AMBIENT, k)
	for e in lights:
		var l: PointLight2D = e["light"]
		var en: float = e["base"] * k
		if e["flicker"]:
			var ph: float = e["phase"]
			en *= 1.0 + sin(_t * 9.0 + ph) * 0.18 + sin(_t * 23.0 + ph * 3.0) * 0.1
			# a failing tube: brief dropouts when two slow sines line up
			if sin(_t * 1.3 + ph) + sin(_t * 3.1 + ph * 2.0) > 1.55:
				en *= 0.12
		l.energy = en
		l.enabled = en > 0.01
		var g: Sprite2D = e["glow"]
		g.modulate.a = clampf(en / maxf(e["base"], 0.01), 0.0, 1.0) * 0.9
	var blink := 1.0 if fmod(_t, 1.1) < 0.45 else 0.0
	for h in hazards:
		h.energy = blink * (0.5 + 1.1 * k)
	if player != null:
		player.set_night_amount(k)
	if shadow_group != null and shadow_group.material != null:
		shadow_group.material.set_shader_parameter("opacity", lerpf(0.62, 0.3, k))
	if _grade != null:
		_grade.set_shader_parameter("desat", lerpf(0.2, 0.22, k))
		_grade.set_shader_parameter("vignette", lerpf(0.38, 0.62, k))
		_grade.set_shader_parameter("tint", Vector3(1.0, 1.0, 1.02).lerp(Vector3(0.95, 0.98, 1.06), k))
		_grade.set_shader_parameter("grain", lerpf(0.06, 0.08, k))


func practical_count() -> int:
	return lights.size()
