extends "res://tests/test_case.gd"
## Experiment 003 construction: material costs, stone walls on foundations,
## the foundation piece, iron barricades and reinforced doors, repair by
## material, demolish refunds, the workbench (scrap -> iron) and the palette's
## slots and material variants.


class FakeState extends RefCounted:
	var inventory := Inventory.new()


class FakeGame extends Node:
	var state: Variant
	var toasts := []

	func toast(text: String, kind: String) -> void:
		toasts.append([text, kind])


func _setup(unlimited := false) -> Array:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	var s := GameState.new_run(7)
	s.cheats["unlimited"] = unlimited
	var b := BuildMode.new()
	b.setup(w, s, null, null)
	add(b)
	await physics_frames(2)
	return [w, s, b]


func _give(s: GameState, items: Dictionary) -> void:
	s.inventory.storage_crates = 4
	for k in items:
		s.inventory.add(k, items[k])


func _reason(b: BuildMode, id: String, p: Vector2, from := Vector2.INF) -> String:
	b.select_id(id)
	return b.evaluate(p, from)["reason"]


func test_costs_per_material_are_paid() -> void:
	var setup: Array = await _setup()
	var w: HouseWorld = setup[0]
	var s: GameState = setup[1]
	var b: BuildMode = setup[2]
	_give(s, {"wood": 40, "nails": 60, "stone": 60, "iron": 30, "scrap": 20})
	var expect := {
		"foundation": {"stone": 2}, "stone_wall": {"stone": 6}, "iron_barricade": {"iron": 3, "wood": 1, "nails": 2},
		"iron_door": {"wood": 4, "nails": 6, "iron": 3}, "workbench": {"wood": 5, "nails": 6, "scrap": 2}, "upgrade": {"iron": 2, "nails": 4},
	}
	for id in expect:
		check_eq(BuildPieces.LIST[BuildPieces.index_of(id)]["cost"], expect[id], "%s cost" % id)
	# a 3 m strip of foundation, then 3 m of stone wall on it
	b.select_id("foundation")
	var r := b.evaluate(Vector2(3.8, 11.0), Vector2(1.2, 11.0))
	check_eq(r["segs"].size(), 3, "a dragged foundation strip")
	check_eq(r["cost"], {"stone": 6}, "2 stone per tile")
	var before: Dictionary = s.inventory.to_dict()["counts"].duplicate()
	check(b.apply(Vector2(3.8, 11.0), Vector2(1.2, 11.0)), "foundation laid")
	check_eq(s.inventory.count("stone"), int(before["stone"]) - 6, "6 stone paid")
	b.select_id("stone_wall")
	check(b.apply(Vector2(3.8, 11.0), Vector2(1.2, 11.0)), "stone wall built on it")
	check_eq(s.inventory.count("stone"), int(before["stone"]) - 24, "18 more stone paid")
	check_eq(s.inventory.count("wood"), int(before["wood"]), "no planks for masonry")
	check_eq(w.sections[Vector3i(0, 11, 2)]["material"], "stone", "recorded as a stone section")
	check_eq(w.sections[Vector3i(0, 11, 2)]["strength"], HouseWorld.SECTION_MATERIALS["stone"]["strength"], "with its strength")
	var c := w.grid.cell_of(Vector3(2.5, 1.0, 11.0))
	check(w.grid.get_mat(c.x, c.y, c.z) in [VoxelMat.MASONRY, VoxelMat.MORTAR], "masonry voxels")
	check_eq(w.nav.get_raw(w.nav.cell_of(Vector2(2.5, 11.0))), GridNav.WALL, "navigation closed")
	# iron pieces
	var iron0 := s.inventory.count("iron")
	b.select_id("iron_barricade")
	check(b.apply(Vector2(6.5, 11.0)), "an iron barricade")
	check_eq(s.inventory.count("iron"), iron0 - 3, "3 iron")
	b.select_id("upgrade")
	check(b.apply(Vector2(2.5, 11.1)), "iron plating on the stone wall")
	check_eq(s.inventory.count("iron"), iron0 - 5, "2 iron more")
	check_eq(w.section_strength(Vector3i(0, 11, 2)), HouseWorld.SECTION_MATERIALS["stone"]["strength"] * HouseWorld.PLATED_FACTOR, "plated stone is the strongest")
	b.select_id("upgrade")
	s.inventory.remove("iron", s.inventory.count("iron"))
	check(_reason(b, "upgrade", Vector2(9.5, 9.0)).begins_with("Needs 2 iron"), "plating needs iron (%s)" % _reason(b, "upgrade", Vector2(9.5, 9.0)))


