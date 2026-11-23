class_name VoxelScenarios
extends RefCounted
## Showcase states for screenshots (`--scenario=<name>` on the command line).
## They only arrange the existing scene: place the player, fire real shots,
## spawn enemies, frame the camera, and optionally freeze the frame ("photo")
## so short-lived effects are visible under a slow software renderer.
##   overview   - whole house from above, a few holes, psychos outside
##   blasted    - south wall shot open from outside, close zoom on the holes
##   interior   - inside: a wall chewed through, showing both paint layers
##   layers     - kitchen wall close-up: tiles, paint, insulation, studs, siding
##   shooting   - the player firing at an interior wall, frozen mid-burst
##   enemies    - psychos closing in on the house, frozen mid-step
##   firefight  - psychos inside the living room, the player shooting

static var _events: Array = []
static var _t := 0.0


static func setup(d: Node, name: String) -> void:
	_events = []
	_t = 0.0
	d.spawner.enabled = false
	match name:
		"overview":
			_shoot_pattern(d, Vector2(8.5, 10.6), Vector2(8.5, 9.0), 14)
			_shoot(d, Vector2(9.6, 11.0), [Vector3(7.0, 1.4, 9.0)])
			_shoot(d, Vector2(1.6, 2.0), [Vector3(-0.2, 1.1, 2.6), Vector3(-0.2, 1.3, 2.8), Vector3(-0.2, 0.8, 2.4)])
			_place(d, Vector2(6.0, 6.3), Vector3(4.0, 1.0, 1.0))
			d.camera.set_distance(24.0)
			_at(0.2, func(): _spawn_ring(d, [Vector2(-2.5, 6.5), Vector2(10.5, 11.8), Vector2(16.5, 3.0), Vector2(3.0, -2.6)]))
			_at(3.8, func(): d.get_tree().paused = true)
		"blasted":
			# South wall from outside: one walk-through hole, grazing gouges that
			# peel the siding off the studs and insulation, a shattered window.
			_shoot_pattern(d, Vector2(8.6, 10.6), Vector2(8.6, 9.0), 14)
			_shoot(d, Vector2(9.2, 9.75), [Vector3(10.9, 1.7, 9.15), Vector3(11.2, 1.35, 9.15), Vector3(11.5, 1.95, 9.15),
				Vector3(11.0, 2.2, 9.15), Vector3(11.6, 1.55, 9.15)])
			_shoot(d, Vector2(11.0, 10.4), [Vector3(10.95, 1.2, 9.0), Vector3(11.3, 0.8, 9.0)])
			_shoot(d, Vector2(7.0, 10.8), [Vector3(7.0, 1.5, 9.0)])
			_shoot(d, Vector2(5.8, 10.8), [Vector3(5.6, 0.7, 9.0), Vector3(5.7, 1.7, 9.0)])
			_place(d, Vector2(9.9, 11.2), Vector3(11.3, 1.3, 9.1))
			d.camera.set_distance(11.0)
		"interior":
			_shoot_pattern(d, Vector2(1.4, 5.0), Vector2(1.25, 4.0), 12)
			_shoot(d, Vector2(3.0, 5.4), [Vector3(5.8, 1.6, 4.0), Vector3(5.65, 2.1, 4.0)])
			_place(d, Vector2(2.9, 6.3), Vector3(1.25, 1.2, 4.0))
			d.camera.set_distance(12.0)
		"layers":
			# Kitchen north wall from inside: tiles, paint, insulation, studs, siding.
			_shoot(d, Vector2(9.5, 2.4), [Vector3(9.25, 1.2, 0.0), Vector3(9.6, 1.35, 0.0), Vector3(9.45, 1.65, 0.0),
				Vector3(9.45, 1.6, 0.0), Vector3(9.4, 1.4, 0.0), Vector3(9.7, 2.05, 0.0), Vector3(9.2, 2.4, 0.0), Vector3(9.55, 2.45, 0.0)])
			_shoot(d, Vector2(12.2, 2.4), [Vector3(12.25, 1.45, 0.0), Vector3(12.2, 2.3, 0.0)])
			_shoot(d, Vector2(10.9, 1.8), [Vector3(11.0, 1.5, 0.0)])
			_place(d, Vector2(10.0, 3.3), Vector3(9.5, 1.5, 0.0))
			d.camera.set_distance(11.0)
		"shooting":
			_shoot_pattern(d, Vector2(2.6, 6.2), Vector2(1.3, 4.0), 7)
			_place(d, Vector2(2.9, 6.3), Vector3(1.4, 1.25, 4.0))
			d.camera.set_distance(12.0)
			for k in 6:
				var tgt := Vector3(1.0 + k * 0.17, 1.0 + 0.12 * (k % 3), 4.0)
				_at(1.2 + k * 0.45, func(): d.player.aim_point = tgt; d.fire(tgt))
			_at(3.85, func(): d.player.aim_point = Vector3(1.55, 1.35, 4.0); d.fire(Vector3(1.55, 1.35, 4.0)))
			_at(3.86, func(): d.get_tree().paused = true)
		"enemies":
			_place(d, Vector2(6.2, 7.2), Vector3(6.3, 1.2, 10.5))
			d.camera.set_distance(17.0)
			_shoot(d, Vector2(6.4, 8.0), [Vector3(7.0, 1.4, 9.0)])
			_at(0.1, func(): _spawn_ring(d, [Vector2(3.2, 12.0), Vector2(6.0, 12.6), Vector2(8.8, 11.8), Vector2(11.5, 12.4), Vector2(-1.8, 8.2)]))
			_at(3.0, func(): d.player.aim_point = Vector3(6.0, 1.1, 10.8); d.fire(Vector3(6.0, 1.1, 10.8)))
			_at(3.02, func(): d.get_tree().paused = true)
		"firefight":
			_shoot_pattern(d, Vector2(8.5, 10.6), Vector2(8.5, 9.0), 14)
			_place(d, Vector2(3.6, 6.9), Vector3(7.5, 1.1, 7.6))
			d.camera.set_distance(15.0)
			_at(0.1, func(): _spawn_ring(d, [Vector2(9.0, 11.6), Vector2(10.6, 12.6), Vector2(9.6, 6.6), Vector2(4.6, 11.9)]))
			_at(1.6, func(): _fire_at_nearest(d))
			_at(2.1, func(): _fire_at_nearest(d))
			_at(2.5, func(): _fire_at_nearest(d))
			_at(2.52, func(): d.get_tree().paused = true)
	d.camera.snap()


