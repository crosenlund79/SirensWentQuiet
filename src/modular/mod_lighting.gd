class_name ModLighting
extends Node3D
## Environment, sun/moon and the house's practical lights (HousePlan.LIGHTS).
## Day: overcast late afternoon, soft shadows, interior fixtures off.
## Night: moonlit blue, warm practicals (bathroom bulb flickers), the
## player's weapon light (owned by ModPlayer). Transitions blend over 0.5 s.

const M := preload("res://src/modular/kit/mod_materials.gd")

var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var night := false
var blend := 0.0                   ## 0 day .. 1 night (eased)
var lamps: Array[GeometryInstance3D] = []   ## meshes with glowing shades

var _lights: Array[Dictionary] = []
var _vignette: ShaderMaterial
var _time := 0.0

const DAY := {
	"sun_color": Color(1.0, 0.86, 0.72), "sun_energy": 0.95, "sun_rot": Vector3(-26, -58, 0),
	"sky_top": Color(0.42, 0.46, 0.52), "sky_horizon": Color(0.62, 0.63, 0.63),
	"ambient": Color(0.56, 0.62, 0.72), "ambient_energy": 0.82,
	"fog": Color(0.5, 0.54, 0.58), "exposure": 1.05, "glow": 0.3, "saturation": 0.82,
	"vol_fog": 0.0, "vignette": 0.42,
}
const NIGHT := {
	"sun_color": Color(0.55, 0.66, 1.0), "sun_energy": 0.42, "sun_rot": Vector3(-48, 30, 0),
	"sky_top": Color(0.02, 0.03, 0.06), "sky_horizon": Color(0.05, 0.065, 0.11),
	"ambient": Color(0.2, 0.26, 0.42), "ambient_energy": 0.55,
	"fog": Color(0.03, 0.04, 0.07), "exposure": 1.35, "glow": 0.7, "saturation": 0.95,
	"vol_fog": 0.012, "vignette": 0.6,
}


func _ready() -> void:
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 0.0
	sky_mat.ground_bottom_color = Color(0.12, 0.12, 0.11)
	sky_mat.ground_horizon_color = Color(0.4, 0.4, 0.38)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 1.8
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssil_enabled = true
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.7
	env.glow_enabled = true
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 20.0
	env.fog_depth_end = 62.0
	env.fog_depth_curve = 1.6
	env.fog_density = 1.0
	env.fog_sky_affect = 0.0
	env.volumetric_fog_enabled = false
	env.volumetric_fog_length = 40.0
	env.volumetric_fog_anisotropy = 0.5
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_angular_distance = 0.0
	sun.shadow_blur = 3.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 48.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)

	for l in HousePlan.LIGHTS:
		_add_practical(l)
	_add_vignette()
	_apply(0.0)