func test_stone_walls_need_a_foundation() -> void:
	var setup: Array = await _setup(true)
	var w: HouseWorld = setup[0]
	var b: BuildMode = setup[2]
	check_eq(_reason(b, "stone_wall", Vector2(0.5, 11.0)), BuildMode.FOUNDATION_REASON, "not on bare ground")
	check_eq(_reason(b, "wall", Vector2(0.5, 11.0)), "", "a wooden wall needs none")
	check(w.is_founded(Vector3i(0, 6, 12)), "the house floor counts as a foundation")
	check(_reason(b, "stone_wall", Vector2(12.5, 6.0)) != BuildMode.FOUNDATION_REASON, "so a stone wall inside needs no foundation")
	check_eq(_reason(b, "foundation", Vector2(0.5, 11.0)), "", "a foundation tile on the lawn")
	b.select_id("foundation")
	check(b.apply(Vector2(0.5, 11.0)), "laid")
	check(w.foundations.has(Vector3i(0, 11, 0)), "recorded")
	check(w.is_founded(Vector3i(0, 11, 0)), "the wall line is founded now")
	check_eq(_reason(b, "stone_wall", Vector2(0.5, 11.0)), "", "a stone wall on it is valid")
	# the foundation is flat: no nav, collision or exit-rule effect
	check(w.nav.is_walkable(w.nav.cell_of(Vector2(0.5, 11.0))), "walkable")
	check(not w.is_blocked(Vector2(0.5, 11.0)), "no collision")
	var c := w.grid.cell_of(Vector3(0.3, -0.05, 11.2))
	check_eq(w.grid.get_mat(c.x, c.y, c.z), VoxelMat.PAVING, "paving voxels flush with the floor")
	# refusals
	check_eq(_reason(b, "foundation", Vector2(0.5, 11.0)), "There's already a floor here.", "twice")
	check_eq(_reason(b, "foundation", Vector2(6.5, 6.0)), "There's already a floor here.", "inside the house")
	check(_reason(b, "foundation", Vector2(-4.4, 5.0)).begins_with("Outside the lot"), "outside the lot")
	b.select_id("wall")
	b.apply(Vector2(2.5, 11.0))
	check_eq(_reason(b, "foundation", Vector2(2.5, 11.0)), "There's a wall in the way.", "not under a wall")


