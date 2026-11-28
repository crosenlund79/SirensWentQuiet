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
## Exp 007 (N): a calm enemy turned hostile (noise, seeing Eli, being hurt).
signal provoked(enemy: AIEnemy, reason: String)
## Exp 012 (E): dead and settled (keep_corpse): the corpse helper takes the body.
signal corpse_settled(enemy: AIEnemy)

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
var windup := SWING_IMPACT          ## Exp 006 (B): s from a swing's start to its impact (EnemyDefs "windup")
var wall_strikes := 1               ## world.enemy_strike calls per wall swing
var blast_damage := 0.0             ## bomber: character damage at the centre
var small_damage := 0.0             ## bomber: the pop when killed mid-fuse
var extras := {}                    ## attached look nodes (EnemyLooks.apply)
var look := 1
## Exp 011: the appearance seed (HumanoidLooks.make_rig): which person this
## is. Stable per enemy (POI encounters save it as "app").
var appearance := -1
var retreating := false
var death_cause := ""
var swings := {"player": 0, "wall": 0}   ## counts (tests, debug)
## Experiment 004 storeys (owner L, src/levels/game_levels.gd): the storey the
## enemy is on (-1 basement, 0 ground, 1 upper; floor_y is its height) and a
## goal that replaces the behaviour's while the player is on another storey
## (the stairs). INF = none.
var storey := 0
var goal_override := Vector2.INF
## Exp 006 (D), defences (src/defense/): the ground under the enemy (trench,
## water) slows it (speed x terrain_scale) and lowers it (floor_y), and
## spikes it touches hurt it (DefenseGrid.enemy_step; `spike_cd` is its
## contact cooldown). Brutes wade through water-filled trenches.
var terrain_scale := 1.0
var spike_cd := 0.0
## Exp 007 (N): calm until provoked (src/ai/straggler_mind.gd). A StragglerMind
## while calm (night stragglers, POI enemies); null = hostile (the archetype's
## behaviour). Invasion enemies never get one.
var mind: StragglerMind = null
var provoked_by := ""
## Exp 012 (E): who this was (HumanNames, from the appearance seed and the
## look's sex: it persists wherever the seed does), the first-sight reaction
## (EnemyReaction: startle, scream, charge) and, with keep_corpse (set by the
## game's corpse helper), a body that stays (corpse_settled, src/ai/corpse.gd)
## instead of fading out.
var display_name := ""
var reaction: EnemyReaction
var keep_corpse := false
var _settled := false

var _retreat_goal := Vector2.ZERO
var _yaw := 0.0
var _vanish := false


## Sets the archetype and its scaled numbers. opts: level, invasion, hp
## (override), speed (speed_scale override), look (VoxelRig look of kinds
## without a humanoid archetype), appearance (Exp 011: the person's seed).
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
	appearance = int(opts.get("appearance", appearance if appearance >= 0 else randi() % 1000000))
	brain = PursuitBrain.new(nav)
	brain.speed = float(def["speed"]) * speed_scale
	brain.attack_range = float(def["attack_range"])
	brain.attack_interval = float(def["attack_interval"]) * float(st.get("attack_scale", 1.0))
	brain.reach = float(def["reach"])
	# Exp 006 (B): quicker re-targeting and less time stuck (EnemyDefs; old values as fallbacks)
	brain.repath_interval = float(def.get("repath", Tuning.ENEMY_REPATH_INTERVAL))
	brain.stuck_time = float(def.get("stuck", PursuitBrain.STUCK_TIME))
	brain.progress_time = float(def.get("progress", PursuitBrain.PROGRESS_TIME))
	windup = float(def.get("windup", SWING_IMPACT * (1.4 if kind == "brute" else 1.0)))
	brain.planner = WeightedNav.for_nav(nav, float(def["bash_weight"]), wades())    # Exp 006 (D): + wading
	behaviour = EnemyBehaviour.make(str(def["behaviour"]))
	behaviour.configure(self)
	rig = HumanoidLooks.make_rig(kind, appearance, look)      # Exp 011: people for kinds with an archetype
	display_name = HumanNames.for_enemy(kind, appearance)    # Exp 012 (E)
	reaction = EnemyReaction.new(hash([appearance, "react"])) if EnemyReaction.applies(kind) else null


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
		rig = HumanoidLooks.make_rig(kind, maxi(appearance, 0), look)
	add_child(rig)
	extras = EnemyLooks.apply(rig, kind)
	_yaw = rig.rotation.y


func speed() -> float:
	return float(def["speed"]) * speed_scale * terrain_scale * (mind.pace() if mind != null else 1.0) \
		* (reaction.speed_factor() if reaction != null and mind == null else 1.0)    # Exp 007 (N): calm pace; Exp 012 (E): the charge


## Exp 006 (D): crosses water-filled trenches (slowly); the others can't.
## An archetype's "wades" field wins; by default only the brute wades.
func wades() -> bool:
	return bool(def.get("wades", kind == "brute"))


## Behaviour state for overlays and tests ("chase", "seek", "fuse", "spent").
func state_name() -> String:
	if not alive:
		return "dead"
	if retreating:
		return "retreat"
	if mind != null:                     # Exp 007 (N): wander, pass, window, door, examine, investigate, lurk
		return mind.state
	return behaviour.state_name()


# --- Exp 007 (N): calm until provoked ---------------------------------------------------

