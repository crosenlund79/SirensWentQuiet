class_name ModPlayer
extends CharacterBody3D
## The player: WASD movement, body turns toward the aim, two-handed pistol
## with muzzle flash and recoil. Weapon light + faint self light at night.
## Cannot die; does not collide with enemies.

const LAYER_PLAYER := 4          # physics layer 3
const MASK := 1 | 2 | 16         # environment, walls, low obstacles

var figure: ModFigure
var weapon_light: SpotLight3D
var self_light: OmniLight3D
var flash_light: OmniLight3D
var flash_mesh: MeshInstance3D
var aim_dir := Vector2(0, -1)    ## plan-space facing (unit)
var night := false

var _flash_t := 0.0


func _ready() -> void:
	collision_layer = LAYER_PLAYER
	collision_mask = MASK
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = Tuning.PLAYER_RADIUS
	cap.height = Tuning.CLEARANCE_HEIGHT - 0.05
	cs.shape = cap
	cs.position = Vector3(0, 0.05 + cap.height * 0.5, 0)
	add_child(cs)

	figure = ModFigure.new()
	figure.look = {
		"skin": Color(0.84, 0.66, 0.52), "hair": Color(0.18, 0.13, 0.1),
		"top": Color(0.17, 0.2, 0.25), "top2": Color(0.13, 0.15, 0.19),
		"pants": Color(0.24, 0.26, 0.3), "shoes": Color(0.36, 0.25, 0.16),
		"accent": Color(0.95, 0.45, 0.12), "pack": Color(0.28, 0.27, 0.22), "gun": true,
	}
	figure.aiming = true
	figure.position.y = 0.025
	add_child(figure)

	weapon_light = SpotLight3D.new()
	weapon_light.light_color = Color(0.92, 0.95, 1.0)
	weapon_light.light_energy = 0.0
	weapon_light.spot_range = 15.0
	weapon_light.spot_angle = 26.0
	weapon_light.spot_angle_attenuation = 0.8
	weapon_light.spot_attenuation = 0.6
	weapon_light.shadow_enabled = true
	weapon_light.shadow_bias = 0.05
	weapon_light.light_volumetric_fog_energy = 1.5
	weapon_light.position = Vector3(0.12, Tuning.MUZZLE_HEIGHT, 0.35)
	weapon_light.visible = false
	add_child(weapon_light)

	self_light = OmniLight3D.new()
	self_light.light_color = Color(0.75, 0.8, 1.0)
	self_light.omni_range = 2.6
	self_light.light_energy = 0.0
	self_light.position = Vector3(0, 2.2, 0.4)
	self_light.visible = false
	add_child(self_light)

	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.75, 0.4)
	flash_light.omni_range = 5.0
	flash_light.light_energy = 0.0
	flash_light.visible = false
	add_child(flash_light)

	flash_mesh = MeshInstance3D.new()
	flash_mesh.mesh = _flash_star()
	flash_mesh.material_override = ModMaterials.fx_add()
	flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_mesh.visible = false
	# the flash rides on the gun so recoil and turning carry it along
	figure.muzzle.add_child(flash_mesh)
	flash_light.reparent(figure.muzzle, false)
	flash_light.position = Vector3.ZERO


func plan_pos() -> Vector2:
	return Vector2(global_position.x, global_position.z)


## World position of the gun muzzle.
func muzzle_position() -> Vector3:
	if figure != null and figure.muzzle != null:
		return figure.muzzle.global_position
	return global_position + Vector3(aim_dir.x, 0, aim_dir.y) * 0.5 + Vector3(0, Tuning.MUZZLE_HEIGHT, 0)


func move_with(input: Vector2, delta: float) -> void:
	var target := input.limit_length(1.0) * Tuning.PLAYER_SPEED
	var v := Vector2(velocity.x, velocity.z).move_toward(target, Tuning.PLAYER_ACCEL * delta)
	velocity = Vector3(v.x, 0, v.y)
	move_and_slide()
	global_position.y = 0.0
	figure.speed = Vector2(velocity.x, velocity.z).length()


func face(dir: Vector2, delta: float) -> void:
	if dir.length_squared() < 1e-4:
		return
	aim_dir = dir.normalized()
	var target := atan2(aim_dir.x, aim_dir.y)
	figure.rotation.y = lerp_angle(figure.rotation.y, target, minf(1.0, delta * 18.0))
	var basis_y := Basis(Vector3.UP, figure.rotation.y)
	weapon_light.position = basis_y * Vector3(0.1, Tuning.MUZZLE_HEIGHT, 0.4)


## Point the weapon light at a world point (keeps the beam on the aim).
func aim_light_at(point: Vector3) -> void:
	if not weapon_light.visible:
		return
	var from := global_position + weapon_light.position
	var to := Vector3(point.x, minf(point.y, from.y - 0.25), point.z)
	if from.distance_to(to) > 0.3:
		weapon_light.look_at(to, Vector3.UP)


func fired() -> void:
	figure.recoil = 1.0
	_flash_t = 0.06
	flash_light.visible = true
	flash_light.light_energy = 3.5
	flash_mesh.visible = true
	flash_mesh.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	var s := randf_range(0.8, 1.2)
	flash_mesh.scale = Vector3(s, s, s)


func set_night(on: bool) -> void:
	night = on
	weapon_light.visible = on
	self_light.visible = on
	weapon_light.light_energy = 5.0 if on else 0.0
	self_light.light_energy = 0.55 if on else 0.0
	figure.set_param("rim", 0.35 if on else 0.0)


func _process(delta: float) -> void:
	figure.animate(delta)
	if _flash_t > 0.0:
		_flash_t -= minf(delta, 0.05)   # always survives at least one frame
		if _flash_t <= 0.0:
			flash_light.visible = false
			flash_mesh.visible = false
		else:
			flash_light.light_energy = 3.5 * (_flash_t / 0.06)


## Small spiky star for the muzzle flash (additive, vertex coloured).
static func _flash_star() -> ArrayMesh:
	var mm := ModMesh.new()
	var core := Color(1.0, 0.92, 0.65)
	var outer := Color(1.0, 0.55, 0.15, 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var a: Vector3 = axis
		var b := a.cross(Vector3(0.3, 0.7, 0.2)).normalized()
		for k in 6:
			var ang0 := TAU * k / 6.0
			var ang1 := TAU * (k + 1) / 6.0
			var r0 := 0.3 if k % 2 == 0 else 0.09
			var r1 := 0.3 if (k + 1) % 2 == 0 else 0.09
			var c := a.cross(b)
			st.set_color(core)
			st.add_vertex(Vector3.ZERO)
			st.set_color(outer)
			st.add_vertex((b * cos(ang0) + c * sin(ang0)) * r0)
			st.set_color(outer)
			st.add_vertex((b * cos(ang1) + c * sin(ang1)) * r1)
	mm = null
	return st.commit()
