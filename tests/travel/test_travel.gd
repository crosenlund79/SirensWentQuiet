extends "res://tests/test_case.gd"
## Exp 007 (T): visible travel and the home <-> POI flow (src/travel), with the
## stand-in POI (TravelTestSite) when agent P's src/poi is not in the project:
## home -> map -> travel (animated, skipped) -> the POI scene -> carry an item
## and car cargo -> leave -> home restored with them, time passed, the house
## as it was; an invasion while away damages the house a little; a save at a
## POI continues at the POI.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_travel.dat"
const TravelFlow := preload("res://src/travel/travel_flow.gd")


func _boot(mode: String) -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 7007
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.death_delay = 0.05
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	return g


## Frees a game and boots the next scene as the scene change would.
func _next_scene(g: Node) -> Node:
	check(g.left_to == GameLaunch.GAME_SCENE, "changes scene (left_to '%s')" % g.left_to)
	g.queue_free()
	await frames(2)
	return await _boot(GameLaunch.mode)


func _wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await frames(1)
	return cond.call()


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	GameLaunch.notice = ""
	GameLaunch.site = "home"
	GameLaunch.carry = {}
	TravelFlow.skip_animation = false
	await super.cleanup()


# --- pure rules ------------------------------------------------------------------------------

func test_travel_rules_times_fuel_and_daylight() -> void:
	var s := GameState.new_run(5)
	s.total_minutes = 9.0 * 60.0
	var foot := TravelRules.minutes("forest")
	check(foot > 0 and TravelRules.minutes("forest", true) <= foot, "the car is faster (%d)" % foot)
	check(TravelRules.anim_seconds(foot) >= 4.0 and TravelRules.anim_seconds(600.0) <= 8.0, "4-8 s on foot")
	check(TravelRules.timing(s, "forest")["before_dark"], "a morning trip is back before dark")
	s.total_minutes = 19.0 * 60.0
	check(not TravelRules.timing(s, "military")["before_dark"], "an evening trip far away is not")
	check(TravelRules.block_reason(s, "forest", true) != "", "no car yet")
	s.car_repaired = true
	s.inventory.add("fuel", 1)
	check_eq(TravelRules.block_reason(s, "forest", true), "", "a running car with fuel")
	check(TravelRules.block_reason(s, "police") != "" or s.region.is_discovered("police"), "unknown places can't be travelled to")
	check(TravelSites.provider() != null, "a site provider")


func test_offscreen_invasion_damages_the_house_a_little() -> void:
	var lighting := VoxelLighting.new()
	add(lighting)
	var w := HouseWorld.new()
	w.setup(lighting)
	add(w)
	w.build_new()
	var s := GameState.new_run(9)
	var due := float(s.run.get("next_invasion_at", 0.0))
	s.total_minutes = due
	OffscreenHome.begin(s)
	OffscreenHome.record_invasion(s, due)
	check(float(s.run.get("next_invasion_at", 0.0)) > due, "the schedule moved on")
	check(not s.run.get("invasion_active", false), "nothing is running")
	var d := OffscreenHome.defence(w)
	check(int(d["doors"]) >= 2 and float(d["score"]) > 0.0, "the house has doors and a defence (%s)" % [d])
	var r := OffscreenHome.resolve(w, s, 3)
	OffscreenHome.finish(s)
	var dmg := w.damage_summary()
	check_eq(int(r["attacks"]), 1, "one attack")
	check(int(r["strikes"]) >= 1, "it lands blows (%d)" % r["strikes"])
	check(int(dmg["missing_voxels"]) > 0 or int(dmg["damaged_objects"]) > 0 or not r["destroyed"].is_empty(), "the house is damaged (%s)" % [dmg])
	check(not (r["lines"] as Array).is_empty() and str(r["lines"][0]).contains("they came"), "a report line (%s)" % [r["lines"]])
	check(not OffscreenHome.is_away(s), "the ledger is closed")


# --- the flow in the game --------------------------------------------------------------------

