extends "res://tests/test_case.gd"
## Exp 008 (T): travel from one POI straight on to the next (src/travel):
## Home -> Corner Store -> (the map, M) -> Public Library -> Home. What Eli
## takes at both stops comes home exactly once, both visits are counted, the
## clock moves by each leg's own minutes, the home snapshot and the ledger
## of attacks at home travel along and are resolved once at home; by car the
## fuel follows the chain rule and the boot comes home; a save at the second
## stop continues there with the chain intact. Plus the pure leg rules.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_travel_chain.dat"
const TravelFlow := preload("res://src/travel/travel_flow.gd")


func _boot(mode: String) -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 8118
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


## Searches the first open container with something in it and takes it all
## (the player's own flow: E, the timer, the take-only panel). Returns what
## was taken.
func _take_from_a_container(g: Node) -> Dictionary:
	for sp in g.world.spots_of("container"):
		if str(sp.data.get("needs", "")) != "" or (g.poi.record["c"][sp.id]["items"] as Dictionary).is_empty():
			continue
		g.debug_teleport_player(Vector2(sp.position.x, sp.position.z))
		await physics_frames(1)
		g.poi.interact_spot(sp)
		await frames(2)
		g.poi.complete_action()
		if not g.poi.panel.is_open:
			continue
		var got: Dictionary = g.poi.panel.take_everything()
		g.poi.close_panel()
		await frames(1)
		if not got.is_empty():
			return got
	return {}


# --- pure rules ------------------------------------------------------------------------------

func test_leg_rules_poi_to_poi_minutes_fuel_and_the_chain_daylight() -> void:
	var s := GameState.new_run(5)
	# the road time of a leg between two places: the same estimate as from home
	var m := TravelRules.minutes_between("convenience", "library")
	var km := TravelRules.km_between("convenience", "library")
	var expect := maxi(int(round(km * RegionLocations.ROAD_FACTOR * RegionLocations.MINUTES_PER_KM / 5.0)) * 5, 10)
	check_eq(m, expect, "Corner Store -> Library: %.2f km" % km)
	check(m != TravelRules.minutes("library"), "not the time from home (%d vs %d)" % [m, TravelRules.minutes("library")])
	check_eq(TravelRules.minutes_between("library", "convenience"), m, "the same both ways")
	var mc := TravelRules.minutes_between("convenience", "library", true)
	check(mc < m and mc % 5 == 0, "the car is faster (%d)" % mc)
	check_eq(TravelRules.minutes_between("home", "library"), TravelRules.minutes("library"), "from home as before")
	check_eq(TravelRules.minutes_between("library", "home", true), TravelRules.minutes("library", true), "home by car as before")
	check_eq(TravelRules.minutes_between("library", "library"), 0, "no leg to where you are")
	# fuel: leaving home by car 1 can (there and back), each further stop by car 1 more, home paid, walking free
	check_eq(TravelRules.leg_fuel("home", "convenience", true), 1, "setting out by car")
	check_eq(TravelRules.leg_fuel("convenience", "library", true), 1, "a further stop by car")
	check_eq(TravelRules.leg_fuel("library", "home", true), 0, "the way home is paid")
	check_eq(TravelRules.leg_fuel("convenience", "library", false), 0, "walking is free")
	# the mode Eli came with, and the gate
	check_eq(TravelRules.leg_block_reason(s, "convenience", "library", true, false), "The car is at home.", "walked out: walks on")
	check_eq(TravelRules.leg_block_reason(s, "convenience", "library", false, true), "The car comes with you.", "drove out: drives on")
	s.car_repaired = true
	s.inventory.remove("fuel", s.inventory.count("fuel"))
	check(TravelRules.leg_block_reason(s, "convenience", "library", true, true).contains("fuel"), "no fuel for a further stop")
	check_eq(TravelRules.leg_block_reason(s, "convenience", "home", true, true), "", "home is always open (the way home is paid)")
	s.inventory.add("fuel", 1)
	check_eq(TravelRules.leg_block_reason(s, "convenience", "library", true, true), "", "with a can, on by car")
	check_eq(TravelRules.leg_block_reason(s, "convenience", "library", false, false), "", "on foot")
	check(TravelRules.leg_block_reason(s, "convenience", "military", false, false) != "", "not to an unknown place")
	check(TravelRules.leg_block_reason(s, "convenience", "convenience", false, false) != "", "not to where you are")
	# daylight: there, a stay, then home FROM THERE
	s.total_minutes = 9.0 * 60.0
	var tm := TravelRules.leg_timing(s, "convenience", "library")
	check_eq(int(tm["minutes"]), m, "the leg's minutes")
	check_eq(int(tm["home_minutes"]), TravelRules.minutes("library"), "the way home from the library")
	check(absf(float(tm["back_at"]) - (s.total_minutes + m + int(tm["stay"]) + TravelRules.minutes("library"))) < 0.01, "home at: there + stay + home")
	check(bool(tm["before_dark"]) and str(tm["text"]).begins_with("Back home by "), "a morning chain is home before dark (%s)" % tm["text"])
	s.total_minutes = 19.0 * 60.0
	tm = TravelRules.leg_timing(s, "convenience", "library")
	check(not bool(tm["before_dark"]) and str(tm["text"]).contains("after dark"), "an evening stop: home after dark (%s)" % tm["text"])
	var th := TravelRules.leg_timing(s, "library", "home")
	check(int(th["stay"]) == 0 and absf(float(th["back_at"]) - (s.total_minutes + TravelRules.minutes("library"))) < 0.01, "the home leg has no stay")
	check_eq(TravelRules.timing(s, "library")["back_at"], TravelRules.leg_timing(s, "home", "library")["back_at"], "timing() is the leg from home")
	# what the panel says a place is good for
	check(MapInfo.good_for("clinic").has("Medical"), "the clinic: medical (%s)" % [MapInfo.good_for("clinic")])
	check(MapInfo.good_for("hardware").has("Building materials"), "the hardware store: building materials")
	check(MapInfo.good_for("library").has("Books"), "the library: books")
	check_eq(MapInfo.visit_text(s, "library"), "Not yet", "never been")