func test_iron_objects_are_stronger_and_cost_iron_to_repair() -> void:
	var setup: Array = await _setup()
	var w: HouseWorld = setup[0]
	var s: GameState = setup[1]
	var b: BuildMode = setup[2]
	_give(s, {"wood": 30, "nails": 60, "iron": 20, "scrap": 10})
	b.select_id("barricade")
	check(b.apply(Vector2(0.5, 11.0)), "a wooden barricade")
	b.select_id("iron_barricade")
	check(b.apply(Vector2(2.5, 11.0)), "an iron barricade")
	var wood: WorldObject = w.object_at(Vector2(0.5, 11.0))
	var iron: WorldObject = w.object_at(Vector2(2.5, 11.0))
	check(wood.mat == "wood" and iron.mat == "iron" and iron.kind == "barricade", "kinds and materials")
	check_eq(iron.max_hp, 30, "iron barricade HP")
	check_eq(iron.display_name(), "Iron barricade", "its name")
	check_eq(w.nav.get_raw(w.nav.cell_of(Vector2(2.5, 11.0))), GridNav.WALL, "an iron barricade is WALL for navigation")
	for k in 12:
		w.enemy_strike(Vector3(0.5, 0, 11.7), Vector2(0.5, 11.0))
		w.enemy_strike(Vector3(2.5, 0, 11.7), Vector2(2.5, 11.0))
	await physics_frames(1)
	check(not w.objects.has(wood), "12 swings break the wooden barricade")
	check(w.objects.has(iron) and iron.hp == 18, "the iron one stands at 18/30")
	for k in 4:
		w.enemy_strike(Vector3(2.5, 0, 11.7), Vector2(2.5, 11.0), 3.0)
	check_eq(iron.hp, 6, "a brute's swing (strength 3) does 3")
	b.select_id("repair")
	var r := b.evaluate(Vector2(2.5, 11.0))
	check_eq(r["cost"], {"iron": 3, "wood": 1, "nails": 2}, "repair costs the iron barricade's materials (80 %% lost)")
	check(b.apply(Vector2(2.5, 11.0)), "repaired")
	check_eq(iron.hp, 30, "full HP")
	# a reinforced door into the house wall
	b.select_id("iron_door")
	check(b.apply(Vector2(14.0, 3.5)), "a reinforced door cut into the kitchen wall")
	var d: WorldObject = w.object_at(Vector2(14.0, 3.5))
	check(d != null and d.kind == "door" and d.mat == "iron" and d.max_hp == 42, "kind door, iron, 42 HP")
	check(d.interact_prompt() == "[E] Open door", "opens like any door")
	w.toggle_door(d)
	await physics_frames(1)
	check(w.nav.is_walkable(w.nav.cell_of(Vector2(14.0, 3.5))), "open: walkable")
	# demolish refunds by material
	var iron_before := s.inventory.count("iron")
	b.select_id("demolish")
	check(b.apply(Vector2(2.5, 11.0)), "iron barricade taken down")
	check_eq(s.inventory.count("iron"), iron_before + 1, "half of 3 iron back")


func test_repair_is_paid_in_the_sections_material() -> void:
	var setup: Array = await _setup()
	var w: HouseWorld = setup[0]
	var s: GameState = setup[1]
	var b: BuildMode = setup[2]
	var segs := [Vector3i(0, 11, 0), Vector3i(0, 11, 1), Vector3i(0, 11, 2)]
	w.build_foundation(segs)
	w.build_walls(segs, "stone")
	w.build_walls([Vector3i(0, 11, 4)])
	w.upgrade_section(Vector3i(0, 11, 4))
	w.explode(Vector3(1.5, 1.0, 11.55), 1.6, 24.0)
	w.explode(Vector3(4.8, 1.0, 11.55), 1.6, 24.0)
	var ms := w.section_missing_by(Vector3i(0, 11, 1))
	check(ms["stone"] > 50 and ms["wood"] == 0, "the stone section misses masonry only (%s)" % ms)
	var mp := w.section_missing_by(Vector3i(0, 11, 4))
	check(mp["iron"] > 0, "the plated section misses plate (%s)" % mp)
	_give(s, {"stone": 40, "iron": 20, "wood": 20, "nails": 40})
	b.select_id("repair")
	var r := b.evaluate(Vector2(1.5, 11.0))
	check_eq(r["cost"], BuildPieces.section_repair_cost_by(ms), "cost by material")
	check(r["cost"].has("stone") and not r["cost"].has("wood"), "stone repairs stone (%s)" % r["cost"])
	var stone0 := s.inventory.count("stone")
	check(b.apply(Vector2(1.5, 11.0)), "repaired")
	check_eq(s.inventory.count("stone"), stone0 - int(r["cost"]["stone"]), "stone paid")
	check_eq(w.section_missing(Vector3i(0, 11, 1)), 0, "masonry restored")
	var rp := b.evaluate(Vector2(4.5, 11.0))
	check(rp["cost"].has("iron"), "plate repairs cost iron (%s)" % rp["cost"])
	check_eq(BuildPieces.section_repair_cost_by({"wood": 300, "stone": 0, "iron": 0}), BuildPieces.section_repair_cost(300), "timber keeps the Experiment 002 rate")


