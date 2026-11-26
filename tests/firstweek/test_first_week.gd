extends "res://tests/test_case.gd"
## Experiment 008 (lead): the first-week loop, end to end, through the real
## game scene and the player's own actions where practical (E on the nearest
## thing, the map's Travel button, the exits). Headless; the travel animation
## is shown for a moment, then skipped.
##
## Core loop (the user's §1): new game -> equip -> pick a place on the map ->
## travel visibly -> the POI -> search and take -> enemies (unaware at first)
## -> leave by an exit -> home with exactly that -> use it -> sleep into the
## next day -> save and Continue.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_first_week.dat"
const TravelFlow := preload("res://src/travel/travel_flow.gd")


func _boot(mode: String) -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 8008
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


## Stands Eli in front of a spot (where the player would stand to use it).
func _stand_at(g: Node, sp: PoiSpot) -> void:
	var at: Vector2 = sp.plan_pos() + sp.front * 0.75 if sp.front != Vector2.ZERO else sp.plan_pos() + Vector2(0, 0.7)
	g.debug_teleport_player(at)
	await physics_frames(2)
	await frames(2)


## Presses E the way the player does and lets a timed action run in real frames.
func _press_e_and_wait(g: Node) -> void:
	g.debug_interact()
	await _wait_until(func(): return g.poi._action.is_empty(), 600)
	await frames(2)


func _total(s: GameState) -> Dictionary:
	return s.inventory.counts.duplicate()


func test_the_core_loop_food_trip_and_back() -> void:
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 8.0 * 60.0
	# 2. equipment: a crowbar from the garage (as found on day one) on the tool slot
	s.inventory.add("crowbar", 1)
	check_eq(s.equip("crowbar"), "", "the crowbar is equipped")
	var start := _total(s)
	# 3. the map: pick the Corner Store
	g.debug_open("map")
	check_eq(g.debug_modal(), "map", "the map is open")
	var screen: RegionMapScreen = g.map.screen
	screen.select("convenience")
	check(screen.request_travel(), "Travel is offered")
	# 4. travel, visibly
	await frames(15)
	check(screen.travelling, "the map animates the trip")
	screen.skip_travel()
	check(await _wait_until(func(): return g.left_to != "", 90), "the scene changes after the trip")
	# 5. the POI
	g = await _next_scene(g)
	s = g.debug_state()
	check(not g.is_home() and g.site_id() == "convenience", "at the Corner Store")
	check_eq(s.equipped("tool"), "crowbar", "still holding the crowbar")
	for id in start:
		check_eq(s.inventory.count(id), int(start[id]), "%s came along unchanged" % id)
	# 7. anyone here starts unaware
	for w in g.poi.watch:
		check(str(w["state"]) != "hunt", "an enemy here doesn't know Eli yet (%s)" % w["state"])
	# 6. search a shelf with E, in real frames
	var shelf: PoiSpot = null
	for sp in g.world.spots_of("container"):
		if str(sp.data.get("needs", "")) == "" and not bool(sp.data.get("picked", false)) and not (g.poi.record["c"][sp.id]["items"] as Dictionary).is_empty():
			shelf = sp
			break
	if not check(shelf != null, "a shelf with something on it"):
		return
	var shelf_id := shelf.id
	await _stand_at(g, shelf)
	check(g.debug_prompt().begins_with("[E] Search the"), "the prompt offers the search (%s)" % g.debug_prompt())
	var t0 := s.total_minutes
	await _press_e_and_wait(g)
	check(g.poi.panel.is_open, "the take-only panel opens")
	check(s.total_minutes > t0 + 3.0, "searching took game time (%.1f min)" % (s.total_minutes - t0))
	var got: Dictionary = g.poi.panel.take_everything()
	g.poi.close_panel()
	await frames(2)
	check(not got.is_empty(), "something taken (%s)" % [got])
	# the locked stockroom: force it with the crowbar, then search inside
	var door: PoiDoor = g.world.door("stockroom")
	if check(door != null and door.locked, "the stockroom is locked"):
		g.debug_teleport_player(Vector2(door.position.x, door.position.z + 0.8))
		await physics_frames(2)
		await frames(2)
		check(g.debug_prompt().contains("Force"), "E would force the door (%s)" % g.debug_prompt())
		await _press_e_and_wait(g)
		check(not door.locked, "the crowbar opened it")
	var carried := _total(s)
	# 8. leave through an exit with E
	TravelFlow.skip_animation = true
	var exit: PoiSpot = g.world.spots_of("exit")[0]
	g.debug_teleport_player(exit.plan_pos())
	await physics_frames(2)
	await frames(2)
	check(g.debug_prompt().contains("Leave"), "the exit's prompt (%s)" % g.debug_prompt())
	g.debug_interact()
	check(await _wait_until(func(): return g.left_to != "", 60), "leaves")
	# 9.-10. home with exactly what was carried
	g = await _next_scene(g)
	s = g.debug_state()
	check(g.is_home(), "home")
	for id in carried:
		check_eq(s.inventory.count(id), int(carried[id]), "%s: home with exactly what was carried" % id)
	for id in s.inventory.counts:
		check(carried.has(id), "%s didn't appear from nowhere" % id)
	# 11. use it: eat, and build a barricade from the planks and nails (no cheats)
	var hunger0 := s.hunger
	var food := "canned_food" if s.inventory.count("canned_food") > 0 else "snacks"
	check(s.use_item(food) != "" or s.hunger > hunger0, "ate %s" % food)
	check(s.hunger > hunger0, "less hungry (%.0f -> %.0f)" % [hunger0, s.hunger])
	var wood0 := s.inventory.count("wood")
	g.build.set_active(true)
	await frames(2)
	g.build.select_id("crate")
	var built: bool = g.build.apply(Vector2(11.25, 11.75))
	check(built, "a crate built from what Eli has (%s)" % str(g.build.last_eval.get("reason", "")))
	check(s.inventory.count("wood") < wood0, "paid in planks (%d -> %d)" % [wood0, s.inventory.count("wood")])
	g.build.set_active(false)
	await frames(2)
	# 12. sleep into the next day
	var day0 := s.day()
	s.total_minutes = float(day0 - 1) * 1440.0 + 22.5 * 60.0
	s.energy = 40.0
	var plan: Dictionary = await g.debug_sleep(-1.0)
	check(not plan.is_empty(), "slept (%s)" % [plan])
	check(s.day() == day0 + 1 or bool(plan.get("interrupted", false)), "the next day (day %d -> %d, %s)" % [day0, s.day(), plan.get("reason", "")])
	# 13. save and Continue
	var crates: int = g.debug_world().count_objects("crate")
	var saved := _total(s)
	var day1 := s.day()
	check_eq(g.debug_save(), "", "saving is allowed")
	g.queue_free()
	await frames(3)
	g = await _boot("continue")
	s = g.debug_state()
	check(g.is_home(), "Continue: home")
	check_eq(s.day(), day1, "the same day")
	check_eq(g.debug_world().count_objects("crate"), crates, "the crate is still there")
	for id in saved:
		check_eq(s.inventory.count(id), int(saved[id]), "%s survived the save" % id)
	check_eq(s.region.visits("convenience"), 1, "the visit is remembered")
	var rec: Dictionary = s.region.poi.get("convenience", {})
	check(not rec.is_empty() and bool((rec.get("c", {}) as Dictionary).get(shelf_id, {}).get("searched", false)), "the searched shelf is remembered")


