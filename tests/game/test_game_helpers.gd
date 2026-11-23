extends "res://tests/test_case.gd"
## The game root's small helpers: footsteps, interaction finder, save
## composition and parsing, invasion pacing.

const Footsteps := preload("res://src/game/footsteps.gd")
const Finder := preload("res://src/game/interaction_finder.gd")
const RunSave := preload("res://src/game/run_save.gd")
const Director := preload("res://src/game/invasion_director.gd")


class Thing extends Node3D:
	var prompt := "[E] Use"
	func interact_prompt() -> String:
		return prompt
	func interact(_game: Node) -> void:
		pass


func test_footsteps_alternate_at_a_speed_based_interval() -> void:
	var f := Footsteps.new()
	check_eq(f.tick(0.5, 0.0), "", "standing: silent")
	var seen := []
	var t := 0.0
	while t < 3.0:
		var s := f.tick(0.05, 4.0)
		if s != "":
			seen.append(s)
		t += 0.05
	check(seen.size() >= 8 and seen.size() <= 11, "about 3 steps a second at full speed (%d)" % seen.size())
	check_eq(seen.slice(0, 4), ["player/footstep_1", "player/footstep_2", "player/footstep_3", "player/footstep_4"], "variants cycle")
	check(Footsteps.interval(2.4) > Footsteps.interval(4.0), "slower walk, slower steps")


func test_interaction_finder_picks_the_nearest_visible_prompt() -> void:
	var a: Thing = add(Thing.new())
	var b: Thing = add(Thing.new())
	var c: Thing = add(Thing.new())
	a.position = Vector3(1.0, 0, 0)
	b.position = Vector3(0.5, 0, 0)
	c.position = Vector3(3.0, 0, 0)
	b.prompt = ""                       # hidden prompt: skipped
	check(Finder.nearest([a, b, c], Vector2.ZERO) == a, "nearest with a prompt")
	check(Finder.nearest([c], Vector2.ZERO) == null, "out of reach")
	check(Finder.nearest([a, null, "x"], Vector2.ZERO) == a, "ignores junk")


func test_save_composition_round_trip_and_validation() -> void:
	var s := GameState.new_run(5)
	s.advance(90.0)
	var d: Dictionary = RunSave.compose(s, {"house": 1}, Vector3(3.5, 0, 7.25), 0.75, {"time_scale": 2.0})
	check(d.has("summary") and d.has("state") and d.has("world") and d.has("game"), "layout")
	check_eq(d["game"]["player"]["pos"], [3.5, 7.25], "player position as [x, z]")
	check_eq(d["game"]["time_scale"], 2.0, "extras merged")
	var p: Dictionary = RunSave.parse(d)
	check(p["ok"], "parses")
	check_eq(p["player_pos"], Vector3(3.5, 0, 7.25), "position back")
	check_eq(p["yaw"], 0.75, "yaw back")
	check_eq((p["state"] as GameState).clock_text(), s.clock_text(), "state back")
	check(not d.has("game_data"), "no stub-era mirror any more")
	var old := d.duplicate(true)            # a stub-era save: "game" overwritten, data in "game_data"
	old["game_data"] = old["game"]
	old["game"] = "sirens_went_quiet"
	check_eq(RunSave.parse(old)["player_pos"], Vector3(3.5, 0, 7.25), "game_data still read as a fallback")
	check(not RunSave.parse({"state": {"x": 1}, "world": {}})["ok"], "bad state rejected")
	check(not RunSave.parse({"state": s.to_dict()})["ok"], "missing world rejected")
	var dead := GameState.new_run(5)
	dead.damage(500.0, "test")
	check(not RunSave.parse({"state": dead.to_dict(), "world": {}})["ok"], "a finished run can't be continued")
	var odd := d.duplicate(true)
	odd["game"]["player"]["pos"] = [NAN, 1.0]
	check(RunSave.parse(odd)["ok"] and RunSave.parse(odd)["player_pos"] == null, "bad position: ignored, not fatal")


func test_invasion_director_paces_the_wave() -> void:
	var d := Director.new()
	d.begin(3, 4, 1.1, 9)
	var spawned := 0
	var t := 0.0
	var times := []
	while t < 200.0 and spawned < 3:
		var n := d.tick(0.5)
		if n > 0:
			times.append(t)
		spawned += n
		t += 0.5
	check_eq(spawned, 3, "all three spawn")
	check(d.all_spawned(), "all_spawned")
	check(times[0] <= Director.FIRST_DELAY + 0.5, "the first comes soon")
	for i in range(1, times.size()):
		var gap: float = times[i] - times[i - 1]
		check(gap >= SurvivalTuning.INVASION_SPAWN_GAP.x - 0.5 and gap <= SurvivalTuning.INVASION_SPAWN_GAP.y + 0.5, "staggered 25-40 s (%.1f)" % gap)
	check_eq(d.tick(100.0), 0, "no more after the wave")
	for p in Director.fog_points():
		check(not FogBoundary.LOT.has_point(p) and HousePlan.YARD.has_point(p), "fog band point %s" % p)
	check(Director.fog_points().size() >= 4, "enough fog points")
	var pick := d.pick_spawn(Vector2(6.5, 7.8))
	check(pick.distance_to(Vector2(6.5, 7.8)) >= Director.MIN_SPAWN_DISTANCE - 0.6, "spawns away from the player")
