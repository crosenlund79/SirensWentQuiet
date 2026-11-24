extends "res://tests/test_case.gd"
## Experiment 004 (agent D): the furniture lifecycle (intact mesh -> voxels
## -> rubble), furniture and original structures demolished for salvage,
## full refunds for the player's pieces, the door that steps the player
## clear, window boards, door reinforcement and metal doors, the fuse box,
## persistence of all of it, and a destruction stress test whose costs stay
## flat.


func _world() -> HouseWorld:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	await physics_frames(2)
	return w


func _build_mode(w: HouseWorld, unlimited := true) -> Array:
	var s := GameState.new_run(7)
	s.cheats["unlimited"] = unlimited
	var b := BuildMode.new()
	b.setup(w, s, null, null)
	add(b)
	await physics_frames(1)
	return [s, b]


func _furniture_voxels(w: HouseWorld, id: String) -> int:
	return w.furniture._count_voxels(w.furniture.pieces[id])


func _body(layer: int, at: Vector3) -> CharacterBody3D:
	var b := CharacterBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = Tuning.PLAYER_RADIUS
	cyl.height = 1.6
	cs.shape = cyl
	cs.position.y = 0.9
	b.add_child(cs)
	add(b)
	b.global_position = at
	return b


func test_a_shot_fridge_turns_to_voxels_then_to_rubble() -> void:
	var w: HouseWorld = await _world()
	var changed := []
	w.furniture_changed.connect(func(id: String) -> void: changed.append(id))
	check_eq(w.furniture.state_of("fridge"), "intact", "starts intact")
	check(w.get_node_or_null("Prop_fridge") != null, "as a mesh")
	check_eq(_furniture_voxels(w, "fridge"), 0, "with no voxels")
	var o := Vector3(8.5, 1.2, 3.2)
	var t := Vector3(8.5, 1.1, 0.55)
	var r := w.shoot(o, t - o, [])
	check_eq(r["kind"], "voxel", "the first shot hits the fridge's voxels")
	check_eq(w.furniture.state_of("fridge"), "damaged", "damaged after one shot")
	check(w.furniture.pieces["fridge"]["node"] == null, "the mesh is gone")
	check(_furniture_voxels(w, "fridge") > 100, "the fridge is voxels now (%d)" % _furniture_voxels(w, "fridge"))
	check(w.furniture_ok("fridge"), "still works while damaged")
	check(changed.has("fridge"), "furniture_changed fired")
	var shots := 1
	while w.furniture_ok("fridge") and shots < 60:
		w.shoot(o, t + Vector3(randf_range(-0.25, 0.25), randf_range(-0.5, 0.5), 0) - o, [])
		shots += 1
	check_eq(w.furniture.state_of("fridge"), "destroyed", "destroyed after %d shots" % shots)
	check(not w.furniture_ok("fridge"), "furniture_ok is false")
	check_eq(_furniture_voxels(w, "fridge"), 0, "no voxels left")
	check(w.furniture.pieces["fridge"]["rubble"] != null, "rubble marks the spot")
	check(w.nav.get_raw(w.nav.cell_of(Vector2(8.5, 0.55))) != GridNav.WALL, "navigation opened")
	check(not w.furniture_in(Rect2(8.3, 0.3, 0.4, 0.4)), "and it no longer counts as furniture for building")
	print("    fridge: %d shots; voxelise %.1f ms, destroy %.1f ms" % [shots, w.furniture.stats["voxelise_ms"], w.furniture.stats["destroy_ms"]])


