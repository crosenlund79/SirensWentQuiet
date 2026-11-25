extends "res://tests/test_case.gd"
## Exp 007 (T): visible travel and the home <-> POI flow (src/travel) with
## agent P's POIs: home -> map -> travel (animated, skipped) -> the Corner
## Store -> search a shelf, take it -> leave by an exit -> home with exactly
## that, time passed, the house as it was; by car, the boot comes home; an
## invasion while away damages the house a little; a save at a POI continues
## at the POI.

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
	check(TravelRules.capacity_text(s, true).contains("boot"), "the pack and the boot")


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

## A container at the POI with something in it and no lock (agent P's spots).
func _spot_with_items(g: Node) -> Node3D:
	for sp in g.world.spots_of("container"):
		if str(sp.data.get("needs", "")) == "" and not (g.poi.record["c"][sp.id]["items"] as Dictionary).is_empty():
			return sp
	return null


func _count(s: GameState, items: Dictionary) -> int:
	var n := 0
	for id in items:
		n += s.inventory.count(id)
	return n


## The user's loop: the map, the walk (animated), the Corner Store, search a
## shelf, take what's there, leave by an exit, home with exactly that.
func test_travel_to_the_store_search_a_shelf_and_bring_it_home() -> void:
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 9.0 * 60.0
	var t_depart := s.total_minutes
	g.debug_open("map")
	check_eq(g.debug_modal(), "map", "the map is open")
	var screen: RegionMapScreen = g.map.screen
	screen.select("convenience")
	check(screen.request_travel(), "Travel is offered for the Corner Store")
	check_eq(g.debug_modal(), "travel", "travelling")
	check(screen.travelling, "the map animates the trip")
	await frames(20)
	var walker: Node3D = screen.view.get_node_or_null("Traveller")
	check(walker != null, "a tiny Eli walks on the map")
	check(not screen.travelling or walker.position.distance_to(screen.view.terrain.anchor_of("home")) > 0.1, "and has moved")
	screen.skip_travel()
	check(await _wait_until(func(): return g.left_to != "", 60), "the scene changes after the walk")
	check_eq(GameLaunch.site, "convenience", "to the Corner Store")
	check_eq(GameLaunch.mode, "carry", "carrying the run")
	check(GameLaunch.carry.has("home") and GameLaunch.carry.has("state"), "with the home snapshot and the state")
	check("departed" in g.autosave_log, "the departure checkpoint (%s)" % [g.autosave_log])
	# at the store
	g = await _next_scene(g)
	s = g.debug_state()
	check(not g.is_home() and g.site_id() == "convenience", "at the Corner Store")
	check(g.world is PoiWorld, "agent P's POI world")
	var leg := TravelRules.minutes("convenience")
	check(absf(s.total_minutes - (t_depart + leg)) < 2.0, "the road took its time (%.1f -> %.1f)" % [t_depart, s.total_minutes])
	check("arrived" in g.autosave_log, "autosaved on arrival (%s)" % [g.autosave_log])
	check(g.levels == null and g.car == null and g.boundary == null and g.security == null and g.storage == null, "no home-only helpers here")
	check(g.travel != null and g.poi != null and g.noise != null and g.visibility != null, "travel, the POI helper, noise and visibility")
	check(g.debug_player_pos().distance_to(g.world.entry_point()) < 0.5, "Eli starts at the entry")
	# search a shelf and take what's there
	var shelf := _spot_with_items(g)
	if not check(shelf != null, "a shelf with something on it"):
		return
	var items: Dictionary = (g.poi.record["c"][shelf.id]["items"] as Dictionary).duplicate()
	g.debug_teleport_player(Vector2(shelf.position.x, shelf.position.z))
	await physics_frames(1)
	g.poi.interact_spot(shelf)
	await frames(2)
	g.poi.complete_action()
	check(g.poi.panel.is_open, "the take-only panel")
	var before := _count(s, items)
	var got: Dictionary = g.poi.panel.take_everything()
	g.poi.close_panel()
	await frames(1)
	check(not got.is_empty() and _count(s, items) > before, "taken into the pack (%s)" % [got])
	var carried := {}
	for id in got:
		carried[id] = s.inventory.count(id)
	# leave by an exit
	TravelFlow.skip_animation = true
	var exit: Node3D = g.world.spots_of("exit")[0]
	check_eq(exit.interact_prompt(), "[E] Leave for home", "the exit")
	g.poi.interact_spot(exit)
	check(await _wait_until(func(): return g.left_to != "", 30), "leaves for home")
	check_eq(GameLaunch.site, "home", "home")
	var t_back: float = s.total_minutes
	# home again
	g = await _next_scene(g)
	s = g.debug_state()
	check(g.is_home(), "home")
	for id in carried:
		check_eq(s.inventory.count(id), int(carried[id]), "%s came home" % id)
	check_eq(s.region.visits("convenience"), 1, "the visit is counted")
	check(absf(s.total_minutes - t_back) < 0.5 and t_back >= t_depart + 2 * leg - 1.0, "time passed there and back")
	check_eq(int(g.debug_world().damage_summary()["missing_voxels"]), 0, "the house is as it was")
	check(FogBoundary.LOT.has_point(g.debug_player_pos()), "Eli stands on the lot")
	check("returned" in g.autosave_log, "autosaved (%s)" % [g.autosave_log])
	check(GameLaunch.carry.is_empty(), "nothing left in carry")
	check(not OffscreenHome.is_away(s), "the ledger is closed")