func test_section_load_hint() -> void:
	var setup: Array = await _setup(true)
	var w: HouseWorld = setup[0]
	var house := Vector3i(0, 9, 8)
	check(is_equal_approx(w.section_load_hint(house), 1.0), "an intact house wall on the slab: 1.0 (%.2f)" % w.section_load_hint(house))
	w.build_walls([Vector3i(0, 11, 0)])
	check(is_equal_approx(w.section_load_hint(Vector3i(0, 11, 0)), 0.6 * HouseWorld.UNFOUNDED_LOAD), "an unfounded wooden wall: 0.3")
	w.build_foundation([Vector3i(0, 11, 2)])
	w.build_walls([Vector3i(0, 11, 2)], "stone")
	check(is_equal_approx(w.section_load_hint(Vector3i(0, 11, 2)), 2.5), "a stone wall on a foundation: 2.5")
	w.explode(Vector3(2.5, 1.0, 11.55), 1.6, 24.0)
	var hint := w.section_load_hint(Vector3i(0, 11, 2))
	check(hint < 2.5 and hint > 0.0, "damage lowers it (%.2f)" % hint)
	check_eq(w.section_load_hint(Vector3i(0, 30, 0)), 0.0, "no section: 0")
	var info := w.section_info(Vector3i(0, 11, 2))
	check(info["material"] == "stone" and info["founded"] and is_equal_approx(info["load"], hint), "section_info carries material, foundation and load")


func test_demolish_stone_walls_and_foundations() -> void:
	var setup: Array = await _setup()
	var w: HouseWorld = setup[0]
	var s: GameState = setup[1]
	var b: BuildMode = setup[2]
	_give(s, {"stone": 20})
	b.select_id("foundation")
	check(b.apply(Vector2(0.5, 11.0)), "foundation")
	b.select_id("stone_wall")
	check(b.apply(Vector2(0.5, 11.0)), "stone wall")
	b.select_id("demolish")
	var stone0 := s.inventory.count("stone")
	check(b.apply(Vector2(0.5, 11.0)), "stone wall taken down")
	check_eq(s.inventory.count("stone"), stone0 + 3, "half its 6 stone back")
	check(not w.built.has(Vector3i(0, 11, 0)), "gone")
	check(w.is_founded(Vector3i(0, 11, 0)), "the foundation stays")
	check(b.apply(Vector2(0.5, 11.3)), "then the foundation")
	check_eq(s.inventory.count("stone"), stone0 + 4, "half its 2 stone back")
	check(not w.foundations.has(Vector3i(0, 11, 0)) and not w.is_founded(Vector3i(0, 11, 0)), "taken up")
	# a foundation carrying a stone wall can't go
	w.build_foundation([Vector3i(0, 11, 4)])
	w.build_walls([Vector3i(0, 11, 4)], "stone")
	b.select_id("demolish")
	var r := b.evaluate(Vector2(4.05, 11.45))
	check_eq(r["reason"], "Take the stone wall down first.", "a foundation under a stone wall")


