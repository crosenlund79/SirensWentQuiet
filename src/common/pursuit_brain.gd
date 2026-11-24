class_name PursuitBrain
extends RefCounted
## Deliberately simple enemy decision-making, shared by all three versions.
## Works purely in plan meters on a GridNav; each version moves its own body
## (CharacterBody3D / CharacterBody2D) along `move` and plays the swings.
##
## Behaviour: walk the grid path toward the goal (the player); if the path
## crosses a wall (only chosen when the detour through openings is long), stop
## and bash the wall; when close to the goal, swing at it (attack_goal).
## Repaths periodically and immediately whenever the GridNav changes, so new
## openings are used as soon as they exist.
##
## Two stuck rules:
## - position: the body hasn't moved for STUCK_TIME in a tight (bashable) spot
##   on its path -> bash the nearest wall there;
## - progress (Experiment 003, see docs/BACKLOG.md): the remaining path to the
##   goal hasn't shrunk by PROGRESS_STEP for PROGRESS_TIME, although the goal
##   stayed put and nothing was swung at. That catches a body oscillating in a
##   half-open gap (cells OPEN but not walkable), which the position rule
##   misses because the body keeps moving. It then bashes the nearest raw WALL
##   within reach or, with none, repaths and sidesteps briefly.
##   `result["stalled"]` reports it.
##
## Per-instance tuning (defaults = the Experiment 001/002 psycho): speed,
## attack_range, attack_interval, reach, attack_goal (false: just walk there),
## bash (false: never swings at walls) and an optional `planner` (any object
## with find_path(from, to) -> PackedVector2Array, e.g. a weighted nav layer).

const REACH := 0.8            ## m from body centre to a wall cell centre it can hit
const LOOKAHEAD := 6          ## path cells inspected for smoothing / walls
const STUCK_TIME := 0.5       ## s without moving before bashing a tight spot
const PROGRESS_TIME := 2.5    ## s without getting closer to the goal before the progress rule acts
const PROGRESS_STEP := 0.3    ## m the remaining path must shrink to count as progress
const GOAL_MOVED := 1.0       ## m the goal may move before the progress baseline resets
const SIDESTEP_TIME := 0.45   ## s of sideways walking when stalled away from any wall

var nav: GridNav
var path := PackedVector2Array()
var path_index := 0

var speed := Tuning.ENEMY_SPEED
var attack_range := Tuning.ENEMY_ATTACK_RANGE
var attack_interval := Tuning.ENEMY_ATTACK_INTERVAL
var reach := REACH
var attack_goal := true       ## swing at the goal when close (false: arrive and stop)
var arrive_radius := 0.3      ## m; with attack_goal off, "arrived" inside this
var bash := true              ## swing at walls on the path
var planner: Object = null    ## find_path(from, to) provider; null = nav

var _repath_timer := 0.0
var _nav_revision := -1
var _cooldown := 0.0
var _stuck_timer := 0.0
var _last_pos := Vector2.INF
var _cum := PackedFloat32Array()      # cumulative path length per waypoint
var _best_left := INF
var _progress_t := 0.0
var _progress_goal := Vector2.INF
var _sidestep_t := 0.0
var _sidestep := Vector2.ZERO
var _flip := false


func _init(grid: GridNav) -> void:
	nav = grid


