extends "res://tests/test_case.gd"
## BuildMode: placement validity and refusal reasons, the exit rule, costs and
## the unlimited cheat, repair, upgrade (metal sheathing), demolish refunds,
## doors and doorways.


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


func _reason(b: BuildMode, id: String, p: Vector2, from := Vector2.INF) -> String:
	b.select_id(id)
	return b.evaluate(p, from)["reason"]


func test_placement_validity_and_refusal_reasons() -> void:
	var setup: Array = await _setup()
	var w: HouseWorld = setup[0]
	var b: BuildMode = setup[2]
	check_eq(_reason(b, "wall", Vector2(0.5, 11.0)), "", "a wall segment in the open yard is valid")
	check(_reason(b, "wall", Vector2(-4.9, 5.0)).begins_with("Outside the lot"), "outside the lot")
	b.select_id("wall")
	var hw := b.evaluate(Vector2(8.5, 9.0))
	check(hw["ok"] and hw["replace"].size() == 1, "over a house wall it replaces it (Refinement 01: %s)" % hw["reason"])
	check_eq(_reason(b, "wall", Vector2(4.5, 7.0)), "Furniture is in the way.", "through the sofa")
	check_eq(_reason(b, "wall", Vector2(4.5, 9.0)), "Something is already standing here.", "on the front door")
	check_eq(_reason(b, "wall", Vector2(1.5, 9.0)), "There's a window here.", "over a window")
	var p := VoxelPlayer.new()
	add(p)
	p.global_position = Vector3(2.5, 0, 11.0)
	await physics_frames(2)
	check_eq(_reason(b, "wall", Vector2(2.5, 11.0)), "Someone is standing there.", "on the player")
	check_eq(_reason(b, "crate", Vector2(2.5, 11.0)), "Someone is standing there.", "a crate on the player")
	check_eq(_reason(b, "crate", Vector2(4.4, 7.1)), "Furniture is in the way.", "a crate on the sofa")
	check_eq(_reason(b, "crate", Vector2(8.5, 9.0)), "There's a wall in the way.", "a crate in a wall")
	check_eq(_reason(b, "crate", Vector2(12.0, 6.3)), "", "a crate in the utility room")
	check_eq(_reason(b, "door", Vector2(2.0, 11.0)), "A door needs a wall or a 1 m doorway.", "a door in the open")
	check_eq(_reason(b, "door", Vector2(1.5, 9.0)), "Not in a window.", "a door in a window")
	check(_reason(b, "door", Vector2(14.0, 3.5)).begins_with("Needs"), "a door needs scrap metal")
	(setup[1] as GameState).inventory.add("scrap", 1)
	check_eq(_reason(b, "door", Vector2(14.0, 3.5)), "", "a door into a solid wall")
	check_eq(_reason(b, "door", Vector2(4.5, 9.0)), "There's already something in this opening.", "a door where one hangs")
	check_eq(_reason(b, "upgrade", Vector2(1.5, 0.0)), "Windows can't be plated.", "plating a window")
	check_eq(_reason(b, "repair", Vector2(8.5, 9.0)), "This wall is intact.", "repairing an intact wall")
	check_eq(_reason(b, "demolish", Vector2(2.0, 11.0)), "Nothing to demolish here.", "demolishing nothing")
	# a run along one axis
	b.select_id("wall")
	var r := b.evaluate(Vector2(3.8, 12.1), Vector2(0.2, 12.0))
	check_eq(r["segs"].size(), 4, "a click-drag run covers 4 segments")
	check_eq(r["cost"], {"wood": 16, "nails": 24}, "costs per metre")
	check(r["reason"].begins_with("Needs"), "can't afford it with the starting materials (%s)" % r["reason"])


func test_exit_rule_refuses_sealing_the_house() -> void:
	var setup: Array = await _setup(true)
	var w: HouseWorld = setup[0]
	var b: BuildMode = setup[2]
	check_eq(_reason(b, "barricade", Vector2(2.5, 4.0)), BuildMode.SEAL_REASON, "barricading the bedroom doorway")
	check_eq(_reason(b, "wall", Vector2(2.5, 4.0)), BuildMode.SEAL_REASON, "walling it up")
	b.select_id("barricade")
	check(not b.apply(Vector2(2.5, 4.0)), "apply refuses")
	check_eq(w.count_objects("barricade"), 0, "nothing placed")
	# a door in that doorway is fine: doors count as passable
	check_eq(_reason(b, "door", Vector2(2.5, 4.0)), "", "a door in the bedroom doorway")
	# seal the front: the back door remains, so that's allowed
	check_eq(_reason(b, "barricade", Vector2(4.5, 10.0)), "", "a barricade outside the front door")
	# crates around the bed's foot can't wall it in
	b.select_id("wall")
	check(b.apply(Vector2(3.6, 4.0), Vector2(0.2, 4.0)) == false, "a run over the bedroom wall and its doorway is refused")
	check_eq(b.last_eval["reason"], BuildMode.SEAL_REASON, "it would seal the doorway")