func test_enemy_blows_and_blasts_damage_furniture() -> void:
	var w: HouseWorld = await _world()
	var sofa := Vector2(4.5, 7.05)
	check_eq(w.nav.get_raw(w.nav.cell_of(sofa)), GridNav.WALL, "a standing sofa is bashable (WALL)")
	var hp0: int = w.furniture.pieces["sofa"]["hp"]
	w.enemy_strike(Vector3(4.5, 0, 8.2), sofa)
	check(int(w.furniture.pieces["sofa"]["hp"]) < hp0, "a blow costs it HP")
	check_eq(w.furniture.state_of("sofa"), "damaged", "and voxelises it")
	for k in 20:
		w.enemy_strike(Vector3(4.5, 0, 8.2), sofa)
	check_eq(w.furniture.state_of("sofa"), "destroyed", "enough blows smash it")
	check(w.nav.is_walkable(w.nav.cell_of(sofa)) or w.nav.get_raw(w.nav.cell_of(sofa)) == GridNav.OPEN, "its cells open")
	var out := w.explode(Vector3(7.8, 0.6, 5.65), 1.6, 24.0)
	check(out["furniture"].has("dining_table"), "a blast at the dining table destroys it (%s)" % str(out["furniture"]))
	check(not w.furniture_ok("dining_chair_1"), "and the chairs around it")
	print("    blast in the dining room: %.1f ms, furniture destroyed %s" % [out["ms"], str(out["furniture"])])


func test_demolish_furniture_and_original_structures_for_salvage() -> void:
	var w: HouseWorld = await _world()
	var sb: Array = await _build_mode(w, false)
	var s: GameState = sb[0]
	var b: BuildMode = sb[1]
	b.select_id("demolish")
	var inv := {}
	for k in ["wood", "nails", "scrap", "iron"]:
		inv[k] = s.inventory.count(k)
	var r := b.evaluate(Vector2(4.5, 7.05))
	check_eq(r.get("furniture", ""), "sofa", "the demolish tool finds the sofa")
	check_eq(r["refund"], {"wood": 2, "nails": 3, "scrap": 1}, "sofa salvage")
	check(b.apply(Vector2(4.5, 7.05)), "taken apart")
	check_eq(w.furniture.state_of("sofa"), "removed", "removed")
	check_eq(s.inventory.count("scrap"), inv["scrap"] + 1, "scrap back")
	check(w.nav.is_walkable(w.nav.cell_of(Vector2(4.5, 7.05))), "the floor is free")
	check(b.apply(Vector2(8.52, 0.55)), "the fridge")
	check_eq(s.inventory.count("iron"), inv["iron"] + 2, "2 iron from the fridge")
	# a window: knocked out for salvage
	var scrap := s.inventory.count("scrap")
	r = b.evaluate(Vector2(1.5, 0.0))
	check(r.get("window", false) and r["ok"], "the bedroom window can be knocked out (%s)" % r["reason"])
	check(b.apply(Vector2(1.5, 0.0)), "knocked out")
	check_eq(s.inventory.count("scrap"), scrap + 2, "window salvage: 2 scrap")
	check(not w.section_info(Vector3i(0, 0, 1))["glass"], "no glass left there")
	check(w.exit_path_exists(), "still a way out")
	# an original door: half its cost
	var nails := s.inventory.count("nails")
	check(b.apply(Vector2(14.0, 6.5)), "the back door")
	check_eq(s.inventory.count("nails"), nails + 3, "half the door's nails")
	# a player-built crate: its full cost
	s.inventory.add("wood", 3)
	s.inventory.add("nails", 4)
	b.select_id("crate")
	check(b.apply(Vector2(12.0, 6.25)), "crate built")
	var wood := s.inventory.count("wood")
	b.select_id("demolish")
	check(b.apply(Vector2(12.0, 6.25)), "crate taken down")
	check_eq(s.inventory.count("wood"), wood + 3, "the crate's full cost back")
	check_eq(BuildPieces.object_refund("door", "iron", false), {"wood": 2, "nails": 7, "iron": 3}, "a reinforced original door: half the door plus the plating")


