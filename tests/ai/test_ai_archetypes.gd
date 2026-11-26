extends "res://tests/test_case.gd"
## Archetypes on the shared body (SPEC-003 §5): stats and difficulty scaling,
## looks, the runner's preference for openings, the brute's heavy strikes and
## knockback resistance, the weighted nav layer, reacting to a new opening.

const Roster := preload("res://src/game/enemy_roster.gd")

var world: HouseWorld
var player: VoxelPlayer
var roster: Node3D


func _setup(player_at: Vector2) -> void:
	world = HouseWorld.new()
	add(world)
	world.build_new()
	player = VoxelPlayer.new()
	player.input_enabled = false
	add(player)
	player.global_position = Vector3(player_at.x, 0, player_at.y)
	roster = Roster.new()
	roster.setup(world, player, 5)
	add(roster)
	roster.wall_swing.connect(func(e, t): world.enemy_strike(e.global_position, t))
	await physics_frames(2)


func _door(at: Vector2) -> WorldObject:
	for o in world.objects:
		if o.kind == "door" and o.pos.distance_to(at) < 0.1:
			return o
	return null


func _bash_cells(nav: GridNav, path: PackedVector2Array) -> int:
	var n := 0
	for p in path:
		if not nav.is_walkable(nav.cell_of(p)):
			n += 1
	return n


func test_ai_archetype_stats_and_difficulty_scaling() -> void:
	# Exp 006 (B): faster, quicker-swinging archetypes; the order between them stays
	var p := EnemyDefs.get_def("psycho")
	check(p["speed"] > Tuning.ENEMY_SPEED and p["speed"] < 2.2 and p["hp"] == Tuning.ENEMY_HP, "psycho: faster than Experiment 002 (about 1.85 m/s), 3 hp")
	check(is_equal_approx(p["bash_weight"], GridNav.BASH_WEIGHT) and p["wall_strikes"] == 1, "psycho bashes like before")
	check(p["attack_interval"] < Tuning.ENEMY_ATTACK_INTERVAL and float(p["windup"]) < AIEnemy.SWING_IMPACT, "psycho swings sooner and more often")
	var r := EnemyDefs.get_def("runner")
	check(r["speed"] >= p["speed"] * 1.5 and r["speed"] < Tuning.PLAYER_SPEED and r["hp"] <= 2, "runner: clearly faster than the psycho, under the player's walk, 1-2 hp")
	check(r["bash_weight"] > p["bash_weight"] * 3.0, "runner: high bash cost (prefers openings)")
	var b := EnemyDefs.get_def("brute")
	check(b["speed"] < p["speed"] and b["hp"] >= 8 and b["player_damage"] > p["player_damage"] * 1.5, "brute: slowest, 8 hp, hits hardest")
	check(b["wall_strikes"] >= 3 and b["bash_weight"] < p["bash_weight"], "brute: three strikes a swing, happy to bash")
	check(b["knockback"] <= 0.2 and b["stagger"] < 0.5, "brute: knockback resistant")
	check((b["scale"] as Vector3).y > 1.15, "brute: a bigger rig")
	var x := EnemyDefs.get_def("bomber")
	check(x["behaviour"] == "bomber" and x["hp"] == 2 and absf(x["speed"] - 2.0) < 0.2, "bomber: 2 hp, about 2 m/s")
	check(absf(x["fuse"] - 2.2) < 0.01 and x["wall_strikes"] == 0 and x["player_damage"] == 0.0, "bomber: 2.2 s fuse, never swings")
	check(EnemyDefs.stats("psycho", "easy", 1)["attack_scale"] > 1.0 and EnemyDefs.stats("psycho", "hard", 1)["attack_scale"] < 1.0,
		"swings are slower on Easy and quicker on Hard")
	for k in EnemyDefs.KINDS:
		var e := EnemyDefs.stats(k, "easy", 1)
		var n := EnemyDefs.stats(k, "normal", 1)
		var h := EnemyDefs.stats(k, "hard", 1)
		check(e["hp"] <= n["hp"] and n["hp"] <= h["hp"] and e["hp"] < h["hp"], "%s hp easy %d <= normal %d <= hard %d" % [k, e["hp"], n["hp"], h["hp"]])
		check(e["speed_scale"] < n["speed_scale"] and n["speed_scale"] < h["speed_scale"], "%s speed scales with difficulty" % k)
		check_eq(n["hp"], int(EnemyDefs.get_def(k)["hp"]), "%s Normal invasion 1 = the table" % k)
	var hps := []
	for inv in range(1, 6):
		hps.append(EnemyDefs.stats("psycho", "normal", inv)["hp"])
	check_eq(hps, [3, 3, 4, 4, 5], "psycho hp per invasion as in Experiment 002")
	check(is_equal_approx(EnemyDefs.stats("bomber", "hard", 1)["blast_damage"], 60.0 * 1.3), "blast damage scales with enemy_damage")
	check(is_equal_approx(EnemyDefs.blast_damage_at(0.0, 60.0, 4.0), 60.0) and is_equal_approx(EnemyDefs.blast_damage_at(2.0, 60.0, 4.0), 30.0)
		and EnemyDefs.blast_damage_at(4.5, 60.0, 4.0) == 0.0, "linear blast fall-off to 0 at the reach")


