class_name AIEnemy
extends VoxelEnemy
## The one enemy body of Experiment 003 (SPEC-003 §5): a CharacterBody3D that
## any archetype in EnemyDefs drives, with a shared behaviour core:
##   perception and target selection  -> EnemyBehaviour (chase / bomber hook)
##   navigation, bashing, stuck rules -> PursuitBrain on the shared GridNav,
##                                       through a WeightedNav for the
##                                       archetype's bash cost
##   new breaches                     -> the brain repaths on every nav revision
##   wall, door and barricade attacks -> wall_swing (the roster turns it into
##                                       `wall_strikes` world.enemy_strike calls)
##   player attacks                   -> player_swing (damage_scale for the game)
##   damage, stagger, knockback, death, retreat, wave membership (meta "invader")
##
## It extends VoxelEnemy only for type compatibility with the Experiment 002
## game (HouseWorld.shoot's `is VoxelEnemy`, the game's typed signal handlers):
## every behaviour is overridden here, VoxelEnemy's own brain and unstick code
## are unused, and VoxelEnemy itself is unchanged (the Experiment 001 demo
## keeps using it). Call configure() before adding it to the tree.

signal fuse_started(enemy: AIEnemy, at: Vector3, seconds: float)
signal detonated(at: Vector3, radius: float, damage: float)
signal fizzled(enemy: AIEnemy, at: Vector3)
signal died(enemy: AIEnemy, cause: String)

const SWING_IMPACT := 0.28          ## s from the swing start to the impact
const RETREAT_SPEED := 1.1          ## x speed while walking back into the fog

var kind := "psycho"
var def: Dictionary = EnemyDefs.get_def("psycho")
var world: HouseWorld               ## may be null (then: no bomber targets)
var nav: GridNav
var behaviour: EnemyBehaviour
var level := "normal"
var invasion := 1
var max_hp := Tuning.ENEMY_HP
var damage_scale := 1.0             ## x GameState.enemy_damage() per player hit
var wall_strikes := 1               ## world.enemy_strike calls per wall swing
var blast_damage := 0.0             ## bomber: character damage at the centre
var small_damage := 0.0             ## bomber: the pop when killed mid-fuse
var extras := {}                    ## attached look nodes (EnemyLooks.apply)
var look := 1
var retreating := false
var death_cause := ""
var swings := {"player": 0, "wall": 0}   ## counts (tests, debug)
## Experiment 004 storeys (owner L, src/levels/game_levels.gd): the storey the
## enemy is on (-1 basement, 0 ground, 1 upper; floor_y is its height) and a
## goal that replaces the behaviour's while the player is on another storey
## (the stairs). INF = none.
var storey := 0
var goal_override := Vector2.INF

var _retreat_goal := Vector2.ZERO
var _yaw := 0.0
var _vanish := false


## Sets the archetype and its scaled numbers. opts: level, invasion, hp
## (override), speed (speed_scale override), look (VoxelRig look).
func configure(k: String, w: HouseWorld, target: Node3D, opts := {}) -> void:
	kind = k if EnemyDefs.has(k) else "psycho"
	def = EnemyDefs.get_def(kind)
	world = w
	nav = opts.get("nav", w.nav if w != null else null)
	player = target
	level = Difficulty.valid(str(opts.get("level", "normal")))
	invasion = maxi(int(opts.get("invasion", 1)), 1)
	var st := EnemyDefs.stats(kind, level, invasion)
	hp = int(opts.get("hp", st["hp"]))
	max_hp = hp
	speed_scale = float(opts.get("speed", st["speed_scale"]))
	damage_scale = st["damage_scale"]
	blast_damage = st["blast_damage"]
	small_damage = st["small_damage"]
	wall_strikes = int(def["wall_strikes"])
	var looks: Array = def["looks"]
	look = int(opts.get("look", looks[0]))
	brain = PursuitBrain.new(nav)
	brain.speed = float(def["speed"]) * speed_scale
	brain.attack_range = float(def["attack_range"])
	brain.attack_interval = float(def["attack_interval"])
	brain.reach = float(def["reach"])
	brain.planner = WeightedNav.for_nav(nav, float(def["bash_weight"]))
	behaviour = EnemyBehaviour.make(str(def["behaviour"]))
	behaviour.configure(self)
	rig = VoxelRig.new(look)


func _ready() -> void:
	collision_layer = 1 << 3                 # enemies
	collision_mask = 1 | 2 | 8 | 16          # environment, walls, enemies, low obstacles
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = float(def["radius"])
	cyl.height = VoxelPlayer.BODY_TOP - VoxelPlayer.BODY_BOTTOM
	cs.shape = cyl
	cs.position.y = (VoxelPlayer.BODY_TOP + VoxelPlayer.BODY_BOTTOM) * 0.5
	add_child(cs)
	if rig == null:
		rig = VoxelRig.new(look)
	add_child(rig)
	extras = EnemyLooks.apply(rig, kind)
	_yaw = rig.rotation.y


