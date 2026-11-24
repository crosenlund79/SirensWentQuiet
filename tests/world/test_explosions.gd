extends "res://tests/test_case.gd"
## Experiment 003: HouseWorld.explode (voxels removed by material, objects
## damaged by distance and shielding, nav and collision opened, the slab
## kept, scorch and scars, persistence after a blast) and weak_points.

const LINE := 11
const SEGS := [Vector3i(0, LINE, 0), Vector3i(0, LINE, 1), Vector3i(0, LINE, 2)]
const HOLE := Vector2(1.5, LINE)


func _world() -> HouseWorld:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	await physics_frames(2)
	return w


func _count(g: VoxelGrid, m: int) -> int:
	var n := 0
	for v in g.mat:
		if v == m:
			n += 1
	return n


func test_blast_breaches_a_wooden_wall_and_updates_nav_and_collision() -> void:
	var w: HouseWorld = await _world()
	w.build_walls(SEGS)
	await physics_frames(2)
	check(w.is_blocked(HOLE), "the wall blocks before")
	check(not w.nav.is_walkable(w.nav.cell_of(HOLE)), "and is not walkable")
	var changed := [0]
	w.structure_changed.connect(func() -> void: changed[0] += 1)
	var r := w.explode(Vector3(HOLE.x, 1.0, LINE + 0.55), 1.6, 24.0)
	print("    wooden wall blast: %d voxels, %d nav cells opened, breach %s, %.0f ms %s" % [r["voxels"], r["opened"], r["breach"], r["ms"], w.stats["blast"]])
	check(r["voxels"] > 300, "voxels removed (%d)" % r["voxels"])
	check(r["breach"] and r["opened"] > 0, "a breach opened in navigation")
	check(w.nav.is_walkable(w.nav.cell_of(HOLE)), "walkable through the hole right away")
	check(not w.is_blocked(HOLE), "collision opened in the same frame")
	check(not r["sections"].is_empty() and r["sections"].has(Vector3i(0, LINE, 1)), "the hit sections are reported")
	check(w.section_integrity(Vector3i(0, LINE, 1)) < 0.5, "the section's integrity dropped (%.2f)" % w.section_integrity(Vector3i(0, LINE, 1)))
	check(changed[0] > 0, "structure_changed emitted")
	check_eq(w.scars.size(), 1, "a scorch mark on the ground")
	check(w.fx.blast_active(), "the flash and fireball play")


func test_stone_and_iron_resist_more_than_wood() -> void:
	var removed := {}
	for kind in ["wood", "wood+iron", "stone", "stone+iron"]:
		var w: HouseWorld = await _world()
		if kind.begins_with("stone"):
			w.build_foundation(SEGS)
			w.build_walls(SEGS, "stone")
		else:
			w.build_walls(SEGS)
		if kind.ends_with("+iron"):
			for s in SEGS:
				w.upgrade_section(s)
		var r := w.explode(Vector3(HOLE.x, 1.0, LINE + 0.55), 1.6, 24.0)
		removed[kind] = r["voxels"]
		removed[kind + " breach"] = r["breach"]
	print("    one blast (r 1.6 m, 0.55 m out, 1 m up): ", removed)
	check(removed["wood"] > removed["wood+iron"], "iron plating keeps more of a wooden wall")
	check(removed["wood"] > removed["stone"] * 2, "stone loses far fewer voxels than wood")
	check(removed["stone"] > removed["stone+iron"], "plated stone loses the fewest")
	check(removed["wood breach"], "wood is breached by one blast")
	check(not removed["stone breach"], "stone is not breached by one blast")


