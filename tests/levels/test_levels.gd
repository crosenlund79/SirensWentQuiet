extends "res://tests/test_case.gd"
## Experiment 004 storeys (src/levels): stairs geometry and routes (pure), the
## upper floor and basement worlds, and one smoke run in the real game scene
## (build the upper floor, take the stairs, build on it, dig a basement, an
## enemy following the player upstairs, no blows through a floor, save and
## continue on the upper floor).

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_levels.dat"


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()


func test_stairs_geometry_and_routes() -> void:
	var up := Levels.make_stairs(Levels.GROUND, Vector2i(8, 7), 1)      # east
	check_eq(Levels.stairs_cells(up), [Vector2i(8, 7), Vector2i(9, 7)], "two cells east")
	check_eq(Levels.stairs_rect(up), Rect2(8, 7, 2, 1), "rect")
	check_eq(Levels.foot_cell(up), Vector2i(7, 7), "foot cell")
	check_eq(Levels.far_cell(up), Vector2i(10, 7), "far cell")
	check(Levels.exit_point(up, Levels.GROUND).is_equal_approx(Vector2(7.5, 7.5)), "ground exit at the foot")
	check(Levels.exit_point(up, Levels.UPPER).is_equal_approx(Vector2(10.5, 7.5)), "upper exit past the top")
	check_eq(Levels.other_storey(up, Levels.GROUND), Levels.UPPER, "up joins 0 and 1")
	check_eq(Levels.other_storey(up, Levels.BASEMENT), Levels.BASEMENT, "not the basement")
	check(Levels.step_height(up, Levels.STEPS - 1) > 2.8, "rises to the upper floor")
	var down := Levels.make_stairs(Levels.BASEMENT, Vector2i(6, 8), 1)
	check(Levels.exit_point(down, Levels.GROUND).is_equal_approx(Vector2(5.5, 8.5)), "down: ground exit at the start")
	check(Levels.exit_point(down, Levels.BASEMENT).is_equal_approx(Vector2(8.5, 8.5)), "down: basement exit past the end")
	check(Levels.step_height(down, 0) < 0.0, "descends")
	var stairs := [up, down]
	check_eq(Levels.route(stairs, Levels.GROUND, Levels.UPPER, Vector2(1, 1)), up, "ground -> upper takes the stairs up")
	check_eq(Levels.route(stairs, Levels.UPPER, Levels.BASEMENT, Vector2(1, 1)), up, "upper -> basement goes down first")
	check_eq(Levels.route(stairs, Levels.GROUND, Levels.BASEMENT, Vector2(1, 1)), down, "ground -> basement")
	check(Levels.route([up], Levels.GROUND, Levels.BASEMENT, Vector2(1, 1)).is_empty(), "no stairs down: no route")
	check_eq(Levels.stairs_from_array(Levels.stairs_to_array(down)), down, "serialises")
	check(Levels.stairs_from_array([0, 13, 8, 1]) == null, "stairs outside the house are refused")
	check(Levels.stairs_from_array([2, 1, 1, 0]) == null, "unknown storey refused")
	check_eq(Levels.storey_at(2.9), Levels.UPPER, "storey of a height")
	check_eq(Levels.storey_at(-2.9), Levels.BASEMENT, "")
	check_eq(Levels.storey_at(0.4), Levels.GROUND, "")


func test_upper_floor_and_basement_worlds() -> void:
	var u := LevelWorld.new()
	u.configure(Levels.UPPER, null)
	add(u)
	u.build_new()
	check(u.has_floor_at(Vector2(5.5, 5.5)), "the deck covers the house")
	check(not u.has_floor_at(Vector2(-2.0, 5.0)), "no deck outside")
	check(u.nav.is_walkable(u.nav.cell_of(Vector2(5.5, 5.5))), "walkable on the deck")
	check(not u.nav.is_walkable(u.nav.cell_of(Vector2(-2.0, 5.0))), "outside the deck is not")
	check(u.section_info(Vector3i(0, 0, 4))["wall"], "outer walls")
	check(u.section_info(Vector3i(0, 0, 2))["glass"], "with windows")
	check(u.grid.origin.y > 2.0, "the grid sits at the storey's height")
	Levels.remove_floor(u, Vector2i(3, 3))
	check(not u.has_floor_at(Vector2(3.5, 3.5)), "a floor tile taken up leaves a hole")
	check(not u.nav.is_walkable(u.nav.cell_of(Vector2(3.5, 3.5))), "holes are not walkable")
	Levels.lay_wood_floor(u, Vector2i(3, 3))
	check(u.has_floor_at(Vector2(3.5, 3.5)), "and a wooden floor closes it")
	u.build_walls([Vector3i(0, 5, 3)])
	var d := u.save_data()
	var u2 := LevelWorld.new()
	u2.configure(Levels.UPPER, null)
	add(u2)
	check(u2.load_data(d), "the upper floor loads")
	check(u2.built.has(Vector3i(0, 5, 3)), "with the wall built on it")
	check_eq(u2.damage_summary(), u.damage_summary(), "same damage")

	var b := LevelWorld.new()
	b.configure(Levels.BASEMENT, null)
	add(b)
	b.build_new()
	var c := Vector2i(4, 4)
	check(not b.nav.is_walkable(b.nav.cell_of(Vector2(4.5, 4.5))), "earth is not walkable")
	check(b.dig(c), "dig")
	check(not b.dig(c), "a dug cell can't be dug twice")
	b.dig(Vector2i(5, 4))
	check(b.nav.is_walkable(b.nav.cell_of(Vector2(5.0, 4.5))), "dug cells are walkable")
	check(not b.has_floor_at(Vector2(8.5, 4.5)) or b.design.get_mat(80, VoxelHouse.NAV_ROW_LO, 50) == VoxelMat.EARTH, "undug stays earth")
	var b2 := LevelWorld.new()
	b2.configure(Levels.BASEMENT, null)
	add(b2)
	check(b2.load_data(b.save_data()), "the basement loads")
	check(b2.is_dug(c) and b2.is_dug(Vector2i(5, 4)) and b2.dug.size() == 2, "with its dug cells")
	check(b2.nav.is_walkable(b2.nav.cell_of(Vector2(5.0, 4.5))), "and its nav")