# --- the chain in the game -------------------------------------------------------------------

## On foot: home -> the Corner Store (take) -> M, the map from there -> the
## Library (take; save; Continue) -> home with both stops' finds once.
func test_chain_on_foot_store_then_library_by_the_map_then_home() -> void:
	TravelFlow.skip_animation = true
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 8.0 * 60.0
	await g.travel.depart("convenience")
	g = await _next_scene(g)
	s = g.debug_state()
	check(g.site_id() == "convenience", "at the Corner Store")
	g.debug_kill_enemies()
	# the house is attacked while Eli is out (recorded, resolved at home)
	g.dev_trigger_invasion()
	check_eq(OffscreenHome.events(s).size(), 1, "an attack on the house is recorded")
	var got_a := await _take_from_a_container(g)
	check(not got_a.is_empty(), "took something at the store (%s)" % [got_a])
	# a refused leave doesn't end the visit (it would count twice later)
	s.run["invasion_active"] = true
	g.poi.leave()
	await frames(2)
	check_eq(g.left_to, "", "refused: Eli stays")
	check(PoiState.in_visit(g.poi.record) and g.poi.finished.is_empty(), "and the visit goes on")
	s.run.erase("invasion_active")
	var exit: PoiSpot = g.world.spots_of("exit")[0]
	check_eq(exit.interact_prompt(), "[E] Leave location", "the exit (Exp 009: its choice offers home and travelling on)")
	# M: the map, from here
	var t1: float = s.total_minutes
	g.open_map()
	check_eq(g.debug_modal(), "map", "M opens the map at a POI")
	var screen: RegionMapScreen = g.map.screen
	check_eq(screen.origin, "convenience", "the map travels from here")
	check_eq(screen.selected, "convenience", "you are here")
	check(screen.markers.route_world.is_empty(), "no route to where you are")
	screen.select(MapInfo.HOME)
	var go_home: Button = screen._info.find_child("Travel", true, false)
	check(go_home != null and go_home.text == "Go home" and not go_home.disabled, "home is always offered")
	screen.select("library")
	var leg := TravelRules.minutes_between("convenience", "library")
	var foot: Button = screen._info.find_child("OnFoot", true, false)
	check(foot != null and UiTheme.caption_of(foot) == UiTheme.duration_text(leg), "on foot: the time from here (%s)" % (UiTheme.caption_of(foot) if foot != null else "none"))
	var by_car: Button = screen._info.find_child("ByCar", true, false)
	check(by_car != null and by_car.disabled, "the car is at home: walk on")
	check(screen.markers.route_world.size() >= 2, "the road from here is drawn")
	check(screen.request_travel(), "Travel goes on to the Library")
	check(await _wait_until(func(): return g.left_to != "", 60), "leaves")
	check_eq(GameLaunch.site, "library", "to the Library")
	check_eq(str(GameLaunch.carry.get("travel", {}).get("from", "")), "convenience", "from the store")
	check((GameLaunch.carry.get("home", {}) as Dictionary).has("world"), "the home snapshot travels along")
	check_eq(s.region.visits("convenience"), 1, "the store's visit is finished and counted before the next leg")
	check(not PoiState.in_visit(PoiState.record(s, "convenience")), "and closed")
	# the Library
	g = await _next_scene(g)
	s = g.debug_state()
	check(g.site_id() == "library" and g.world is PoiWorld, "at the Library")
	check(absf(s.total_minutes - (t1 + leg)) < 2.0, "the clock moved by the leg's own minutes (%.1f -> %.1f, leg %d)" % [t1, s.total_minutes, leg])
	check_eq(OffscreenHome.events(s).size(), 1, "the ledger came along")
	check(OffscreenHome.is_away(s), "still away")
	check(not g.travel.home_snapshot.is_empty(), "the home snapshot came along")
	check_eq(g.travel.stops(), ["convenience"], "the chain so far")
	check(not g.travel.by_car() and not g.world.has_car, "still on foot")
	for id in got_a:
		check(int(g.poi.pack.get(id, 0)) >= mini(int(got_a[id]), s.inventory.count(id)), "%s from the store still counts in the pack" % id)
	g.debug_kill_enemies()
	await _take_from_a_container(g)
	var carried := s.inventory.counts.duplicate()
	var pack: Dictionary = g.poi.pack.duplicate()
	# save at the second stop, Continue there
	check_eq(g.debug_save(), "", "saving at the second stop")
	g.queue_free()
	await frames(3)
	g = await _boot("continue")
	s = g.debug_state()
	check(not g.is_home() and g.site_id() == "library", "Continue: at the Library")
	check_eq(g.travel.stops(), ["convenience"], "the chain survived the save")
	check_eq(OffscreenHome.events(s).size(), 1, "and the ledger")
	check(not g.travel.home_snapshot.is_empty(), "and the carried home")
	check_eq(g.poi.pack, pack, "and the pack")
	for id in carried:
		check_eq(s.inventory.count(id), int(carried[id]), "%s once after Continue" % id)
	# home, with a short transition
	TravelFlow.skip_animation = false
	var t2: float = s.total_minutes
	g.leave_site()
	check(await _wait_until(func(): return g.map.screen.travelling, 30), "the walk home is shown")
	var dep: Node = g.travel.card
	check(dep != null and is_instance_valid(dep) and str(dep.title_text()) == "Leaving Public Library", "a departure card (%s)" % (dep.title_text() if dep != null and is_instance_valid(dep) else "none"))
	g.map.screen.skip_travel()
	check(await _wait_until(func(): return g.left_to != "", 60), "leaves for home")
	g = await _next_scene(g)
	s = g.debug_state()
	check(g.is_home(), "home")
	var arr: Node = g.travel.card
	check(arr != null and is_instance_valid(arr) and str(arr.title_text()) == "Home" and str(arr.sub_text()).contains("back from Corner Store and Public Library"),
		"an arrival card (%s / %s)" % ([arr.title_text(), arr.sub_text()] if arr != null and is_instance_valid(arr) else ["none", ""]))
	for id in carried:
		check_eq(s.inventory.count(id), int(carried[id]), "%s: both stops' finds came home exactly once" % id)
	for id in s.inventory.counts:
		check(carried.has(id), "%s didn't appear from nowhere" % id)
	check_eq(s.region.visits("convenience"), 1, "the store: one visit")
	check_eq(s.region.visits("library"), 1, "the library: one visit")
	check(absf(s.total_minutes - (t2 + TravelRules.minutes("library"))) < 1.0, "the way home from the library")
	check_eq(int(g.travel.last_report.get("attacks", 0)), 1, "the attack is resolved once, at home")
	check(not OffscreenHome.is_away(s), "the ledger is closed")
	check(GameLaunch.carry.is_empty(), "nothing left in carry")
	await seconds(1.6)
	check(not is_instance_valid(arr), "the card is gone after a moment")


