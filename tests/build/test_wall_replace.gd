extends "res://tests/test_case.gd"
## Refinement 01: replacing a wall directly with another material (BuildMode
## wall runs): one action, the old wall's refund (the player's own in full,
## the house's as salvage) against the new wall's cost, nothing changes when
## it can't be paid, plating stays, mixed runs, skipped doors and windows,
## no resources from going back and forth, and save/load.


func _setup() -> Array:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	var s := GameState.new_run(7)
	s.inventory.storage_crates = 4
	var b := BuildMode.new()
	b.setup(w, s, null, null)
	add(b)
	await physics_frames(2)
	return [w, s, b]


func _counts(s: GameState) -> Dictionary:
	var out := {}
	for k in ["wood", "nails", "stone", "iron", "scrap"]:
		out[k] = s.inventory.count(k)
	return out


func _set_counts(s: GameState, counts: Dictionary) -> void:
	for k in counts:
		s.inventory.remove(k, s.inventory.count(k))
		s.inventory.add(k, counts[k])


func test_own_wall_wood_to_stone_and_back() -> void:
	var setup: Array = await _setup()
	var w: HouseWorld = setup[0]
	var s: GameState = setup[1]
	var b: BuildMode = setup[2]
	_set_counts(s, {"wood": 20, "nails": 30, "stone": 30})
	var seg := Vector3i(0, 11, 1)
	b.select_id("foundation")
	check(b.apply(Vector2(1.5, 11.0)), "a foundation tile")
	b.select_id("wall")
	check(b.apply(Vector2(1.5, 11.0)), "a wooden wall on it")
	var start := _counts(s)
	check_eq(start, {"wood": 16, "nails": 24, "stone": 28, "iron": 0, "scrap": 0}, "paid 2 stone, 4 planks, 6 nails")
	# wood -> stone: pay 6 stone, get the 4 planks and 6 nails back
	b.select_id("stone_wall")
	var r := b.evaluate(Vector2(1.5, 11.0))
	check(r["ok"], "a stone wall over the wooden one is valid (%s)" % r["reason"])
	check_eq(r["replace"].size(), 1, "it replaces one section")
	check_eq(r["cost"], {"stone": 6}, "pays the stone wall")
	check_eq(r["refund"], {"wood": 4, "nails": 6}, "and gets the wooden wall back in full")
	check_eq(b.replace_text(r), "Replace wood → stone: pay 6 stone, back 4 planks, 6 nails", "the ghost's text")
	check(b.apply(Vector2(1.5, 11.0)), "replaced in one action")
	check_eq(w.sections[seg]["material"], "stone", "now a stone section")
	check(w.built.has(seg), "still the player's own")
	check_eq(w.sections[seg]["strength"], HouseWorld.SECTION_MATERIALS["stone"]["strength"], "with stone's strength")
	check_eq(w.section_missing(seg), 0, "intact")
	check_eq(_counts(s), {"wood": 20, "nails": 30, "stone": 22, "iron": 0, "scrap": 0}, "materials after wood -> stone")
	# stone -> wood -> stone -> wood: no free resources
	for i in 3:
		b.select_id("wall" if i % 2 == 0 else "stone_wall")
		check(b.apply(Vector2(1.5, 11.0)), "replacement %d" % (i + 2))
	check_eq(w.sections[seg]["material"], "wood", "back to wood")
	check_eq(_counts(s), start, "the same materials as with the first wooden wall")
	# the same material again is not a replacement
	b.select_id("wall")
	check_eq(b.evaluate(Vector2(1.5, 11.0))["reason"], "There's already a wooden wall here (Repair mends it).", "wood over wood")


func test_unaffordable_or_invalid_changes_nothing() -> void:
	var setup: Array = await _setup()
	var w: HouseWorld = setup[0]
	var s: GameState = setup[1]
	var b: BuildMode = setup[2]
	_set_counts(s, {"wood": 20, "nails": 30, "stone": 2})
	var seg := Vector3i(0, 11, 1)
	b.select_id("foundation")
	b.apply(Vector2(1.5, 11.0))
	b.select_id("wall")
	b.apply(Vector2(1.5, 11.0))
	b.select_id("wall")
	b.apply(Vector2(3.5, 11.0))            # a wooden wall on bare ground, no foundation
	var before := _counts(s)
	b.select_id("stone_wall")
	check(not b.apply(Vector2(1.5, 11.0)), "6 stone can't be paid with 0 (the refund is planks and nails)")
	check_eq(b.last_eval["reason"], "Needs 6 stone.", "says what is missing")
	check(not b.apply(Vector2(3.5, 11.0)), "no stone wall without a foundation")
	check_eq(b.last_eval["reason"], BuildMode.FOUNDATION_REASON, "the foundation rule still holds")
	check_eq(w.sections[seg]["material"], "wood", "the wall stays wooden")
	check_eq(w.sections[Vector3i(0, 11, 3)]["material"], "wood", "both")
	check_eq(_counts(s), before, "and nothing was paid")