func test_closing_a_door_steps_the_player_clear_but_not_an_enemy() -> void:
	var w: HouseWorld = await _world()
	var front: WorldObject = w.object_at(Vector2(4.5, 9.0))
	w.set_door_open(front, true)
	await physics_frames(2)
	var p := _body(1 << 2, Vector3(4.6, 0, 8.85))
	await physics_frames(2)
	check(w.bodies_in(front.footprint().grow(0.05)), "the player stands in the doorway")
	check_eq(w.toggle_door(front), "", "closing works anyway")
	check(not front.open, "closed")
	check(p.global_position.z < 9.0 - 0.4 and absf(p.global_position.x - 4.5) <= 0.26, "the player stepped inside (%s)" % str(p.global_position))
	await physics_frames(2)
	check(not w.bodies_in(front.footprint().grow(0.05)), "the doorway is clear")
	check_eq(w.toggle_door(front), "", "opens again")
	await physics_frames(2)
	var e := _body(1 << 3, Vector3(4.5, 0, 9.05))
	await physics_frames(2)
	check_eq(w.toggle_door(front), "Something is in the way.", "an enemy in the doorway blocks it")
	check(front.open, "still open")
	e.queue_free()


func test_window_boards_reinforced_and_metal_doors() -> void:
	var w: HouseWorld = await _world()
	var sb: Array = await _build_mode(w)
	var b: BuildMode = sb[1]
	b.select_id("window_boards")
	check_eq(b.evaluate(Vector2(4.5, 0.0))["reason"], "Window boards go over a window.", "not on a plain wall")
	check(b.apply(Vector2(1.5, 0.0)), "boards over the bedroom window")
	var bo: WorldObject = w.object_at(Vector2(1.5, 0.0))
	check(bo != null and bo.kind == "boards", "window boards hang there")
	if bo == null:
		return
	check_eq(bo.facing(), "N", "on the outside")
	check_eq(b.evaluate(Vector2(1.5, 0.0))["reason"], "This window is already boarded up.", "only once")
	var missing := w.section_missing(Vector3i(0, 0, 1))
	w.enemy_strike(Vector3(1.5, 0, -0.8), Vector2(1.5, 0.0))
	check(bo.hp < bo.max_hp, "an enemy hits the boards first")
	check_eq(w.section_missing(Vector3i(0, 0, 1)), missing, "not the window")
	var hp := bo.hp
	var o := Vector3(1.5, 1.4, -3.0)
	w.shoot(o, Vector3(1.5, 1.4, 0.0) - o, [])
	check_eq(bo.hp, hp - 1, "bullets hit boards")
	var kinds := []
	for wp in w.weak_points(Vector2(1.5, -4.0)):
		kinds.append(wp["kind"])
	check(kinds.has("boards"), "boards are a bomber target")
	# Reinforce: wood -> reinforced -> metal
	var back: WorldObject = w.object_at(Vector2(14.0, 6.5))
	b.select_id("upgrade")
	var r := b.evaluate(Vector2(14.0, 6.5))
	check_eq(r["cost"], {"iron": 3, "nails": 4}, "reinforcing costs iron and nails")
	check(b.apply(Vector2(14.0, 6.5)), "reinforced")
	check_eq(back.mat, "iron", "a reinforced door")
	check_eq(back.max_hp, 42, "with the reinforced door's HP")
	check(b.apply(Vector2(14.0, 6.5)), "and again")
	check_eq(back.mat, "metal", "a metal door")
	check_eq(back.hp, 70, "70 HP")
	check_eq(b.evaluate(Vector2(14.0, 6.5))["reason"], "Already a metal door.", "the end of the line")
	# a new metal door
	b.select_id("metal_door")
	check(b.apply(Vector2(14.0, 3.5)), "a metal door cut into the kitchen wall")
	var md: WorldObject = w.object_at(Vector2(14.0, 3.5))
	check(md != null and md.mat == "metal" and md.hp == 70, "metal, 70 HP")
	var ld := Vector3(16.0, 1.2, 3.5)
	w.shoot(ld, Vector3(14.0, 1.2, 3.5) - ld, [])
	check_eq(md.hp, 69, "a bullet dents it")
	var wp_md := {}
	for wp in w.weak_points(Vector2(17.0, 3.5)):
		if wp["object"] == md:
			wp_md = wp
	check(not wp_md.is_empty() and float(wp_md["strength"]) > 3.5, "a strong bomber target")
	var saved := w.save_data()
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(saved), "saved and loaded")
	var md2: WorldObject = w2.object_at(Vector2(14.0, 3.5))
	check(md2 != null and md2.mat == "metal" and md2.hp == 69, "the metal door persists")
	check(w2.object_at(Vector2(1.5, 0.0)) != null and w2.object_at(Vector2(1.5, 0.0)).kind == "boards", "the boards persist")