## A save at the POI after taking things, then Continue: nothing doubles,
## nothing goes missing, the shelf stays searched (the user's §10).
func test_save_at_the_poi_never_duplicates_loot() -> void:
	TravelFlow.skip_animation = true
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 9.0 * 60.0
	await g.travel.depart("convenience")
	g = await _next_scene(g)
	s = g.debug_state()
	g.debug_kill_enemies()
	var shelf: PoiSpot = null
	for sp in g.world.spots_of("container"):
		if str(sp.data.get("needs", "")) == "" and not (g.poi.record["c"][sp.id]["items"] as Dictionary).is_empty():
			shelf = sp
			break
	if not check(shelf != null, "a shelf with something"):
		return
	var shelf_id := shelf.id
	await _stand_at(g, shelf)
	await _press_e_and_wait(g)
	var got: Dictionary = g.poi.panel.take_everything()
	g.poi.close_panel()
	await frames(2)
	var have := _total(s)
	var pack: Dictionary = g.poi.pack.duplicate()
	check_eq(g.debug_save(), "", "saving at the POI")
	g.queue_free()
	await frames(3)
	g = await _boot("continue")
	s = g.debug_state()
	check(not g.is_home() and g.site_id() == "convenience", "Continue at the store")
	for id in have:
		check_eq(s.inventory.count(id), int(have[id]), "%s once" % id)
	check_eq(g.poi.pack, pack, "the pack record came back")
	var box: Dictionary = g.poi.record["c"][shelf_id]
	check(bool(box["searched"]), "the shelf is still searched")
	for id in got:
		check_eq(int((box["items"] as Dictionary).get(id, 0)), 0, "%s isn't back on the shelf" % id)
	# and home: the same once more
	g.leave_site()
	check(await _wait_until(func(): return g.left_to != "", 60), "leaves")
	g = await _next_scene(g)
	s = g.debug_state()
	for id in have:
		check_eq(s.inventory.count(id), int(have[id]), "%s once at home" % id)


