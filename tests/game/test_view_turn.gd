extends "res://tests/test_case.gd"
## Refinement 01 in the real game scene: the view turns in quarter turns (Z /
## C) and WASD follows it, the cutaway faces the camera from every side, the
## roof toggle (V), and building on the upper floor through the real camera
## (walls, a replacing stone wall, a door, demolish, repair, a floor tile)
## from every side; the turn and the roof toggle are saved with the run.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_view_turn.dat"


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()


func _boot(mode := "new") -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 41
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


func test_turning_view_roofs_and_upstairs_building() -> void:
	var g: Node = await _boot()
	var cam: VoxelCamera = g.camera
	var pl: VoxelPlayer = g.player
	var s: GameState = g.debug_state()
	# --- the view turns; WASD follows the screen ---
	g.debug_teleport_player(Vector2(3.0, 12.5))
	g.turn_camera(1)
	check_eq(cam.turns, 1, "C: a quarter turn right")
	await frames(40)
	check(absf(cam.yaw - PI * 0.5) < 0.02, "the camera swings round smoothly (%.3f)" % cam.yaw)
	check(cam.global_position.x > pl.global_position.x + 8.0, "it now looks from the east")
	check(absf(pl.move_yaw - cam.yaw) < 0.001, "movement follows the view")
	var p0 := pl.global_position
	Input.action_press("move_up")
	await physics_frames(20)
	Input.action_release("move_up")
	var d := pl.global_position - p0
	check(d.x < -0.4 and absf(d.z) < 0.15, "W walks away from the camera: west (%s)" % str(d))
	g.turn_camera(-1)
	cam.snap()
	check_eq(cam.turns, 0, "Z turns back")
	# --- the cutaway faces the camera from every side ---
	var w: HouseWorld = g.world
	g.debug_teleport_player(Vector2(7.0, 6.5))
	for t in 4:
		cam.set_turns(t)
		cam.snap()
		w.update_view(pl.global_position, cam, 1.0)
		var back := Vector3(cam.back_dir().x, 0.0, cam.back_dir().z).normalized()
		var near := pl.global_position + back * 1.5 + Vector3(0, 2.0, 0)
		var far := pl.global_position - back * 1.5 + Vector3(0, 2.0, 0)
		check(w.is_cut(w.grid.cell_of(near)) and not w.is_cut(w.grid.cell_of(far)), "turn %d: cut toward the camera only" % t)
	cam.set_turns(0)
	# --- V: roofs ---
	var lv: Node = g.levels
	s.cheats["unlimited"] = true
	lv.dev_build_upper()
	g.debug_teleport_player(Vector2(5.0, 12.0))
	await frames(30)
	check(w.yard.roof_visible() and lv.upper.visible, "from the yard: the upper floor and the roof show")
	g.toggle_roofs()
	await frames(30)
	check(lv.roofs_hidden and not w.yard.roof_visible() and not lv.upper.visible, "V hides the roof and the upper floor")
	g.toggle_roofs()
	await frames(30)
	check(w.yard.roof_visible() and lv.upper.visible, "V again shows them")
	# --- upstairs: build through the real camera from every side ---
	lv.dev_goto(Levels.UPPER)
	await frames(30)
	check(not w.yard.roof_visible(), "upstairs the roof over you is faded")
	g._set_build(true)
	var bm: BuildMode = g.build
	var up: LevelWorld = lv.upper
	var h := Levels.HEIGHT
	var spots := [Vector2(4.5, 3.0), Vector2(11.5, 3.0), Vector2(11.5, 7.0), Vector2(4.5, 7.0)]
	for t in 4:
		cam.set_turns(t)
		cam.snap()
		await frames(2)
		bm.select_id("wall")
		var p := _aim(g, Vector3(spots[t].x, h, spots[t].y))
		check(p.distance_to(spots[t]) < 0.05, "turn %d: the pointer finds the deck (%s)" % [t, str(p)])
		check(bm.apply(p), "turn %d: a wall upstairs (%s)" % [t, bm.last_eval["reason"]])
		var seg := HouseWorld.nearest_seg(spots[t])
		check(up.built.has(seg) and not w.built.has(seg), "turn %d: on the upper floor only" % t)
	cam.set_turns(0)
	cam.snap()
	await frames(2)
	# replace one with stone (Refinement 01 issue 7, upstairs)
	bm.select_id("stone_wall")
	var r := bm.evaluate(_aim(g, Vector3(4.5, h, 3.0)))
	check(r["ok"] and r["replace"].size() == 1, "a stone wall replaces it upstairs (%s)" % r["reason"])
	check(bm.apply(_aim(g, Vector3(4.5, h, 3.0))), "replaced")
	check_eq(up.sections[Vector3i(0, 3, 4)]["material"], "stone", "upstairs, in stone")
	# a door into the far (north) outer wall, aimed at its face
	bm.select_id("door")
	var dp := _aim(g, Vector3(8.5, h + 1.2, 0.12))
	check(bm.apply(dp), "a door in the upper north wall (%s at %s)" % [bm.last_eval["reason"], str(dp)])
	check_eq(up.count_objects("door"), 1, "hung upstairs")
	# repair a damaged upper wall, demolish one, take a deck tile up and lay a new one
	for k in 4:
		up.shoot(Vector3(11.5, h + 1.2, 5.0), Vector3(0, 0, -1), [])
	check(up.section_missing(Vector3i(0, 3, 11)) > 0, "the upper wall took damage")
	bm.select_id("repair")
	check(bm.apply(Vector2(11.5, 3.0)), "repaired upstairs (%s)" % bm.last_eval["reason"])
	check_eq(up.section_missing(Vector3i(0, 3, 11)), 0, "intact again")
	bm.select_id("demolish")
	check(bm.apply(_aim(g, Vector3(11.5, h + 1.0, 7.0))), "demolished upstairs (%s)" % bm.last_eval["reason"])
	check(not up.built.has(Vector3i(0, 7, 11)), "the wall is gone")
	check(bm.apply(_aim(g, Vector3(9.5, h, 5.5))), "a deck tile taken up (%s)" % bm.last_eval["reason"])
	check(not up.has_floor_at(Vector2(9.5, 5.5)), "a hole in the deck")
	bm.select_id("wood_floor")
	check(bm.apply(_aim(g, Vector3(9.5, h, 5.5))), "a wooden floor tile laid upstairs (%s)" % bm.last_eval["reason"])
	check(up.has_floor_at(Vector2(9.5, 5.5)), "the deck is whole again")
	g._set_build(false)
	# --- saved with the run ---
	g.turn_camera(1)
	g.toggle_roofs()
	await frames(2)
	check_eq(g.debug_save(), "", "saved")
	g.queue_free()
	await frames(3)
	var h2: Node = await _boot("continue")
	check_eq(h2.camera.turns, 1, "the view's turn is restored")
	check(h2.levels.roofs_hidden, "and the roof toggle")
	check_eq(h2.levels.upper.sections[Vector3i(0, 3, 4)]["material"], "stone", "the replaced upper wall loads as stone")
