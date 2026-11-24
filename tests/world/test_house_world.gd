extends "res://tests/test_case.gd"
## HouseWorld (survival house): navigation recompute, objects, doors, the exit
## rule, persistence round trip, furniture meshes, cutaway and night lights.


func _world(light := false) -> HouseWorld:
	var w := HouseWorld.new()
	if light:
		var l := VoxelLighting.new()
		add(l)
		w.setup(l)
	add(w)
	w.build_new()
	await physics_frames(2)
	return w


func _door(w: HouseWorld, at: Vector2) -> WorldObject:
	for o in w.objects:
		if o.kind == "door" and o.pos.distance_to(at) < 0.1:
			return o
	return null


func _raw(w: HouseWorld, p: Vector2) -> int:
	return w.nav.get_raw(w.nav.cell_of(p))


## Shoots a 3 x 4 pattern at `hole` from `from` until the nav cell is walkable.
func _open_hole(w: HouseWorld, from: Vector2, hole: Vector2, vertical := false) -> int:
	var pattern := [Vector2(-0.3, 0.3), Vector2(0.0, 0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.75), Vector2(0.0, 0.75), Vector2(0.3, 0.75),
		Vector2(-0.3, 1.2), Vector2(0.0, 1.2), Vector2(0.3, 1.2), Vector2(-0.3, 1.6), Vector2(0.0, 1.6), Vector2(0.3, 1.6)]
	var shots := 0
	var o := Vector3(from.x, Tuning.MUZZLE_HEIGHT, from.y)
	while shots < 60 and not w.nav.is_walkable(w.nav.cell_of(hole)):
		var k: Vector2 = pattern[shots % pattern.size()]
		var t := Vector3(hole.x, k.y, hole.y + k.x) if vertical else Vector3(hole.x + k.x, k.y, hole.y)
		w.shoot(o, t - o, [])
		shots += 1
	return shots if w.nav.is_walkable(w.nav.cell_of(hole)) else 99


func test_new_house_matches_plan_raster_and_starts_with_closed_doors() -> void:
	var w: HouseWorld = await _world()
	check_eq(w.count_objects("door"), 2, "front and back doors")
	var front := _door(w, Vector2(4.5, 9.0))
	var back := _door(w, Vector2(14.0, 6.5))
	check(front != null and back != null, "doors stand in the front and back doorways")
	if front == null or back == null:
		return
	check(not front.open and not back.open, "doors start closed")
	check_eq(_raw(w, Vector2(4.5, 9.0)), GridNav.WALL, "a closed door is WALL for navigation")
	w.set_door_open(front, true)
	w.set_door_open(back, true)
	var ref := GridNav.new()
	HousePlan.rasterize_into(ref)
	# Experiment 004: blocking furniture is bashable (WALL) for the survival house's nav
	for f in HousePlan.FURNITURE:
		if f["blocks"]:
			ref.mark_rect(f["rect"], GridNav.WALL)
	ref.rebuild()
	var bad := []
	for j in ref.size.y:
		for i in ref.size.x:
			var c := Vector2i(i, j)
			if ref.get_raw(c) != w.nav.get_raw(c):
				bad.append("%s ref %d got %d" % [ref.center_of(c), ref.get_raw(c), w.nav.get_raw(c)])
	check(bad.is_empty(), "with doors open the recomputed nav equals the shared plan raster, furniture bashable (%d differ: %s)" % [bad.size(), str(bad.slice(0, 6))])
	check(w.exit_path_exists(), "the intact house has a way out")
	print("    build %.0f ms (nav %.0f ms)" % [w.stats["build_ms"], w.stats["nav_ms"]])


func test_doors_open_and_close_in_nav_and_collision() -> void:
	var w: HouseWorld = await _world()
	var front := _door(w, Vector2(4.5, 9.0))
	check(w.is_blocked(Vector2(4.5, 9.0)), "a closed door blocks bodies")
	check(w.interactables().has(front) and front.interact_prompt() == "[E] Open door", "the door is an interactable")
	front.interact(null)
	await physics_frames(2)
	check(front.open, "E opens it")
	check_eq(_raw(w, Vector2(4.5, 9.0)), GridNav.OPEN, "an open door is OPEN")
	check(w.nav.is_walkable(w.nav.cell_of(Vector2(4.5, 9.0))), "and walkable")
	check(not w.is_blocked(Vector2(4.5, 9.0)), "an open door lets bodies through")
	front.interact(null)
	await physics_frames(2)
	check(not front.open and _raw(w, Vector2(4.5, 9.0)) == GridNav.WALL, "closed again")
	check(w.is_blocked(Vector2(4.5, 9.0)), "and blocking again")