func test_objects_are_damaged_by_distance_material_and_shielding() -> void:
	var w: HouseWorld = await _world()
	var near := w.place_object("barricade", Vector2(-1.5, 11.0), 0)
	var far := w.place_object("barricade", Vector2(-1.5, 13.0), 0)
	var iron := w.place_object("barricade", Vector2(0.5, 11.0), 0, true, "iron")
	var out_of_reach := w.place_object("crate", Vector2(5.5, 12.25), 0)
	var destroyed := []
	w.object_destroyed.connect(func(k: String, _at: Vector3) -> void: destroyed.append(k))
	var r := w.explode(Vector3(-0.5, 1.0, 11.3), 1.6, 24.0)
	print("    hit %s, destroyed %s; far barricade %d/%d, iron barricade %d/%d" % [r["hit"], r["destroyed"],
		far.hp if is_instance_valid(far) else 0, far.max_hp, iron.hp if is_instance_valid(iron) else 0, iron.max_hp])
	check(not w.objects.has(near), "the wooden barricade next to the blast is destroyed")
	check(w.objects.has(far) and far.hp < far.max_hp and far.hp > 0, "one 2 m away is damaged, not destroyed")
	check(w.objects.has(iron) and iron.hp < iron.max_hp, "an iron barricade at the same distance survives, damaged")
	check(out_of_reach.hp == out_of_reach.max_hp, "an object out of reach is untouched")
	check(destroyed.has("barricade"), "object_destroyed emitted for the barricade")
	check(r["destroyed"].has("barricade") and r["hit"].size() >= 3, "and reported")
	# shielding: the same blast distance, a crate behind a stone wall vs in the open
	var w2: HouseWorld = await _world()
	w2.build_foundation(SEGS)
	w2.build_walls(SEGS, "stone")
	var shielded := w2.place_object("crate", Vector2(1.5, 10.25), 0)
	var open := w2.place_object("crate", Vector2(5.5, 10.25), 0)
	w2.explode(Vector3(1.5, 0.8, 11.55), 1.6, 10.0)
	w2.explode(Vector3(5.5, 0.8, 11.55), 1.6, 10.0)
	var lost_shielded := shielded.max_hp - shielded.hp if w2.objects.has(shielded) else shielded.max_hp
	var lost_open := open.max_hp - open.hp if w2.objects.has(open) else open.max_hp
	print("    crate behind a stone wall lost %d HP, one in the open %d HP" % [lost_shielded, lost_open])
	check(lost_shielded < lost_open, "a wall shields what stands behind it")


func test_doors_take_blast_damage_and_open_navigation() -> void:
	var w: HouseWorld = await _world()
	var front: WorldObject = w.object_at(Vector2(4.5, 9.0))
	check(front != null and front.kind == "door", "the front door")
	var r := w.explode(Vector3(4.5, 1.0, 9.6), 1.2, 24.0)
	check(r["destroyed"].has("door"), "a close blast destroys a wooden door (%s)" % str(r["destroyed"]))
	check(w.nav.is_walkable(w.nav.cell_of(Vector2(4.5, 9.0))), "the doorway is open for navigation")
	var w2: HouseWorld = await _world()
	var d2: WorldObject = w2.object_at(Vector2(4.5, 9.0))
	w2.remove_object(d2)
	var reinforced := w2.place_object("door", Vector2(4.5, 9.0), d2.rot, true, "iron")
	var r2 := w2.explode(Vector3(4.5, 1.0, 9.6), 1.2, 24.0)
	check(w2.objects.has(reinforced) and reinforced.hp < reinforced.max_hp, "a reinforced door survives the same blast (%d/%d)" % [reinforced.hp, reinforced.max_hp])
	check(not r2["destroyed"].has("door"), "not destroyed")


func test_the_foundation_slab_never_goes_and_the_floor_is_cratered() -> void:
	var w: HouseWorld = await _world()
	var slab := _count(w.grid, VoxelMat.FOUNDATION)
	var floor0 := _count(w.grid, VoxelMat.FLOOR)
	var r := w.explode(Vector3(6.5, 0.2, 6.0), 2.2, 30.0)
	check(r["voxels"] > 0, "the blast removed voxels (%d)" % r["voxels"])
	check_eq(_count(w.grid, VoxelMat.FOUNDATION), slab, "every foundation voxel is still there")
	check(_count(w.grid, VoxelMat.FLOOR) < floor0, "the floor finish is cratered")
	# scorch: exposed voxels around the crater darkened in the current grid only
	var c := w.grid.cell_of(Vector3(6.5, -0.05, 7.9))
	var i := w.grid.idx(c.x, c.y, c.z)
	if w.grid.mat[i] != 0:
		check(w.grid.col[i] != w.design.col[i], "the floor near the crater is scorched")
	w.repair_all()
	check_eq(w.grid.col, w.design.col, "repair_all cleans the scorch")