func test_workbench_turns_scrap_into_iron() -> void:
	var fake := FakeState.new()
	fake.inventory.add("scrap", 7)
	var r := Workbench.convert(fake, 1)
	check(r["ok"], "converts with 7 scrap (%s)" % r["text"])
	check_eq(r["iron"], 1, "1 iron")
	check_eq(r["scrap"], 3, "for 3 scrap")
	check_eq(fake.inventory.count("iron"), 1, "iron in the inventory")
	check_eq(fake.inventory.count("scrap"), 4, "scrap left")
	print("    workbench conversion via: ", r["via"])
	r = Workbench.convert(fake, 1)
	check(r["ok"] and fake.inventory.count("scrap") == 1, "a second batch")
	r = Workbench.convert(fake, 1)
	check(not r["ok"] and r["text"].contains("3 scrap"), "not enough scrap: %s" % r["text"])
	fake.inventory.add("scrap", 9)
	fake.inventory.add("iron", 100)
	r = Workbench.convert(fake, 1)
	check(not r["ok"] and r["text"].contains("No room"), "iron at its cap: %s" % r["text"])
	check_eq(r["via"], "fallback", "a stand-in state uses the local rule")
	check(not Workbench.convert(null)["ok"], "no state, no iron")
	# built and used through the real pieces
	var setup: Array = await _setup()
	var w: HouseWorld = setup[0]
	var s: GameState = setup[1]
	var b: BuildMode = setup[2]
	_give(s, {"wood": 10, "nails": 10, "scrap": 8})
	b.select_id("workbench")
	check(b.apply(Vector2(12.0, 6.3)), "a workbench in the utility room")
	check_eq(s.inventory.count("scrap"), 6, "2 scrap paid")
	var bench: WorldObject = w.object_at(Vector2(12.0, 6.3))
	check(bench != null and bench.kind == "workbench", "placed")
	check(w.interactables().has(bench) and bench.interact_prompt().contains("scrap"), "an interactable with a prompt")
	check_eq(w.nav.get_raw(w.nav.cell_of(bench.pos)), GridNav.SOLID, "SOLID for navigation")
	var game := FakeGame.new()
	game.state = s
	add(game)
	bench.interact(game)
	check_eq(s.inventory.count("iron"), 1, "E made 1 iron")
	check_eq(s.inventory.count("scrap"), 3, "from 3 scrap")
	check(not game.toasts.is_empty() and game.toasts[-1][1] == "info", "with a toast (%s)" % str(game.toasts))
	check_eq(Workbench.convert(s, 1)["via"], "Crafting", "a GameState goes through Crafting.convert_scrap")
	check_eq(s.inventory.count("scrap"), 0, "the last 3 scrap")
	bench.interact(game)
	check(game.toasts[-1][1] == "warn" and game.toasts[-1][0].contains("scrap"), "no scrap: Crafting's reason (%s)" % game.toasts[-1][0])
	s.cheats["unlimited"] = true
	var iron := s.inventory.count("iron")
	bench.interact(game)
	check_eq(s.inventory.count("iron"), iron + 1, "the unlimited cheat makes the scrap free (Crafting's rule)")
	s.cheats["unlimited"] = false
	var d := w.save_data()
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(d) and w2.count_objects("workbench") == 1, "the workbench persists")


func test_palette_slots_and_material_variants() -> void:
	var setup: Array = await _setup(true)
	var b: BuildMode = setup[2]
	b.set_active(true)
	await frames(1)
	check_eq(b.palette.slot_labels().size(), 10, "ten building classes")
	b.select_slot(2)
	b.select_slot(0)
	check_eq(b.piece_id(), "wall", "1: walls, wood first")
	b.select_slot(0)
	check_eq(b.piece_id(), "stone_wall", "1 again: stone")
	b.select_slot(0)
	check_eq(b.piece_id(), "wall", "and back to wood")
	b.select_slot(1)
	b.select_slot(1)
	check_eq(b.piece_id(), "iron_barricade", "2, 2: iron barricade")
	b.select_slot(2)
	check_eq(b.piece_id(), "door", "3: door")
	b.select_slot(1)
	check_eq(b.piece_id(), "iron_barricade", "2 remembers the iron variant")
	b.select_slot(9)
	check_eq(b.piece_id(), "foundation", "0: stone foundation")
	b.select_slot(5)
	b.select_slot(5)
	check_eq(b.piece_id(), "workbench", "6, 6: workbench")
	# number keys through the real input handler
	var ev := InputEventKey.new()
	ev.keycode = KEY_7
	ev.pressed = true
	b._unhandled_input(ev)
	check_eq(b.piece_id(), "repair", "key 7: repair (as in Experiment 002)")
	ev.keycode = KEY_2
	b._unhandled_input(ev)
	check_eq(b.piece_id(), "iron_barricade", "key 2: the barricade slot's last variant")
	ev.keycode = KEY_0
	b._unhandled_input(ev)
	check_eq(b.piece_id(), "foundation", "key 0: foundation")
	# Experiment 002 indices still select the same pieces
	for i in 9:
		b.select(i)
		check_eq(b.piece_id(), ["wall", "barricade", "door", "doorway", "crate", "rain_collector", "repair", "upgrade", "demolish"][i], "index %d unchanged" % i)