## Returns {"move": Vector2 (unit or zero), "face": Vector2 (unit),
##          "swing": "" | "player" | "wall", "target": Vector2 (swing point),
##          "stalled": bool, "arrived": bool}.
## A swing is reported once per attack_interval. `player` is the goal.
func update(delta: float, pos: Vector2, player: Vector2) -> Dictionary:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_repath_timer -= delta
	var result := {"move": Vector2.ZERO, "face": (player - pos).normalized(), "swing": "", "target": player,
		"stalled": false, "arrived": false}

	# Movement tracking (for tight spots).
	if _last_pos != Vector2.INF and pos.distance_to(_last_pos) < speed * delta * 0.25:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
	_last_pos = pos

	# Close enough to the goal: swing at it, or stop there.
	if attack_goal:
		if pos.distance_to(player) <= attack_range and nav.segment_clear(pos, player):
			_reset_progress(player)
			if _cooldown <= 0.0:
				_cooldown = attack_interval
				result["swing"] = "player"
			return result
	elif pos.distance_to(player) <= arrive_radius:
		_reset_progress(player)
		result["arrived"] = true
		return result

	if _repath_timer <= 0.0 or _nav_revision != nav.revision or path_index >= path.size():
		_repath(pos, player)

	# Drop waypoints we've reached.
	while path_index < path.size() - 1 and pos.distance_to(path[path_index]) < 0.2:
		path_index += 1
	if path_index >= path.size():
		result["move"] = (player - pos).normalized()
		return result

	# The progress rule (see the header).
	if _progress_goal == Vector2.INF or player.distance_to(_progress_goal) > GOAL_MOVED:
		_reset_progress(player)
	var left := _remaining(pos)
	if left < _best_left - PROGRESS_STEP:
		_best_left = left
		_progress_t = 0.0
	else:
		_progress_t += delta
	if _sidestep_t > 0.0:
		_sidestep_t -= delta
		result["move"] = _sidestep
		result["face"] = _sidestep
		return result
	if _progress_t >= PROGRESS_TIME:
		result["stalled"] = true
		_progress_t = 0.0
		_best_left = left
		if bash:
			var w := nav.nearest_raw_wall(nav.cell_of(pos), pos, 3)
			if w.x >= 0 and pos.distance_to(nav.center_of(w)) <= reach + 0.25:
				return _wall_swing(result, pos, w)
		_repath(pos, player)
		if not path.is_empty():
			var ahead := (path[mini(path_index, path.size() - 1)] - pos).normalized()
			if ahead == Vector2.ZERO:
				ahead = (player - pos).normalized()
			_flip = not _flip
			_sidestep = Vector2(-ahead.y, ahead.x) * (1.0 if _flip else -1.0)
			_sidestep_t = SIDESTEP_TIME
		if path_index >= path.size():
			return result

	# Wall on the way? A raw WALL cell on the path within reach, or a tight
	# (bashable) spot we are physically stuck in.
	var last := mini(path.size(), path_index + LOOKAHEAD)
	var first_tight := Vector2i(-1, -1)
	if bash:
		for k in range(path_index, last):
			var c := nav.cell_of(path[k])
			if nav.is_walkable(c):
				if first_tight.x >= 0:
					break
				continue
			if first_tight.x < 0:
				first_tight = c
			if nav.get_raw(c) == GridNav.WALL:
				if pos.distance_to(nav.center_of(c)) <= reach:
					return _wall_swing(result, pos, c)
				break
		if first_tight.x >= 0 and _stuck_timer >= STUCK_TIME:
			var w := nav.nearest_raw_wall(first_tight, pos, 1)
			if w.x >= 0 and pos.distance_to(nav.center_of(w)) <= reach:
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


## Seconds since the remaining path last shrank (the progress rule's clock).
func stall_time() -> float:
	return _progress_t


## Forces a new path on the next update (e.g. after the goal changed).
func invalidate() -> void:
	_repath_timer = 0.0
	path = PackedVector2Array()
	path_index = 0
	_progress_goal = Vector2.INF


func _wall_swing(result: Dictionary, pos: Vector2, wall: Vector2i) -> Dictionary:
	var p := nav.center_of(wall)
	result["face"] = (p - pos).normalized()
	result["target"] = p
	_reset_progress(Vector2.INF)
	if _cooldown <= 0.0:
		_cooldown = attack_interval
		result["swing"] = "wall"
	return result


func _reset_progress(goal: Vector2) -> void:
	if goal != Vector2.INF:
		_progress_goal = goal
	_best_left = INF
	_progress_t = 0.0


func _remaining(pos: Vector2) -> float:
	if path_index >= path.size() or _cum.size() != path.size():
		return INF
	return pos.distance_to(path[path_index]) + _cum[_cum.size() - 1] - _cum[path_index]


func _repath(pos: Vector2, player: Vector2) -> void:
	path = planner.find_path(pos, player) if planner != null else nav.find_path(pos, player)
	path_index = 1 if path.size() > 1 else 0
	_repath_timer = Tuning.ENEMY_REPATH_INTERVAL
	_nav_revision = nav.revision
	_cum.resize(path.size())
	var acc := 0.0
	for i in path.size():
		if i > 0:
			acc += path[i].distance_to(path[i - 1])
		_cum[i] = acc
