extends Node3D
## The enemies currently in the world (AIEnemy bodies of any archetype, see
## src/ai): spawning, positional moans, the dawn retreat into the fog, blasts
## between enemies, and their signals for the game. Docs:
## docs/experiment-003/ai.md. Retreating enemies are harmless: they are not
## threats (they don't block sleep, saving or expeditions) and their swings are
## ignored.
##
## Experiment 002 API (unchanged): spawn(), living(), invaders_alive(),
## present(), positions(), threats(), retreat_all(), kill_all(), is_threat(),
## wall_swing, player_swing. Experiment 003 adds spawn_type(kind, at, opts),
## living_by_kind(), level / invasion defaults, and the signals below.
##
## wall_swing fires once per STRIKE: a brute's swing is `wall_strikes` (3)
## strikes, so the game's world.enemy_strike handler needs no change.

signal wall_swing(enemy: VoxelEnemy, target: Vector2)
signal player_swing(enemy: VoxelEnemy)
signal enemy_spawned(enemy: VoxelEnemy, kind: String)
signal enemy_died(enemy: VoxelEnemy, kind: String, cause: String)
## A bomber lit its fuse at `at`; it blows in `seconds` (HUD warning).
signal fuse_started(enemy: VoxelEnemy, at: Vector3, seconds: float)
## A blast at `at`: characters within `radius` take up to `damage` at the
## centre, falling off linearly to 0 at `radius` (EnemyDefs.blast_damage_at).
## The roster already hurt the other enemies; the game hurts the player.
signal detonated(at: Vector3, radius: float, damage: float)
## Exp 007 (N): a calm enemy (a straggler, a POI enemy) turned hostile.
signal enemy_provoked(enemy: VoxelEnemy, reason: String)

const MOAN_GAP := Vector2(6.0, 14.0)    ## s between one enemy's moans
const RETREAT_TIMEOUT := 14.0           ## s before a retreating enemy fades anyway
const RETREAT_REACHED := 1.6            ## m from its fog point
const FADE_TIME := 1.2

var world: HouseWorld
var player: Node3D
var enemies: Array = []                 ## AIEnemy (may hold one freed this frame)
var rng := RandomNumberGenerator.new()
var level := "normal"                   ## default difficulty for spawn_type
var invasion := 1                       ## default invasion index for spawn_type
var blasts := 0                         ## detonations seen (tests, debug)
var _count := 0


func setup(w: HouseWorld, p: Node3D, seed := 0) -> void:
	world = w
	player = p
	rng.seed = seed


## Experiment 002: a psycho with the given hp and speed scale.
func spawn(at: Vector2, hp := Tuning.ENEMY_HP, speed := 1.0, invader := false) -> VoxelEnemy:
	return spawn_type("psycho", at, {"hp": hp, "speed": speed, "invader": invader})


## Any archetype (EnemyDefs.KINDS) at plan point `at`. opts:
##   level, invasion   difficulty and invasion index for the scaled numbers
##                     (default: this roster's level / invasion)
##   hp, speed         overrides (speed = scale on the archetype speed)
##   invader           counts for invaders_alive() (a wave member)
##   look              VoxelRig look (psychos vary by default)
##   facing            initial yaw (default random)
##   mode              Exp 007 (N): calm until provoked: "straggler" (home
##                     nights), "wander", "hidden", "arrive" (POIs); absent
##                     or "hostile": attacks at once (invasions). Exp 009
##                     (P): "dormant" (POIs), with the spot in opts "dormant"
##                     (DormantMind.configure)
func spawn_type(kind: String, at: Vector2, opts := {}) -> Node:
	var k := kind if EnemyDefs.has(kind) else "psycho"
	var o := opts.duplicate()
	o["level"] = o.get("level", level)
	o["invasion"] = o.get("invasion", invasion)
	if k == "psycho" and not o.has("look"):
		o["look"] = 1 + (_count + rng.randi() % 4) % 4
	var e := AIEnemy.new()
	e.configure(k, world, player, o)
	e.name = "%s_%d" % [k.capitalize(), _count]
	_count += 1
	e.set_meta("invader", bool(o.get("invader", false)))
	e.set_meta("moan_t", rng.randf_range(1.5, MOAN_GAP.y))
	add_child(e)
	e.global_position = Vector3(at.x, 0, at.y)
	e.set_facing(float(o.get("facing", rng.randf() * TAU)))
	e.wall_swing.connect(_on_wall_swing)
	e.player_swing.connect(_on_player_swing)
	e.fuse_started.connect(_on_fuse_started)
	e.detonated.connect(_on_detonated.bind(e))
	e.died.connect(_on_died)
	e.provoked.connect(func(en: AIEnemy, why: String): enemy_provoked.emit(en, why))   # Exp 007 (N)
	var mode := str(o.get("mode", o.get("calm", "")))
	if mode != "" and mode != "hostile":
		e.set_calm_mode(mode, rng.randi(), o.get("dormant", {}))
	enemies.append(e)
	enemy_spawned.emit(e, k)
	return e


## Untyped on purpose: the list can hold an enemy freed this frame.
static func is_threat(e) -> bool:
	return is_instance_valid(e) and e is VoxelEnemy and e.alive and not e.has_meta("retreat")


## Living enemies that are still a threat (not dead, not retreating).
func living() -> int:
	var n := 0
	for e in enemies:
		if is_threat(e):
			n += 1
	return n


