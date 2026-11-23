extends CharacterBody2D
## A "psycho": shared PursuitBrain decisions, token presentation (shamble
## sway, lunge on swings, hit flash, knockback) and a collapse into an
## illustrated fallen pose that fades after Tuning.ENEMY_CORPSE_TIME.

signal died(enemy)
signal swung(enemy, kind: String, target: Vector2)

const Art := preload("res://src/illustrated/ill_art.gd")
const Token := preload("res://src/illustrated/token.gd")

var brain: PursuitBrain
var target_provider: Callable          ## () -> Vector2 player plan position
var variant := "a"
var hp := Tuning.ENEMY_HP
var alive := true
var frozen := false                    ## scenarios: stand still (still reacts to hits)
var token: Token
var _stagger := 0.0
var _kb := Vector2.ZERO
var _kb_t := 0.0
var _walk := 0.0
var _phase := 0.0
var _corpse: Sprite2D


func setup(nav: GridNav, provider: Callable, p_variant: String) -> void:
	brain = PursuitBrain.new(nav)
	target_provider = provider
	variant = p_variant


func _ready() -> void:
	add_to_group("ill_enemies")
	collision_layer = 8                     # layer 4 "enemies"
	collision_mask = 1 | 2 | 8 | 16         # environment, walls, enemies, low obstacles
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = Art.m(Tuning.ENEMY_RADIUS)
	cs.shape = c
	add_child(cs)
	token = Token.new()
	token.z_index = Art.Z_ACTORS
	token.z_as_relative = false
	add_child(token)
	token.setup("psycho_" + variant, 1.0)
	_phase = randf() * TAU
	token.facing = randf() * TAU


func plan_pos() -> Vector2:
	return Art.plan(global_position)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	var r := brain.update(delta, plan_pos(), target_provider.call())
	var v := Vector2.ZERO
	if _stagger > 0.0:
		_stagger -= delta
	elif not frozen:
		v = r["move"] * Tuning.ENEMY_SPEED * Art.PX_PER_M
	if _kb_t > 0.0:
		v += _kb
		_kb_t -= delta
	velocity = v
	move_and_slide()
	var face: Vector2 = r["face"]
	if face.length() > 0.1:
		token.face(face.angle(), delta, 5.0)
	# shamble: uneven sway and a slow bob while walking
	var speed := clampf(velocity.length() / (Tuning.ENEMY_SPEED * Art.PX_PER_M), 0.0, 1.0)
	_walk += delta * 6.0 * speed
	token.sway = (sin(_walk + _phase) * 0.16 + sin(_walk * 0.5 + _phase) * 0.07) * speed + (0.3 if _stagger > 0.0 else 0.0) * sin(_stagger * 40.0)
	token.bob = absf(sin(_walk)) * 0.03 * speed
	if r["swing"] != "":
		token.kick = -Art.m(0.16)          # lunge forward, springs back
		swung.emit(self, r["swing"], r["target"])


func hit(dmg: int, dir: Vector2) -> void:
	if not alive:
		return
	hp -= dmg
	token.flash()
	_stagger = Tuning.ENEMY_HIT_STAGGER
	_kb = dir.normalized() * Art.m(Tuning.ENEMY_KNOCKBACK) / 0.12
	_kb_t = 0.12
	token.kick = Art.m(0.06)
	if hp <= 0:
		die(dir)


func die(dir: Vector2) -> void:
	if not alive:
		return
	alive = false
	collision_layer = 0
	collision_mask = 0
	died.emit(self)
	var ang := dir.angle() if dir != Vector2.ZERO else token.facing
	# the standing token tips and fades while the fallen pose settles in
	var tw := token.create_tween().set_parallel(true)
	tw.tween_property(token, "sway", 0.9 * (1.0 if randf() < 0.5 else -1.0), 0.25)
	tw.tween_property(token, "bob", -0.25, 0.25)
	tw.tween_property(token, "modulate:a", 0.0, 0.3)
	var tex := Art.tex("psycho_%s_dead" % variant)
	if tex != null:
		_corpse = Sprite2D.new()
		_corpse.texture = tex
		var k := 2.0 * Art.PX_PER_M / tex.get_size().x
		_corpse.scale = Vector2(k, k) * 0.9
		_corpse.rotation = ang + randf_range(-0.25, 0.25)
		_corpse.z_index = Art.Z_CORPSES
		_corpse.z_as_relative = false
		_corpse.modulate.a = 0.0
		_corpse.position = Vector2.ZERO
		add_child(_corpse)
		var ct := _corpse.create_tween().set_parallel(true)
		ct.tween_property(_corpse, "modulate:a", 1.0, 0.18)
		ct.tween_property(_corpse, "position", Vector2.RIGHT.rotated(ang) * Art.m(0.45), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ct.tween_property(_corpse, "scale", Vector2(k, k), 0.3)
	var fade := create_tween()
	fade.tween_interval(Tuning.ENEMY_CORPSE_TIME)
	fade.tween_property(self, "modulate", Color(0.35, 0.33, 0.32, 0.0), 1.4)
	fade.tween_callback(queue_free)
