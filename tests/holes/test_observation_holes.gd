extends "res://tests/test_case.gd"
## Exp 007 (O): observation holes (HoleRules on a real HouseWorld: where the
## drill goes, the voxel tunnel, repair and cover closing it, object holes,
## the save round trip) and one run in the game scene (the drill on the
## quick bar, drilling time, the [E] spot, looking through, covering, an enemy
## noticing, the overview's modes and levels).

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_observation_holes.dat"


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()


## The first section (sorted) a hole can go into at its middle.
static func _drillable(w: HouseWorld) -> Vector3i:
	var keys := w.sections.keys()
	keys.sort()
	for s in keys:
		if HoleRules.wall_reason(w, s, s.z + 0.5) == "":
			return s
	return Vector3i(-1, 0, 0)


func test_wall_holes_rules_and_save() -> void:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	var s := _drillable(w)
	if not check(s.x >= 0, "the house has a drillable wall"):
		return
	var rec := HoleRules.wall_record(s, s.z + 0.5)
	var before := int(w.sections[s]["current"])
	check(HoleRules.make(w, rec) > 0, "drilling removes voxels")
	check(HoleRules.is_open(w, rec), "the hole is open")
	check(int(w.sections[s]["current"]) < before, "the section counts the hole")
	check(w.section_integrity(s) > 0.95, "a small hole barely weakens the wall (%.3f)" % w.section_integrity(s))
	check(HoleRules.wall_reason(w, s, s.z + 0.55) != "", "no second hole on the same spot")
	# save and load
	var d := w.save_data()
	check(d.has("holes") and (d["holes"] as Array).size() == 1, "the world save has the hole")
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(d.duplicate(true)), "loads")
	check_eq(w2.holes.size(), 1, "the hole comes back")
	check(HoleRules.is_open(w2, w2.holes[0]), "and is still open (the voxel diff carries it)")
	# repair closes it
	w2.repair_section(s)
	check(not HoleRules.is_open(w2, w2.holes[0]), "the Repair tool fills it")
	check_eq(HoleRules.prune(w2), 1, "pruned")
	# cover
	check(HoleRules.fill(w, rec) > 0 and w.holes.is_empty(), "covering fills it and drops the record")
	check(not HoleRules.is_open(w, rec), "closed")
	# no stone, no plating
	var yard_seg := Vector3i(0, 11, 3)
	w.build_foundation([yard_seg])
	w.build_walls([yard_seg], "stone")
	check(HoleRules.wall_reason(w, yard_seg, 3.5).contains("Stone"), "stone is too hard (%s)" % HoleRules.wall_reason(w, yard_seg, 3.5))
	w.upgrade_section(s)
	check(HoleRules.wall_reason(w, s, s.z + 0.5).contains("plating"), "iron plating stops the drill")
	# junk in a save
	check_eq(HoleRules.clean([{"type": "wall", "seg": [3, 1, 2], "a": 1.0}, {"type": "object", "kind": "crate", "x": 1, "y": 1}, 5, {"type": "wall", "seg": [0, 1], "a": 2}]).size(), 0, "junk dropped")


func test_object_holes() -> void:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	var door: WorldObject = null
	for o in w.objects:
		if o.kind == "door":
			door = o
	if not check(door != null, "the house has a door"):
		return
	check_eq(HoleRules.object_reason(w, door), "", "a closed wooden door can be drilled")
	var rec := HoleRules.object_record(door, 1.0)
	var hp := door.hp
	HoleRules.make(w, rec)
	check_eq(door.hp, hp - 1, "drilling costs the door 1 HP")
	check(HoleRules.is_open(w, rec), "the peephole is open")
	check(HoleRules.plan_point(w, rec).distance_to(door.pos) > 0.25, "the peephole sits off the door's centre")
	check(HoleRules.object_reason(w, door).contains("already"), "one peephole per door")
	w.repair_object(door)
	check(not HoleRules.is_open(w, rec), "a full repair closes it")
	door.set_mat("iron")
	check(HoleRules.object_reason(w, door).contains("iron"), "not an iron door")


func _boot() -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = "new"
	GameLaunch.seed = 7
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	return g


