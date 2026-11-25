extends "res://tests/test_case.gd"
## Exp 006 (B): the house supply (pool + storage furniture: exact, atomic
## payments, refund overflow), walling up windows (a real wall: rooms, support,
## plating, save), timber footings and the foundation rules, the TV and radio
## rules (one per room, a house-wide cap, mood), and one smoke run in the real
## game (the house TV, comfort and mood, F10 House & balance, the save).


class FakeWorld extends RefCounted:
	var list := []

	func containers() -> Array:
		return list


func _world() -> HouseWorld:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	await physics_frames(2)
	return w


func _empty_run() -> GameState:
	var s := GameState.new_run(11)
	for k in ["wood", "nails", "stone", "iron", "scrap"]:
		s.inventory.remove(k, s.inventory.count(k))
	return s


func test_supply_pays_the_pool_first_then_storage_exactly() -> void:
	var s := _empty_run()
	s.inventory.add("wood", 5)
	s.inventory.add("nails", 1)
	var fw := FakeWorld.new()
	var chest := {"wood": 10, "nails": 3}
	var shelf := {"nails": 4}
	var pile := {"wood": 100}
	fw.list = [{"id": "a", "type": "storage_chest", "items": chest}, {"id": "p", "type": "loot_pile", "items": pile},
		{"id": "b", "type": "shelves", "items": shelf}]
	var sup := HouseSupply.new(s, func(): return [fw])
	check_eq(sup.available("wood"), 15, "carried 5 + stored 10 (the loot pile doesn't count)")
	check_eq(sup.count_text("nails"), "1 + 7 stored", "the menu's combined count")
	check(not sup.can_pay({"wood": 16}), "16 planks are more than the house has")
	# a failed payment takes nothing
	check(not sup.pay({"wood": 12, "nails": 99}), "a cost the house can't cover fails")
	check(s.inventory.count("wood") == 5 and s.inventory.count("nails") == 1 and chest == {"wood": 10, "nails": 3} and shelf == {"nails": 4},
		"and nothing was taken")
	# a mixed payment takes the exact amounts: the pool first, then the containers in order
	check(sup.pay({"wood": 12, "nails": 6}), "12 planks and 6 nails paid")
	check_eq(s.inventory.count("wood"), 0, "all 5 carried planks first")
	check_eq(s.inventory.count("nails"), 0, "the carried nail first")
	check_eq(chest, {"wood": 3}, "7 planks and all 3 nails from the chest")
	check_eq(shelf, {"nails": 2}, "the last 2 nails from the shelf")
	check_eq(pile, {"wood": 100}, "the loot pile is never touched")
	check_eq(sup.last_paid, {"inventory": {"wood": 5, "nails": 1}, "stored": {"wood": 7, "nails": 5}}, "what came from where")
	# refunds: the pool up to its cap, the rest into a container that takes it
	s.inventory.add("wood", 1000)
	var room := FurnitureStorage.space_left("storage_chest", chest)
	var g := sup.give({"wood": 4})
	check(g["inv"].is_empty() and g["stored"] == {"wood": 4}, "a full pool sends the refund into storage (%s)" % str(g))
	check_eq(int(chest["wood"]), 7, "into the chest")
	check_eq(FurnitureStorage.space_left("storage_chest", chest), room - 4, "taking its space")
	s.cheats["unlimited"] = true
	check(sup.pay({"wood": 500}) and int(chest["wood"]) == 7, "the unlimited cheat pays nothing")


