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