func test_bad_input_does_nothing() -> void:
	var w: HouseWorld = await _world()
	var before := w.grid.solid_count
	for args in [[Vector3(NAN, 1, 1), 1.6, 20.0], [Vector3(1, 1, 1), NAN, 20.0], [Vector3(1, 1, 1), -1.0, 20.0], [Vector3(1, 1, 1), 1.6, INF]]:
		var r := w.explode(args[0], args[1], args[2])
		check_eq(r["voxels"], 0, "no effect for %s" % str(args))
	check_eq(w.grid.solid_count, before, "nothing removed")
	var r2 := w.explode(Vector3(40, 1, 40), 1.6, 20.0)
	check_eq(r2["voxels"], 0, "a blast off the grid removes nothing and doesn't crash")


func test_persistence_round_trip_after_blasts() -> void:
	var w: HouseWorld = await _world()
	w.build_foundation(SEGS)
	w.build_walls(SEGS, "stone")
	w.build_walls([Vector3i(0, LINE, 4), Vector3i(0, LINE, 5)])
	w.place_object("barricade", Vector2(7.5, 11.0), 0, true, "iron")
	w.explode(Vector3(HOLE.x, 1.0, LINE + 0.55), 1.6, 24.0)
	w.explode(Vector3(5.0, 1.0, LINE + 0.55), 1.6, 24.0)
	w.explode(Vector3(8.5, 1.0, 9.6), 1.6, 24.0)
	await frames(2)
	var d := w.save_data()
	check_eq(d["version"], 2, "saved as version 2")
	var bytes := var_to_bytes(d)
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(bytes_to_var(bytes)), "loads")
	await physics_frames(2)
	print("    save after three blasts: %d bytes" % bytes.size())
	for name in ["mat", "col", "pcol", "pmask"]:
		check(w.grid.get(name) == w2.grid.get(name), "current grid %s identical (craters and scorch)" % name)
		check(w.design.get(name) == w2.design.get(name), "design grid %s identical" % name)
	var nav_bad := 0
	for j in w.nav.size.y:
		for i in w.nav.size.x:
			if w.nav.get_raw(Vector2i(i, j)) != w2.nav.get_raw(Vector2i(i, j)):
				nav_bad += 1
	check_eq(nav_bad, 0, "the same nav raw cells")
	check_eq(w2.scars, w.scars, "the scorch marks")
	check_eq(w2.foundations, w.foundations, "the foundations")
	for s in w.sections:
		check(w2.sections.has(s) and w2.sections[s]["material"] == w.sections[s]["material"] and w2.sections[s]["current"] == w.sections[s]["current"], "section %s" % s)
	var a := []
	var b := []
	for o in w.objects:
		a.append(o.to_dict())
	for o in w2.objects:
		b.append(o.to_dict())
	a.sort_custom(func(p, q): return str(p) < str(q))
	b.sort_custom(func(p, q): return str(p) < str(q))
	check_eq(b, a, "the same objects, materials and HP")
	check_eq(w2.nav.is_walkable(w2.nav.cell_of(Vector2(8.5, 9.0))), w.nav.is_walkable(w.nav.cell_of(Vector2(8.5, 9.0))), "the blasted house wall")
	# bad scars and object materials are refused
	for patch in [{"scars": [[1.0, 2.0]]}, {"scars": [[1.0, 2.0, NAN]]}, {"stone": [[0, 1]]},
			{"objects": [{"kind": "door", "x": 4.5, "y": 9.0, "rot": 2, "hp": 10, "mat": "gold"}]},
			{"objects": [{"kind": "door", "x": 4.5, "y": 9.0, "rot": 2, "hp": 40, "mat": "wood"}]}]:
		var dd := d.duplicate(true)
		dd.merge(patch, true)
		var w3 := HouseWorld.new()
		add(w3)
		check(not w3.load_data(dd), "refused: %s" % str(patch))


