extends "res://tests/test_case.gd"
## Experiment 005 (V): five levels (-2..+2) with one set of rules. Pure
## stairs geometry for any two adjacent storeys, the -2 and +2 worlds, the
## floor-cell support grid and pillars, and one run in the real game scene
## through build mode and the real camera: stairs up, the next storey, PageUp
## to build on it from below, +2 from +1, walls, a door, floor tiles,
## demolish and replace upstairs, digging down to -2 with stairs, the level
## indicator, an enemy following down two storeys, save and continue.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_five_levels.dat"


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()


func test_stairs_between_any_two_storeys() -> void:
	check_eq(Levels.label(1), "Level +1 · First upper floor", "label")
	check_eq(Levels.label(-2), "Level -2 · Lower basement", "label below")
	check_eq(Levels.storey_at(5.8), Levels.UPPER2, "+2 by height")
	check_eq(Levels.storey_at(-5.8), Levels.LOWER_BASEMENT, "-2 by height")
	check_eq(Levels.storey_at(12.0), Levels.HIGHEST, "nothing above +2")
	var up2 := Levels.make_stairs(Levels.UPPER, Vector2i(2, 6), 1)
	check(Levels.is_up(up2) and Levels.start_storey(up2) == Levels.UPPER, "stairs +1 -> +2 start on +1")
	check(Levels.exit_point(up2, Levels.UPPER).is_equal_approx(Vector2(1.5, 6.5)), "foot exit on +1")
	check(Levels.exit_point(up2, Levels.UPPER2).is_equal_approx(Vector2(4.5, 6.5)), "top exit on +2")
	var dn2 := Levels.make_stairs(Levels.LOWER_BASEMENT, Vector2i(5, 7), 3)
	check(not Levels.is_up(dn2) and Levels.start_storey(dn2) == Levels.BASEMENT, "stairs -1 -> -2 start on -1")
	check(Levels.exit_point(dn2, Levels.BASEMENT).is_equal_approx(Vector2(6.5, 7.5)), "top exit on -1")
	check(Levels.exit_point(dn2, Levels.LOWER_BASEMENT).is_equal_approx(Vector2(3.5, 7.5)), "bottom exit on -2")
	check(Levels.step_height(dn2, Levels.STEPS - 1) < -2.8, "descends a storey")
	var up := Levels.make_stairs(Levels.GROUND, Vector2i(8, 7), 1)
	var dn := Levels.make_stairs(Levels.BASEMENT, Vector2i(4, 6), 1)
	var all := [up, up2, dn, dn2]
	check_eq(Levels.route(all, Levels.LOWER_BASEMENT, Levels.UPPER2, Vector2(1, 1)), dn2, "-2 -> +2: up to -1 first")
	check_eq(Levels.route(all, Levels.UPPER, Levels.UPPER2, Vector2(1, 1)), up2, "+1 -> +2")
	check_eq(Levels.route(all, Levels.UPPER2, Levels.GROUND, Vector2(1, 1)), up2, "+2 -> 0: down to +1 first")
	check_eq(Levels.stairs_from_array(Levels.stairs_to_array(dn2)), dn2, "-2 stairs serialise")
	check_eq(Levels.stairs_from_array(Levels.stairs_to_array(up2)), up2, "+1 stairs serialise")
	check(Levels.stairs_from_array([2, 3, 3, 0]) == null and Levels.stairs_from_array([-3, 3, 3, 0]) == null, "nothing past -2 / +2")


func test_lower_basement_and_second_upper_floor_worlds() -> void:
	var t := LevelWorld.new()
	t.configure(Levels.UPPER2, null)
	add(t)
	t.build_new()
	check(t.grid.origin.y > 5.0 and t.has_floor_at(Vector2(5.5, 5.5)), "+2 has a deck at its height")
	check(t.section_info(Vector3i(0, 0, 4))["wall"], "+2 has outer walls")
	var b := LevelWorld.new()
	b.configure(Levels.LOWER_BASEMENT, null)
	add(b)
	b.build_new()
	check(b.grid.origin.y < -5.0, "-2 sits under the basement")
	check(not b.nav.is_walkable(b.nav.cell_of(Vector2(4.5, 4.5))), "-2 is earth")
	check(b.dig(Vector2i(4, 4)) and b.dig(Vector2i(5, 4)), "-2 digs")
	check(b.nav.is_walkable(b.nav.cell_of(Vector2(5.0, 4.5))), "dug cells are walkable")
	var b2 := LevelWorld.new()
	b2.configure(Levels.LOWER_BASEMENT, null)
	add(b2)
	check(b2.load_data(b.save_data()) and b2.dug.size() == 2, "-2 saves and loads its dug cells")
	t.repair_all()
	check_eq(t.count_objects("fuse_box"), 0, "repairing a storey adds no fuse box")


