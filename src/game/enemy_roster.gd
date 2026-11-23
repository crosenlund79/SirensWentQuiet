extends Node3D
## The psychos currently in the world (VoxelEnemy bodies): spawning, positional
## moans, the dawn retreat into the fog, and their swing signals for the game.
## Retreating psychos are harmless: they are not threats (they don't block
## sleep, saving or expeditions) and their swings are ignored.

signal wall_swing(enemy: VoxelEnemy, target: Vector2)
signal player_swing(enemy: VoxelEnemy)

const MOAN_GAP := Vector2(6.0, 14.0)    ## s between one psycho's moans
const RETREAT_TIMEOUT := 14.0           ## s before a retreating psycho fades anyway
const RETREAT_REACHED := 1.6            ## m from its fog point
const FADE_TIME := 1.2

var world: HouseWorld
var player: Node3D
var enemies: Array[VoxelEnemy] = []
var rng := RandomNumberGenerator.new()
var _count := 0
var _markers := {}                      ## fog point -> Node3D the retreaters walk to


func setup(w: HouseWorld, p: Node3D, seed := 0) -> void:
	world = w
	player = p
	rng.seed = seed


func spawn(at: Vector2, hp := Tuning.ENEMY_HP, speed := 1.0, invader := false) -> VoxelEnemy:
	var e := VoxelEnemy.new()
	e.setup(world.nav, player, 1 + (_count + rng.randi() % 4) % 4)
	_count += 1
	e.hp = hp
	e.speed_scale = speed
	e.set_meta("invader", invader)
	e.set_meta("moan_t", rng.randf_range(1.5, MOAN_GAP.y))
	add_child(e)
	e.global_position = Vector3(at.x, 0, at.y)
	e.rig.rotation.y = rng.randf() * TAU
	e.wall_swing.connect(_on_wall_swing)
	e.player_swing.connect(_on_player_swing)
	enemies.append(e)
	return e


static func is_threat(e: VoxelEnemy) -> bool:
	return is_instance_valid(e) and e.alive and not e.has_meta("retreat")


## Living psychos that are still a threat (not dead, not retreating).
func living() -> int:
	var n := 0
	for e in enemies:
		if is_threat(e):
			n += 1
	return n


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


## Every threat turns around and walks into the nearest fog point, then fades.
func retreat_all(points: Array) -> int:
	var n := 0
	for e in enemies:
		if not is_threat(e) or points.is_empty():
			continue
		var best: Vector2 = points[0]
		for p in points:
			if (p as Vector2).distance_to(e.plan_pos()) < best.distance_to(e.plan_pos()):
				best = p
		e.player = _marker(best)
		e.set_meta("retreat", 0.0)
		n += 1
	return n


## Dev / test helper: kills every living psycho (they collapse as if shot).
func kill_all() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.alive:
			var guard := 0
			while e.alive and guard < 100:
				e.take_hit(Vector3.FORWARD)
				guard += 1
			n += 1
	return n


func _marker(p: Vector2) -> Node3D:
	var key := "%.2f,%.2f" % [p.x, p.y]
	if not _markers.has(key):
		var m := Node3D.new()
		m.name = "FogPoint"
		add_child(m)
		m.global_position = Vector3(p.x, 0, p.y)
		_markers[key] = m
	return _markers[key]


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
		var t: float = e.get_meta("moan_t", 5.0) - delta
		if t <= 0.0:
			t = rng.randf_range(MOAN_GAP.x, MOAN_GAP.y)
			Sfx.play("enemy/moan_%d" % rng.randi_range(1, 2), e.global_position + Vector3(0, 1.5, 0))
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
	var goal := Vector2(e.player.global_position.x, e.player.global_position.z)
	if e.plan_pos().distance_to(goal) < RETREAT_REACHED or t > RETREAT_TIMEOUT:
		e.set_physics_process(false)
		e.collision_layer = 0
		e.collision_mask = 0
		e.set_meta("fade", 0.0)


func _on_wall_swing(e: VoxelEnemy, target: Vector2) -> void:
	if is_threat(e):
		wall_swing.emit(e, target)


func _on_player_swing(e: VoxelEnemy) -> void:
	if is_threat(e):
		player_swing.emit(e)
