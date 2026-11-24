class_name RegionMapView
extends Node3D
## The 3D miniature of the region (SPEC-003 §6). Owner: M.
## Lives in its own World3D (RegionMapScreen's SubViewport): environment, a
## soft sun, the terrain/prop/water meshes, tree MultiMeshes, the house's warm
## light, two drifting cloud layers, and a camera rig (focus point, distance,
## pitch that flattens as you zoom in). Pure presentation: it reads the shared
## RegionTerrain and stores nothing.

const CLOUD_Y := 24.0
const CLOUD_SPEED := Vector2(0.75, 0.3)      ## world units per second (slow)
const FOV := 32.0
const DIST_MIN := 16.0
const DIST_MAX := 200.0
const PITCH_NEAR := 42.0
const PITCH_FAR := 60.0
const GROUND_Y := 3.5                        ## pan plane (town level)
const FOG := Color(0.56, 0.59, 0.61)
const CLOUD_OPACITY := [0.55, 0.22]

const DAY := {"bg": FOG, "ambient": Color(0.64, 0.67, 0.72), "ambient_energy": 0.92,
	"sun": Color(1.0, 0.91, 0.78), "sun_energy": 1.25, "fog": FOG}
const NIGHT := {"bg": Color(0.07, 0.085, 0.12), "ambient": Color(0.24, 0.3, 0.46), "ambient_energy": 0.55,
	"sun": Color(0.55, 0.65, 0.95), "sun_energy": 0.32, "fog": Color(0.07, 0.085, 0.12)}

var terrain: RegionTerrain
var camera: Camera3D
var environment: Environment
var sun: DirectionalLight3D
var home_light: OmniLight3D
var surface_mat: ShaderMaterial
var props_mat: ShaderMaterial
var tree_mat: ShaderMaterial
var water_mat: ShaderMaterial
var cloud_mats: Array[ShaderMaterial] = []
var stats := {}

## Camera rig: the camera looks at `focus` from `distance` away, from the
## south (yaw 0 = north up). Targets are eased toward each frame.
var focus := Vector3(80.0, GROUND_Y, 64.0)
var distance := 150.0
var yaw := 0.0
var focus_target := focus
var distance_target := distance
var cloud_time := 0.0
var cloud_rate := 1.0                         ## preview/tests can speed the drift up
var cloud_amount := 1.0                       ## 0 hides the cloud layer (not the shadows)
var night := 0.0
var _clear_a := Vector2(-999, -999)
var _clear_b := Vector2(-999, -999)
var _built := false

static var _cloud_tex: Texture2D


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	var t0 := Time.get_ticks_usec()
	terrain = RegionTerrain.shared()
	var meshes := RegionMapMesher.build(terrain)
	_make_environment()
	_make_materials()
	var draws := 0
	for m in meshes["terrain"]:
		draws += _add_mesh(m, surface_mat, true)
	for m in meshes["props"]:
		draws += _add_mesh(m, props_mat, true)
	draws += _add_mesh(meshes["water"], water_mat, false)
	for mm in meshes["trees"]:
		if (mm as MultiMesh).instance_count == 0:
			continue
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = tree_mat
		add_child(mmi)
		draws += 1
	_make_fog_floor()
	_make_clouds()
	home_light = OmniLight3D.new()
	home_light.light_color = Color(1.0, 0.72, 0.42)
	home_light.omni_range = 3.2
	home_light.light_energy = 1.0
	home_light.position = terrain.home_light
	add_child(home_light)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.5
	camera.far = 600.0
	camera.current = true
	add_child(camera)
	frame_region(true)
	var faces: Dictionary = meshes["faces"]
	stats = {"terrain_ms": terrain.build_ms, "mesh_ms": meshes["ms"], "view_ms": (Time.get_ticks_usec() - t0) / 1000.0,
		"faces": faces, "faces_total": int(faces["terrain"]) + int(faces["props"]) + int(faces["water"]) + int(faces["trees"]),
		"mesh_instances": draws + cloud_mats.size(), "trees": terrain.trees.size(), "boxes": terrain.boxes.size()}
	_apply_camera()


func _add_mesh(m: ArrayMesh, mat: Material, shadows: bool) -> int:
	if m == null or m.get_surface_count() == 0:
		return 0
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return 1


## A seamless fractal noise texture shared by clouds, cloud shadows, water
## ripples and the ragged fog edge.
static func cloud_texture() -> Texture2D:
	if _cloud_tex == null:
		var n := FastNoiseLite.new()
		n.seed = 77
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.frequency = 0.012
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 5
		n.fractal_gain = 0.5
		var img := n.get_seamless_image(256, 256, false, false, 0.1, true)
		img.convert(Image.FORMAT_L8)
		img.generate_mipmaps()
		_cloud_tex = ImageTexture.create_from_image(img)
	return _cloud_tex