func test_support_grid_and_pillars() -> void:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	var u := LevelWorld.new()
	u.configure(Levels.UPPER, null)
	add(u)
	u.build_new()
	await physics_frames(1)
	var sup := w.support
	sup.set_storey(Levels.UPPER, u)
	# An island of deck: the living room's middle cell with a ring of tiles taken up around it.
	var mid := Vector2i(2, 6)
	check(not HouseSupport.carried_from_below(w, mid), "no wall under the living room's middle")
	for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
		Levels.remove_floor(u, mid + d)
	w.process_structure()
	u.process_structure()
	check(not u.has_floor_at(Levels.cell_center(mid)), "a floating piece of floor falls")
	check(u.has_floor_at(Vector2(6.5, 6.5)), "the rest of the deck stands")
	check(sup.tile_support_reason(u, w, mid) != "", "a tile can't be laid in mid-air (%s)" % sup.tile_support_reason(u, w, mid))
	check_eq(sup.tile_support_reason(u, w, Vector2i(3, 6)), "", "next to the deck it can")
	# A pillar under it carries a tile.
	Levels.stamp_pillar(w, mid)
	check(Levels.pillar_stands(w, mid), "the pillar stands")
	check(HouseSupport.carried_from_below(w, mid), "it carries the cell above")
	check_eq(sup.tile_support_reason(u, w, mid), "", "a tile can go on it")
	Levels.lay_wood_floor(u, mid)
	w.process_structure()
	check(u.has_floor_at(Levels.cell_center(mid)), "and stays")
	Levels.clear_pillar(w, mid)
	check(not Levels.pillar_stands(w, mid), "the pillar is gone")
	w.process_structure()
	u.process_structure()
	check(not u.has_floor_at(Levels.cell_center(mid)), "without the pillar the tile falls")


## Stands in for GameLevels' pillar registry.
class PillarStub extends RefCounted:
	var pillars := {0: {}}
	func pillars_on(w: HouseWorld) -> Array:
		return pillars[0].keys().filter(func(c): return Levels.pillar_stands(w, c))


func test_pillars_prop_an_outer_wall() -> void:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	await physics_frames(1)
	var stub := PillarStub.new()
	w.support.levels = stub
	Levels.stamp_pillar(w, Vector2i(2, 1))
	stub.pillars[0][Vector2i(2, 1)] = true
	for k in range(0, 5):
		w.cut_opening(Vector3i(0, 0, k), true)
	w.process_structure()
	check(not w.support.roof_gone.has("bedroom"), "a pillar 1.5 m inside props the bedroom's roof over a 5 m gap")
	check(w.support.status_text().contains("1 pillar"), "the support status counts it")
	Levels.clear_pillar(w, Vector2i(2, 1))
	w.process_structure()
	check(w.support.roof_gone.has("bedroom"), "without it the roof comes down")


func _boot(mode := "new") -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 55
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	return g


## The plan point build mode picks with the mouse over world point `at`.
func _aim(g: Node, at: Vector3) -> Vector2:
	var cam: Camera3D = g.camera
	return g.build.pointer_at(cam.unproject_position(at))


func _apply(g: Node, id: String, at: Vector3, rot := 0) -> bool:
	var bm: BuildMode = g.build
	bm.select_id(id)
	bm.rot = rot
	var p := _aim(g, at)
	var ok := bm.apply(p)
	if not ok:
		check(false, "%s at %s (%s): %s" % [id, str(at), str(p), bm.last_eval.get("reason", "")])
	return ok


func _view(g: Node, dir: int) -> void:
	g.levels.step_view(dir)
	g.camera.snap()
	await frames(2)