func test_build_mode_builds_from_house_storage() -> void:
	var w := await _world()
	var s := _empty_run()
	s.inventory.add("hammer", 1)
	var b := BuildMode.new()
	b.setup(w, s, null, null)
	add(b)
	await physics_frames(1)
	var chest := w.place_object("storage_chest", Vector2(-2.5, 10.5), 0, true)
	chest.items["wood"] = 3
	s.inventory.add("wood", 2)
	s.inventory.add("nails", 6)
	b.select_id("wall")
	check(not b.evaluate(Vector2(-1.5, 11.0))["ok"], "without the supply the carried 2 planks aren't enough")
	b.supply = HouseSupply.new(s, func(): return [w])
	var shelf_nails := int(w.storage_of("shelves").get("nails", 0))
	check(b.evaluate(Vector2(-1.5, 11.0))["ok"], "with the house's storage they are (%s)" % b.evaluate(Vector2(-1.5, 11.0))["reason"])
	check_eq(b.available("wood"), 5, "available = carried + stored")
	check(b.apply(Vector2(-1.5, 11.0)), "the wall goes up")
	check(w.built.has(Vector3i(0, 11, -2)), "built")
	check_eq(s.inventory.count("wood"), 0, "the carried planks went first")
	check_eq(int(chest.items.get("wood", 0)), 1, "then exactly 2 from the chest")
	check_eq(s.inventory.count("nails"), 0, "6 carried nails")
	check_eq(int(w.storage_of("shelves").get("nails", 0)), shelf_nails, "no nails from the shelf")
	# demolish: the refund goes back to the pool
	b.select_id("demolish")
	check(b.apply(Vector2(-1.5, 11.0)), "taken down")
	check(s.inventory.count("wood") == 4 and s.inventory.count("nails") == 6, "the full cost back into the pool")


func test_window_becomes_a_real_wall() -> void:
	var w := await _world()
	var s := Vector3i(0, 0, 1)            # the bedroom window, north wall 1..3 m
	var segs := WindowFill.window_segments(w, s)
	check_eq(segs, [Vector3i(0, 0, 1), Vector3i(0, 0, 2)], "the whole 2 m window")
	var wins := HouseRooms.windows(w, 0).size()
	var before := int(w.sections[s]["design"])
	check(w.section_info(s)["glass"], "glass before")
	var b := BuildMode.new()
	var st := _empty_run()
	st.cheats["unlimited"] = true
	var R = load("res://src/research/research.gd") if ResourceLoader.exists("res://src/research/research.gd") else null
	if R != null:
		R.learn_all(st)          # Exp 006 (R): iron plating is gated
	b.setup(w, st, null, null)
	add(b)
	await physics_frames(1)
	b.select_id("remove_window")
	var r := b.evaluate(Vector2(1.5, 0.0))
	check(r["ok"] and r["segs"].size() == 2, "Remove window aims at it (%s)" % r["reason"])
	check_eq(r["cost"], BuildPieces.times(BuildPieces.WINDOW_FILL_COST, 2), "a wall's cost per metre")
	check_eq(r["refund"], BuildPieces.times(BuildPieces.WINDOW_FRAME_SALVAGE, 2), "the frame's salvage per metre")
	check(b.apply(Vector2(1.5, 0.0)), "walled up")
	for q in segs:
		var info := w.section_info(q)
		check(not info["glass"] and info["wall"] and info["coverage"] > 0.95, "%s is solid wall" % str(q))
		check(w.section_missing(q) == 0, "%s is whole (design = current)" % str(q))
		check(HouseSupport.section_bears(w, q), "%s carries load" % str(q))
	check(int(w.sections[s]["design"]) > before, "more wall than the window had (%d > %d)" % [int(w.sections[s]["design"]), before])
	check_eq(HouseRooms.windows(w, 0).size(), wins - 1, "rooms no longer list it")
	var c := w.nav.cell_of(Vector2(1.5, 0.0))
	check(not w.nav.is_walkable(c), "it blocks passage")
	b.select_id("upgrade")
	check(b.evaluate(Vector2(1.5, 0.0))["ok"], "it can be plated (%s)" % b.evaluate(Vector2(1.5, 0.0))["reason"])
	b.select_id("demolish")
	var d := b.evaluate(Vector2(1.5, 0.0))
	check(d["ok"] and d.get("opening", false) and not d.get("window", false), "Demolish knocks it out as a wall section")
	b.select_id("remove_window")
	check(not b.evaluate(Vector2(1.5, 0.0))["ok"], "no window there any more")
	# boards must come down first
	w.place_object("boards", HouseWorld.seg_center(Vector3i(0, 0, 10)), w.seg_rot(Vector3i(0, 0, 10)), true)
	check(b.evaluate(Vector2(10.5, 0.0))["reason"].contains("boards"), "a boarded window: boards first")
	# saved and restored through the voxel diffs
	var data := w.save_data()
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(data), "loads")
	await physics_frames(1)
	check(not WindowFill.is_window(w2, s) and w2.section_info(s)["wall"], "still a wall after loading")
	check_eq(HouseRooms.windows(w2, 0).size(), wins - 1, "and still not a window")