func _make_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = FOG
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = DAY["ambient"]
	environment.ambient_light_energy = DAY["ambient_energy"]
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 6.0
	environment.ssao_enabled = true
	environment.ssao_radius = 1.6
	environment.ssao_intensity = 1.4
	environment.ssao_power = 1.3
	environment.glow_enabled = true
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = FOG
	environment.fog_density = 0.0016
	environment.fog_sky_affect = 0.0
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.9
	environment.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44.0, -52.0, 0.0)
	sun.light_color = DAY["sun"]
	sun.light_energy = DAY["sun_energy"]
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.shadow_bias = 0.06
	add_child(sun)


func _sun_shift() -> Vector2:
	var to_sun := sun.basis.z.normalized()
	return Vector2(to_sun.x, to_sun.z) / maxf(to_sun.y, 0.2)


func _make_materials() -> void:
	var tex := cloud_texture()
	var shift := _sun_shift()
	var surface := load("res://src/map/shaders/map_surface.gdshader") as Shader
	surface_mat = ShaderMaterial.new()
	surface_mat.shader = surface
	props_mat = ShaderMaterial.new()
	props_mat.shader = surface
	props_mat.set_shader_parameter("roughness", 0.8)
	tree_mat = ShaderMaterial.new()
	tree_mat.shader = surface
	tree_mat.set_shader_parameter("roughness", 0.95)
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://src/map/shaders/map_water.gdshader") as Shader
	for m in [surface_mat, props_mat, tree_mat, water_mat]:
		_common(m, tex, shift)


func _common(m: ShaderMaterial, tex: Texture2D, shift: Vector2) -> void:
	m.set_shader_parameter("cloud_tex", tex)
	m.set_shader_parameter("cloud_y", CLOUD_Y)
	m.set_shader_parameter("sun_shift", shift)
	m.set_shader_parameter("region_size", Vector2(RegionTerrain.W, RegionTerrain.H))
	m.set_shader_parameter("fog_color", FOG)


## A wide floor beyond the region in the same shader, so the fog at the edge
## and the fog beyond it are the same colour (the background never shows).
func _make_fog_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = props_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(RegionTerrain.W * 0.5, RegionTerrain.BASE * RegionTerrain.STEP, RegionTerrain.H * 0.5)
	add_child(mi)


func _make_clouds() -> void:
	var shader := load("res://src/map/shaders/map_clouds.gdshader") as Shader
	var tex := cloud_texture()
	for k in 2:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_common(mat, tex, _sun_shift())
		mat.set_shader_parameter("opacity", CLOUD_OPACITY[k])
		mat.set_shader_parameter("layer_shift", float(k))
		mat.render_priority = k
		var plane := PlaneMesh.new()
		plane.size = Vector2(RegionTerrain.W + 36, RegionTerrain.H + 36)
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(RegionTerrain.W * 0.5, CLOUD_Y + k * 6.0, RegionTerrain.H * 0.5)
		add_child(mi)
		cloud_mats.append(mat)


# --- camera ---------------------------------------------------------------------

## Frames the whole region (instant or eased).
func frame_region(instant := false) -> void:
	set_view(Vector3(RegionTerrain.W * 0.5, GROUND_Y, RegionTerrain.H * 0.57), 190.0, instant)


func set_view(f: Vector3, dist: float, instant := false) -> void:
	focus_target = _clamp_focus(f)
	distance_target = clampf(dist, DIST_MIN, DIST_MAX)
	if instant:
		focus = focus_target
		distance = distance_target
		_apply_camera()


func pan(delta_world: Vector3) -> void:
	focus_target = _clamp_focus(focus_target + Vector3(delta_world.x, 0.0, delta_world.z))


func zoom_by(factor: float, toward := Vector3.INF) -> void:
	var old := distance_target
	distance_target = clampf(distance_target * factor, DIST_MIN, DIST_MAX)
	if toward != Vector3.INF and old > 0.0:
		var k := 1.0 - distance_target / old
		pan((toward - focus_target) * k)


func pitch_for(dist: float) -> float:
	return lerpf(PITCH_NEAR, PITCH_FAR, smoothstep(DIST_MIN, DIST_MAX * 0.8, dist))


func _clamp_focus(f: Vector3) -> Vector3:
	return Vector3(clampf(f.x, 0.0, RegionTerrain.W), GROUND_Y, clampf(f.z, 0.0, RegionTerrain.H))


