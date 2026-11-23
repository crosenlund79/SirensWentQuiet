class_name ModEnemy
extends CharacterBody3D
## A "psycho": disturbed ordinary person. Movement decisions come only from
## the shared PursuitBrain. Hit flash, stagger and knockback; collapses on
## death, lies still, then sinks away. Swings are harmless.

signal swung(enemy: ModEnemy, kind: String, target: Vector2)
signal died(enemy: ModEnemy)

const LAYER_ENEMY := 8              # physics layer 4
const MASK := 1 | 2 | 8 | 16        # environment, walls, enemies, low obstacles

const LOOKS := [
	{"top": Color(0.78, 0.76, 0.7), "pants": Color(0.32, 0.36, 0.44), "hair": Color(0.16, 0.13, 0.12)},
	{"top": Color(0.42, 0.5, 0.6), "pants": Color(0.45, 0.42, 0.36), "hair": Color(0.5, 0.48, 0.45)},
	{"top": Color(0.48, 0.2, 0.2), "pants": Color(0.22, 0.22, 0.24), "hair": Color(0.3, 0.2, 0.14), "bald": false},
	{"top": Color(0.62, 0.55, 0.32), "pants": Color(0.3, 0.32, 0.3), "hair": Color(0.12, 0.1, 0.1)},
	{"top": Color(0.35, 0.42, 0.36), "pants": Color(0.5, 0.47, 0.42), "bald": true},
]

var brain: PursuitBrain
var hp := Tuning.ENEMY_HP
var alive := true
var figure: ModFigure
var player_pos := Vector2.ZERO     ## set by the demo each frame (plan meters)

var _stagger_t := 0.0
var _knock := Vector3.ZERO
var _flash := 0.0
var _swing_t := -1.0
var _dead_t := 0.0
var _shape: CollisionShape3D


func setup(nav: GridNav, variant: int) -> void:
	brain = PursuitBrain.new(nav)
	var l: Dictionary = LOOKS[variant % LOOKS.size()].duplicate()
	l["enemy"] = true
	l["skin"] = Color(0.8, 0.8, 0.74).darkened(randf_range(0.0, 0.12))
	l["shoes"] = Color(0.2, 0.18, 0.17)
	l["top2"] = (l["top"] as Color).darkened(0.12)
	l["hunch"] = randf_range(0.32, 0.5)
	figure = ModFigure.new()
	figure.look = l
	figure.limp = randf_range(0.0, 0.8)
	figure.phase = randf() * TAU


func _ready() -> void:
	collision_layer = LAYER_ENEMY
	collision_mask = MASK
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = Tuning.ENEMY_RADIUS
	cap.height = Tuning.CLEARANCE_HEIGHT - 0.05
	_shape.shape = cap
	_shape.position = Vector3(0, 0.05 + cap.height * 0.5, 0)
	add_child(_shape)
	figure.position.y = 0.025
	add_child(figure)


func plan_pos() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func hit(dir: Vector3) -> void:
	if not alive:
		return
	hp -= Tuning.SHOT_DAMAGE
	_flash = 1.0
	_stagger_t = Tuning.ENEMY_HIT_STAGGER
	figure.stagger = 1.0
	var d := Vector3(dir.x, 0, dir.z).normalized()
	_knock = d * (2.0 * Tuning.ENEMY_KNOCKBACK / 0.15)
	if hp <= 0:
		_die(d)


func _die(d: Vector3) -> void:
	alive = false
	collision_layer = 0
	collision_mask = 0
	_shape.disabled = true
	# fall away from the shot
	var local := figure.global_transform.basis.inverse() * d
	figure.fall_dir = 1.0 if local.z > 0.0 else -1.0
	died.emit(self)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	var move := Vector2.ZERO
	var r := brain.update(delta, plan_pos(), player_pos)
	if _stagger_t > 0.0:
		_stagger_t -= delta
	else:
		move = r["move"]
	var face: Vector2 = r["face"]
	if face.length_squared() > 0.01:
		var target := atan2(face.x, face.y)
		figure.rotation.y = lerp_angle(figure.rotation.y, target, minf(1.0, delta * 6.0))
	if r["swing"] != "":
		_swing_t = 0.0
		swung.emit(self, r["swing"], r["target"])
	var v := Vector3(move.x, 0, move.y) * Tuning.ENEMY_SPEED
	if _knock.length_squared() > 0.0001:
		v += _knock
		_knock = _knock.move_toward(Vector3.ZERO, 2.0 * Tuning.ENEMY_KNOCKBACK / 0.15 / 0.15 * delta)
	velocity = v
	move_and_slide()
	global_position.y = 0.0
	figure.speed = move.length() * Tuning.ENEMY_SPEED


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		figure.set_param("flash", _flash)
	if _swing_t >= 0.0:
		_swing_t += delta / 0.55
		figure.swing = _swing_t
		if _swing_t >= 1.0:
			_swing_t = -1.0
			figure.swing = -1.0
	if not alive:
		_dead_t += delta
		figure.dead = minf(_dead_t / 0.7, 1.0)
		figure.speed = 0.0
		if _dead_t > Tuning.ENEMY_CORPSE_TIME:
			var f := (_dead_t - Tuning.ENEMY_CORPSE_TIME) / 1.2
			figure.set_param("fade", clampf(f, 0.0, 1.0))
			figure.position.y = -0.25 * f
			if f >= 1.0:
				queue_free()
	figure.animate(delta)
