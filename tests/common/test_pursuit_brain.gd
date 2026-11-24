extends "res://tests/test_case.gd"
## PursuitBrain on a point-mass body (no physics): follows doors, swings at
## the player, bashes walls when the detour is long, repaths on new openings.


func _nav() -> GridNav:
	var nav := GridNav.new()
	HousePlan.rasterize_into(nav)
	return nav


func _simulate(brain: PursuitBrain, pos: Vector2, player: Vector2, secs: float, on_step := Callable()) -> Dictionary:
	var dt := 1.0 / 30.0
	var swings := {"player": 0, "wall": 0}
	var walls_entered := 0
	var t := 0.0
	var last_wall := Vector2.INF
	while t < secs:
		var r := brain.update(dt, pos, player)
		if r["swing"] != "":
			swings[r["swing"]] += 1
			if r["swing"] == "wall":
				last_wall = r["target"]
		var next: Vector2 = pos + r["move"] * Tuning.ENEMY_SPEED * dt
		# crude physics: raw WALL / SOLID cells cannot be entered
		if brain.nav.get_raw(brain.nav.cell_of(next)) == GridNav.OPEN:
			pos = next
		else:
			walls_entered += 0
		if on_step.is_valid():
			on_step.call(pos, r)
		t += dt
	return {"pos": pos, "swings": swings, "last_wall": last_wall}


func test_reaches_player_through_front_door() -> void:
	var brain := PursuitBrain.new(_nav())
	var res := _simulate(brain, Vector2(4.5, 12.0), HousePlan.PLAYER_START, 12.0)
	check(res["pos"].distance_to(HousePlan.PLAYER_START) <= Tuning.ENEMY_ATTACK_RANGE + 0.1, "reached the player (%s)" % res["pos"])
	check(res["swings"]["player"] >= 1, "swings at the player")
	check_eq(res["swings"]["wall"], 0, "no wall bashing needed")


func test_bashes_wall_when_detour_is_long_then_walks_in() -> void:
	var nav := _nav()
	var brain := PursuitBrain.new(nav)
	var player := Vector2(3.8, 2.7)
	var res := _simulate(brain, Vector2(4.0, -2.0), player, 6.0)
	check(res["swings"]["wall"] >= 1, "bashes the north wall")
	var w: Vector2 = res["last_wall"]
	check(absf(w.y) <= 0.25 and w.x > 2.9 and w.x < 6.1, "bashes the north wall near x=4 (%s)" % w)
	# The wall gives way (simulate a 1 m section breaking) -> it walks in.
	var hole := HousePlan.span_rect(HousePlan.wall_by_id("north"), 3.0, 4.0 + 1.0)
	nav.mark_rect(hole, GridNav.OPEN)
	nav.refresh_region(hole)
	var res2 := _simulate(brain, res["pos"], player, 6.0)
	check(res2["pos"].distance_to(player) <= Tuning.ENEMY_ATTACK_RANGE + 0.1, "walks in through the breach (%s)" % res2["pos"])


## Crude round-body physics: a 0.25 m body cannot overlap a raw WALL / SOLID
## cell (approximated as a 0.125 m disc); blocked moves slide along an axis.
func _blocked(nav: GridNav, p: Vector2) -> bool:
	var c := nav.cell_of(p)
	for dj in range(-2, 3):
		for di in range(-2, 3):
			var k := c + Vector2i(di, dj)
			if nav.get_raw(k) != GridNav.OPEN and p.distance_to(nav.center_of(k)) < 0.38:
				return true
	return false


func _slide(nav: GridNav, pos: Vector2, step: Vector2) -> Vector2:
	for s in [step, Vector2(step.x, 0.0), Vector2(0.0, step.y)]:
		if (s as Vector2).length() > 0.0001 and not _blocked(nav, pos + s):
			return pos + s
	return pos