func test_mixed_run_original_walls_plating_and_save() -> void:
	var setup: Array = await _setup()
	var w: HouseWorld = setup[0]
	var s: GameState = setup[1]
	var b: BuildMode = setup[2]
	for k in ["reinforced", "metalworking", "advanced_metal"]:      # Exp 006 (R): gated pieces (without Woodworking's repair discount)
		Research.learn(s, k)
	s.cheats["unlimited"] = true
	# a mixed run: empty, a wooden wall (plated), empty
	b.select_id("foundation")
	b.apply(Vector2(2.8, 11.0), Vector2(0.2, 11.0))
	b.select_id("wall")
	b.apply(Vector2(1.5, 11.0))
	b.select_id("upgrade")
	check(b.apply(Vector2(1.5, 11.1)), "the wooden wall is plated")
	s.cheats["unlimited"] = false
	_set_counts(s, {"wood": 0, "nails": 0, "stone": 30})
	b.select_id("stone_wall")
	var r := b.evaluate(Vector2(2.8, 11.0), Vector2(0.2, 11.0))
	check(r["ok"], "a stone run over empty ground and a wooden wall (%s)" % r["reason"])
	check_eq(r["segs"].size(), 3, "three sections")
	check_eq(r["replace"].size(), 1, "one of them replaced")
	check_eq(r["cost"], {"stone": 18}, "18 stone")
	check(b.apply(Vector2(2.8, 11.0), Vector2(0.2, 11.0)), "built and replaced at once")
	for x in 3:
		check_eq(w.sections[Vector3i(0, 11, x)]["material"], "stone", "section %d is stone" % x)
	check(w.upgraded.has(Vector3i(0, 11, 1)), "the plating stays on the replaced section")
	check_eq(_counts(s), {"wood": 4, "nails": 6, "stone": 12, "iron": 0, "scrap": 0}, "the wooden wall came back")
	# an original house wall: salvage by integrity; a run along the front skips the door and window
	s.cheats["unlimited"] = true
	var front := b.evaluate(Vector2(8.8, 9.0), Vector2(3.2, 9.0))
	var door := Vector3i(0, 9, 4)
	check(not front["segs"].has(door), "the front door is skipped")
	check(int(front["skipped"]) >= 1, "skipped sections are counted")
	var seg := Vector3i(0, 9, 8)
	var full: Dictionary = b.wall_refund(seg)
	check_eq(full, BuildPieces.original_salvage("wall", 1.0), "an intact house wall gives the full salvage")
	for k in 8:
		w.shoot(Vector3(8.5, 1.0, 12.0), Vector3(0, 0, -1), [])
	check(w.section_integrity(seg) < 1.0, "the house wall is damaged")
	var dmg: Dictionary = b.wall_refund(seg)
	check(int(dmg.get("wood", 0)) <= int(full["wood"]) and int(dmg.get("nails", 0)) <= int(full["nails"]), "a damaged one gives no more (%s)" % str(dmg))
	b.select_id("wall")
	check(b.apply(Vector2(8.5, 9.0)), "a wooden wall replaces the house wall (%s)" % b.last_eval["reason"])
	check(w.built.has(seg) and w.sections[seg]["material"] == "wood" and not w.sections[seg]["orig"], "now the player's wooden wall")
	check_eq(w.section_missing(seg), 0, "intact")
	# save and load keep it all
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(w.save_data()), "the house loads")
	check_eq(w2.sections[Vector3i(0, 11, 1)]["material"], "stone", "the replaced stone section")
	check(w2.upgraded.has(Vector3i(0, 11, 1)), "with its plating")
	check(w2.built.has(seg) and w2.sections[seg]["material"] == "wood", "and the replaced house wall")