func test_ai_every_type_spawns_with_its_look_and_numbers() -> void:
	await _setup(Vector2(6.5, 7.8))
	roster.level = "hard"
	roster.invasion = 3
	var spawned := {}
	var i := 0
	for k in EnemyDefs.KINDS:
		var e: AIEnemy = roster.spawn_type(k, Vector2(-4.0 + 2.5 * i, 12.5))
		spawned[k] = e
		i += 1
	await physics_frames(2)
	for k in spawned:
		var e: AIEnemy = spawned[k]
		var st := EnemyDefs.stats(k, "hard", 3)
		check(e is VoxelEnemy and e.kind == k, "%s is a VoxelEnemy-compatible body" % k)
		check_eq(e.hp, st["hp"], "%s hp from the difficulty and invasion" % k)
		check(is_equal_approx(e.speed(), float(EnemyDefs.get_def(k)["speed"]) * st["speed_scale"]), "%s speed" % k)
		check_eq(e.rig.scale, EnemyDefs.get_def(k)["scale"], "%s rig scale" % k)
		check(e.get_meta("invader", true) == false, "%s: not an invader unless asked" % k)
	check(spawned["runner"].rig.parts[0].material_override != spawned["psycho"].rig.parts[0].material_override, "the runner is tinted")
	check(spawned["brute"].rig.parts[0].material_override != spawned["runner"].rig.parts[0].material_override, "the brute has its own tint")
	check(spawned["brute"].extras.has("club"), "the brute carries a club")
	var light: OmniLight3D = spawned["bomber"].extras.get("light")
	check(light != null and spawned["bomber"].extras.has("pack"), "the bomber wears a glowing pack with a light")
	check(spawned["psycho"].rig is HumanoidRig, "the psycho is a voxel person (Exp 011)")
	check_eq(roster.living_by_kind(), {"psycho": 1, "runner": 1, "brute": 1, "bomber": 1}, "living_by_kind")
	check_eq(roster.living(), 4, "living() counts every type")
	check_eq(roster.kill_all(), 4, "kill_all() kills every type")
	await physics_frames(2)
	check_eq(roster.living(), 0, "none left")


func test_ai_brute_shrugs_off_knockback() -> void:
	await _setup(Vector2(6.5, 7.8))
	var p: AIEnemy = roster.spawn_type("psycho", Vector2(-3.0, 13.0), {"hp": 50})
	var b: AIEnemy = roster.spawn_type("brute", Vector2(1.0, 13.0), {"hp": 50})
	await physics_frames(3)
	p.set_physics_process(false)
	b.set_physics_process(false)
	var p0 := p.plan_pos()
	var b0 := b.plan_pos()
	p.take_hit(Vector3(0, 0, 1))
	b.take_hit(Vector3(0, 0, 1))
	p.set_physics_process(true)
	b.set_physics_process(true)
	var pd := 0.0
	var bd := 0.0
	for f in 24:
		await physics_frames(1)
		pd = maxf(pd, p.plan_pos().y - p0.y)
		bd = maxf(bd, b.plan_pos().y - b0.y)
	check(pd > 0.05, "a psycho is knocked back (%.3f m)" % pd)
	check(bd < pd * 0.35, "a brute barely moves back (%.3f m vs %.3f m)" % [bd, pd])


## The brute's swing counts three strikes; a psycho's one (on the front door).
func test_ai_brute_strikes_three_times_per_swing() -> void:
	await _setup(Vector2(4.6, 7.4))
	var door := _door(Vector2(4.5, 9.0))
	var strikes := {"n": 0}
	roster.wall_swing.connect(func(_e, _t): strikes["n"] += 1)
	var b: AIEnemy = roster.spawn_type("brute", Vector2(4.5, 10.6))
	var t := 0.0
	while t < 20.0 and b.swings["wall"] == 0:
		await physics_frames(3)
		t += 0.05
	check(b.swings["wall"] >= 1, "the brute swung at the door (%.1f s)" % t)
	check_eq(strikes["n"], 3 * b.swings["wall"], "three strikes per swing")
	check_eq(door.max_hp - door.hp, 3 * b.swings["wall"], "the door lost 3 hp per swing (%d)" % (door.max_hp - door.hp))
	b.kill_quietly()
	world.repair_object(door)
	strikes["n"] = 0
	var p: AIEnemy = roster.spawn_type("psycho", Vector2(4.5, 10.6))
	t = 0.0
	while t < 20.0 and p.swings["wall"] == 0:
		await physics_frames(3)
		t += 0.05
	check(p.swings["wall"] >= 1, "the psycho swung at the door")
	check_eq(door.max_hp - door.hp, p.swings["wall"], "one hp per psycho swing")