## BACKLOG (Experiment 001): in a half-open gap (cells OPEN but not walkable)
## a body bounces between the jambs, so the position-based rule never sees it
## as stuck and it stops bashing. The progress rule must catch it, and the
## bites it then makes must open the gap enough to walk in.
func test_progress_rule_bashes_out_of_an_oscillating_half_open_gap() -> void:
	# One wall line at y = 5 across the yard, with a 2-cell gap (x = 4.0, 4.25):
	# the gap cells are OPEN but not walkable, so the path runs through them
	# and never past a raw WALL cell.
	var nav := GridNav.new()
	nav.mark_rect(Rect2(-6.0, 4.85, 20.0, 0.3), GridNav.WALL)
	nav.mark_rect(Rect2(3.9, 4.85, 0.45, 0.3), GridNav.OPEN)
	nav.rebuild()
	var cell := nav.cell_of(Vector2(4.0, 5.0))
	check(nav.get_raw(cell) == GridNav.OPEN and not nav.is_walkable(cell) and nav.is_bashable(cell), "a half-open gap")
	var brain := PursuitBrain.new(nav)
	var player := Vector2(4.1, 8.0)
	var dt := 1.0 / 30.0
	# Phase 1: the body jitters in front of the gap (as between two jambs),
	# moving every frame, never closer.
	var walls := []
	var first := -1.0
	var t := 0.0
	var k := 0
	while t < 4.0:
		var pos := Vector2(4.1 + (0.06 if k % 2 == 0 else -0.06), 4.58)
		var r := brain.update(dt, pos, player)
		if r["swing"] == "wall":
			walls.append(r["target"])
			if first < 0.0:
				first = t
		t += dt
		k += 1
	check(not walls.is_empty(), "the progress rule makes it bash although it never stood still")
	if walls.is_empty():
		return
	check(first >= PursuitBrain.PROGRESS_TIME - 0.1, "only after the progress time (%.2f s)" % first)
	check((walls[0] as Vector2).distance_to(Vector2(4.1, 5.0)) < 0.7, "at the wall beside the gap (%s)" % walls[0])
	# Phase 2: real (crude) physics; each wall swing clears its cell (a bite).
	var pos2 := Vector2(4.1, 4.58)
	t = 0.0
	var bites := 0
	while t < 20.0 and pos2.distance_to(player) > Tuning.ENEMY_ATTACK_RANGE + 0.1:
		var r := brain.update(dt, pos2, player)
		if r["swing"] == "wall":
			var c := nav.cell_of(r["target"])
			nav.set_raw(c, GridNav.OPEN)
			nav.refresh_region(Rect2(nav.center_of(c), Vector2.ZERO).grow(0.2))
			bites += 1
		pos2 = _slide(nav, pos2, r["move"] * Tuning.ENEMY_SPEED * dt)
		t += dt
	check(pos2.distance_to(player) <= Tuning.ENEMY_ATTACK_RANGE + 0.1, "bashed the gap open and walked in (%s after %.1f s, %d bites)" % [pos2, t, bites])


## The progress rule must not fire while the goal keeps moving: chasing a
## player along the outside of the south wall never swings at the wall.
func test_progress_rule_ignores_a_moving_goal() -> void:
	var nav := _nav()
	var brain := PursuitBrain.new(nav)
	var pos := Vector2(-1.5, 9.55)
	var player := Vector2(0.5, 9.55)
	var dt := 1.0 / 30.0
	var t := 0.0
	var wall_swings := 0
	while t < 7.0:
		player.x = minf(player.x + 2.0 * dt, 16.0)
		var r := brain.update(dt, pos, player)
		if r["swing"] == "wall":
			wall_swings += 1
		pos = _slide(nav, pos, r["move"] * Tuning.ENEMY_SPEED * dt)
		t += dt
	check_eq(wall_swings, 0, "no wall swings while chasing")
	check(pos.x > 5.0, "it kept following (%s)" % pos)


## attack_goal off (the bomber's walk): arrives, stops, never swings.
func test_walk_to_a_goal_without_attacking() -> void:
	var brain := PursuitBrain.new(_nav())
	brain.attack_goal = false
	brain.bash = false
	var goal := Vector2(4.5, 9.6)
	var res := _simulate(brain, Vector2(4.4, 13.0), goal, 6.0)
	check(res["pos"].distance_to(goal) <= brain.arrive_radius + 0.05, "arrived (%s)" % res["pos"])
	check_eq(res["swings"]["player"] + res["swings"]["wall"], 0, "no swings")
	check(brain.update(0.1, res["pos"], goal)["arrived"], "reports arrived")
