extends CharacterBody2D
## The player of Version C: WASD movement, mouse aim, token presentation and
## (at night) a shadow-casting weapon light plus a faint self light.
## Shooting is resolved by the scene root (one gun, one hitscan).

const Art := preload("res://src/illustrated/ill_art.gd")
const Token := preload("res://src/illustrated/token.gd")

var token: Token
var aim_dir := Vector2.RIGHT
var aim_point := Vector2.ZERO
var use_mouse := true
var weapon_light: PointLight2D
var self_light: PointLight2D
var _walk := 0.0


func _ready() -> void:
	collision_layer = 4                 # layer 3 "player"
	collision_mask = 1 | 2 | 16         # environment, walls, low obstacles
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = Art.m(Tuning.PLAYER_RADIUS)
	cs.shape = c
	add_child(cs)
	token = Token.new()
	token.z_index = Art.Z_ACTORS + 1
	token.z_as_relative = false
	add_child(token)
	token.setup("player", 1.0)
	weapon_light = PointLight2D.new()
	weapon_light.texture = Art.tex("light_cone")
	weapon_light.texture_scale = 1.15
	weapon_light.color = Color(1.0, 0.95, 0.84)
	weapon_light.energy = 0.0
	weapon_light.shadow_enabled = true
	weapon_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	weapon_light.shadow_filter_smooth = 1.5
	weapon_light.shadow_color = Color(0, 0, 0, 0.85)
	weapon_light.enabled = false
	add_child(weapon_light)
	self_light = PointLight2D.new()
	self_light.texture = Art.tex("light_soft")
	self_light.texture_scale = 0.45
	self_light.color = Color(0.85, 0.8, 0.72)
	self_light.energy = 0.0
	self_light.enabled = false
	add_child(self_light)
	aim_point = global_position + Vector2.RIGHT * 100.0


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var target := input * Tuning.PLAYER_SPEED * Art.PX_PER_M
	velocity = velocity.move_toward(target, Tuning.PLAYER_ACCEL * Art.PX_PER_M * delta)
	move_and_slide()
	if use_mouse:
		aim_point = get_global_mouse_position()
	var d := aim_point - global_position
	if d.length() > 6.0:
		aim_dir = d.normalized()
	token.face(aim_dir.angle(), delta, 22.0)
	var speed := clampf(velocity.length() / (Tuning.PLAYER_SPEED * Art.PX_PER_M), 0.0, 1.0)
	_walk += delta * 10.0 * speed
	token.bob = absf(sin(_walk)) * 0.04 * speed
	token.sway = sin(_walk) * 0.07 * speed
	weapon_light.rotation = aim_dir.angle()


func plan_pos() -> Vector2:
	return Art.plan(global_position)


func muzzle_position() -> Vector2:
	return global_position + aim_dir * Art.m(0.46)


func recoil() -> void:
	token.kick = Art.m(0.08)
	token.facing += randf_range(-0.06, 0.06)


## 0 = day, 1 = night (blended during the transition).
func set_night_amount(k: float) -> void:
	weapon_light.energy = 1.35 * k
	weapon_light.enabled = k > 0.01
	self_light.energy = 0.55 * k
	self_light.enabled = k > 0.01