## Walks the player onto the stairs `st` from its storey `from` (teleport onto them).
func _walk_stairs(g: Node, st: Dictionary, from: int) -> void:
	var c := Levels.stairs_rect(st).get_center()
	g.player.global_position = Vector3(c.x, Levels.base_y(from), c.y)
	await physics_frames(3)
	g.levels._cooldown = 0.0


func test_five_levels_in_the_game() -> void:
	var g: Node = await _boot()
	var lv: Node = g.levels
	var s: GameState = g.debug_state()
	var cam: VoxelCamera = g.camera
	var bm: BuildMode = g.build
	s.cheats["unlimited"] = true
	s.inventory.add("shovel", 1)
	check_eq(lv.storeys(), [0], "a new house has only the ground floor")
	check_eq(lv.indicator.text(), "Level 0 · Ground floor", "the indicator shows the level")
	g.debug_teleport_player(Vector2(3.0, 3.0))
	await frames(2)
	g._set_build(true)
	await frames(2)
	check(lv.indicator.text().begins_with("Building on Level 0 · Ground floor"), "prominent in build mode (%s)" % lv.indicator.text())
	check(not g.world.yard.roof_visible() or g.world.yard.hide_roof, "the roof never hides building")
	# --- ground: stairs up, then the next storey ---
	check(_apply(g, "stairs_up", Vector3(8.5, 0, 7.5), 1), "stairs up")
	check(_apply(g, "upper_floor", Vector3(5.0, 0, 5.0)), "next storey: +1")
	check(lv.upper != null and lv.storeys() == [0, 1], "+1 exists")
	check_eq(lv.roof_storey(), 1, "the roof sits on +1")
	# --- PageUp: build on +1 while standing on the ground ---
	var key := InputEventKey.new()
	key.keycode = KEY_PAGEUP
	key.pressed = true
	Input.parse_input_event(key)
	await frames(2)
	cam.snap()
	await frames(1)
	check_eq(lv.view_storey, 1, "PageUp shows +1")
	check_eq(lv.player_storey, 0, "the player stays on the ground")
	check(bm.world == lv.upper and is_equal_approx(bm.plane_y, Levels.HEIGHT), "build mode targets +1")
	check(is_equal_approx(cam.lift, Levels.HEIGHT), "the camera lifts to +1")
	check(lv.upper.visible and g.world.visible, "+1 and the ground below show")
	check(lv.indicator.text().contains("You are on Level 0"), "the indicator says where you are (%s)" % lv.indicator.text())
	check(_apply(g, "wall", Vector3(4.5, Levels.HEIGHT, 3.0)), "a wall on +1 from below")
	check(lv.upper.built.has(Vector3i(0, 3, 4)) and not g.world.built.has(Vector3i(0, 3, 4)), "built on +1 only")
	check(_apply(g, "stairs_up", Vector3(2.5, Levels.HEIGHT, 6.5), 1), "stairs up on +1")
	check(_apply(g, "upper_floor", Vector3(5.0, Levels.HEIGHT, 5.0)), "next storey: +2")
	check(lv.world_of(2) != null and lv.roof_storey() == 2, "+2 exists, the roof on top of it")
	await _view(g, 1)
	check_eq(lv.view_storey, 2, "PageUp shows +2")
	bm.select_id("upper_floor")
	check(bm.evaluate(Vector2(5, 5))["reason"].contains("five levels"), "nothing above +2 (%s)" % bm.evaluate(Vector2(5, 5))["reason"])
	await _view(g, 1)
	check_eq(lv.view_storey, 2, "and no higher")
	g._set_build(false)
	await frames(2)
	check_eq(lv.view_storey, 0, "leaving build mode looks at your own level again")
	check(is_equal_approx(cam.lift, 0.0), "the camera comes back down")
	# --- up the stairs to +2 ---
	await _walk_stairs(g, lv.stairs[0], 0)
	check_eq(lv.player_storey, 1, "up to +1")
	await _walk_stairs(g, lv.stairs[1], 1)
	check_eq(lv.player_storey, 2, "up to +2")
	check(absf(g.player.global_position.y - Levels.base_y(2)) < 0.01, "standing on +2")
	check_eq(lv.indicator.text(), "Level +2 · Second upper floor", "the indicator follows")
	check(lv.world_of(2).visible and lv.upper.visible and g.world.visible, "+2 and the storeys below show")
	# --- build on +2 through the real camera ---
	var top: LevelWorld = lv.world_of(2)
	var h := Levels.base_y(2)
	g._set_build(true)
	cam.snap()
	await frames(2)
	check(_apply(g, "wall", Vector3(9.5, h, 3.0)), "a wall on +2")
	check(top.built.has(Vector3i(0, 3, 9)), "on +2")
	check(_apply(g, "stone_wall", Vector3(9.5, h, 3.0)), "replaced with stone")
	check_eq(top.sections[Vector3i(0, 3, 9)]["material"], "stone", "in stone")
	check(_apply(g, "door", Vector3(8.5, h + 1.2, 0.12)), "a door in +2's north wall")
	check_eq(top.count_objects("door"), 1, "hung on +2")
	check(_apply(g, "demolish", Vector3(11.5, h, 5.5)), "a deck tile taken up on +2")
	check(not top.has_floor_at(Vector2(11.5, 5.5)), "a hole in +2")
	check(_apply(g, "wood_floor", Vector3(11.5, h, 5.5)), "a tile laid on +2 next to the deck")
	check(top.has_floor_at(Vector2(11.5, 5.5)), "closed again")
	check(_apply(g, "demolish", Vector3(9.5, h + 1.0, 3.0)), "the stone wall demolished on +2")
	check(not top.built.has(Vector3i(0, 3, 9)), "gone")
	# a pillar on +1 (PageDown from +2)
	await _view(g, -1)
	check(_apply(g, "pillar", Vector3(11.5, Levels.HEIGHT, 6.5)), "a pillar on +1")
	check(lv.pillars.get(1, {}).has(Vector2i(11, 6)) and Levels.pillar_stands(lv.upper, Vector2i(11, 6)), "it stands")
	g._set_build(false)
	await frames(2)
	# --- down to the ground and dig to -2 ---
	lv.dev_goto(0)
	g.debug_teleport_player(Vector2(1.5, 2.5))
	await frames(2)
	g._set_build(true)
	await _view(g, -1)
	check_eq(lv.view_storey, -1, "PageDown shows the (undug) basement")
	check(lv.indicator.text().contains("Not built yet") or lv.indicator.text().contains("Excavate"), "says how to make it (%s)" % lv.indicator.text())
	for j in [7, 8]:
		for i in range(5, 9):
			s.energy = 100.0
			check(_apply(g, "excavate", Vector3(i + 0.5, Levels.base_y(-1), j + 0.5)), "dig -1 (%d, %d)" % [i, j])
	check(lv.basement != null and lv.basement.dug.size() == 8, "8 m² of basement")
	await frames(1)
	var bw: LevelWorld = lv.basement
	check(bw.plan_view and bw.is_cut(bw.grid.cell_of(Vector3(1.5, Levels.base_y(-1) + 1.5, 1.5))), "building underground: a floor plan, the earth cut away")
	check(not bw.is_cut(bw.grid.cell_of(Vector3(1.5, Levels.base_y(-1) + 0.2, 1.5))), "knee-high earth stays")
	await _view(g, -1)
	check_eq(lv.view_storey, -2, "PageDown shows -2")
	for i in range(5, 8):
		s.energy = 100.0
		check(_apply(g, "excavate", Vector3(i + 0.5, Levels.base_y(-2), 7.5)), "dig -2 under the basement (%d)" % i)
	check(lv.world_of(-2) != null and lv.world_of(-2).dug.size() == 3, "3 m² of lower basement")
	bm.select_id("excavate")
	check(bm.evaluate(Vector2(5.5, 7.5))["reason"].contains("Nothing below"), "nothing below -2")
	await _view(g, 1)
	await _view(g, 1)
	check_eq(lv.view_storey, 0, "back to the ground")
	check(_apply(g, "stairs_down", Vector3(6.5, 0, 8.5), 1), "stairs down from the ground")
	await _view(g, -1)
	check(_apply(g, "stairs_down", Vector3(7.5, Levels.base_y(-1), 7.5), 3), "stairs down from -1 to -2")
	check_eq(lv.stairs.size(), 4, "four stairs")
	g._set_build(false)
	await frames(2)
	await _walk_stairs(g, lv.stairs[2], 0)
	check_eq(lv.player_storey, -1, "down to -1")
	await _walk_stairs(g, lv.stairs[3], -1)
	check_eq(lv.player_storey, -2, "down to -2")
	check(lv.world_of(-2).visible and not lv.basement.visible and not g.world.visible and not lv.upper.visible, "only -2 shows")
	check_eq(lv.indicator.text(), "Level -2 · Lower basement", "the indicator says so")
	# --- an enemy on the ground follows down two storeys ---
	var e: AIEnemy = g.roster.spawn_type("psycho", Vector2(2.0, 7.0))
	await physics_frames(2)
	check(e.goal_override.distance_to(Levels.exit_point(lv.stairs[2], 0)) < 0.01, "it heads for the stairs down")
	var x0 := Levels.exit_point(lv.stairs[2], 0)
	e.global_position = Vector3(x0.x, 0, x0.y)
	await physics_frames(2)
	check_eq(e.storey, -1, "it follows to -1")
	check(e.goal_override.distance_to(Levels.exit_point(lv.stairs[3], -1)) < 0.01, "and heads for the stairs to -2")
	var x1 := Levels.exit_point(lv.stairs[3], -1)
	await physics_frames(40)
	e.global_position = Vector3(x1.x, Levels.base_y(-1), x1.y)
	await physics_frames(2)
	check_eq(e.storey, -2, "it follows to -2")
	check(e.world == lv.world_of(-2) and e.visible, "on -2's nav, seen")
	g.roster.kill_all()
	await frames(2)
	# --- save and continue ---
	check_eq(g.debug_save(), "", "saved")
	g.queue_free()
	await frames(3)
	var h2: Node = await _boot("continue")
	var l2: Node = h2.levels
	check_eq(l2.storeys(), [-2, -1, 0, 1, 2], "all five levels load")
	check_eq(l2.player_storey, -2, "the player continues on -2")
	check_eq(l2.stairs.size(), 4, "with the stairs")
	check(l2.basement.dug.size() == 8 and l2.world_of(-2).dug.size() == 3, "the dug cells")
	check(l2.upper.built.has(Vector3i(0, 3, 4)), "the wall built on +1")
	check(l2.pillars.get(1, {}).has(Vector2i(11, 6)) and Levels.pillar_stands(l2.upper, Vector2i(11, 6)), "the pillar")
	check(l2.world_of(2).count_objects("door") == 1 and l2.world_of(2).has_floor_at(Vector2(11.5, 5.5)), "+2's door and tile")
	check_eq(l2.roof_storey(), 2, "the roof on +2")
	check(is_equal_approx(h2.world.yard.roof.position.y, 2.0 * Levels.HEIGHT), "the roof mesh raised two storeys")
	check_eq(l2.indicator.text(), "Level -2 · Lower basement", "the indicator after loading")


