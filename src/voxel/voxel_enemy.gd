class_name VoxelEnemy
extends CharacterBody3D
## A "psycho" (Version A): moves on the shared PursuitBrain's decisions,
## swings at walls (the root carves a bite) and at the player (no damage).
## Hit: flash, stagger, knockback. Death: collapse, linger, sink away.

signal wall_swing(enemy: VoxelEnemy, target: Vector2)
signal player_swing(enemy: VoxelEnemy)

var brain: PursuitBrain
var player: Node3D
var rig: VoxelRig
var hp := Tuning.ENEMY_HP
var alive := true
var _stagger := 0.0
var _knock := Vector3.ZERO
var _dead_t := 0.0
var _fall_axis := Vector3.RIGHT
var _swing_pending := 0.0
var _swing_kind := ""
var _swing_target := Vector2.ZERO
var _tight_time := 0.0
var _unstick_cd := 0.0
var _best_d := INF

## Voxel holes open cell by cell, so a body can sit in a half-open gap where
## the shared brain's path is OPEN but not yet walkable and it oscillates
## instead of reporting "stuck". After this long without getting closer to the
## player we swing at the nearest remaining wall cell within reach (same
## reach and rhythm as the brain's own wall swings).
const TIGHT_UNSTICK := 2.5


func setup(nav: GridNav, target: Node3D, look: int) -> void:
	brain = PursuitBrain.new(nav)
	player = target
	rig = VoxelRig.new(look)


func _ready() -> void:
	collision_layer = 1 << 3                 # enemies
	collision_mask = 1 | 2 | 8 | 16          # environment, walls, enemies, low obstacles
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = Tuning.ENEMY_RADIUS
	cyl.height = VoxelPlayer.BODY_TOP - VoxelPlayer.BODY_BOTTOM
	cs.shape = cyl
	cs.position.y = (VoxelPlayer.BODY_TOP + VoxelPlayer.BODY_BOTTOM) * 0.5
	add_child(cs)
	add_child(rig)


func plan_pos() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func take_hit(dir: Vector3) -> void:
	if not alive:
		return
	hp -= Tuning.SHOT_DAMAGE
	rig.set_flash(1.0)
	rig.stagger = 1.0
	_stagger = Tuning.ENEMY_HIT_STAGGER
	var d := Vector3(dir.x, 0, dir.z).normalized()
	_knock = d * (Tuning.ENEMY_KNOCKBACK / Tuning.ENEMY_HIT_STAGGER)
	if hp <= 0:
		_die(d)


func _die(dir: Vector3) -> void:
	alive = false
	collision_layer = 0
	collision_mask = 0
	_fall_axis = dir.cross(Vector3.UP).normalized() if dir.length() > 0.01 else Vector3.RIGHT
	_dead_t = 0.0


func _physics_process(delta: float) -> void:
	if not alive:
		_dead_t += delta
		# collapse: knees buckle, then topple along the shot direction
		var fall := clampf(_dead_t / 0.45, 0.0, 1.0)
		fall = fall * fall
		rig.transform.basis = Basis(_fall_axis, -fall * PI * 0.48)
		rig.position.y = -0.1 * fall
		rig.speed = 0.0
		rig.animate(delta)
		if _dead_t > Tuning.ENEMY_CORPSE_TIME:
			var k := clampf((_dead_t - Tuning.ENEMY_CORPSE_TIME) / 1.2, 0.0, 1.0)
			rig.position.y = -0.1 - 0.35 * k
			rig.set_fade(1.0 - k)
			if k >= 1.0:
				queue_free()
		return
	var me := plan_pos()
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var r := brain.update(delta, me, pp)
	var move: Vector2 = r["move"]
	var face: Vector2 = r["face"]
	if _stagger > 0.0:
		_stagger -= delta
		velocity = _knock
		_knock = _knock.move_toward(Vector3.ZERO, delta * 8.0)
	else:
		velocity = Vector3(move.x, 0, move.y) * Tuning.ENEMY_SPEED
	move_and_slide()
	global_position.y = 0.0
	if face.length() > 0.01:
		var yaw := atan2(-face.x, -face.y)
		rig.rotation.y = lerp_angle(rig.rotation.y, yaw, 1.0 - exp(-delta * 6.0))
	_unstick(delta, me, r)
	if r["swing"] != "":
		rig.swing = 1.0
		_swing_kind = r["swing"]
		_swing_target = r["target"]
		_swing_pending = 0.28        # impact lands at the bottom of the swing
	if _swing_pending > 0.0:
		_swing_pending -= delta
		if _swing_pending <= 0.0:
			if _swing_kind == "wall":
				wall_swing.emit(self, _swing_target)
			elif _swing_kind == "player":
				player_swing.emit(self)
	rig.swing = maxf(rig.swing - delta / 0.5, 0.0)
	rig.speed = Vector2(velocity.x, velocity.z).length() if _stagger <= 0.0 else 0.0
	rig.animate(delta)


func _unstick(delta: float, me: Vector2, r: Dictionary) -> void:
	var nav := brain.nav
	var d := me.distance_to(Vector2(player.global_position.x, player.global_position.z))
	_unstick_cd = maxf(_unstick_cd - delta, 0.0)
	if r["swing"] != "" or d < _best_d - 0.3 or d <= Tuning.ENEMY_ATTACK_RANGE + 0.2:
		_best_d = minf(_best_d, d) if r["swing"] == "" else d
		_tight_time = 0.0
		return
	_tight_time += delta
	if _tight_time < TIGHT_UNSTICK or _unstick_cd > 0.0:
		return
	var w := nav.nearest_raw_wall(nav.cell_of(me), me, 3)
	if w.x >= 0 and me.distance_to(nav.center_of(w)) <= PursuitBrain.REACH + 0.25:
		r["swing"] = "wall"
		r["target"] = nav.center_of(w)
		_unstick_cd = Tuning.ENEMY_ATTACK_INTERVAL
	else:
		_best_d = d
		_tight_time = 0.0
