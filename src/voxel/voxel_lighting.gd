class_name VoxelLighting
extends Node3D
## Day / night presentation for Version A (Forward+): environment, sun/moon,
## the house's practical lights (HousePlan.LIGHTS) and material night uniforms.
## Day: overcast late afternoon, fixtures off. Night: moonlit blue, warm
## practicals with shadows, flickering bathroom bulb. Tweens over ~0.5 s.
##
## Experiment 004 (survival game): `set_northern(true)` swaps in the far-north
## palette (a pale low sun by day, much darker blue nights), `set_aurora(0..1)`
## tints the night ambient, moon and fog green toward the northern lights, and
## `set_electric({light id: bool})` lets the house's switches and fuse box
## drive each practical directly, day or night (HomeElectrical).

const TWEEN_TIME := 0.5

## Per light kind: [energy, range, colour]
const KINDS := {
	"floor_lamp": [4.2, 7.0, Color(1.0, 0.72, 0.42)],
	"hood": [1.6, 3.6, Color(1.0, 0.82, 0.6)],
	"table_lamp": [1.6, 3.8, Color(1.0, 0.68, 0.4)],
	"ceiling": [2.4, 5.0, Color(0.92, 0.95, 1.0)],
	"bare_bulb": [2.4, 5.0, Color(1.0, 0.78, 0.5)],
}

## The light source sits just outside its voxel fixture (a solid shade would
## otherwise swallow the shadowed light): under the floor lamp's shade, above
## the table lamp, under the hood.
const KIND_OFFSET := {"floor_lamp": -0.36, "table_lamp": 0.17, "hood": -0.12}

var environment: Environment
var sun: DirectionalLight3D
var practicals: Array[OmniLight3D] = []
var night_materials: Array[ShaderMaterial] = []   ## get `night` (0..1)
var night := false
var night_amount := 0.0
var _flicker: OmniLight3D
var _flicker_base := 0.0
var _t := 0.0
var _tween: Tween
var northern := false
var aurora := 0.0                 ## 0..1, the northern lights' current strength
var electric := false             ## practicals follow set_electric(), not the night
var _eflicker: OmniLight3D

const DAY := {
	"ambient": Color(0.6, 0.64, 0.7), "ambient_energy": 0.95,
	"sun_color": Color(1.0, 0.87, 0.72), "sun_energy": 1.35,
	"sun_rot": Vector3(-34.0, -62.0, 0.0),
	"fog": Color(0.56, 0.6, 0.65), "fog_density": 0.006,
	"bg": Color(0.42, 0.45, 0.48), "exposure": 1.0, "glow": 0.25,
	"saturation": 0.86,
}
## Experiment 004: far north. Overcast pale days with a low sun; dark nights.
const NORTH_DAY := {
	"ambient": Color(0.6, 0.67, 0.78), "ambient_energy": 0.62,
	"sun_color": Color(0.93, 0.94, 0.97), "sun_energy": 1.0,
	"sun_rot": Vector3(-27.0, -62.0, 0.0),
	"fog": Color(0.64, 0.7, 0.78), "fog_density": 0.008,
	"bg": Color(0.5, 0.55, 0.6), "exposure": 0.92, "glow": 0.2,
	"saturation": 0.8,
}
const NORTH_NIGHT := {
	"ambient": Color(0.13, 0.17, 0.3), "ambient_energy": 0.24,
	"sun_color": Color(0.5, 0.62, 0.95), "sun_energy": 0.16,
	"sun_rot": Vector3(-52.0, 32.0, 0.0),
	"fog": Color(0.022, 0.03, 0.055), "fog_density": 0.014,
	"bg": Color(0.008, 0.012, 0.022), "exposure": 1.0, "glow": 0.75,
	"saturation": 0.9,
}
## What the northern lights push the night toward (scaled by aurora × night).
const AURORA_AMBIENT := Color(0.16, 0.52, 0.42)
const AURORA_MOON := Color(0.45, 0.95, 0.75)
const AURORA_FOG := Color(0.03, 0.12, 0.09)

const NIGHT := {
	"ambient": Color(0.22, 0.28, 0.45), "ambient_energy": 0.55,
	"sun_color": Color(0.55, 0.66, 1.0), "sun_energy": 0.42,
	"sun_rot": Vector3(-52.0, 32.0, 0.0),
	"fog": Color(0.05, 0.07, 0.12), "fog_density": 0.012,
	"bg": Color(0.02, 0.025, 0.04), "exposure": 1.15, "glow": 0.65,
	"saturation": 0.92,
}


func _ready() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 6.0
	environment.ssao_enabled = true
	environment.ssao_radius = 0.9
	environment.ssao_intensity = 1.6
	environment.ssao_power = 1.4
	environment.ssao_detail = 0.6
	environment.glow_enabled = true
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.1
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_sun_scatter = 0.05
	environment.fog_aerial_perspective = 0.0
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_angular_distance = 2.5
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 48.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)

	for l in HousePlan.LIGHTS:
		var o := OmniLight3D.new()
		var k: Array = KINDS.get(l["kind"], KINDS["ceiling"])
		o.light_color = k[2]
		o.omni_range = k[1]
		o.omni_attenuation = 1.3
		o.light_energy = 0.0
		o.shadow_enabled = true
		o.shadow_bias = 0.06
		o.light_specular = 0.25
		o.position = Vector3(l["pos"].x, l["height"] + KIND_OFFSET.get(l["kind"], 0.0), l["pos"].y)
		o.set_meta("night_energy", k[0] if l["night_on"] else 0.0)
		o.visible = false
		add_child(o)
		practicals.append(o)
		if l["flicker"]:
			_flicker = o
	_apply(0.0)