func test_fuse_box_contract_rebuild_and_persistence() -> void:
	var w: HouseWorld = await _world()
	var fb := w.fuse_box()
	check(fb != null, "the house has a fuse box")
	if fb == null:
		return
	check(fb.pos.distance_to(HouseWorld.FUSE_BOX_AT) < 0.01 and fb.mains_on, "in the utility room, mains on")
	check_eq(fb.interact_prompt(), "[E] Switch the main power off", "its prompt")
	check(w.interactables().has(fb), "an interactable")
	check(not w.furniture_in(fb.footprint()) and w.objects_in(fb.footprint()).size() == 1, "clear of furniture")
	var n := [0]
	w.power_changed.connect(func() -> void: n[0] += 1)
	fb.interact(null)
	check(not fb.mains_on and n[0] == 1, "E switches the power off and power_changed fires")
	check_eq(fb.interact_prompt(), "[E] Switch the main power on", "then offers on")
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(w.save_data()), "saved and loaded")
	check(w2.fuse_box() != null and not w2.fuse_box().mains_on, "the switch state persists")
	w.damage_object(fb, 100, Vector3(12.0, 1.0, 8.0))
	check(w.fuse_box() == null and n[0] == 2, "destroyed: gone, power_changed fired")
	var sb: Array = await _build_mode(w)
	var b: BuildMode = sb[1]
	b.select_id("fuse_box")
	var r := b.evaluate(Vector2(13.85, 7.5))
	check(r["ok"], "a new one can go on the east wall (%s)" % r["reason"])
	check(b.apply(Vector2(13.85, 7.5)), "built")
	var nb := w.fuse_box()
	check(nb != null and nb.facing() == "W" and nb.pos.x < 13.85, "on the inside, facing the room (%s)" % (str(nb.pos) if nb != null else "none"))
	check_eq(n[0], 3, "power_changed on rebuild")
	check_eq(b.evaluate(Vector2(13.85, 2.5))["reason"], "There's already a fuse box.", "only one")
	w.damage_object(nb, 100)
	w.repair_all()
	check(w.fuse_box() != null, "repair everything brings one back")
	var o := Vector3(12.0, 1.4, 8.3)
	var hp := w.fuse_box().hp
	w.shoot(o, Vector3(13.8, 1.4, 8.3) - o, [])
	check_eq(w.fuse_box().hp, hp - 1, "bullets damage it")
	var out := w.explode(Vector3(13.0, 1.0, 8.3), 1.6, 24.0)
	check(out["destroyed"].has("fuse_box"), "a blast next to it destroys it")


func test_furniture_states_persist_and_old_saves_load() -> void:
	var w: HouseWorld = await _world()
	w.furniture.strike("wardrobe", 2, Vector3(3.5, 0, 1.2))
	w.furniture.destroy("sofa")
	w.demolish_furniture("dining_chair_1")
	var left: int = w.furniture.pieces["wardrobe"]["left"]
	var hp: int = w.furniture.pieces["wardrobe"]["hp"]
	var d := w.save_data()
	check(d.has("furniture") and d["furniture"].size() == 3, "three pieces saved (%s)" % str(d.get("furniture")))
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(d), "loads")
	await physics_frames(2)
	check_eq(w2.furniture.state_of("wardrobe"), "damaged", "the wardrobe is still damaged")
	check_eq(int(w2.furniture.pieces["wardrobe"]["hp"]), hp, "with its HP")
	check_eq(int(w2.furniture.pieces["wardrobe"]["left"]), left, "and its voxels")
	check(w2.furniture.pieces["wardrobe"]["node"] == null, "no mesh")
	check_eq(w2.furniture.state_of("sofa"), "destroyed", "the sofa is rubble")
	check(w2.furniture.pieces["sofa"]["rubble"] != null, "rubble rebuilt")
	check_eq(w2.furniture.state_of("dining_chair_1"), "removed", "the chair is gone")
	check(w2.nav.is_walkable(w2.nav.cell_of(Vector2(4.5, 7.05))), "the sofa's floor is walkable")
	check(w2.furniture_ok("sink_counter") and w2.furniture_ok("fridge"), "the kitchen works")
	# a save from before Experiment 004: every piece intact, the pristine fuse box added
	var old := d.duplicate(true)
	old.erase("furniture")
	old.erase("exp4")
	var objs := []
	for e in old["objects"]:
		if e["kind"] != "fuse_box":
			objs.append(e)
	old["objects"] = objs
	var w3 := HouseWorld.new()
	add(w3)
	check(w3.load_data(old), "an Experiment 003 save loads")
	check_eq(w3.furniture.state_of("sofa"), "intact", "with its furniture intact")
	check(w3.fuse_box() != null, "and the pristine fuse box")
	w2.repair_all()
	check_eq(w2.furniture.count(HouseFurniture.INTACT), w2.furniture.pieces.size(), "repair everything restores all furniture")
	check_eq(w2.furniture._count_voxels(w2.furniture.pieces["wardrobe"]), 0, "as meshes")