func test_by_car_an_invasion_while_away_and_a_save_at_the_poi() -> void:
	TravelFlow.skip_animation = true
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 10.0 * 60.0
	s.car_repaired = true
	s.inventory.add("fuel", 2 - s.inventory.count("fuel"))
	var stone0 := s.inventory.count("stone")
	await g.travel.depart("forest", true)
	g = await _next_scene(g)
	s = g.debug_state()
	check(not g.is_home(), "at the POI")
	check(g.travel.by_car() and g.world.has_car, "by car, and the car stands there")
	check_eq(s.inventory.count("fuel"), 1, "one fuel can for the trip")
	g.poi.cargo["stone"] = 4                 # in the boot (P's live visit record)
	# they come for the house while Eli is out
	g.dev_trigger_invasion()
	check(not g.debug_director().active, "no wave here")
	check_eq(OffscreenHome.events(s).size(), 1, "recorded for the house")
	# save here, continue here
	var here: Vector2 = g.debug_player_pos() + Vector2(0.6, 0.0)
	g.debug_teleport_player(here)
	check_eq(g.debug_save(), "", "saving at a POI works")
	var data: Dictionary = SaveGame.read().get("data", {})
	check(typeof(data.get("site")) == TYPE_DICTIONARY and data["site"]["id"] == "forest", "the save knows the place")
	g.queue_free()
	await frames(2)
	g = await _boot("continue")
	s = g.debug_state()
	check(not g.is_home() and g.site_id() == "forest", "Continue: still at Pine Woods")
	check(g.debug_player_pos().distance_to(here) < 0.3, "where Eli stood (%s)" % g.debug_player_pos())
	check(g.world.has_car and int(g.poi.cargo.get("stone", 0)) == 4, "the car and its boot too")
	check_eq(OffscreenHome.events(s).size(), 1, "the ledger survived the save")
	check(not g.travel.home_snapshot.is_empty(), "the home snapshot came along")
	g.leave_site()
	check(await _wait_until(func(): return g.left_to != "", 30), "leaves for home")
	g = await _next_scene(g)
	s = g.debug_state()
	check(g.is_home(), "home")
	check_eq(int(g.travel.last_cargo.get("stone", 0)), 4, "the boot was unloaded")
	check_eq(s.inventory.count("stone"), stone0 + 4, "into the household")
	var rep: Dictionary = g.travel.last_report
	check_eq(int(rep.get("attacks", 0)), 1, "one attack resolved")
	check(int(rep.get("strikes", 0)) >= 1, "with blows on the house")
	var dmg: Dictionary = g.debug_world().damage_summary()
	check(int(dmg["missing_voxels"]) > 0 or int(dmg["damaged_objects"]) > 0 or not (rep["destroyed"] as Array).is_empty(), "the house took damage (%s)" % [dmg])
	check(g.last_toast != "", "a report")
