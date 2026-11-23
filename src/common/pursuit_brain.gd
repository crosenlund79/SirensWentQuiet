class_name PursuitBrain
extends RefCounted
## Deliberately simple enemy decision-making, shared by all three versions.
## Works purely in plan meters on a GridNav; each version moves its own body
## (CharacterBody3D / CharacterBody2D) along `move` and plays the swings.
##
## Behaviour: walk the grid path toward the player; if the path crosses a wall
## (only chosen when the detour through openings is long), stop and bash the
## wall; when close to the player, swing at them (the player cannot die).
## Repaths periodically and immediately whenever the GridNav changes, so new
## openings are used as soon as they exist.

const REACH := 0.8            ## m from body centre to a wall cell centre it can hit
const LOOKAHEAD := 6          ## path cells inspected for smoothing / walls
const STUCK_TIME := 0.5       ## s without progress before bashing a tight spot

var nav: GridNav
var path := PackedVector2Array()
var path_index := 0

var _repath_timer := 0.0
var _nav_revision := -1
var _cooldown := 0.0
var _stuck_timer := 0.0
var _last_pos := Vector2.INF


func _init(grid: GridNav) -> void:
	nav = grid


## Returns {"move": Vector2 (unit or zero), "face": Vector2 (unit),
##          "swing": "" | "player" | "wall", "target": Vector2 (swing point)}.
## A swing is reported once per Tuning.ENEMY_ATTACK_INTERVAL.
func update(delta: float, pos: Vector2, player: Vector2) -> Dictionary:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_repath_timer -= delta
	var result := {"move": Vector2.ZERO, "face": (player - pos).normalized(), "swing": "", "target": player}

	# Progress tracking (for tight spots).
	if _last_pos != Vector2.INF and pos.distance_to(_last_pos) < Tuning.ENEMY_SPEED * delta * 0.25:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
	_last_pos = pos

	# Close enough to the player: swing.
	if pos.distance_to(player) <= Tuning.ENEMY_ATTACK_RANGE and nav.segment_clear(pos, player):
		if _cooldown <= 0.0:
			_cooldown = Tuning.ENEMY_ATTACK_INTERVAL
			result["swing"] = "player"
		return result

	if _repath_timer <= 0.0 or _nav_revision != nav.revision or path_index >= path.size():
		_repath(pos, player)

	# Drop waypoints we've reached.
	while path_index < path.size() - 1 and pos.distance_to(path[path_index]) < 0.2:
		path_index += 1
	if path_index >= path.size():
		result["move"] = (player - pos).normalized()
		return result

	# Wall on the way? A raw WALL cell on the path within reach, or a tight
	# (bashable) spot we are physically stuck in.
	var last := mini(path.size(), path_index + LOOKAHEAD)
	var first_tight := Vector2i(-1, -1)
	for k in range(path_index, last):
		var c := nav.cell_of(path[k])
		if nav.is_walkable(c):
			if first_tight.x >= 0:
				break
			continue
		if first_tight.x < 0:
			first_tight = c
		if nav.get_raw(c) == GridNav.WALL:
			if pos.distance_to(nav.center_of(c)) <= REACH:
				return _wall_swing(result, pos, c)
			break
	if first_tight.x >= 0 and _stuck_timer >= STUCK_TIME:
		var w := nav.nearest_raw_wall(first_tight, pos, 1)
		if w.x >= 0 and pos.distance_to(nav.center_of(w)) <= REACH:
			return _wall_swing(result, pos, w)

	# Steer to the farthest waypoint we can walk to in a straight line.
	var aim := path[path_index]
	for k in range(last - 1, path_index, -1):
		if nav.segment_walkable(pos, path[k]):
			aim = path[k]
			break
	var d := aim - pos
	result["move"] = d.normalized() if d.length() > 0.01 else Vector2.ZERO
	if result["move"] != Vector2.ZERO:
		result["face"] = result["move"]
	return result


func _wall_swing(result: Dictionary, pos: Vector2, wall: Vector2i) -> Dictionary:
	var p := nav.center_of(wall)
	result["face"] = (p - pos).normalized()
	result["target"] = p
	if _cooldown <= 0.0:
		_cooldown = Tuning.ENEMY_ATTACK_INTERVAL
		result["swing"] = "wall"
	return result


func _repath(pos: Vector2, player: Vector2) -> void:
	path = nav.find_path(pos, player)
	path_index = 1 if path.size() > 1 else 0
	_repath_timer = Tuning.ENEMY_REPATH_INTERVAL
	_nav_revision = nav.revision