func test_costs_are_paid_and_the_unlimited_cheat_is_free() -> void:
	var setup: Array = await _setup()
	var w: HouseWorld = setup[0]
	var s: GameState = setup[1]
	var b: BuildMode = setup[2]
	var msgs := []
	b.message.connect(func(t: String, ok: bool) -> void: msgs.append([t, ok]))
	b.select_id("wall")
	check(b.apply(Vector2(0.5, 11.0)), "one wall segment")
	check_eq(s.inventory.count("wood"), 2, "4 planks paid")
	check_eq(s.inventory.count("nails"), 6, "6 nails paid")
	check(not msgs.is_empty() and msgs[-1][1], "positive feedback")
	check(not b.apply(Vector2(1.5, 11.0)), "the next one is unaffordable")
	check(msgs[-1][0].begins_with("Needs"), "with a reason (%s)" % msgs[-1][0])
	s.cheats["unlimited"] = true
	b.select_id("crate")
	check(b.apply(Vector2(12.0, 6.3)), "with the cheat a crate is free")
	check_eq(s.inventory.count("wood"), 2, "nothing deducted")
	check_eq(w.count_objects("crate"), 1, "crate placed")
	check_eq(w.nav.get_raw(w.nav.cell_of(Vector2(12.0, 6.25))), GridNav.SOLID, "a crate is SOLID for navigation")


func test_repair_restores_voxels_and_charges_the_cost() -> void:
	var setup: Array = await _setup()
	var w: HouseWorld = setup[0]
	var s: GameState = setup[1]
	var b: BuildMode = setup[2]
	s.inventory.add("wood", 30)
	s.inventory.add("nails", 60)
	for t in [Vector3(8.3, 1.0, 9.0), Vector3(8.6, 1.3, 9.0), Vector3(8.5, 0.6, 9.0)]:
		var o := Vector3(8.5, 1.3, 11.0)
		w.shoot(o, t - o, [])
	var seg := Vector3i(0, 9, 8)
	var missing := w.section_missing(seg)
	check(missing > 50, "shots removed voxels (%d)" % missing)
	var cost := BuildPieces.section_repair_cost(missing)
	check_eq(cost, {"wood": ceili(missing / 150.0), "nails": ceili(missing / 60.0)}, "SPEC repair cost")
	var wood := s.inventory.count("wood")
	var nails := s.inventory.count("nails")
	b.select_id("repair")
	check(b.apply(Vector2(8.5, 9.0)), "repair applies")
	check_eq(s.inventory.count("wood"), wood - cost["wood"], "planks charged")
	check_eq(s.inventory.count("nails"), nails - cost["nails"], "nails charged")
	check_eq(w.section_missing(seg), 0, "the design is restored")
	# objects: lost-HP fraction x cost, at least one plank
	var front: WorldObject = w.object_at(Vector2(4.5, 9.0))
	w.damage_object(front, 9)
	var oc := BuildPieces.object_repair_cost("door", front.hp, front.max_hp)
	check_eq(oc, {"wood": 2, "nails": 3, "scrap": 1}, "half a door's cost")
	check_eq(BuildPieces.object_repair_cost("barricade", 11, 12), {"wood": 1, "nails": 1}, "minimum one plank")
	s.inventory.add("scrap", 2)
	check(b.apply(Vector2(4.5, 9.0)), "door repaired")
	check_eq(front.hp, front.max_hp, "full HP")


func test_upgrade_makes_walls_harder() -> void:
	var setup: Array = await _setup(true)
	var w: HouseWorld = setup[0]
	var b: BuildMode = setup[2]
	b.select_id("upgrade")
	check(b.apply(Vector2(4.5, -0.05)), "sheathe the north bedroom wall (x 4-5)")
	check(w.upgraded.has(Vector3i(0, 0, 4)), "recorded")
	var c := w.grid.cell_of(Vector3(4.5, 1.2, -0.1))
	check_eq(w.grid.get_mat(c.x, c.y, c.z), VoxelMat.METAL_SHEET, "the outer skin is sheet metal")
	check(VoxelMat.HARDNESS[VoxelMat.METAL_SHEET] > VoxelMat.HARDNESS[VoxelMat.SIDING], "harder than siding")
	check_eq(_reason(b, "upgrade", Vector2(4.5, -0.05)), "Already plated with iron.", "only once")
	var plain := 0
	var sheet := 0
	for k in 3:
		for x in [3.5, 4.5]:
			var before := w.grid.solid_count
			var o := Vector3(x, 1.3, -2.5)
			w.shoot(o, Vector3(x + 0.1 * k - 0.1, 0.9 + 0.2 * k, -0.15) - o, [])
			if x < 4.0:
				plain += before - w.grid.solid_count
			else:
				sheet += before - w.grid.solid_count
	print("    voxels removed by 3 shots: plain wall %d, sheathed wall %d" % [plain, sheet])
	check(sheet * 2 < plain, "sheathing removes far fewer voxels per shot (%d vs %d)" % [sheet, plain])


