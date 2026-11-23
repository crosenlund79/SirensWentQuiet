class_name VoxelLighting
extends Node3D
## Day / night presentation for Version A (Forward+): environment, sun/moon,
## the house's practical lights (HousePlan.LIGHTS) and material night uniforms.
## Day: overcast late afternoon, fixtures off. Night: moonlit blue, warm
## practicals with shadows, flickering bathroom bulb. Tweens over ~0.5 s.

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

const DAY := {
	"ambient": Color(0.6, 0.64, 0.7), "ambient_energy": 0.95,
	"sun_color": Color(1.0, 0.87, 0.72), "sun_energy": 1.35,
	"sun_rot": Vector3(-34.0, -62.0, 0.0),
	"fog": Color(0.56, 0.6, 0.65), "fog_density": 0.006,
	"bg": Color(0.42, 0.45, 0.48), "exposure": 1.0, "glow": 0.25,
	"saturation": 0.86,
}
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


func set_night(on: bool, instant := false) -> void:
	night = on
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if instant or not is_inside_tree():
		_apply(1.0 if on else 0.0)
		return
	_tween = create_tween()
	_tween.tween_method(_apply, night_amount, 1.0 if on else 0.0, TWEEN_TIME)


func _apply(t: float) -> void:
	night_amount = t
	var e := environment
	e.background_color = (DAY["bg"] as Color).lerp(NIGHT["bg"], t)
	e.ambient_light_color = (DAY["ambient"] as Color).lerp(NIGHT["ambient"], t)
	e.ambient_light_energy = lerpf(DAY["ambient_energy"], NIGHT["ambient_energy"], t)
	e.fog_light_color = (DAY["fog"] as Color).lerp(NIGHT["fog"], t)
	e.fog_density = lerpf(DAY["fog_density"], NIGHT["fog_density"], t)
	e.tonemap_exposure = lerpf(DAY["exposure"], NIGHT["exposure"], t)
	e.glow_intensity = lerpf(DAY["glow"], NIGHT["glow"], t)
	e.adjustment_saturation = lerpf(DAY["saturation"], NIGHT["saturation"], t)
	sun.light_color = (DAY["sun_color"] as Color).lerp(NIGHT["sun_color"], t)
	sun.light_energy = lerpf(DAY["sun_energy"], NIGHT["sun_energy"], t)
	var rd: Vector3 = DAY["sun_rot"]
	var rn: Vector3 = NIGHT["sun_rot"]
	sun.rotation_degrees = rd.lerp(rn, t) if t > 0.0 and t < 1.0 else (rn if t >= 1.0 else rd)
	for o in practicals:
		var ne: float = o.get_meta("night_energy")
		o.light_energy = ne * t
		o.visible = ne > 0.0 and t > 0.01
	if _flicker != null:
		_flicker_base = _flicker.light_energy
	for m in night_materials:
		m.set_shader_parameter("night", t)


func _process(delta: float) -> void:
	_t += delta
	if _flicker != null and night_amount > 0.0:
		# Unstable bulb: summed sines, with an occasional near-blackout.
		var s := sin(_t * 23.0) * 0.18 + sin(_t * 7.3 + 1.7) * 0.22 + sin(_t * 61.0) * 0.08
		var drop := 0.15 if sin(_t * 1.9) + sin(_t * 3.1) > 1.55 else 1.0
		_flicker.light_energy = _flicker_base * clampf((0.8 + s) * drop, 0.0, 1.3)