## Back door open, front door closed, player in the living room, enemies at
## the north side: a psycho's plan bashes in; a runner's goes round to the
## open back door, and in play it gets in without a single wall swing.
func test_ai_runner_detours_to_an_open_door() -> void:
	await _setup(Vector2(6.5, 7.8))
	var back := _door(Vector2(14.0, 6.5))
	world.set_door_open(back, true)
	await physics_frames(2)
	var from := Vector2(6.0, -2.5)
	var to := player.plan_pos()
	var psycho_path := world.nav.find_path(from, to)
	var runner_planner: Object = WeightedNav.for_nav(world.nav, EnemyDefs.get_def("runner")["bash_weight"])
	var runner_path: PackedVector2Array = runner_planner.find_path(from, to)
	check(_bash_cells(world.nav, psycho_path) > 0, "a psycho's plan bashes through a wall (%d cells)" % _bash_cells(world.nav, psycho_path))
	check_eq(_bash_cells(world.nav, runner_path), 0, "a runner's plan needs no bashing")
	var via_back := false
	for p in runner_path:
		if p.distance_to(Vector2(14.0, 6.5)) < 0.6:
			via_back = true
	check(via_back, "through the open back door")
	var r: AIEnemy = roster.spawn_type("runner", from)
	var rref: WeakRef = weakref(r)
	var acc := {"max_x": -INF}
	var t := 0.0
	var reached := false
	while t < 25.0 and not reached:
		await physics_frames(6)
		t += 0.1
		var rr = rref.get_ref()
		if rr == null:
			break
		acc["max_x"] = maxf(acc["max_x"], rr.plan_pos().x)
		reached = rr.swings["player"] > 0
	print("    runner reached the player after %.1f s; wall swings %d" % [t, r.swings["wall"]])
	check(reached, "the runner reached the player and attacked")
	check_eq(r.swings["wall"], 0, "without a wall swing")
	check(acc["max_x"] > 13.5, "by way of the back door (max x %.1f)" % acc["max_x"])


## A psycho heading for the closed front door changes course when the door
## opens (nav revision) and walks in without breaking anything.
func test_ai_chaser_uses_a_new_opening_at_once() -> void:
	await _setup(Vector2(4.6, 7.4))
	var door := _door(Vector2(4.5, 9.0))
	var p: AIEnemy = roster.spawn_type("psycho", Vector2(4.4, 12.6))
	await physics_frames(30)
	world.set_door_open(door, true)
	var t := 0.0
	while t < 15.0 and p.swings["player"] == 0:
		await physics_frames(6)
		t += 0.1
	check(p.swings["player"] >= 1, "it reached the player (%.1f s)" % t)
	check_eq(p.swings["wall"], 0, "no wall or door swings")
	check(is_instance_valid(door) and door.hp == door.max_hp, "the door is intact")


func test_ai_weighted_nav_follows_the_shared_nav() -> void:
	var nav := GridNav.new()
	HousePlan.rasterize_into(nav)
	var a: WeightedNav = WeightedNav.for_nav(nav, 60.0)
	check(WeightedNav.for_nav(nav, 60.0) == a, "one shared layer per weight")
	check(WeightedNav.for_nav(nav, GridNav.BASH_WEIGHT) == nav, "the default weight is the nav itself")
	var p1 := a.find_path(Vector2(-3.0, 4.5), Vector2(6.5, 7.8))
	check(not p1.is_empty() and _bash_cells(nav, p1) == 0, "walk-only path through the (open) plan doorways")
	check_eq(a.rebuilds, 1, "built once")
	# Close the front and back doorways and the windows' gaps: now it must bash.
	for r in [Rect2(4.0, 8.85, 1.0, 0.3), Rect2(13.85, 6.0, 0.3, 1.0)]:
		nav.mark_rect(r, GridNav.WALL)
		nav.refresh_region(r)
	var p2 := a.find_path(Vector2(-3.0, 4.5), Vector2(6.5, 7.8))
	check_eq(a.rebuilds, 1, "patched, not rebuilt")
	check(a.patched > 0 and a.patched < 200, "a few cells patched (%d)" % a.patched)
	var ref := WeightedNav.new(nav, 60.0)
	check_eq(p2, ref.find_path(Vector2(-3.0, 4.5), Vector2(6.5, 7.8)), "same path as a fresh layer")