## Screen-space finish: soft vignette, slight cool tint in the corners and a
## faint grain, so the frame reads as quiet and uneasy rather than clinical.
func _add_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength = 0.4;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 q = (UV - 0.5) * vec2(1.6, 1.0);
	float v = smoothstep(0.35, 1.05, length(q));
	float g = (hash(FRAGCOORD.xy + fract(TIME) * 61.0) - 0.5) * 0.035;
	COLOR = vec4(vec3(0.02, 0.025, 0.04) + g, v * strength + abs(g));
}
"""
	_vignette = ShaderMaterial.new()
	_vignette.shader = sh
	rect.material = _vignette
	layer.add_child(rect)


func _add_practical(l: Dictionary) -> void:
	var p: Vector2 = l["pos"]
	var h: float = l["height"]
	var o := OmniLight3D.new()
	o.position = Vector3(p.x, h, p.y)
	o.light_color = Color(1.0, 0.72, 0.45)
	o.shadow_enabled = true
	o.shadow_bias = 0.06
	o.omni_attenuation = 1.4
	var energy := 2.2
	var rng := 6.0
	match l["kind"]:
		"floor_lamp":
			energy = 2.4
			rng = 6.5
			o.position.y = h - 0.15
		"hood":
			o.shadow_enabled = false
			energy = 1.4
			rng = 4.0
			o.position.y = h - 0.12
			o.light_color = Color(1.0, 0.8, 0.55)
		"table_lamp":
			o.shadow_enabled = false
			energy = 1.5
			rng = 4.0
			_lamp_mesh(Vector3(p.x, 0.575, p.y))
			o.position.y = 0.95
		"bare_bulb":
			energy = 2.2
			rng = 6.0
			o.light_color = Color(1.0, 0.78, 0.5)
			_bulb_mesh(Vector3(p.x, h, p.y))
		"ceiling":
			energy = 2.0
			rng = 5.5
			o.light_color = Color(0.85, 0.92, 1.0) if l["flicker"] else Color(1.0, 0.8, 0.6)
	o.omni_range = rng
	o.visible = false
	add_child(o)
	_lights.append({"light": o, "energy": energy, "on": l["night_on"], "flicker": l["flicker"]})


func _lamp_mesh(base: Vector3) -> void:
	var mm := ModMesh.new()
	mm.set_mat(M.L_GLOSSY, Color(0.35, 0.45, 0.42))
	mm.cylinder(Vector3.ZERO, 0.06, 0.07, 0.04, 8)
	mm.cylinder(Vector3(0, 0.04, 0), 0.03, 0.04, 0.2, 8)
	mm.set_mat(M.L_EMISSIVE, Color(0.98, 0.9, 0.75))
	mm.cylinder(Vector3(0, 0.2, 0), 0.13, 0.09, 0.17, 10, false)
	var mi := MeshInstance3D.new()
	mi.mesh = mm.commit()
	mi.material_override = M.kit()
	mi.position = base
	add_child(mi)
	lamps.append(mi)


func _bulb_mesh(at: Vector3) -> void:
	var mm := ModMesh.new()
	mm.set_mat(M.L_PLAIN, Color(0.1, 0.1, 0.1))
	mm.cylinder(Vector3(0, 0.06, 0), 0.006, 0.006, 0.22, 4)
	mm.cylinder(Vector3(0, 0.03, 0), 0.025, 0.025, 0.04, 6)
	mm.set_mat(M.L_EMISSIVE, Color(1.0, 0.85, 0.6))
	mm.blob(Vector3.ZERO, Vector3(0.04, 0.05, 0.04), 3, 6)
	var mi := MeshInstance3D.new()
	mi.mesh = mm.commit()
	mi.material_override = M.kit()
	mi.position = at
	add_child(mi)
	lamps.append(mi)


func set_night(on: bool, instant := false) -> void:
	night = on
	if instant:
		blend = 1.0 if on else 0.0
		_apply(blend)


func _process(delta: float) -> void:
	_time += delta
	var goal := 1.0 if night else 0.0
	if not is_equal_approx(blend, goal):
		blend = move_toward(blend, goal, delta / 0.5)
		_apply(blend)
	_flicker()


func _apply(t: float) -> void:
	var e := t * t * (3.0 - 2.0 * t)
	sun.light_color = DAY.sun_color.lerp(NIGHT.sun_color, e)
	sun.light_energy = lerpf(DAY.sun_energy, NIGHT.sun_energy, e)
	sun.rotation_degrees = DAY.sun_rot.lerp(NIGHT.sun_rot, e)
	sky_mat.sky_top_color = DAY.sky_top.lerp(NIGHT.sky_top, e)
	sky_mat.sky_horizon_color = DAY.sky_horizon.lerp(NIGHT.sky_horizon, e)
	sky_mat.ground_horizon_color = DAY.sky_horizon.lerp(NIGHT.sky_horizon, e).darkened(0.3)
	env.ambient_light_color = DAY.ambient.lerp(NIGHT.ambient, e)
	env.ambient_light_energy = lerpf(DAY.ambient_energy, NIGHT.ambient_energy, e)
	env.fog_light_color = DAY.fog.lerp(NIGHT.fog, e)
	env.tonemap_exposure = lerpf(DAY.exposure, NIGHT.exposure, e)
	env.glow_intensity = lerpf(DAY.glow, NIGHT.glow, e)
	env.adjustment_saturation = lerpf(DAY.saturation, NIGHT.saturation, e)
	env.volumetric_fog_density = lerpf(DAY.vol_fog, NIGHT.vol_fog, e)
	env.volumetric_fog_enabled = e > 0.01
	env.volumetric_fog_albedo = Color(0.6, 0.65, 0.8)
	if _vignette != null:
		_vignette.set_shader_parameter("strength", lerpf(DAY.vignette, NIGHT.vignette, e))
	for d in _lights:
		var o: OmniLight3D = d["light"]
		var on: bool = d["on"]
		o.visible = on and e > 0.01
		o.light_energy = d["energy"] * e if on else 0.0
	for g in lamps:
		g.set_instance_shader_parameter("lit", e)


func _flicker() -> void:
	if blend <= 0.0:
		return
	for d in _lights:
		if not d["flicker"] or not d["on"]:
			continue
		var t := _time
		var f := 0.62 + 0.22 * sin(t * 7.3) + 0.14 * sin(t * 17.9 + 1.3) + 0.1 * sin(t * 41.0)
		if sin(t * 2.1) + sin(t * 3.7) > 1.55:
			f *= 0.15
		(d["light"] as OmniLight3D).light_energy = d["energy"] * blend * clampf(f, 0.05, 1.1)