## Scenario C: research and building. A manual from the library comes home,
## is read, and the piece it unlocks is no longer locked in the build menu;
## planks and nails from the trip pay for a barricade.
func test_scenario_c_a_book_comes_home_and_unlocks_building() -> void:
	TravelFlow.skip_animation = true
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 9.0 * 60.0
	s.inventory.add("crowbar", 1)
	s.inventory.add("flashlight", 1)
	s.equip("crowbar")
	s.equip("flashlight")
	await g.travel.depart("library")
	g = await _next_scene(g)
	s = g.debug_state()
	g.debug_kill_enemies()
	# open what's locked, then search every container until a manual turns up
	for d in g.world.objects:
		if d is PoiDoor and d.locked:
			d.locked = false
	var book := ""
	for sp in g.world.spots_of("container"):
		var items: Dictionary = g.poi.record["c"][sp.id]["items"]
		for id in items:
			if str(id).begins_with("book_") and book == "" and Research.prerequisites(Research.book_skill(str(id))).all(func(p): return Research.knows(s, p)):
				book = str(id)          # one Eli can read now (an advanced manual waits for its prerequisite)
		if book != "":
			await _stand_at(g, sp)
			if str(sp.data.get("needs", "")) == "crowbar":
				g.poi.record["forced"][sp.id] = true
			await _press_e_and_wait(g)
			check(g.poi.panel.is_open, "the %s opens" % sp.label())
			check(g.poi.panel.take(book, 1) == 1, "took %s" % book)
			g.poi.close_panel()
			await frames(2)
			break
	if book == "":
		skip("no manual at all at the library in this run (about 1 first visit in 11)")
		return
	if not check(s.inventory.count(book) == 1, "a manual found at the library (%s)" % book):
		return
	g.leave_site()
	check(await _wait_until(func(): return g.left_to != "", 60), "leaves")
	g = await _next_scene(g)
	s = g.debug_state()
	check_eq(s.inventory.count(book), 1, "the manual came home")
	var skill := Research.book_skill(book)
	var gated := []
	for piece in Research.GATES:
		if str(Research.GATES[piece]) == skill:
			gated.append(piece)
	var r := Research.read_book(s, book)
	check(bool(r["ok"]), "read it: %s" % r["text"])
	check(Research.knows(s, skill), "%s is learned" % skill)
	g.build.set_active(true)
	await frames(2)
	for piece in gated:
		g.build.select_id(piece)
		var ev: Dictionary = g.build.evaluate(Vector2(2.5, 11.0))
		check(not bool(ev.get("locked", false)), "%s is no longer locked (%s)" % [piece, ev.get("reason", "")])
	g.build.select_id("crate")
	check(g.build.apply(Vector2(11.25, 11.75)), "and planks and nails still build (%s)" % str(g.build.last_eval.get("reason", "")))
	g.build.set_active(false)