## mode: "straggler" (home nights), "wander", "hidden", "arrive" (POIs); ""
## or "hostile" turns a calm enemy hostile. Call after configure().
## Exp 009 (P): "dormant" (POIs) with `data` (the spot: behaviour, spot,
## target, radius, sensitivity, mumble) gives it a DormantMind.
func set_calm_mode(mode: String, seed := -1, data := {}) -> void:
	if mode == "" or mode == "hostile" or mode == "attack":
		provoke("mode")
		return
	if not alive or brain == null:
		return
	if mode == "dormant":
		var dm := DormantMind.new()
		dm.configure(data)
		mind = dm
	else:
		mind = StragglerMind.new()
	mind.setup(self, mode, seed if seed >= 0 else randi())


func is_calm() -> bool:
	return mind != null and alive


## A person who'd harm Eli (for sensors and turrets, agent S): every living
## enemy, calm, wandering or investigating ones included; false only while it
## leaves (retreating at dawn or walking off into the fog) or once dead.
func is_hostile() -> bool:
	return alive and not retreating and not has_meta("retreat")


## A noise it heard (NoiseEvent): `loud` = level x exposure x fall-off.
func hear(at: Vector2, loud: float, source := "") -> void:
	if mind != null and alive and not retreating:
		mind.hear(self, at, loud, source)


## Comes to look at plan point p (calm enemies only).
func investigate(p: Vector2) -> void:
	if mind != null and alive and not retreating:
		mind.investigate(self, p)


## Turns hostile: the archetype's behaviour takes over.
func provoke(reason := "") -> void:
	if mind == null or not alive:
		return
	mind.on_provoked(self)                # Exp 009 (P): a dormant one falls silent
	mind = null
	provoked_by = reason
	if reaction != null:
		reaction.on_provoked(self, reason)      # Exp 012 (E): startle, scream, charge
	if has_meta("calm_leave") and not has_meta("fade"):     # it was walking off into the fog: it turns back
		remove_meta("calm_leave")
		remove_meta("retreat")
		remove_meta("retreat_to")
		retreating = false
	behaviour.configure(self)
	brain.arrive_radius = 0.3 if str(def["behaviour"]) == "chase" else brain.arrive_radius
	brain.invalidate()
	provoked.emit(self, reason)


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
	elif mind != null:
		provoke("hurt: " + cause)          # Exp 007 (N)


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
	if storey == 0 and world != null and world.defense != null:     # Exp 006 (D): trenches, water, spikes
		world.defense.enemy_step(self, delta)
		if not alive:
			return
	var goal := _retreat_goal
	if not retreating:
		if mind != null:                      # Exp 007 (N): calm: the mind's goal
			goal = mind.goal_of(self)
		else:
			goal = goal_override if goal_override != Vector2.INF else behaviour.goal(self)
	var r := brain.update(delta, me, goal)
	if not retreating:
		r = mind.think(self, delta, r) if mind != null else behaviour.think(self, delta, r)
		if reaction != null and mind == null:
			r = reaction.think(self, delta, r)      # Exp 012 (E): the first-sight reaction
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
		_swing_pending = windup        # Exp 006 (B): per archetype (was 0.28 s, x1.4 for the brute)
	if _swing_pending > 0.0:
		_swing_pending -= delta
		if _swing_pending <= 0.0 and alive:
			if _swing_kind == "wall":
				swings["wall"] += 1
				if storey == 0 and world != null and world.defense != null:      # Exp 006 (D): bashing spikes hurts
					world.defense.spike_swing(self, _swing_target)
				wall_swing.emit(self, _swing_target)
			elif _swing_kind == "player":
				swings["player"] += 1
				player_swing.emit(self)
	rig.swing = maxf(rig.swing - delta / (0.7 if kind == "brute" else 0.5), 0.0)
	rig.speed = Vector2(velocity.x, velocity.z).length() if _stagger <= 0.0 else 0.0
	rig.animate(delta)
	if mind != null:
		mind.pose(self, delta)              # Exp 009 (P): a dormant one's lean, sway, stare or tap
	elif reaction != null:
		reaction.pose(self, delta)          # Exp 012 (E): the scream


func _corpse(delta: float) -> void:
	_dead_t += delta
	var fall := clampf(_dead_t / 0.45, 0.0, 1.0)
	fall = fall * fall
	if rig is HumanoidRig:
		(rig as HumanoidRig).collapse(delta, _dead_t, _fall_axis, _yaw)    # Exp 011: knees buckle, then it falls
	else:
		var s: Vector3 = def["scale"]
		rig.transform.basis = Basis(_fall_axis, -fall * PI * 0.48) * Basis(Vector3.UP, _yaw) * Basis.from_scale(s)
		rig.position.y = -0.1 * fall
		rig.speed = 0.0
		rig.animate(delta)
	if keep_corpse:                         # Exp 012 (E): the body stays (the corpse helper takes it)
		if _dead_t >= Corpse.SETTLE and not _settled:
			_settled = true
			set_physics_process(false)
			corpse_settled.emit(self)
		return
	if _dead_t > Tuning.ENEMY_CORPSE_TIME:
		var k := clampf((_dead_t - Tuning.ENEMY_CORPSE_TIME) / 1.2, 0.0, 1.0)
		rig.position.y -= 0.35 * k
		rig.set_fade(1.0 - k)
		for n in extras.values():
			if n is Node3D:
				(n as Node3D).visible = k < 0.5
		if k >= 1.0:
			queue_free()


# --- Exp 012 (E): identity --------------------------------------------------------------

## "Psycho", "Runner", "Brute" or "Bomber" (the story's watcher is never an AIEnemy).
func kind_label() -> String:
	return HumanNames.kind_label(kind)
