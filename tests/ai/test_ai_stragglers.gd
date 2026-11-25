extends "res://tests/test_case.gd"
## Experiment 007 (N): calm-until-provoked enemies (StragglerMind). A night
## straggler plans a few activities and never swings while calm; noises draw
## it or turn it; seeing Eli, being shot or hurt turns it; invasion enemies
## stay hostile; POI modes (hidden, wander) stay near their spot; a provoked
## bomber goes back to its own behaviour.

const Roster := preload("res://src/game/enemy_roster.gd")
const LIVING_ROOM := Vector2(6.0, 8.2)

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
	roster.setup(world, player, 11)
	add(roster)
	roster.wall_swing.connect(func(e, t): world.enemy_strike(e.global_position, t))
	await physics_frames(2)


func test_straggler_is_calm_plans_and_never_swings() -> void:
	await _setup(LIVING_ROOM)
	var e: AIEnemy = roster.spawn_type("psycho", Vector2(20.0, 4.0), {"mode": "straggler"})
	check(e.is_calm() and e.mind.mode == "straggler", "a calm straggler")
	check(e.state_name() in ["pass", "window", "door", "examine"], "busy with an activity (%s)" % e.state_name())
	check(e.mind.plan.size() <= 4, "a few activities planned (%s)" % [e.mind.plan])
	var hostile := float(e.def["speed"]) * e.speed_scale
	check(e.speed() < hostile * 0.7, "it walks slowly (%.2f < %.2f)" % [e.speed(), hostile])
	check(not e.brain.attack_goal and not e.brain.bash, "no swings at the goal, no bashing")
	var start := e.plan_pos()
	await physics_frames(240)
	check(e.swings["player"] == 0 and e.swings["wall"] == 0, "four seconds without a swing")
	check(e.plan_pos().distance_to(start) > 1.0, "it moves (%.1f m)" % e.plan_pos().distance_to(start))
	check(e.is_calm(), "still calm: Eli is inside, out of sight (%s)" % e.provoked_by)
	check_eq(roster.calm_count(), 1, "the roster counts it as calm")


func test_noise_draws_then_turns_it() -> void:
	await _setup(LIVING_ROOM)
	var e: AIEnemy = roster.spawn_type("psycho", Vector2(9.0, 13.5), {"mode": "straggler"})
	var got := []
	roster.enemy_provoked.connect(func(en, why): got.append(why))
	e.hear(Vector2(4.5, 9.4), 1.2, "hammer_metal")
	check(e.is_calm() and e.state_name() == "investigate", "a moderate noise draws it to look (%s)" % e.state_name())
	check(e.mind.goal != Vector2.INF and not HousePlan.FOOTPRINT.grow(-0.2).has_point(e.mind.goal),
		"a noise in the house draws it to a way in, outside (%s)" % e.mind.goal)
	e.hear(Vector2(4.5, 9.4), 2.5, "gunfire")
	check(not e.is_calm() and e.state_name() == "chase", "enough noise turns it hostile (%s)" % e.state_name())
	check(got.size() == 1 and str(got[0]).begins_with("noise"), "the roster says why (%s)" % [got])
	check(e.brain.attack_goal and e.brain.bash, "hostile: swings and bashes again")


func test_sight_and_harm_turn_it() -> void:
	await _setup(Vector2(9.0, 12.0))
	var near: AIEnemy = roster.spawn_type("psycho", Vector2(9.0, 13.5), {"mode": "straggler"})
	await physics_frames(20)
	check(not near.is_calm() and near.provoked_by == "saw Eli", "Eli in the open, close by: it turns (%s)" % near.provoked_by)
	var shot: AIEnemy = roster.spawn_type("brute", Vector2(-6.0, 6.0), {"mode": "wander"})
	shot.take_damage(1, Vector3.RIGHT, "shot")
	check(not shot.is_calm() and shot.provoked_by.begins_with("hurt"), "a shot turns it (%s)" % shot.provoked_by)
	var invader: AIEnemy = roster.spawn_type("runner", Vector2(20.0, 14.0), {"invader": true})
	check(not invader.is_calm() and invader.brain.attack_goal, "invasion enemies attack at once")


func test_poi_modes_and_bomber() -> void:
	await _setup(LIVING_ROOM)
	var lurker: AIEnemy = roster.spawn_type("psycho", Vector2(-5.0, 10.0), {"mode": "hidden"})
	var wanderer: AIEnemy = roster.spawn_type("runner", Vector2(19.0, -4.0), {"mode": "wander"})
	var bomber: AIEnemy = roster.spawn_type("bomber", Vector2(19.0, 13.0), {"mode": "wander"})
	check(lurker.state_name() == "lurk" and wanderer.state_name() == "wander", "hidden lurks, wander roams")
	await physics_frames(180)
	check(lurker.plan_pos().distance_to(Vector2(-5.0, 10.0)) < 1.0, "the hidden one stays put")
	check(wanderer.plan_pos().distance_to(Vector2(19.0, -4.0)) < StragglerMind.WANDER_RANGE + 1.5, "the wanderer stays near its spot")
	check(bomber.state_name() != "fuse" and bomber.is_calm(), "a calm bomber doesn't light its fuse (%s)" % bomber.state_name())
	bomber.provoke("test")
	check(not bomber.is_calm() and bomber.state_name() != "wander", "provoked, the bomber goes back to its own behaviour (%s)" % bomber.state_name())
	lurker.set_calm_mode("hostile")
	check(not lurker.is_calm(), "set_calm_mode(\"hostile\") turns it")
	lurker.set_calm_mode("wander")
	check(lurker.is_calm() and lurker.state_name() == "wander", "and back to calm")
	lurker.investigate(Vector2(-3.0, 9.0))
	check_eq(lurker.state_name(), "investigate", "investigate(pos) sends it to look")