func test_enemy_strikes_damage_and_destroy_doors_and_barricades() -> void:
	var w: HouseWorld = await _world()
	var front := _door(w, Vector2(4.5, 9.0))
	var destroyed := []
	w.object_destroyed.connect(func(k: String, at: Vector3) -> void: destroyed.append([k, at]))
	var before := w.grid.solid_count
	for k in 17:
		w.enemy_strike(Vector3(4.5, 0, 9.7), Vector2(4.5, 9.0))
	check_eq(front.hp, 1, "17 swings leave the door at 1 HP")
	check_eq(w.grid.solid_count, before, "strikes on the door don't bite the wall")
	check_eq(w.damage_summary()["damaged_objects"], 1, "damage summary counts the door")
	w.enemy_strike(Vector3(4.5, 0, 9.7), Vector2(4.5, 9.0))
	await physics_frames(2)
	check_eq(destroyed.size(), 1, "object_destroyed emitted once")
	check(not destroyed.is_empty() and destroyed[0][0] == "door", "for the door")
	check_eq(w.count_objects("door"), 1, "the door is gone")
	check_eq(_raw(w, Vector2(4.5, 9.0)), GridNav.OPEN, "its cells open")
	check(not w.is_blocked(Vector2(4.5, 9.0)), "and its collision is gone")
	# a barricade in the yard
	var b := w.place_object("barricade", Vector2(1.5, 11.0), 0)
	await physics_frames(2)
	check_eq(_raw(w, Vector2(1.5, 11.0)), GridNav.WALL, "a barricade is WALL")
	check(w.is_blocked(Vector2(1.5, 11.0)), "and blocks bodies")
	var space := w.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(Vector3(1.5, 1.2, 12.0), Vector3(1.5, 1.2, 10.0), 1 | 8)
	check(space.intersect_ray(ray).is_empty(), "bullets pass a barricade")
	for k in 12:
		w.enemy_strike(Vector3(1.5, 0, 11.7), Vector2(1.5, 11.0))
	await physics_frames(2)
	check(not is_instance_valid(b) or b.is_queued_for_deletion() or not w.objects.has(b), "12 swings break a barricade")
	check_eq(_raw(w, Vector2(1.5, 11.0)), GridNav.OPEN, "its cells open")


func test_nav_recompute_built_wall_closes_and_repair_restores() -> void:
	var w: HouseWorld = await _world()
	var hole := Vector2(8.5, 9.0)
	var shots := _open_hole(w, Vector2(8.5, 10.8), hole)
	await physics_frames(2)
	check(shots < 40, "a walk-through hole opens in the south wall (%d shots)" % shots)
	check(not w.is_blocked(hole), "collision follows the hole")
	var miss := w.section_missing(Vector3i(0, 9, 8))
	check(miss > 100, "the section knows what's missing (%d voxels)" % miss)
	check(w.section_integrity(Vector3i(0, 9, 8)) < 0.9, "and its live integrity dropped (%.2f)" % w.section_integrity(Vector3i(0, 9, 8)))
	for s in [Vector3i(0, 9, 7), Vector3i(0, 9, 8), Vector3i(0, 9, 9)]:
		w.repair_section(s)
	await physics_frames(2)
	check_eq(_raw(w, hole), GridNav.WALL, "repair closes the nav again")
	check(not w.nav.is_walkable(w.nav.cell_of(hole)), "not walkable")
	check(w.is_blocked(hole), "and blocks bodies")
	check_eq(w.section_missing(Vector3i(0, 9, 8)), 0, "nothing missing after repair")
	check(is_equal_approx(w.section_integrity(Vector3i(0, 9, 8)), 1.0), "integrity back to 1")
	# a wall in the open yard closes nav; demolishing reopens it
	var segs := [Vector3i(0, 11, 0), Vector3i(0, 11, 1)]
	check_eq(_raw(w, Vector2(0.5, 11.0)), GridNav.OPEN, "open yard before")
	w.build_walls(segs)
	await physics_frames(2)
	for x in [0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 1.75]:
		check_eq(_raw(w, Vector2(x, 11.0)), GridNav.WALL, "built wall is WALL at x=%.2f" % x)
	check(w.is_blocked(Vector2(1.0, 11.0)), "built wall blocks bodies")
	w.demolish_wall(segs[0])
	w.demolish_wall(segs[1])
	await physics_frames(2)
	check_eq(_raw(w, Vector2(0.5, 11.0)), GridNav.OPEN, "demolished: open again")
	check(not w.is_blocked(Vector2(1.0, 11.0)), "and passable")


