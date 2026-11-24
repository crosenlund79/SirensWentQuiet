class_name NorthernSky
extends Node3D
## Experiment 004 northern atmosphere for the survival game: the northern
## lights and the falling snow.
##
## - Northern lights: on most nights (AURORA_CHANCE, seeded per run and night,
##   with a strength that varies by night; `force_tonight()` for F10). The
##   camera looks down at the lot and never sees the sky, so the aurora shows
##   as emissive, softly folding curtains standing in the fog band at the top
##   of the frame (placed from the camera each frame), plus a green tint of the
##   night ambient light, the moon and the fog (VoxelLighting.set_aurora,
##   FogBoundary.set_aurora_tint).
## - Snow: light falling flakes (CPUParticles3D) around the camera's view,
##   never drawn inside the house; `set_snow(false)` stops them.

const AURORA_CHANCE := 0.7
const AURORA_MIN := 0.45
const RIBBONS := [
	{"x": -6.0, "back": 0.0, "width": 46.0, "height": 15.0, "seed": 0.0, "strength": 1.0},
	{"x": 9.0, "back": 3.5, "width": 54.0, "height": 18.0, "seed": 4.3, "strength": 0.75},
	{"x": -2.0, "back": 7.5, "width": 60.0, "height": 20.0, "seed": 9.1, "strength": 0.55},
]
const AURORA_SHADER := preload("res://src/home/shaders/aurora.gdshader")
const SNOW_SHADER := preload("res://src/home/shaders/snowfall.gdshader")
const SNOW_DAY := Color(0.9, 0.93, 0.97)
const SNOW_NIGHT := Color(0.32, 0.38, 0.5)

var camera: Camera3D
var lighting: VoxelLighting
var boundary: FogBoundary
var run_seed := 0
var forced_key := -999999          ## a night forced on by F10 (its key)
var snow_on := true
var ribbons: Array[MeshInstance3D] = []
var snow: CPUParticles3D
var tonight := 0.0                 ## tonight's roll (0 = no northern lights)
var shown := 0.0                   ## what is on screen now (roll x night x pulse)
var _key := -999999
var _minutes := 0.0
var _snow_mat: ShaderMaterial


## The night a moment belongs to: from noon to the next noon.
static func night_key(total_minutes: float) -> int:
	return int(floor((total_minutes - 720.0) / 1440.0))


## Tonight's northern lights for a run: 0 (none, about 30 % of nights) or a
## strength in AURORA_MIN..1. Deterministic per (seed, night).
static func aurora_strength(seed: int, key: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("aurora:%d:%d" % [seed, key])
	if rng.randf() >= AURORA_CHANCE:
		return 0.0
	return rng.randf_range(AURORA_MIN, 1.0)


func setup(cam: Camera3D, light: VoxelLighting, fog: FogBoundary, seed: int) -> void:
	camera = cam
	lighting = light
	boundary = fog
	run_seed = seed


func _ready() -> void:
	var noise := FogBoundary.noise_texture()
	for i in RIBBONS.size():
		var spec: Dictionary = RIBBONS[i]
		var q := QuadMesh.new()
		q.size = Vector2(spec["width"], spec["height"])
		q.subdivide_width = 64
		var m := ShaderMaterial.new()
		m.shader = AURORA_SHADER
		m.set_shader_parameter("noise_tex", noise)
		m.set_shader_parameter("seed", spec["seed"])
		m.set_shader_parameter("strength", 0.0)
		var mi := MeshInstance3D.new()
		mi.name = "Aurora%d" % i
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 8.0
		mi.visible = false
		add_child(mi)
		ribbons.append(mi)
	_build_snow()


func _build_snow() -> void:
	snow = CPUParticles3D.new()
	snow.name = "Snowfall"
	snow.amount = 700
	snow.lifetime = 10.0
	snow.preprocess = 10.0
	snow.local_coords = false
	snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snow.emission_box_extents = Vector3(17.0, 0.6, 14.0)
	snow.direction = Vector3(0.12, -1.0, 0.04)
	snow.spread = 14.0
	snow.initial_velocity_min = 0.7
	snow.initial_velocity_max = 1.2
	snow.gravity = Vector3(0.1, -0.12, 0.03)
	snow.scale_amount_min = 0.6
	snow.scale_amount_max = 1.4
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	_snow_mat = ShaderMaterial.new()
	_snow_mat.shader = SNOW_SHADER
	var f := HousePlan.FOOTPRINT.grow(0.3)
	_snow_mat.set_shader_parameter("house", Vector4(f.position.x, f.position.y, f.end.x, f.end.y))
	q.material = _snow_mat
	snow.mesh = q
	add_child(snow)


## F10: the northern lights tonight, at full strength.
func force_tonight() -> void:
	forced_key = night_key(_minutes)
	_key = -999999


func set_snow(on: bool) -> void:
	snow_on = on
	if snow != null:
		snow.emitting = on
		snow.visible = on


## Called by the game helper every frame with the clock and the night amount.
func tick(total_minutes: float, night: float) -> void:
	_minutes = total_minutes
	var key := night_key(total_minutes)
	if key != _key:
		_key = key
		tonight = 1.0 if key == forced_key else aurora_strength(run_seed, key)
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.85 + 0.15 * sin(t * 0.37) * sin(t * 0.23 + 1.3)
	shown = tonight * smoothstep(0.35, 0.9, night) * pulse
	if lighting != null:
		lighting.set_aurora(shown)
	if boundary != null and is_instance_valid(boundary):
		boundary.set_aurora_tint(shown * night)
	for i in ribbons.size():
		var mi := ribbons[i]
		mi.visible = shown > 0.01
		if mi.visible:
			(mi.material_override as ShaderMaterial).set_shader_parameter("strength", shown * float(RIBBONS[i]["strength"]))
	if _snow_mat != null:
		_snow_mat.set_shader_parameter("tint", SNOW_DAY.lerp(SNOW_NIGHT, night))


func _process(_delta: float) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var cam := camera.global_position
	# The ground point a few degrees inside the top edge of the frame: the
	# curtains stand there, so their bright lower edge shows above the fog line.
	var top := deg_to_rad(-VoxelCamera.PITCH_DEG - camera.fov * 0.5 + 5.0)
	var reach := cam.y / tan(top)
	for i in ribbons.size():
		var spec: Dictionary = RIBBONS[i]
		var mi := ribbons[i]
		mi.global_position = Vector3(cam.x + float(spec["x"]), float(spec["height"]) * 0.5 - 0.6, cam.z - reach - float(spec["back"]))
	if snow != null:
		# over the camera's focus (pitch 56 degrees), a little to the north
		snow.global_position = Vector3(cam.x, 11.0, cam.z - (cam.y - 1.0) * 0.674 - 2.0)