func test_weak_points_rank_for_a_wall_seeking_attacker() -> void:
	var w: HouseWorld = await _world()
	var from := Vector2(4.5, 14.0)
	var wp := w.weak_points(from)
	check(wp.size() > 20, "doors and exterior wall sections (%d)" % wp.size())
	check(wp[0]["kind"] == "door", "a closed door ranks first on the intact house (%s)" % wp[0]["kind"])
	for p in wp:
		var pos: Vector2 = p["pos"]
		check(not HousePlan.FOOTPRINT.has_point(pos), "%s %s: the attacker stands outside (%s)" % [p["kind"], p["target"], pos])
		check(w.nav.is_walkable(w.nav.cell_of(pos)), "on a walkable cell (%s)" % pos)
		check(pos.distance_to(p["target"]) <= 1.3, "next to its target")
	# interior walls are not candidates
	for p in wp:
		if p["kind"] == "wall":
			var s: Vector3i = p["seg"]
			check(w._is_outer_wall(s), "only outer walls (%s)" % s)
	var south := _entry(wp, Vector3i(0, 9, 8))
	check(not south.is_empty() and south["pos"].y > 9.0, "the south wall's stand point is on the south (outside) face")
	# weaker sections rank higher: damage one, plate another
	w.upgrade_section(Vector3i(0, 9, 6))
	for k in 4:
		w.shoot(Vector3(7.5, 1.3, 10.8), Vector3(7.5 + 0.2 * k - 0.3, 0.5 + 0.3 * k, 9.0) - Vector3(7.5, 1.3, 10.8), [])
	wp = w.weak_points(from)
	var damaged := _entry(wp, Vector3i(0, 9, 7))
	var plated := _entry(wp, Vector3i(0, 9, 6))
	var plain := _entry(wp, Vector3i(0, 9, 9))
	check(not damaged.is_empty() and not plated.is_empty() and not plain.is_empty(), "all three listed")
	if not damaged.is_empty() and not plated.is_empty() and not plain.is_empty():
		check(damaged["score"] > plain["score"], "a damaged section ranks above an intact one")
		check(plated["score"] < plain["score"], "an iron-plated section ranks below a plain one")
	# near the player's room
	var near_bed := w.weak_points(from, Vector2(2.0, 2.0))
	var north_w := _entry(near_bed, Vector3i(0, 0, 4))
	var north_far := _entry(near_bed, Vector3i(0, 0, 13))
	check(north_w["score"] > north_far["score"], "a wall next to the player ranks above the same wall far away")
	# a breached section is no target any more; materials of built walls
	var w2: HouseWorld = await _world()
	w2.build_walls([Vector3i(0, LINE, 0)])
	w2.build_foundation([Vector3i(0, LINE, 2)])
	w2.build_walls([Vector3i(0, LINE, 2)], "stone")
	w2.place_object("door", Vector2(4.5, 11.0), 2, true, "iron")
	var wp2 := w2.weak_points(Vector2(1.5, 14.0))
	var wood := _entry(wp2, Vector3i(0, LINE, 0))
	var stone := _entry(wp2, Vector3i(0, LINE, 2))
	check(not wood.is_empty() and not stone.is_empty(), "built walls are candidates")
	if not wood.is_empty() and not stone.is_empty():
		check(wood["score"] > stone["score"], "a wooden wall ranks above a stone wall")
		check(wood["material"] == "wood" and stone["material"] == "stone", "with their materials")
		check(wood["pos"].y > LINE, "built walls face away from the bed")
	var iron_door := {}
	var wood_door := {}
	for p in wp2:
		if p["kind"] == "door" and p["material"] == "iron":
			iron_door = p
		elif p["kind"] == "door" and p["target"].distance_to(Vector2(4.5, 9.0)) < 0.1:
			wood_door = p
	check(not iron_door.is_empty() and not wood_door.is_empty() and iron_door["strength"] > wood_door["strength"] * 2.0, "a reinforced door counts as much stronger")
	w2.explode(Vector3(0.5, 1.0, LINE + 0.55), 1.6, 24.0)
	check(_entry(w2.weak_points(Vector2(1.5, 14.0)), Vector3i(0, LINE, 0)).is_empty(), "a breached section is no longer listed")


func _entry(list: Array, s: Vector3i) -> Dictionary:
	for p in list:
		if p["kind"] == "wall" and p["seg"] == s:
			return p
	return {}