func test_upper_storey_window_walls_up() -> void:
	var u := LevelWorld.new()
	u.configure(1, null)
	add(u)
	u.build_new()
	await physics_frames(1)
	var s: Vector3i = LevelWorld.UPPER_WINDOWS[0]
	var segs := WindowFill.window_segments(u, s)
	check(not segs.is_empty(), "an upstairs window")
	check_eq(WindowFill.block_reason(u, segs), "", "it can be walled up")
	WindowFill.fill(u, segs)
	check(not WindowFill.is_window(u, s) and u.section_info(s)["wall"], "upstairs it becomes siding and gypsum too")
	check(HouseSupport.section_bears(u, s), "and carries")


func test_timber_footing_and_the_foundation_rules() -> void:
	var w := await _world()
	# a timber footing: wooden walls on it are founded, stone walls are not
	var t := Vector3i(0, 11, 2)
	w.build_foundation([t], "wood")
	check(w.foundations.has(t) and w.timber.has(t) and w.foundation_material(t) == "wood", "a timber footing tile")
	check(w.is_founded(t) and not w.is_stone_founded(t), "founded for wood, not for stone")
	var b := BuildMode.new()
	var st := _empty_run()
	st.cheats["unlimited"] = true
	b.setup(w, st, null, null)
	add(b)
	await physics_frames(1)
	b.select_id("stone_wall")
	check_eq(b.evaluate(Vector2(2.5, 11.0))["reason"], BuildMode.FOUNDATION_REASON, "no stone wall on timber")
	b.select_id("wall")
	check(b.apply(Vector2(2.5, 11.0)), "a wooden wall on the footing")
	check(not w.on_bare_ground(t), "it stands on a footing")
	check(b.apply(Vector2(5.5, 11.0)), "a wooden wall on bare ground")
	check(w.on_bare_ground(Vector3i(0, 11, 5)), "that one stands on bare ground (blows bite deeper)")
	check(not w.on_bare_ground(Vector3i(0, 0, 4)), "the house's own walls are founded")
	b.select_id("timber_footing")
	check(b.apply(Vector2(8.5, 11.0)), "Timber footing through build mode")
	check(w.timber.has(Vector3i(0, 11, 8)), "laid as timber")
	b.select_id("demolish")
	var d := b.evaluate(Vector2(8.5, 11.2))
	check(d.get("foundation", false) and d["refund"] == BuildPieces.TIMBER_FOOTING_COST, "demolish refunds a footing's cost (%s)" % str(d))
	# saved
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(w.save_data()), "loads")
	check(w2.timber.has(t) and not w2.is_stone_founded(t), "the footing stays timber")
	# support: outside the house only founded walls prop the roof
	var sup: HouseSupport = w.support
	for k in [3, 4, 5]:
		w.cut_opening(Vector3i(0, 0, k), true)
	check(not sup.line_bears(w, "north", 4), "a knocked-out north wall bears nothing")
	w.build_walls([Vector3i(0, -1, 3), Vector3i(0, -1, 4), Vector3i(0, -1, 5)])
	check(not sup.line_bears(w, "north", 4), "a wall 1 m outside on bare ground doesn't prop it")
	w.demolish_wall(Vector3i(0, -1, 3))
	w.demolish_wall(Vector3i(0, -1, 4))
	w.demolish_wall(Vector3i(0, -1, 5))
	w.build_foundation([Vector3i(0, -1, 3), Vector3i(0, -1, 4), Vector3i(0, -1, 5)])
	w.build_walls([Vector3i(0, -1, 3), Vector3i(0, -1, 4), Vector3i(0, -1, 5)])
	check(sup.line_bears(w, "north", 4), "the same wall on a foundation does")
	check(sup.is_bearing(w, Vector3i(0, -1, 4)), "and Demolish warns about it")
	# a third level needs a stone footing along each outer wall
	var w3 := await _world()
	check(HouseSupport.footing_reason(w3).contains("north, south, west, east"), "no footing yet: %s" % HouseSupport.footing_reason(w3))
	w3.build_foundation([Vector3i(0, -1, 2), Vector3i(0, -1, 3), Vector3i(0, 10, 2), Vector3i(0, 10, 3), Vector3i(1, -1, 2), Vector3i(1, -1, 3)])
	check_eq(HouseSupport.footing_missing(w3), ["east"], "only the east side is missing")
	w3.build_foundation([Vector3i(1, 15, 2), Vector3i(1, 15, 3)], "wood")
	check_eq(HouseSupport.footing_missing(w3), ["east"], "timber doesn't count as a stone footing")
	w3.build_foundation([Vector3i(1, 15, 5), Vector3i(1, 15, 6)])
	check_eq(HouseSupport.footing_reason(w3), "", "a stone footing all round")