func test_exit_rule_sees_a_sealed_bedroom() -> void:
	var w: HouseWorld = await _world()
	check(w.exit_path_exists(), "a way out at the start (doors count as passable)")
	var b := w.place_object("barricade", Vector2(2.5, 4.0), 0)   # bedroom doorway
	check(not w.exit_path_exists(), "a barricade in the bedroom doorway seals the bed in")
	w.remove_object(b)
	check(w.exit_path_exists(), "removing it reopens the way")
	var extra := {}
	for c in w.nav.cells_in_rect(Rect2(2.0, 3.875, 1.0, 0.25)):
		extra[c] = GridNav.WALL
	check(not w.exit_path_exists(extra), "a previewed change is checked without applying it")


func test_persistence_round_trip_restores_the_exact_house() -> void:
	var w: HouseWorld = await _world()
	_open_hole(w, Vector2(8.5, 10.8), Vector2(8.5, 9.0))
	for t in [Vector3(1.4, 1.2, 0.0), Vector3(12.0, 1.0, 9.0), Vector3(14.0, 1.5, 2.0)]:
		var o := Vector3(t.x, 1.3, t.z) + (Vector3(0, 0, -2.0) if t.z < 1.0 else Vector3(0, 0, 2.0) if t.z > 8.0 else Vector3(2.0, 0, 0))
		w.shoot(o, t - o, [])
	w.build_walls([Vector3i(0, 11, 0), Vector3i(0, 11, 1), Vector3i(0, 11, 2), Vector3i(1, 0, 11)])
	w.place_object("barricade", Vector2(10.5, 11.0), 0)
	w.place_object("crate", Vector2(12.0, 6.25), 0)
	w.place_object("rain_collector", Vector2(16.25, 5.25), 1)
	w.upgrade_section(Vector3i(0, 0, 3))
	w.cut_opening(Vector3i(1, 10, 5))
	w.shoot(Vector3(3.5, 1.3, -2.0), Vector3(0, -0.1, 1), [])   # dent the sheathing
	var front := _door(w, Vector2(4.5, 9.0))
	w.damage_object(front, 5)
	w.set_door_open(_door(w, Vector2(14.0, 6.5)), true)
	await frames(2)
	var t0 := Time.get_ticks_usec()
	var d := w.save_data()
	var bytes := var_to_bytes(d)
	var save_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var d2: Dictionary = bytes_to_var(bytes)
	var w2 := HouseWorld.new()
	add(w2)
	var t1 := Time.get_ticks_usec()
	check(w2.load_data(d2), "load succeeds")
	var load_ms := (Time.get_ticks_usec() - t1) / 1000.0
	print("    save %d bytes; save_data + serialise %.0f ms; load_data %.0f ms (incl. meshing and nav)" % [bytes.size(), save_ms, load_ms])
	for name in ["mat", "col", "pcol", "pmask"]:
		check(w.grid.get(name) == w2.grid.get(name), "current grid %s identical" % name)
		check(w.design.get(name) == w2.design.get(name), "design grid %s identical" % name)
	check_eq(w2.grid.solid_count, w.grid.solid_count, "solid count")
	check(w.grid.mat != w.design.mat, "current differs from design (damage kept)")
	var nav_bad := 0
	for j in w.nav.size.y:
		for i in w.nav.size.x:
			if w.nav.get_raw(Vector2i(i, j)) != w2.nav.get_raw(Vector2i(i, j)):
				nav_bad += 1
	check_eq(nav_bad, 0, "the same nav raw cells")
	var a := []
	var b := []
	for o in w.objects:
		a.append(o.to_dict())
	for o in w2.objects:
		b.append(o.to_dict())
	a.sort_custom(func(p, q): return str(p) < str(q))
	b.sort_custom(func(p, q): return str(p) < str(q))
	check_eq(b, a, "the same objects")
	check_eq(w2.built, w.built, "built sections")
	check_eq(w2.upgraded, w.upgraded, "sheathed sections")
	check_eq(w2.openings.size(), w.openings.size(), "openings")
	for s in w.sections:
		check(w2.sections.has(s) and w2.sections[s]["current"] == w.sections[s]["current"] and w2.sections[s]["design"] == w.sections[s]["design"], "section %s counts" % s)
	check_eq(w2.damage_summary(), w.damage_summary(), "damage summary")
	check(not w2.is_blocked(Vector2(8.5, 9.0)), "the loaded hole is walkable")
	check(w2.is_blocked(Vector2(0.5, 11.0)), "the loaded built wall blocks")