## Survival (no grid power): the house fixtures stay dark. The demo keeps them.
func set_practicals_enabled(on: bool) -> void:
	for i in practicals.size():
		var o := practicals[i]
		var l: Dictionary = HousePlan.LIGHTS[i]
		var k: Array = KINDS.get(l["kind"], KINDS["ceiling"])
		o.set_meta("night_energy", k[0] if (on and l["night_on"]) else 0.0)
	if not on:
		_flicker = null
	_apply(night_amount)


func set_night(on: bool, instant := false) -> void:
	night = on
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if instant or not is_inside_tree():
		_apply(1.0 if on else 0.0)
		return
	_tween = create_tween()
	_tween.tween_method(_apply, night_amount, 1.0 if on else 0.0, TWEEN_TIME)


## Survival: drive the blend from the world clock (0 day .. 1 night), no tween.
func set_amount(t: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	night = t > 0.5
	_apply(clampf(t, 0.0, 1.0))


func _apply(t: float) -> void:
	night_amount = t
	var D: Dictionary = NORTH_DAY if northern else DAY
	var N: Dictionary = NORTH_NIGHT if northern else NIGHT
	var e := environment
	e.background_color = (D["bg"] as Color).lerp(N["bg"], t)
	e.ambient_light_energy = lerpf(D["ambient_energy"], N["ambient_energy"], t)
	e.fog_density = lerpf(D["fog_density"], N["fog_density"], t)
	e.tonemap_exposure = lerpf(D["exposure"], N["exposure"], t)
	e.glow_intensity = lerpf(D["glow"], N["glow"], t)
	e.adjustment_saturation = lerpf(D["saturation"], N["saturation"], t)
	sun.light_energy = lerpf(D["sun_energy"], N["sun_energy"], t)
	var rd: Vector3 = D["sun_rot"]
	var rn: Vector3 = N["sun_rot"]
	sun.rotation_degrees = rd.lerp(rn, t) if t > 0.0 and t < 1.0 else (rn if t >= 1.0 else rd)
	_apply_colors()
	for o in practicals:
		if electric:
			var ee: float = o.get_meta("electric_energy", 0.0)
			o.light_energy = ee
			o.visible = ee > 0.0
		else:
			var ne: float = o.get_meta("night_energy")
			o.light_energy = ne * t
			o.visible = ne > 0.0 and t > 0.01
	if _flicker != null:
		_flicker_base = _flicker.light_energy
	if _eflicker != null:
		_flicker_base = _eflicker.light_energy
	for m in night_materials:
		m.set_shader_parameter("night", t)


## Ambient, moon and fog colours: the palette blend plus the northern lights.
func _apply_colors() -> void:
	var t := night_amount
	var D: Dictionary = NORTH_DAY if northern else DAY
	var N: Dictionary = NORTH_NIGHT if northern else NIGHT
	var a := clampf(aurora, 0.0, 1.0) * t
	var e := environment
	e.ambient_light_color = (D["ambient"] as Color).lerp(N["ambient"], t).lerp(AURORA_AMBIENT, a * 0.5)
	e.fog_light_color = (D["fog"] as Color).lerp(N["fog"], t).lerp(AURORA_FOG, a * 0.6)
	sun.light_color = (D["sun_color"] as Color).lerp(N["sun_color"], t).lerp(AURORA_MOON, a * 0.35)


## Experiment 004: the far-north palette (survival game).
func set_northern(on: bool) -> void:
	northern = on
	_apply(night_amount)


## Experiment 004: the northern lights' strength now (0..1); only the colours change.
func set_aurora(strength: float) -> void:
	strength = clampf(strength, 0.0, 1.0)
	if absf(strength - aurora) < 0.002:
		return
	aurora = strength
	_apply_colors()


## Experiment 004: the house's electric lights by HousePlan.LIGHTS id
## (true = shining). Switches the practicals to electric mode for good.
func set_electric(states: Dictionary) -> void:
	electric = true
	_eflicker = null
	for i in practicals.size():
		var l: Dictionary = HousePlan.LIGHTS[i]
		var k: Array = KINDS.get(l["kind"], KINDS["ceiling"])
		var on: bool = states.get(l["id"], false) == true
		practicals[i].set_meta("electric_energy", k[0] if on else 0.0)
		if on and l["flicker"]:
			_eflicker = practicals[i]
	_flicker = null
	_apply(night_amount)


## Experiment 004: is the practical for light `id` shining (electric mode)?
func practical_on(id: String) -> bool:
	for i in practicals.size():
		if HousePlan.LIGHTS[i]["id"] == id:
			return practicals[i].visible and practicals[i].light_energy > 0.0
	return false


func _process(delta: float) -> void:
	_t += delta
	if _eflicker != null:
		var s := sin(_t * 23.0) * 0.18 + sin(_t * 7.3 + 1.7) * 0.22 + sin(_t * 61.0) * 0.08
		var drop := 0.15 if sin(_t * 1.9) + sin(_t * 3.1) > 1.55 else 1.0
		_eflicker.light_energy = _flicker_base * clampf((0.8 + s) * drop, 0.0, 1.3)
	elif _flicker != null and night_amount > 0.0:
		# Unstable bulb: summed sines, with an occasional near-blackout.
		var s := sin(_t * 23.0) * 0.18 + sin(_t * 7.3 + 1.7) * 0.22 + sin(_t * 61.0) * 0.08
		var drop := 0.15 if sin(_t * 1.9) + sin(_t * 3.1) > 1.55 else 1.0
		_flicker.light_energy = _flicker_base * clampf((0.8 + s) * drop, 0.0, 1.3)