func speed() -> float:
	return float(def["speed"]) * speed_scale


## Behaviour state for overlays and tests ("chase", "seek", "fuse", "spent").
func state_name() -> String:
	if not alive:
		return "dead"
	if retreating:
		return "retreat"
	return behaviour.state_name()


func set_facing(yaw: float) -> void:
	_yaw = yaw
	if rig != null:
		rig.rotation.y = yaw


## Walk to `p` (a fog point) without attacking anything.
func retreat_to(p: Vector2) -> void:
	retreating = true
	_retreat_goal = p
	brain.attack_goal = false
	brain.bash = false
	brain.arrive_radius = 0.6
	brain.invalidate()


# --- damage ----------------------------------------------------------------------------

## A bullet or pellet (HouseWorld.shoot): Tuning.SHOT_DAMAGE.
func take_hit(dir: Vector3) -> void:
	take_damage(Tuning.SHOT_DAMAGE, dir, "shot")


## `n` damage from direction `dir`; knockback and stagger follow the archetype.
func take_damage(n: int, dir: Vector3, cause := "shot") -> void:
	if not alive or n <= 0:
		return
	hp -= n
	rig.set_flash(1.0)
	var st := float(def["stagger"])
	rig.stagger = clampf(st, 0.0, 1.0)
	var d := Vector3(dir.x, 0, dir.z).normalized()
	if st > 0.0:
		_stagger = Tuning.ENEMY_HIT_STAGGER * st
		_knock = d * (Tuning.ENEMY_KNOCKBACK * float(def["knockback"]) / maxf(_stagger, 0.05))
	if hp <= 0:
		death_cause = cause
		_die(d)


## Dev and test helper: dies at once, without a bomber's pop.
func kill_quietly() -> void:
	if not alive:
		return
	hp = 0
	death_cause = "quiet"
	_die(Vector3.FORWARD)


func _die(dir: Vector3) -> void:
	if not alive:
		return
	super._die(dir)
	behaviour.on_death(self, death_cause)
	died.emit(self, death_cause)


## Removes the body at once (a detonated bomber), leaving no corpse.
func vanish() -> void:
	alive = false
	collision_layer = 0
	collision_mask = 0
	_vanish = true
	visible = false
	set_physics_process(false)
	queue_free()


# --- per frame ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	EnemyLooks.sync_night()
	if not alive:
		_corpse(delta)
		return
	var me := plan_pos()
	var goal := _retreat_goal if retreating else (goal_override if goal_override != Vector2.INF else behaviour.goal(self))
	var r := brain.update(delta, me, goal)
	if not retreating:
		r = behaviour.think(self, delta, r)
	var move: Vector2 = r["move"]
	var face: Vector2 = r["face"]
	if _stagger > 0.0:
		_stagger -= delta
		velocity = _knock
		_knock = _knock.move_toward(Vector3.ZERO, delta * 8.0)
	else:
		velocity = Vector3(move.x, 0, move.y) * speed() * (RETREAT_SPEED if retreating else 1.0)
	move_and_slide()
	global_position.y = floor_y
	if face.length() > 0.01:
		_yaw = lerp_angle(_yaw, atan2(-face.x, -face.y), 1.0 - exp(-delta * 6.0))
		rig.rotation.y = _yaw
	if r["swing"] != "" and not retreating:
		rig.swing = 1.0
		_swing_kind = r["swing"]
		_swing_target = r["target"]
		_swing_pending = SWING_IMPACT * (1.4 if kind == "brute" else 1.0)
	if _swing_pending > 0.0:
		_swing_pending -= delta
		if _swing_pending <= 0.0 and alive:
			if _swing_kind == "wall":
				swings["wall"] += 1
				wall_swing.emit(self, _swing_target)
			elif _swing_kind == "player":
				swings["player"] += 1
				player_swing.emit(self)
	rig.swing = maxf(rig.swing - delta / (0.7 if kind == "brute" else 0.5), 0.0)
	rig.speed = Vector2(velocity.x, velocity.z).length() if _stagger <= 0.0 else 0.0
	rig.animate(delta)


func _corpse(delta: float) -> void:
	_dead_t += delta
	var fall := clampf(_dead_t / 0.45, 0.0, 1.0)
	fall = fall * fall
	var s: Vector3 = def["scale"]
	rig.transform.basis = Basis(_fall_axis, -fall * PI * 0.48) * Basis(Vector3.UP, _yaw) * Basis.from_scale(s)
	rig.position.y = -0.1 * fall
	rig.speed = 0.0
	rig.animate(delta)
	if _dead_t > Tuning.ENEMY_CORPSE_TIME:
		var k := clampf((_dead_t - Tuning.ENEMY_CORPSE_TIME) / 1.2, 0.0, 1.0)
		rig.position.y = -0.1 - 0.35 * k
		rig.set_fade(1.0 - k)
		for n in extras.values():
			if n is Node3D:
				(n as Node3D).visible = k < 0.5
		if k >= 1.0:
			queue_free()