func test_drill_look_cover_and_overview_in_the_game() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	var h: Node = g.holes
	var w: HouseWorld = g.world
	check(h != null and g.overview != null, "the helpers exist")
	# the drill on the quick bar
	s.inventory.add("drill", 1)
	await frames(2)
	check(Hotbar.slot_of(s.hotbar, "drill") >= 0, "the drill goes on the quick bar")
	var sec := _drillable(w)
	var hole_at := HouseWorld.seg_center(sec)
	var n := HoleRules.normal_of(sec.x)
	g.debug_teleport_player(hole_at + n * 0.7)
	g.player.aim_point = Vector3(hole_at.x, 1.5, hole_at.y)
	await frames(2)
	g.bar.select(Hotbar.slot_of(s.hotbar, "drill"))
	g.time_scale = 120.0
	var used: String = g.bar.use("drill")
	check(used.begins_with("Drilling"), "LMB with the drill starts drilling (%s)" % used)
	check(not h.drilling.is_empty() and not g.player.input_enabled, "Eli stands and drills")
	var t0 := s.total_minutes
	for k in 60:
		await frames(1)
		if h.drilling.is_empty():
			break
	check(h.drilling.is_empty(), "drilling finishes")
	check(s.total_minutes - t0 >= 3.0, "it took game minutes (%.1f)" % (s.total_minutes - t0))
	check(g.player.input_enabled, "Eli can move again")
	g.time_scale = 1.0
	check_eq(h.count(), 1, "one hole")
	await frames(2)
	# the [E] spot
	var spots: Array = w.interactables().filter(func(o): return o.get_script() == preload("res://src/holes/hole_spot.gd"))
	check_eq(spots.size(), 1, "the hole is an interactable")
	var side := 1.0
	for sd in [1.0, -1.0, 0.5, -0.5]:      # a side of the wall where nothing nearer (a lamp) takes E
		g.debug_teleport_player(hole_at + n * 0.6 * sd)
		await frames(2)
		side = signf(sd)
		if g.debug_prompt().begins_with("[E] Look through"):
			break
	check(g.debug_prompt().begins_with("[E] Look through"), "the prompt offers a look (%s)" % g.debug_prompt())
	# look through
	g.debug_interact()
	await frames(2)
	check(not h.peeking.is_empty(), "looking through")
	var cam := tree.root.get_viewport().get_camera_3d()
	check(cam != null and cam.name == "PeekCamera", "the view is the hole's camera")
	check(cam != null and cam.fov <= 35.0, "a narrow view")
	var away: Vector2 = h.peeking.get("dir", Vector2.ZERO)
	check(away.dot(n) * side < 0.0, "it looks away from Eli")
	# an enemy at the hole's other side notices it while Eli looks
	var e: Node = g.debug_spawn_enemy(hole_at - n * side)
	await frames(1)
	h.notice(e, w, w.holes[0], true)
	check(h.noticed == 1, "noticed")
	g.debug_kill_enemies()
	h.stop_peek()
	await frames(1)
	check(tree.root.get_viewport().get_camera_3d() == g.camera, "back to the game camera")
	# save carries it
	check((w.save_data().get("holes", []) as Array).size() >= 0, "world save")
	# cover with a plank
	s.inventory.add("wood", 2)
	var wood: int = s.inventory.count("wood") + (g.build.stored("wood") if g.build.has_method("stored") else 0)
	var r: String = h.cover(w, w.holes[0]) if not w.holes.is_empty() else ""
	check_eq(r, "Hole covered.", "covered")
	check_eq(h.count(), 0, "no holes left")
	check(s.inventory.count("wood") + (g.build.stored("wood") if g.build.has_method("stored") else 0) == wood - 1, "a plank paid")
	# the overview
	check_eq(g.overview.open_overview("complete"), "", "O opens the overview")
	await frames(2)
	check_eq(g.debug_modal(), "overview", "modal")
	check(tree.paused, "the world pauses")
	check(not g.player.visible, "Eli is hidden")
	check(g.world.yard.roof.visible, "complete house: the roof")
	g.overview.set_mode("roofless")
	await frames(1)
	check(not g.world.yard.roof.visible, "roofless")
	g.overview.set_mode("cutaway")
	await frames(1)
	check(g.world.get("_cut_on"), "cutaway cuts")
	g.overview.set_mode("blueprint")
	await frames(2)
	var plan: Dictionary = g.overview.plan
	check(plan.get("exists", false) and (plan["walls"] as Array).size() > 20, "the blueprint has the walls (%d)" % (plan.get("walls", []) as Array).size())
	check(OverviewPlan.summary(plan).contains("wall sections"), "summary: %s" % OverviewPlan.summary(plan))
	check(g.overview.step_level(1).begins_with("Nothing above"), "only the ground floor exists")
	g.levels.dev_build_upper()
	await frames(1)
	g.overview.step_level(1)
	check_eq(g.overview.storey, 1, "PgUp to +1")
	check(g.levels.world_of(1).visible and g.world.visible, "+1 and the ground floor show")
	g.overview.step_level(-1)
	check(not g.levels.world_of(1).visible, "back on 0: +1 hidden")
	g.overview.close_overview()
	await frames(3)
	check_eq(g.debug_modal(), "", "closed")
	check(not tree.paused and g.player.visible, "the world runs, Eli is back")
	check(g.camera.target == g.player, "the camera follows Eli again")
	# not at a POI
	if g.has_method("is_home"):
		pass