## The stress test: 30 blasts and 300 shots; blast cost, frame time, nodes
## and active debris stay flat.
func test_destruction_costs_stay_flat() -> void:
	var w: HouseWorld = await _world()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var area := HousePlan.FOOTPRINT.grow(1.0)
	var batches := []
	var nodes0 := w.get_child_count()
	for batch in 3:
		var blast_ms := []
		for k in 10:
			var at := Vector3(rng.randf_range(area.position.x, area.end.x), 1.0, rng.randf_range(area.position.y, area.end.y))
			blast_ms.append(float(w.explode(at, 1.5, 24.0)["ms"]))
			await frames(2)
		var t0 := Time.get_ticks_usec()
		for k in 100:
			var o := Vector3(rng.randf_range(-3.0, 17.0), 1.2, rng.randf_range(-2.5, 11.5))
			var t := Vector3(rng.randf_range(0.0, 14.0), rng.randf_range(0.3, 2.0), rng.randf_range(0.0, 9.0))
			w.shoot(o, t - o, [])
		var shot_ms := (Time.get_ticks_usec() - t0) / 1000.0 / 100.0
		var f0 := Time.get_ticks_usec()
		await frames(30)
		var frame_ms := (Time.get_ticks_usec() - f0) / 1000.0 / 30.0
		var avg := 0.0
		for m in blast_ms:
			avg += m
		avg /= blast_ms.size()
		batches.append({"blast": avg, "max": blast_ms.max(), "shot": shot_ms, "frame": frame_ms, "nodes": w.get_child_count(),
			"debris": w.fx.debris_count, "faces": w.chunks.face_count, "destroyed": w.furniture.count(HouseFurniture.DESTROYED)})
	for k in batches.size():
		var bt: Dictionary = batches[k]
		print("    batch %d (blasts %d-%d, shots %d-%d): blast %.1f ms avg / %.1f max, shot %.2f ms, frame %.2f ms, world nodes %d, debris %d, faces %d, furniture destroyed %d" % [
			k + 1, k * 10 + 1, k * 10 + 10, k * 100 + 1, k * 100 + 100, bt["blast"], bt["max"], bt["shot"], bt["frame"], bt["nodes"], bt["debris"], bt["faces"], bt["destroyed"]])
	var first: Dictionary = batches[0]
	var last: Dictionary = batches[2]
	check(float(last["blast"]) < float(first["blast"]) * 2.0 + 20.0, "blast cost stays flat (%.1f -> %.1f ms)" % [first["blast"], last["blast"]])
	check(float(last["frame"]) < float(first["frame"]) * 2.0 + 8.0, "frame time stays flat (%.2f -> %.2f ms)" % [first["frame"], last["frame"]])
	check(int(last["nodes"]) <= nodes0 + 8, "no node build-up (%d -> %d)" % [nodes0, last["nodes"]])
	check(int(last["debris"]) <= VoxelFx.MAX_DEBRIS, "debris is capped")