func test_media_rules_cap_and_mood() -> void:
	check_eq(HouseMedia.room_bonuses([["radio"], ["tv_stand", "tv_stand"], ["tv_stand"], ["radio", "tv_stand"]]), ["", "tv_stand", "tv_stand", ""],
		"one source per room, two rooms in the house (the TVs first)")
	check_eq(HouseMedia.room_bonuses([["radio"], []]), ["radio", ""], "a radio alone counts")
	var base := HomeComfort.evaluate({"area": 12.0, "items": [{"type": "sofa"}], "light": "day", "windows": {"intact": 1}})
	var tv := HomeComfort.evaluate({"area": 12.0, "items": [{"type": "sofa"}], "light": "day", "windows": {"intact": 1}, "media": "tv_stand"})
	check(is_equal_approx(float(tv["comfort"]) - float(base["comfort"]), HouseMedia.comfort_of("tv_stand")), "the TV adds its comfort")
	var s := GameState.new_run(5)
	var m0 := Mood.target(s, {"house": 14.0})
	var m1 := Mood.target(s, {"house": 14.0, "media": "tv_stand"})
	check(is_equal_approx(float(m1["target"]) - float(m0["target"]), HouseMedia.mood_of("tv_stand")), "watching TV lifts the mood target")
	check(HouseMedia.mood_of("tv_stand") <= HouseMedia.MOOD_CAP and HouseMedia.mood_of("radio") < HouseMedia.mood_of("tv_stand"), "modest and capped")
	check(m1["causes"].any(func(c): return c[0] == "Watching TV"), "shown as a cause")


# --- the real game ----------------------------------------------------------------------------

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_house_balance_exp006.save"


func _boot() -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = "new"
	GameLaunch.seed = 6006
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	return g


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()


func test_game_tv_supply_and_f10() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	check(g.balance != null and g.build.supply is HouseSupply, "the balance helper hands build mode the house supply")
	# the house's TV
	g.debug_teleport_player(Vector2(4.5, 5.2))
	await frames(2)
	check_eq(g.debug_prompt(), "[E] Turn the TV on", "E at the house TV")
	g.debug_interact()
	await frames(1)
	check(g.balance.playing_sources().size() == 1, "it plays (the mains are on)")
	check(s.run.get("media", {}).get("tv_stand", false) == true, "saved in the run")
	check(g.balance._fx.size() == 1, "the screen glows")
	g.comfort.recompute()
	await frames(1)
	var room: Dictionary = g.comfort.player_room()
	check(room.get("factors", []).any(func(f): return f[0] == "The TV on"), "the living room counts it (%s)" % str(room.get("factors", [])))
	check_eq(g.comfort._mood_inputs()["media"], "tv_stand", "Eli is watching")
	check_eq(g.debug_prompt(), "[E] Turn the TV off", "and can switch it off")
	# F10
	g.debug_open("dev")
	var dm: Node = g.debug_ui().dev_menu
	for label in ["Aurora: old / subtle", "Remove window here", "TV / radio on/off", "Foundation kit", "Fill a chest", "Spawn runner"]:
		check(dm.button(label) != null, "F10 has '%s'" % label)
	g.ui.dev_menu.toggle()
	await frames(1)
	check(str(g.balance.dev_fill_chest()).contains("+"), "a chest filled with materials")
	check(g.balance.supply.stored("wood") >= 10, "the supply sees the stored planks")
	check(str(g.balance.dev_aurora_preview()).contains("100"), "the aurora preview shows the old look")
	check(str(g.balance.dev_spawn("runner")).begins_with("Runner"), "spawn a runner")
	g.debug_teleport_player(Vector2(1.5, 1.0))
	await frames(1)
	check(str(g.balance.dev_remove_window()).begins_with("Walled up"), "remove the window here")
	check(not WindowFill.is_window(g.world, Vector3i(0, 0, 1)), "the bedroom window is wall now")