func _apply_camera() -> void:
	if camera == null:
		return
	var p := deg_to_rad(pitch_for(distance))
	var offset := Vector3(0.0, sin(p), cos(p)) * distance
	offset = offset.rotated(Vector3.UP, yaw)
	camera.position = focus + offset
	camera.look_at(focus, Vector3.UP)


func _process(delta: float) -> void:
	if not _built:
		return
	var k := 1.0 - exp(-delta * 9.0)
	focus = focus.lerp(focus_target, k)
	distance = lerpf(distance, distance_target, k)
	_apply_camera()
	cloud_time += delta * cloud_rate
	_update_clouds()


func _update_clouds() -> void:
	var off := CLOUD_SPEED * cloud_time
	var cam_fade := smoothstep(CLOUD_Y + 6.0, CLOUD_Y + 40.0, camera.position.y)
	for m in [surface_mat, props_mat, tree_mat, water_mat]:
		m.set_shader_parameter("cloud_offset", off)
	for i in cloud_mats.size():
		var m := cloud_mats[i]
		m.set_shader_parameter("cloud_offset", off * (1.0 + i * 0.25))
		m.set_shader_parameter("opacity", CLOUD_OPACITY[i] * cam_fade * cloud_amount)
		m.set_shader_parameter("clear_a", _clear_a)
		m.set_shader_parameter("clear_b", _clear_b)


## Where to clear the clouds: the cursor (screen position, or Vector2.INF for
## none) and the selected place (world position, or Vector3.INF).
func set_clear_points(cursor: Vector2, selected: Vector3) -> void:
	_clear_a = Vector2(-999, -999)
	_clear_b = Vector2(-999, -999)
	if camera == null:
		return
	if cursor != Vector2.INF:
		var hit := ray_plane(cursor, CLOUD_Y)
		if hit != Vector3.INF:
			_clear_a = Vector2(hit.x, hit.z)
	if selected != Vector3.INF:
		var o := camera.global_position
		var dy := o.y - selected.y
		if dy > 0.01:
			var t := (o.y - CLOUD_Y) / dy
			var q := o.lerp(selected, t)
			_clear_b = Vector2(q.x, q.z)


func set_selected(world: Vector3) -> void:
	surface_mat.set_shader_parameter("sel_pos", world if world != Vector3.INF else Vector3(-1000, 0, -1000))


## 0 = day, 1 = night (state.night_amount()).
func set_night(n: float) -> void:
	night = clampf(n, 0.0, 1.0)
	if environment == null:
		return
	environment.background_color = DAY["bg"].lerp(NIGHT["bg"], night)
	environment.fog_light_color = DAY["fog"].lerp(NIGHT["fog"], night)
	environment.ambient_light_color = DAY["ambient"].lerp(NIGHT["ambient"], night)
	environment.ambient_light_energy = lerpf(DAY["ambient_energy"], NIGHT["ambient_energy"], night)
	sun.light_color = DAY["sun"].lerp(NIGHT["sun"], night)
	sun.light_energy = lerpf(DAY["sun_energy"], NIGHT["sun_energy"], night)
	home_light.light_energy = lerpf(1.0, 3.2, night)
	home_light.omni_range = lerpf(3.2, 5.0, night)
	var fog: Color = environment.background_color
	for m in [surface_mat, props_mat, tree_mat, water_mat]:
		m.set_shader_parameter("night", night)
		m.set_shader_parameter("fog_color", fog)
	for m in cloud_mats:
		m.set_shader_parameter("night", night)


# --- projection -----------------------------------------------------------------

## Intersection of the camera ray through a viewport position with y = plane_y.
func ray_plane(screen: Vector2, plane_y: float) -> Vector3:
	var o := camera.project_ray_origin(screen)
	var d := camera.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return Vector3.INF
	var t := (plane_y - o.y) / d.y
	return o + d * t if t > 0.0 else Vector3.INF


## The ground under a viewport position (marches the heightfield; falls back
## to the pan plane).
func ground_point(screen: Vector2) -> Vector3:
	var o := camera.project_ray_origin(screen)
	var d := camera.project_ray_normal(screen)
	var p := o
	var step := 0.5
	for k in 900:
		p += d * step
		var c := Vector2i(int(floor(p.x)), int(floor(p.z)))
		if RegionTerrain.in_bounds(c) and p.y <= terrain.surface_y(c):
			return p
		if p.y < -4.0:
			break
	var hit := ray_plane(screen, GROUND_Y)
	return hit


func project(world: Vector3) -> Vector2:
	return camera.unproject_position(world)


func is_visible_point(world: Vector3) -> bool:
	return not camera.is_position_behind(world)