func test_load_refuses_other_versions_and_damaged_data() -> void:
	var w: HouseWorld = await _world()
	w.build_walls([Vector3i(0, 11, 0)])
	var d := w.save_data()
	var bad := [
		{"version": 99}, {"layout": "some-other-house"}, {"cells": 12},
		{"objects": [{"kind": "piano", "x": 1.0, "y": 1.0, "rot": 0, "hp": 3}]},
		{"objects": [{"kind": "door", "x": 1.0, "y": 1.0, "rot": 0, "hp": 500}]},
		{"built": [[3, 1, 1]]},
		{"current": {"removed": {"n": 1, "idx": PackedInt32Array([2000000000]).to_byte_array().compress(FileAccess.COMPRESSION_ZSTD)},
			"set": {"n": 0, "idx": PackedByteArray(), "mat": PackedByteArray(), "col": PackedByteArray(), "pcol": PackedByteArray(), "pmask": PackedByteArray()}}},
		{"design": "not a diff"},
	]
	for patch in bad:
		var dd := d.duplicate(true)
		dd.merge(patch, true)
		var w2 := HouseWorld.new()
		add(w2)
		check(not w2.load_data(dd), "refused: %s" % str(patch.keys()))
		check(w2.grid == null and w2.get_child_count() == 0, "nothing built after a refusal")
	check(not HouseWorld.new().load_data({}), "an empty dictionary is refused")