func _boot(mode := "new") -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 77
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	return g


func test_storeys_in_the_game() -> void:
	var g: Node = await _boot()
	var lv: Node = g.levels
	var s: GameState = g.debug_state()
	s.cheats["unlimited"] = true
	check(lv != null and lv.upper == null and lv.basement == null, "a new house has only the ground floor")
	# Build mode: stairs up, then the upper floor (key 0's pieces).
	var bm: BuildMode = g.build
	bm.set_active(true)
	bm.select_id("upper_floor")
	check_eq(bm.evaluate(Vector2(5, 5))["reason"], "Build stairs up first (this key, R turns them).", "the upper floor needs stairs")
	bm.select_id("stairs_up")
	bm.rot = 1
	check(bm.apply(Vector2(8.5, 7.5)), "stairs up built (%s)" % bm.last_eval.get("reason", ""))
	check_eq(lv.stairs.size(), 1, "one stairs")
	check(not g.world.nav.is_walkable(g.world.nav.cell_of(Vector2(9.0, 7.5))), "the ground nav goes round the stairs")
	bm.select_id("upper_floor")
	check(bm.apply(Vector2(5, 5)), "upper floor built (%s)" % bm.last_eval.get("reason", ""))
	check(lv.upper != null, "the upper floor exists")
	check(not lv.upper.has_floor_at(Vector2(9.0, 7.5)), "with a stairwell over the stairs")
	# Take the stairs by walking onto them.
	g.debug_teleport_player(Vector2(8.6, 7.5))
	await physics_frames(3)
	check_eq(lv.player_storey, Levels.UPPER, "walking onto the stairs goes up")
	check(absf(g.player.global_position.y - Levels.HEIGHT) < 0.01, "standing on the upper floor")
	check(bm.world == lv.upper, "build mode builds upstairs")
	bm.select_id("wall")
	check(bm.apply(Vector2(4.5, 6.0)), "a wall on the upper floor (%s)" % bm.last_eval.get("reason", ""))
	check(lv.upper.built.has(Vector3i(0, 6, 4)), "built in the upper floor's world")
	check(not g.world.built.has(Vector3i(0, 6, 4)), "not downstairs")
	check(bm.evaluate(Vector2(-2.0, 4.0))["reason"] != "", "nothing in mid-air outside the house")
	bm.set_active(false)
	# An enemy downstairs comes for the player by the stairs and never hits through the floor.
	var e: AIEnemy = g.roster.spawn_type("psycho", Vector2(4.0, 7.0))
	await physics_frames(2)
	check(e.goal_override.distance_to(Levels.exit_point(lv.stairs[0], Levels.GROUND)) < 0.01, "it heads for the stairs")
	var hp := s.health
	g.combat._on_player_swing(e)
	check_eq(s.health, hp, "a blow from the floor below doesn't land")
	e.global_position = Vector3(7.3, 0, 7.5)
	await physics_frames(2)
	check_eq(e.storey, Levels.UPPER, "at the stairs it follows upstairs")
	check(e.world == lv.upper and e.brain.nav == lv.upper.nav, "and hunts on the upper floor's nav")
	g.roster.kill_all()
	await frames(2)
	# Basement: dig with a shovel, stairs down, go down.
	lv.dev_dig_basement()
	check(lv.basement != null and lv.basement.dug.size() == 9, "a 3 x 3 basement")
	check_eq(lv.stairs.size(), 2, "with stairs down")
	lv.dev_goto(Levels.BASEMENT)
	check_eq(lv.player_storey, Levels.BASEMENT, "in the basement")
	check(not g.world.visible and lv.basement.visible and not lv.upper.visible, "only the basement shows")
	lv.dev_goto(Levels.UPPER)
	check(lv.upper.visible and g.world.visible and not lv.basement.visible, "upstairs: ground and upper show")
	# Save upstairs and continue.
	await frames(2)
	check_eq(g.debug_save(), "", "saved")
	g.queue_free()
	await frames(3)
	var h: Node = await _boot("continue")
	var l2: Node = h.levels
	check(l2.upper != null and l2.basement != null, "both storeys load")
	check_eq(l2.stairs.size(), 2, "the stairs load")
	check_eq(l2.player_storey, Levels.UPPER, "the player continues upstairs")
	check(absf(h.player.global_position.y - Levels.HEIGHT) < 0.01, "on the upper floor")
	check(l2.upper.built.has(Vector3i(0, 6, 4)), "with the wall built up there")
	check_eq(l2.basement.dug.size(), 9, "and the dug basement")