static func process(_d: Node, _name: String, delta: float) -> void:
	_t += delta
	while not _events.is_empty() and _events[0][0] <= _t:
		var e: Array = _events.pop_front()
		(e[1] as Callable).call()


static func _at(t: float, f: Callable) -> void:
	_events.append([t, f])
	_events.sort_custom(func(a, b): return a[0] < b[0])


static func _place(d: Node, p: Vector2, aim: Vector3) -> void:
	d.debug_teleport_player(p)
	d.player.aim_point = aim
	var to: Vector3 = aim - d.player.global_position
	d.player.rig.rotation.y = atan2(-to.x, -to.z)


## Real shots from the player's gun at `from` toward each target.
static func _shoot(d: Node, from: Vector2, targets: Array) -> void:
	d.debug_teleport_player(from)
	for t in targets:
		d.fire(t)


## The smoke test's hole pattern (3 columns x 4 heights) from `from` at `at`.
static func _shoot_pattern(d: Node, from: Vector2, at: Vector2, shots: int) -> void:
	var pattern := [Vector2(-0.3, 0.3), Vector2(0.0, 0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.75), Vector2(0.0, 0.75), Vector2(0.3, 0.75),
		Vector2(-0.3, 1.2), Vector2(0.0, 1.2), Vector2(0.3, 1.2), Vector2(-0.3, 1.6), Vector2(0.0, 1.6), Vector2(0.3, 1.6)]
	d.debug_teleport_player(from)
	var horiz := absf(from.y - at.y) > absf(from.x - at.x)
	for k in shots:
		var o: Vector2 = pattern[k % pattern.size()]
		var tgt := Vector3(at.x + o.x, o.y, at.y) if horiz else Vector3(at.x, o.y, at.y + o.x)
		d.fire(tgt)


static func _spawn_ring(d: Node, points: Array) -> void:
	for p in points:
		d.spawn_enemy(p)


static func _fire_at_nearest(d: Node) -> void:
	var best := Vector2.INF
	var me: Vector2 = d.player.plan_pos()
	for p in d.debug_enemy_positions():
		if me.distance_to(p) < me.distance_to(best):
			best = p
	if best != Vector2.INF:
		var tgt := Vector3(best.x, 1.15, best.y)
		d.player.aim_point = tgt
		d.fire(tgt)