func test_furniture_is_meshes_with_layered_collision_and_cutaway() -> void:
	var w: HouseWorld = await _world()
	var expected := 0
	for f in HousePlan.FURNITURE + HousePlan.PROPS:
		if f["type"] != "rug":
			expected += 1
			check(w.get_node_or_null("Prop_" + f["id"]) != null, "mesh for %s" % f["id"])
	var n := 0
	for c in w.get_children():
		if c.name.begins_with("Prop_"):
			n += 1
	check_eq(n, expected, "one PropKit mesh per furniture and yard prop")
	var tall: StaticBody3D = w.get_node("Body_wardrobe")
	var low: StaticBody3D = w.get_node("Body_sofa")
	check_eq(tall.collision_layer, 1, "tall furniture on layer 1 (stops bullets)")
	check(tall.has_meta("impact"), "with an impact kind for fx")
	check_eq(low.collision_layer, 16, "low furniture on layer 5")
	# no furniture voxels in the structure-only house
	var fridge := w.grid.cell_of(Vector3(8.5, 1.0, 0.55))
	check_eq(w.grid.get_mat(fridge.x, fridge.y, fridge.z), VoxelMat.AIR, "no voxel fridge")
	# cutaway: the bookshelf stands between the camera and a player in the bedroom
	var cam := Camera3D.new()
	add(cam)
	var player := Vector3(0.9, 0, 3.0)
	cam.global_position = player + Vector3(0, 1, 0) + Vector3(0, sin(deg_to_rad(56.0)), cos(deg_to_rad(56.0))) * 20.0
	w.update_view(player, cam, 0.016)
	check(w.is_prop_cut("bookshelf"), "a tall prop between camera and player is hidden")
	check(not w.is_prop_cut("fridge"), "a tall prop elsewhere stays")
	var shelf: Node = w.get_node("Prop_bookshelf")
	var geos := shelf.find_children("*", "GeometryInstance3D", true, false)
	check(not geos.is_empty() and (geos[0] as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "hidden but still casting its shadow")
	var p := Vector3(12.0, 0, 6.5)
	cam.global_position = p + Vector3(0, 1, 0) + Vector3(0, sin(deg_to_rad(56.0)), cos(deg_to_rad(56.0))) * 20.0
	w.update_view(p, cam, 0.016)
	check(not w.is_prop_cut("bookshelf"), "shown again when the player moves away")


func test_no_power_night_lights() -> void:
	var w: HouseWorld = await _world(true)
	var lit := 0
	for o in w.lighting.practicals:
		lit += 1 if o.get_meta("night_energy") > 0.0 else 0
	check_eq(lit, 0, "the house fixtures stay dark (no grid power)")
	check(w.night_lights.size() >= 5, "candles and lanterns (%d)" % w.night_lights.size())
	var shadows := 0
	for l in w.night_lights:
		shadows += 1 if (l["light"] as OmniLight3D).shadow_enabled else 0
	check(shadows >= 2 and shadows <= 3, "only 2-3 of them cast shadows (%d)" % shadows)
	w.lighting.set_amount(1.0)
	await frames(2)
	var e: float = (w.night_lights[0]["light"] as OmniLight3D).light_energy
	check(e > 0.5 and (w.night_lights[0]["light"] as OmniLight3D).visible, "lit at night (%.2f)" % e)
	w.lighting.set_amount(0.0)
	await frames(2)
	check(not (w.night_lights[0]["light"] as OmniLight3D).visible, "out by day")


func test_psychos_path_to_a_closed_door_and_bash_through_it() -> void:
	var w: HouseWorld = await _world()
	var player := VoxelPlayer.new()
	player.input_enabled = false
	add(player)
	player.global_position = Vector3(4.6, 0, 7.4)
	var e := VoxelEnemy.new()
	e.setup(w.nav, player, 1)
	add(e)
	e.global_position = Vector3(4.4, 0, 11.6)
	e.wall_swing.connect(func(en: VoxelEnemy, target: Vector2) -> void: w.enemy_strike(en.global_position, target))
	var before := w.grid.solid_count
	var t := 0.0
	var broke_at := -1.0
	var inside := false
	while t < 60.0 and not inside:
		await seconds(0.25)
		t += 0.25
		player.global_position = Vector3(4.6, 0, 7.4)
		if broke_at < 0.0 and w.count_objects("door") < 2:
			broke_at = t
		inside = e.global_position.z < 8.6
	print("    one psycho broke the front door after %.1f s and was inside after %.1f s (%d wall voxels bitten)" % [broke_at, t, before - w.grid.solid_count])
	check(broke_at > 0.0, "the closed door was bashed down")
	check(inside, "and the psycho came in through the doorway (%.1f s)" % t)


func test_version_a_voxel_furniture_flag() -> void:
	var w := HouseWorld.new()
	w.voxel_furniture = true
	w.damage_quantum = 1
	add(w)
	w.build_new()
	await physics_frames(2)
	var fridge := w.grid.cell_of(Vector3(8.5, 1.0, 0.55))
	check(w.grid.get_mat(fridge.x, fridge.y, fridge.z) != VoxelMat.AIR, "voxel furniture is back (the fridge is voxels)")
	check(w.get_node_or_null("Prop_fridge") == null, "and there are no furniture meshes")
	check(w.yard.voxel_props, "the yard builds its voxel props")
	check(w.exit_path_exists(), "the same rules apply")
	check(w.layout_id() != HouseWorld.new().layout_id(), "saves of the two looks don't mix")


## Experiment 003: shoot's optional max_range (the shotgun's 14 m).
func test_shoot_respects_max_range() -> void:
	var w: HouseWorld = await _world()
	var o := Vector3(8.5, 1.3, 25.0)
	var far := w.shoot(o, Vector3(8.5, 1.0, 9.0) - o, [], Vector3.INF, 14.0)
	check_eq(far["kind"], "none", "a wall 16 m away is out of a 14 m range")
	check(far["pos"].distance_to(o) < 14.01, "the shot ends at its range")
	var near := w.shoot(o, Vector3(8.5, 1.0, 9.0) - o, [])
	check_eq(near["kind"], "voxel", "with the default range it hits the wall")
