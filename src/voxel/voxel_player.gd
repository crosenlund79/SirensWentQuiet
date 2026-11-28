class_name VoxelPlayer
extends CharacterBody3D
## Player body (Version A): WASD movement on the floor plane, turns toward the
## aim point, carries the voxel rig, a weapon light and a faint self light.
## Collision: cylinder 0.14-1.56 m (clears ragged hole sills below 0.15 m).

const BODY_BOTTOM := 0.14
const BODY_TOP := 1.56

var rig: VoxelRig
var aim_point := Vector3.ZERO
var weapon_light: SpotLight3D
var self_light: OmniLight3D
var muzzle_light: OmniLight3D
var input_enabled := true
var speed_scale := 1.0             ## survival: energy / exhaustion (GameState.move_speed_scale)
var move_band: RefCounted = null   ## Exp 012 (V): FogBand at the world's edge (slows outward motion in the fog)
## Experiment 004 storeys (owner L): height of the floor the player stands on
## (0 ground floor; the game's level helper sets it when changing storey).
var floor_y := 0.0
## Experiment 004: holding Shift ("sprint") runs SPRINT_SCALE faster while
## moving; the game clears sprint_allowed when energy runs out and drains
## energy while `sprinting`.
const SPRINT_SCALE := 1.6
var sprint_allowed := true
var sprinting := false
var _last_pos := Vector3.INF          ## Refinement 01: last frame's position, for the gait
## Refinement 01: the camera's yaw (rad); WASD moves relative to the screen.
var move_yaw := 0.0
## Exp 012 (§31): whether the gun's own light (weapon_light) shines by itself
## at night. The demos keep it; the survival game turns it off and its one
## beam is the flashlight in hand (GameHotbar), so Eli never starts with a
## cone lit and a flashlight never adds a second one. The soft self light
## (ambient night visibility around him) stays either way.
var auto_beam := true
## Exp 010: which figure carries the player ("eli" / "original", GameSettings
## "character" + "eli_variant"); a settings change swaps it live (swap_rig).
var character_key := ""


func _ready() -> void:
	collision_layer = 1 << 2            # player
	collision_mask = 1 | 2 | 16 | 32    # environment, walls, low obstacles, lot boundary
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = Tuning.PLAYER_RADIUS
	cyl.height = BODY_TOP - BODY_BOTTOM
	cs.shape = cyl
	cs.position.y = (BODY_TOP + BODY_BOTTOM) * 0.5
	add_child(cs)
	rig = make_rig()
	add_child(rig)
	rig.aiming = true

	weapon_light = SpotLight3D.new()
	weapon_light.light_color = Color(1.0, 0.93, 0.8)
	weapon_light.spot_range = 15.0
	weapon_light.spot_angle = 24.0
	weapon_light.spot_angle_attenuation = 0.7
	weapon_light.light_energy = 0.0
	weapon_light.shadow_enabled = true
	weapon_light.shadow_bias = 0.05
	weapon_light.visible = false
	add_child(weapon_light)
	self_light = OmniLight3D.new()
	self_light.light_color = Color(0.75, 0.82, 1.0)
	self_light.omni_range = 3.2
	self_light.light_energy = 0.0
	self_light.position = Vector3(0, 2.2, 0.4)
	self_light.visible = false
	add_child(self_light)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.75, 0.4)
	muzzle_light.omni_range = 5.0
	muzzle_light.light_energy = 0.0
	muzzle_light.visible = false
	add_child(muzzle_light)


## Exp 010: the rig the settings ask for: Eli (EliRig, a variation) or the
## original voxel figure.
func make_rig() -> VoxelRig:
	character_key = _wanted_character()
	if character_key.begins_with("eli"):
		return EliRig.new(int(character_key.trim_prefix("eli")))
	return VoxelRig.new(VoxelRig.Look.PLAYER)


static func _wanted_character() -> String:
	if str(GameSettings.get_value("character")) == "original":
		return "original"
	return "eli%d" % int(GameSettings.get_value("eli_variant"))


## Exp 010: replaces the rig in place, keeping its facing, aim, weapon pose,
## held item and light (the weapon handler re-dresses the new gun node).
func swap_rig() -> void:
	var old := rig
	var r := make_rig()
	r.rotation = old.rotation
	add_child(r)
	r.aiming = old.aiming
	r.aim_pitch = old.aim_pitch
	r.carry = old.carry
	r.use_t = old.use_t
	r.set_held(old.held)
	r.visible = old.visible
	rig = r
	remove_child(old)
	old.queue_free()
	_last_pos = Vector3.INF


func plan_pos() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func set_night(t: float) -> void:
	weapon_light.light_energy = 2.6 * t if auto_beam else 0.0
	weapon_light.visible = auto_beam and t > 0.01
	self_light.light_energy = 0.5 * t
	self_light.visible = t > 0.01


## Exp 012 (§31): hands the beam to the equipment (see auto_beam); the self
## light reaches a little further to keep the ambient night visibility.
func use_handheld_beam() -> void:
	auto_beam = false
	weapon_light.visible = false
	weapon_light.light_energy = 0.0
	self_light.omni_range = 4.2


func _physics_process(delta: float) -> void:
	if _wanted_character() != character_key:
		swap_rig()
	var dir := Vector2.ZERO
	if input_enabled:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	sprinting = input_enabled and sprint_allowed and dir != Vector2.ZERO and InputMap.has_action("sprint") \
			and Input.is_action_pressed("sprint")
	var want := Vector3(dir.x, 0, dir.y).rotated(Vector3.UP, move_yaw) * Tuning.PLAYER_SPEED * speed_scale * (SPRINT_SCALE if sprinting else 1.0)
	if move_band != null:
		want = move_band.limit(global_position, want)
	var v := Vector3(velocity.x, 0, velocity.z)
	v = v.move_toward(want, Tuning.PLAYER_ACCEL * delta)
	velocity = v
	move_and_slide()
	global_position.y = floor_y
	velocity.y = 0.0
	# Face the aim point.
	var to := aim_point - global_position
	to.y = 0.0
	if to.length() > 0.2:
		var yaw := atan2(-to.x, -to.z)
		rig.rotation.y = lerp_angle(rig.rotation.y, yaw, 1.0 - exp(-delta * 18.0))
		var muzzle_h := Tuning.MUZZLE_HEIGHT
		rig.aim_pitch = clampf(atan2(aim_point.y - floor_y - muzzle_h, to.length()), -0.9, 0.7)
	# Refinement 01: the gait follows how far the body really moved this frame
	# (walls and furniture stop it), not the wanted velocity.
	var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	rig.speed = moved / maxf(delta, 0.0001) if _last_pos != Vector3.INF and moved < 1.0 else 0.0   # a teleport (stairs, waking) is no step
	_last_pos = global_position
	rig.animate(delta)
	# Weapon light follows the gun.
	var m := rig.muzzle_global()
	var fwd := (aim_point - m)
	if fwd.length() < 0.1:
		fwd = -rig.global_transform.basis.z
	weapon_light.global_position = m
	weapon_light.look_at(m + fwd.normalized(), Vector3.UP)
	if muzzle_light.visible:
		muzzle_light.global_position = m + fwd.normalized() * 0.2
		muzzle_light.light_energy = maxf(muzzle_light.light_energy - delta * 90.0, 0.0)
		if muzzle_light.light_energy <= 0.0:
			muzzle_light.visible = false


func on_fired() -> void:
	rig.recoil = 1.0
	muzzle_light.visible = true
	muzzle_light.light_energy = 4.0