func test_experiment_004_save_maps_to_plus_and_minus_one() -> void:
	var u := LevelWorld.new()
	u.configure(Levels.UPPER, null)
	add(u)
	u.build_new()
	u.build_walls([Vector3i(0, 5, 3)])
	var b := LevelWorld.new()
	b.configure(Levels.BASEMENT, null)
	add(b)
	b.build_new()
	for i in range(6, 9):
		b.dig(Vector2i(i, 8))
	var v1 := {"version": 1, "stairs": [[0, 8, 7, 1], [-1, 6, 8, 1]], "laid": {"1": [[3, 3]]},
		"upper": u.save_data(), "basement": b.save_data()}
	var g: Node = await _boot()
	var lv: Node = g.levels
	lv.restore({"levels": v1}, 1, Vector3(3.5, Levels.HEIGHT, 2.5))
	check_eq(lv.storeys(), [-1, 0, 1], "upper -> +1, basement -> -1")
	check(lv.upper.built.has(Vector3i(0, 5, 3)) and lv.basement.dug.size() == 3, "with their contents")
	check_eq(lv.stairs.size(), 2, "and the stairs")
	check(lv.laid.get(1, {}).has(Vector2i(3, 3)), "and the laid tiles")
	check_eq(lv.player_storey, 1, "the player on +1")
	check_eq(lv.roof_storey(), 1, "the roof on +1")
	var d: Dictionary = lv.world_save({})["levels"]
	check(d["version"] == 2 and d["storeys"].has("1") and d["storeys"].has("-1"), "saved again by storey (version 2)")
	check_eq(lv.floor_cells(-1).size(), 1, "floor cells on -1: the dug cell not under the stairs")