## Scenario D: a night at home. The first invasion night with a loaded
## turret by the front door: enemies come, the turret spends real rounds,
## the house takes what it takes, nothing is left broken in the save; then
## an ordinary night's sleep into the morning.
func test_scenario_d_a_night_of_defence() -> void:
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.cheats["invulnerable"] = true          # Eli stands in the yard to watch; he isn't the test
	g.security.dev_unlock()
	g.debug_teleport_player(Vector2(7.0, 10.6))
	g.player.rig.rotation.y = 0.0            # facing the fog to the south (+z is toward the camera)
	await physics_frames(2)
	check(g.security.dev_place_turret().contains("placed"), "a loaded turret by the front path")
	var t: WorldObject = g.security._nearest("turret_mount")
	var rounds0 := Security.box_total(t) + Security.mag(t)
	g.debug_teleport_player(Vector2(7.0, 6.0))   # Eli goes inside
	await physics_frames(2)
	g.debug_set_spawn_gap(Vector2(0.6, 1.2))
	g.dev_trigger_invasion()
	check(g.debug_director().active, "the invasion starts")
	var seen := 0
	for i in 3600:
		await frames(1)
		seen = maxi(seen, g.debug_living_enemies())
		if i > 120 and not g.debug_director().active and g.debug_living_enemies() == 0:
			break
	var rounds1 := Security.box_total(t) + Security.mag(t)
	print("D: enemies at once %d, turret rounds %d -> %d, director %s, living %d, damage %s" % [seen, rounds0, rounds1,
		g.debug_director().active, g.debug_living_enemies(), g.debug_world().damage_summary()])
	check(seen > 0, "enemies came (%d at once)" % seen)
	check(rounds1 < rounds0, "the turret spent real rounds (%d -> %d)" % [rounds0, rounds1])
	if g.debug_living_enemies() > 0:
		g.debug_kill_enemies()
		await frames(5)
	# an ordinary night's sleep after it
	s.cheats["invulnerable"] = false
	s.energy = 30.0
	var day0 := s.day()
	if s.minute_of_day() < 20.0 * 60.0 and s.minute_of_day() > 6.0 * 60.0:
		s.total_minutes = float(day0 - 1) * 1440.0 + 22.5 * 60.0
	var plan: Dictionary = await g.debug_sleep(-1.0)
	print("D: sleep ", plan, " day ", day0, " -> ", s.day(), " ", s.clock_text())
	check(not plan.is_empty(), "Eli sleeps after the fight (%s)" % [plan])
	check(not s.dead, "and lives")
	check_eq(g.debug_save(), "", "the morning saves")


## Scenario B: an equipment trip. Pike's Guns by car; ammunition (and a gun
## when one is there) from the shop and its back room; home: the inventory
## and the equipment hold exactly that, a found shotgun is ready on the bar.
func test_scenario_b_ammunition_from_pikes_guns() -> void:
	TravelFlow.skip_animation = true
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 8.5 * 60.0
	s.car_repaired = true
	s.inventory.add("fuel", 2)
	s.inventory.add("crowbar", 1)
	s.inventory.add("flashlight", 1)
	s.equip("crowbar")
	s.equip("flashlight")
	g.state.region.discover("gun_shop")
	check_eq(await g.travel.depart("gun_shop", true), "", "sets out by car")
	g = await _next_scene(g)
	s = g.debug_state()
	check(not g.is_home() and g.site_id() == "gun_shop", "at Pike's Guns")
	g.debug_kill_enemies()
	for d in g.world.objects:
		if d is PoiDoor and d.locked:
			d.locked = false                # forcing doors is covered by the core loop
	var ammo0 := s.inventory.count("ammo") + s.inventory.count("shells")
	var weapons := {}
	for sp in g.world.spots_of("container"):
		var box: Dictionary = g.poi.record["c"][sp.id]
		var items: Dictionary = box["items"]
		if items.is_empty() or bool(box["searched"]):
			continue
		var wanted := false
		for id in items:
			wanted = wanted or Items.category(str(id)) in ["ammo", "weapon"]
		if not wanted:
			continue
		await _stand_at(g, sp)
		if str(sp.data.get("needs", "")) == "crowbar":
			g.poi.record["forced"][sp.id] = true
		await _press_e_and_wait(g)
		if not g.poi.panel.is_open:
			continue
		for id in (g.poi.record["c"][sp.id]["items"] as Dictionary).duplicate():
			if Items.category(str(id)) in ["ammo", "weapon"]:
				var n := int(g.poi.record["c"][sp.id]["items"][id])
				var k: int = g.poi.panel.take(str(id), n)
				if Items.category(str(id)) == "weapon" and k > 0:
					weapons[str(id)] = k
		g.poi.close_panel()
		await frames(2)
	var ammo1 := s.inventory.count("ammo") + s.inventory.count("shells")
	check(ammo1 > ammo0, "ammunition found (%d -> %d), weapons %s" % [ammo0, ammo1, weapons])
	var carried := _total(s)
	g.leave_site()
	check(await _wait_until(func(): return g.left_to != "", 60), "drives home")
	g = await _next_scene(g)
	s = g.debug_state()
	for id in carried:
		check_eq(s.inventory.count(id), int(carried[id]), "%s home exactly" % id)
	check_eq(s.equipped("tool"), "crowbar", "the crowbar is still in hand")
	check_eq(s.inventory.count("fuel"), 1, "one can for the round trip")
	if weapons.has("shotgun"):
		check(Hotbar.slot_of(s.hotbar, "shotgun") >= 0, "the shotgun is ready on the quick bar")