## Threats per archetype, e.g. {"psycho": 2, "bomber": 1}.
func living_by_kind() -> Dictionary:
	var out := {}
	for e in enemies:
		if is_threat(e):
			var k: String = e.kind if e is AIEnemy else "psycho"
			out[k] = int(out.get(k, 0)) + 1
	return out


func invaders_alive() -> int:
	var n := 0
	for e in enemies:
		if is_threat(e) and e.get_meta("invader", false):
			n += 1
	return n


## Bodies still in the world, including dying and retreating ones.
func present() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e):
			n += 1
	return n


func positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	for e in enemies:
		if is_threat(e):
			out.append(e.plan_pos())
	return out


func threats() -> Array:
	return enemies.filter(func(e): return is_threat(e))


## Exp 007 (N): calm enemies (stragglers and POI enemies not provoked yet).
func calm_count() -> int:
	var n := 0
	for e in enemies:
		if is_threat(e) and e is AIEnemy and (e as AIEnemy).is_calm():
			n += 1
	return n


## Every threat turns around and walks to the nearest fog point, then fades.
## A bomber whose fuse already burns is committed and stays.
func retreat_all(points: Array) -> int:
	var n := 0
	for e in enemies:
		if not is_threat(e) or points.is_empty():
			continue
		if e is AIEnemy and (e as AIEnemy).state_name() == "fuse":
			continue
		var best: Vector2 = points[0]
		for p in points:
			if (p as Vector2).distance_to(e.plan_pos()) < best.distance_to(e.plan_pos()):
				best = p
		e.set_meta("retreat", 0.0)
		e.set_meta("retreat_to", best)
		if e is AIEnemy:
			(e as AIEnemy).retreat_to(best)
		n += 1
	return n


## Dev / test helper: kills every living enemy at once (they collapse as if
## shot). Bombers die quietly: no blast, no pop.
func kill_all() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.alive:
			if e is AIEnemy:
				(e as AIEnemy).kill_quietly()
			else:
				var guard := 0
				while e.alive and guard < 100:
					e.take_hit(Vector3.FORWARD)
					guard += 1
			n += 1
	return n


func _process(delta: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		if not is_instance_valid(enemies[i]):
			enemies.remove_at(i)
	for e in enemies:
		if not e.alive:
			continue
		if e.has_meta("retreat"):
			_retreat_step(e, delta)
			continue
		if e is AIEnemy and (not (e as AIEnemy).def.get("moan", true) or (e as AIEnemy).mind is DormantMind):
			continue                         # Exp 009 (P): a dormant one has its own voice (PsychoVoice)
		var t: float = e.get_meta("moan_t", 5.0) - delta
		if t <= 0.0:
			t = rng.randf_range(MOAN_GAP.x, MOAN_GAP.y)
			Sfx.play("enemy/moan", e.global_position + Vector3(0, 1.5, 0))   # group: a random variant
		e.set_meta("moan_t", t)


func _retreat_step(e: VoxelEnemy, delta: float) -> void:
	var t: float = e.get_meta("retreat") + delta
	e.set_meta("retreat", t)
	if e.has_meta("fade"):
		var f: float = e.get_meta("fade") + delta / FADE_TIME
		e.set_meta("fade", f)
		e.rig.set_fade(clampf(1.0 - f, 0.0, 1.0))
		if f >= 1.0:
			e.queue_free()
		return
	var goal: Vector2 = e.get_meta("retreat_to", e.plan_pos())
	if e.plan_pos().distance_to(goal) < RETREAT_REACHED or t > RETREAT_TIMEOUT:
		e.set_physics_process(false)
		e.collision_layer = 0
		e.collision_mask = 0
		e.set_meta("fade", 0.0)
		if e is AIEnemy:
			for n in (e as AIEnemy).extras.values():
				if n is Node3D:
					(n as Node3D).visible = false


func _on_wall_swing(e: VoxelEnemy, target: Vector2) -> void:
	if not is_threat(e):
		return
	var strikes: int = (e as AIEnemy).wall_strikes if e is AIEnemy else 1
	for i in maxi(strikes, 1):
		wall_swing.emit(e, target)


func _on_player_swing(e: VoxelEnemy) -> void:
	if is_threat(e):
		player_swing.emit(e)


func _on_fuse_started(e: AIEnemy, at: Vector3, seconds: float) -> void:
	fuse_started.emit(e, at, seconds)


func _on_died(e: AIEnemy, cause: String) -> void:
	enemy_died.emit(e, e.kind, cause)


## A blast hurts every other living enemy in range (hits fall off linearly),
## then the game hears about it for the player.
func _on_detonated(at: Vector3, radius: float, damage: float, source: AIEnemy) -> void:
	blasts += 1
	var full := source.death_cause == "detonated"
	var peak := int(EnemyDefs.value(source.kind, "blast_enemy_hits" if full else "small_enemy_hits", 0))
	var p := Vector2(at.x, at.z)
	for e in enemies.duplicate():
		if e == source or not is_instance_valid(e) or not e.alive or not (e is AIEnemy):
			continue
		var d: float = (e as AIEnemy).plan_pos().distance_to(p)
		var hits := ceili(float(peak) * EnemyDefs.blast_falloff(d, radius))
		if hits > 0:
			var dir: Vector3 = (e as AIEnemy).global_position - at
			(e as AIEnemy).take_damage(hits, dir, "blast")
	detonated.emit(at, radius, damage)