func test_home_to_poi_and_back_with_what_eli_carries() -> void:
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 9.0 * 60.0
	var wood0 := s.inventory.count("wood")
	var t_depart := s.total_minutes
	# the map: select Pine Woods, Travel (the animation plays on the map)
	g.debug_open("map")
	check_eq(g.debug_modal(), "map", "the map is open")
	var screen: RegionMapScreen = g.map.screen
	screen.select("forest")
	check(screen.request_travel(), "Travel is offered for Pine Woods")
	check_eq(g.debug_modal(), "travel", "travelling")
	check(screen.travelling, "the map animates the trip")
	await frames(20)
	var walker: Node3D = screen.view.get_node_or_null("Traveller")
	check(walker != null, "a tiny Eli walks on the map")
	check(not screen.travelling or walker.position.distance_to(screen.view.terrain.anchor_of("home")) > 0.1, "and has moved")
	screen.skip_travel()
	check(await _wait_until(func(): return g.left_to != "", 60), "the scene changes after the walk")
	check_eq(GameLaunch.site, "forest", "to Pine Woods")
	check_eq(GameLaunch.mode, "carry", "carrying the run")
	check(GameLaunch.carry.has("home") and GameLaunch.carry.has("state"), "with the home snapshot and the state")
	check("departed" in g.autosave_log, "the departure checkpoint (%s)" % [g.autosave_log])
	# at the POI
	g = await _next_scene(g)
	s = g.debug_state()
	check(not g.is_home() and g.site_id() == "forest", "at Pine Woods")
	check(g.world is TravelTestSite or g.world.has_method("entry_point"), "a POI world")
	var leg := TravelRules.minutes("forest")
	check(absf(s.total_minutes - (t_depart + leg)) < 2.0, "the road took its time (%.1f -> %.1f)" % [t_depart, s.total_minutes])
	check_eq(s.region.visits("forest"), 1, "the visit is recorded")
	check("arrived" in g.autosave_log, "autosaved on arrival (%s)" % [g.autosave_log])
	check(g.levels == null and g.car == null and g.boundary == null, "no home-only helpers here")
	check(g.travel != null and g.poi != null, "travel and the POI helper")
	# carry something, and something in the car's cargo box
	s.inventory.add("wood", 3)
	if "cargo" in g.poi:
		g.poi.cargo = {"stone": 4}
	TravelFlow.skip_animation = true
	g.leave_site()
	check(await _wait_until(func(): return g.left_to != "", 30), "leaves for home")
	check_eq(GameLaunch.site, "home", "home")
	var t_back: float = s.total_minutes
	# home again
	g = await _next_scene(g)
	s = g.debug_state()
	check(g.is_home(), "home")
	check_eq(s.inventory.count("wood"), wood0 + 3, "what Eli carried came home")
	if g.travel.last_cargo.has("stone"):
		check_eq(int(g.travel.last_cargo["stone"]), 4, "the cargo was unloaded")
	check(absf(s.total_minutes - t_back) < 0.5 and t_back >= t_depart + 2 * leg - 1.0, "time passed there and back")
	check_eq(int(g.debug_world().damage_summary()["missing_voxels"]), 0, "the house is as it was")
	check(FogBoundary.LOT.has_point(g.debug_player_pos()), "Eli stands on the lot")
	check("returned" in g.autosave_log, "autosaved (%s)" % [g.autosave_log])
	check(GameLaunch.carry.is_empty(), "nothing left in carry")
	check(not OffscreenHome.is_away(s), "the ledger is closed")


func test_an_invasion_while_away_and_a_save_at_the_poi() -> void:
	TravelFlow.skip_animation = true
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 10.0 * 60.0
	await g.travel.depart("forest")
	g = await _next_scene(g)
	s = g.debug_state()
	check(not g.is_home(), "at the POI")
	# they come for the house while Eli is out
	g.dev_trigger_invasion()
	check(not g.debug_director().active, "no wave here")
	check_eq(OffscreenHome.events(s).size(), 1, "recorded for the house")
	# save here, continue here
	check_eq(g.debug_save(), "", "saving at a POI works")
	var data: Dictionary = SaveGame.read().get("data", {})
	check(typeof(data.get("site")) == TYPE_DICTIONARY and data["site"]["id"] == "forest", "the save knows the place")
	g.debug_teleport_player(Vector2(8.0, 11.0))
	check_eq(g.debug_save(), "", "saved again")
	g.queue_free()
	await frames(2)
	g = await _boot("continue")
	s = g.debug_state()
	check(not g.is_home() and g.site_id() == "forest", "Continue: still at Pine Woods")
	check(g.debug_player_pos().distance_to(Vector2(8.0, 11.0)) < 0.3, "where Eli stood (%s)" % g.debug_player_pos())
	check_eq(OffscreenHome.events(s).size(), 1, "the ledger survived the save")
	check(not g.travel.home_snapshot.is_empty(), "the home snapshot came along")
	g.leave_site()
	check(await _wait_until(func(): return g.left_to != "", 30), "leaves for home")
	g = await _next_scene(g)
	check(g.is_home(), "home")
	var rep: Dictionary = g.travel.last_report
	check_eq(int(rep.get("attacks", 0)), 1, "one attack resolved")
	check(int(rep.get("strikes", 0)) >= 1, "with blows on the house")
	var dmg: Dictionary = g.debug_world().damage_summary()
	check(int(dmg["missing_voxels"]) > 0 or int(dmg["damaged_objects"]) > 0 or not (rep["destroyed"] as Array).is_empty(), "the house took damage (%s)" % [dmg])
	check(g.last_toast != "", "a report")