## By car: one can leaving home, one more for the further stop, none home;
## the boot travels along (also through a save at the second stop) and is
## unloaded only at home; the house comes back exactly as Eli left it.
func test_chain_by_car_fuel_and_the_boot() -> void:
	TravelFlow.skip_animation = true
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 9.0 * 60.0
	s.car_repaired = true
	s.inventory.add("fuel", 3 - s.inventory.count("fuel"))
	var stone0 := s.inventory.count("stone")
	var w0: HouseWorld = g.debug_world()
	var wp: Array = w0.weak_points(Vector2(-3, -2))       # a few blows before leaving: the damage must come back as it was
	for k in 3:
		if not wp.is_empty():
			w0.enemy_strike(Vector3(wp[0]["pos"].x, 0.0, wp[0]["pos"].y), wp[0]["target"], 2.0)
	var dmg0: Dictionary = w0.damage_summary()
	check(int(dmg0["missing_voxels"]) > 0 or int(dmg0["damaged_objects"]) > 0, "the house is a little damaged (%s)" % [dmg0])
	var house0 := var_to_str(w0.save_data())
	await g.travel.depart("convenience", true)
	g = await _next_scene(g)
	s = g.debug_state()
	check_eq(s.inventory.count("fuel"), 2, "one can leaving home")
	check(g.world.has_car, "the car at the store")
	g.poi.cargo["stone"] = 4                 # stowed in the boot (the live visit record)
	g.debug_kill_enemies()
	check(await g.travel.travel_on("library", false) != "", "can't walk on and leave the car")
	check_eq(g.left_to, "", "still here")
	check(PoiState.in_visit(g.poi.record) and g.poi.finished.is_empty(), "the visit goes on after a refusal")
	check_eq(await g.travel.travel_on("library", true), "", "drives on")
	check_eq(int((GameLaunch.carry.get("cargo", {}) as Dictionary).get("stone", 0)), 4, "the boot goes along")
	g = await _next_scene(g)
	s = g.debug_state()
	check(g.site_id() == "library", "at the Library")
	check_eq(s.inventory.count("fuel"), 1, "one more can for the further stop")
	check(g.world.has_car and g.travel.by_car(), "the car came along")
	check_eq(int(g.poi.cargo.get("stone", 0)), 4, "with its boot")
	check_eq(s.inventory.count("stone"), stone0, "nothing unloaded on the way")
	g.poi.cargo["nails"] = int(g.poi.cargo.get("nails", 0)) + 6
	# save at the second stop and Continue: the car, the boot and the chain stay
	g.debug_kill_enemies()
	check_eq(g.debug_save(), "", "saving at the second stop")
	g.queue_free()
	await frames(3)
	g = await _boot("continue")
	s = g.debug_state()
	check(g.site_id() == "library" and g.world.has_car and g.travel.by_car(), "Continue: at the Library with the car")
	check_eq(g.travel.stops(), ["convenience"], "the chain")
	check(int(g.poi.cargo.get("stone", 0)) == 4 and int(g.poi.cargo.get("nails", 0)) >= 6, "the boot (%s)" % [g.poi.cargo])
	# the map here: by car only, the boot shown
	g.open_map()
	var screen: RegionMapScreen = g.map.screen
	check(screen.car_here and screen.by_car, "the map knows the car is here")
	screen.select("hardware")
	var foot: Button = screen._info.find_child("OnFoot", true, false)
	check(foot != null and foot.disabled, "on foot is off: the car comes along")
	check(screen.boot_text().contains("stone"), "the boot's contents (%s)" % screen.boot_text())
	# no fuel for another stop; home is still open
	s.inventory.remove("fuel", 1)
	screen.select("hardware")
	check(not screen.request_travel(), "no fuel, no further stop")
	screen.select(MapInfo.HOME)
	check(screen.request_travel(), "home by car is paid")
	check(await _wait_until(func(): return g.left_to != "", 60), "leaves for home")
	g = await _next_scene(g)
	s = g.debug_state()
	check(g.is_home(), "home")
	check_eq(s.inventory.count("fuel"), 0, "no fuel spent on the way home")
	check_eq(int(g.travel.last_cargo.get("stone", 0)), 4, "the store's stone came home in the boot")
	check_eq(int(g.travel.last_cargo.get("nails", 0)), 6, "and the library's nails")
	check_eq(s.inventory.count("stone"), stone0 + 4, "unloaded once, at home")
	check_eq(s.region.visits("convenience") + s.region.visits("library"), 2, "both visits counted")
	check_eq(int(g.travel.last_report.get("attacks", 0)), 0, "nothing came for the house")
	check(var_to_str(g.debug_world().save_data()) == house0, "the house is exactly as Eli left it")