func test_demolish_refunds_player_pieces_and_opens_original_walls() -> void:
	var setup: Array = await _setup()
	var w: HouseWorld = setup[0]
	var s: GameState = setup[1]
	var b: BuildMode = setup[2]
	b.select_id("wall")
	check(b.apply(Vector2(0.5, 11.0)), "built")
	check_eq(w.nav.get_raw(w.nav.cell_of(Vector2(0.5, 11.0))), GridNav.WALL, "nav closed")
	b.select_id("demolish")
	check(b.apply(Vector2(0.5, 11.0)), "demolished")
	check_eq(s.inventory.count("wood"), 2 + 4, "all the planks back (Experiment 004: full refund)")
	check_eq(s.inventory.count("nails"), 6 + 6, "all the nails back")
	check_eq(w.nav.get_raw(w.nav.cell_of(Vector2(0.5, 11.0))), GridNav.OPEN, "nav open again")
	check(not w.built.has(Vector3i(0, 11, 0)), "no longer a built section")
	# an original wall section becomes an opening (Experiment 004: salvage)
	var wood := s.inventory.count("wood")
	check(b.apply(Vector2(8.0, 3.5)), "knock out the bathroom/kitchen wall at y 3-4")
	check_eq(s.inventory.count("wood"), wood + 2, "salvage from the original house")
	check(w.nav.is_walkable(w.nav.cell_of(Vector2(8.0, 3.5))), "walkable through")
	var top := w.grid.cell_of(Vector3(8.0, 2.4, 3.5))
	check_eq(w.grid.get_mat(top.x, top.y, top.z), VoxelMat.AIR, "full height")
	# an original door: taken down (half its cost as salvage)
	check(b.apply(Vector2(14.0, 6.5)), "take the back door down")
	check_eq(w.count_objects("door"), 1, "one door left")


func test_doors_and_doorways() -> void:
	var setup: Array = await _setup(true)
	var w: HouseWorld = setup[0]
	var b: BuildMode = setup[2]
	b.select_id("door")
	check(b.apply(Vector2(14.0, 3.5)), "a door cut into the kitchen's east wall")
	await physics_frames(2)
	var d: WorldObject = w.object_at(Vector2(14.0, 3.5))
	check(d != null and d.kind == "door" and not d.open, "a closed door hangs there")
	if d == null:
		return
	check_eq(d.facing(), "E", "its front faces out")
	check_eq(w.nav.get_raw(w.nav.cell_of(Vector2(14.0, 3.5))), GridNav.WALL, "closed: WALL")
	check(w.is_blocked(Vector2(14.0, 3.5)), "closed: blocks")
	w.toggle_door(d)
	await physics_frames(2)
	check(w.nav.is_walkable(w.nav.cell_of(Vector2(14.0, 3.5))), "open: walkable through the cut")
	check(not w.is_blocked(Vector2(14.0, 3.5)), "open: passable")
	check(b.apply(Vector2(2.5, 4.0)), "a door filling the bedroom doorway")
	check(w.exit_path_exists(), "doors keep the way out")
	b.select_id("doorway")
	check(b.apply(Vector2(7.5, 4.0)), "a doorway cut between bathroom and living room")
	await physics_frames(2)
	check(w.nav.is_walkable(w.nav.cell_of(Vector2(7.5, 4.0))), "walkable doorway")
	check(not w.is_blocked(Vector2(7.5, 4.0)), "no collision in it")
	var top := w.grid.cell_of(Vector3(7.5, 2.4, 4.0))
	check(VoxelMat.is_struct(w.grid.get_mat(top.x, top.y, top.z)), "a header stays above it")


func test_activation_needs_a_hammer() -> void:
	var setup: Array = await _setup()
	var s: GameState = setup[1]
	var b: BuildMode = setup[2]
	var msgs := []
	b.message.connect(func(t: String, ok: bool) -> void: msgs.append([t, ok]))
	b.set_active(true)
	check(b.active and b.handles_input() and b.palette.visible, "build mode opens its palette")
	b.set_active(false)
	check(not b.palette.visible and not b.handles_input(), "and closes it")
	s.inventory.remove("hammer", 1)
	b.set_active(true)
	check(not b.active, "no hammer, no building")
	check(not msgs.is_empty() and msgs[-1][0] == "You need a hammer to build.", "with a reason")
