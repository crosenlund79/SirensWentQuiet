extends "res://tests/test_case.gd"
## Exp 012 (V): the fog of war, line of sight, the vision cone, the proximity
## sense, its memory in the save, doors in the cutaway and the fog band.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_e12_visibility.dat"
const EYE := Vector2(6.3, 6.6)           ## the living room, between the sofa and the dining table


func test_grid_memory_round_trip() -> void:
	var g := FowGrid.new()
	g.discover_rect(Rect2(0, 0, 4, 3))
	g.begin()
	g.cast(Vector2(10, 10), Vector2(0, -1), deg_to_rad(60), 6.0, 1.75)
	var fresh := g.commit()
	check(fresh > 0 and g.is_visible(Vector2(10, 6)) and not g.is_visible(Vector2(10, 14)), "open ground: ahead seen, behind not")
	check(g.is_visible(Vector2(10, 11.2)), "the close ring sees behind")
	var d := g.save_seen("k")
	var s := JSON.stringify(d)
	check(s.length() < 1500, "the memory is compact (%d chars)" % s.length())
	var g2 := FowGrid.new()
	check(g2.load_seen(JSON.parse_string(s), "k"), "it loads back from JSON")
	check(g2.disc == g.disc, "the same cells are discovered")
	check(not g2.load_seen(d, "other") and not g2.load_seen({"v": 1}, "k") and not g2.load_seen(null, "k"), "another layout, damaged or missing data is refused")


func test_fog_band_slows_out_not_in() -> void:
	var b := FogBand.for_home()
	var inside := Vector3(5, 0, 5)
	check(b.limit(inside, Vector3(3, 0, 0)) == Vector3(3, 0, 0), "inside the lot nothing changes")
	var at := Vector3(FogBoundary.LOT.end.x + 1.0, 0, 5)         # half way into the band, east
	var out := b.limit(at, Vector3(3, 0, 0))
	check(out.x > 0.3 and out.x < 1.5, "walking further out is slowed (%.2f)" % out.x)
	check(b.limit(at, Vector3(-3, 0, 0)).x == -3.0, "walking back is untouched")
	check(b.limit(at, Vector3(0, 0, 3)).z == 3.0, "walking along the edge is untouched")
	var deep := Vector3(FogBoundary.LOT.end.x + FogBand.HOME_DEPTH - 0.05, 0, 5)
	check(b.limit(deep, Vector3(3, 0, 0)).x < 0.05, "at the end of the band he barely moves on")
	var deeper := b.limit(Vector3(FogBoundary.LOT.end.x + 0.3, 0, 5), Vector3(3, 0, 0)).x
	check(deeper > out.x, "gradual: less slowing nearer the lot")


# --- the real game ---------------------------------------------------------------------------

func _boot() -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = "new"
	GameLaunch.seed = 1212
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	return g


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()


func _face(g: Node, at: Vector2, yaw: float) -> void:
	g.debug_teleport_player(at)
	g.player.rig.rotation.y = yaw
	g.player.aim_point = Vector3(at.x - sin(yaw) * 3.0, 1.1, at.y - cos(yaw) * 3.0)


func _enemy(g: Node, at: Vector2) -> AIEnemy:
	return g.roster.spawn_type("psycho", at, {"mode": "hidden"})


func test_game_line_of_sight_cone_and_proximity() -> void:
	var g := await _boot()
	var vis: Node = g.visibility
	var fow: FogOfWar = vis.fow
	check(fow != null and fow.active(), "the game has the fog of war")
	g.debug_kill_enemies()
	_face(g, EYE, PI * 0.5)                                    # looking west down the living room
	var front := _enemy(g, Vector2(2.6, 5.0))                  # in the cone, nothing between
	var walled := _enemy(g, Vector2(3.9, 2.6))                 # the bedroom, behind the wall (no doorway on the line)
	var behind := _enemy(g, Vector2(12.0, 6.5))                # the utility room, behind Eli and a wall
	var close := _enemy(g, Vector2(8.9, 6.9))                  # 2.6 m behind him, clear
	await frames(2)                                            # (before anyone has walked anywhere)
	fow.refresh()
	vis.call("_update_enemies")
	check(front.rig.visible and fow.sees(front), "an enemy in the cone with a clear line is shown (%s)" % fow.info())
	check(not walled.rig.visible and not fow.sees(walled), "an enemy behind a wall is hidden")
	check(not behind.rig.visible and not close.rig.visible, "enemies behind Eli are hidden (eli %s, close at %s)" % [g.debug_player_pos(), close.plan_pos()])
	check(walled.is_physics_processing() and walled.alive, "hidden enemies keep simulating")
	check(fow.sensed == close and fow.cue.strength > 0.2, "the very close one behind is sensed (%s, %.2f)" % [fow.sensed, fow.cue.strength])
	check(fow.cue.side.x > 0.5, "on the right edge of the screen (behind him, east; %s)" % fow.cue.side)
	check(vis.is_point_visible(Vector3(2.6, 1.0, 5.0)) and not vis.is_point_visible(Vector3(3.9, 1.0, 2.6)), "is_point_visible follows the line of sight")
	check(vis.is_discovered(Vector3(3.9, 1.0, 2.6)) and not vis.is_discovered(Vector3(24.0, 0, 18.0)), "the house is known; the far fog isn't")
	# Turning round: the one behind shows, the one in front hides (no ghost left behind).
	_face(g, EYE, -PI * 0.5)
	fow.refresh()
	vis.call("_update_enemies")
	check(close.rig.visible and not front.rig.visible, "turning round swaps who is seen")
	check(fow.sensed == null or fow.sensed == front, "nobody unseen behind but the one in front (%s)" % fow.sensed)
	# A close enemy behind a wall is never sensed.
	close.kill_quietly()
	front.kill_quietly()
	behind.kill_quietly()
	_face(g, Vector2(3.0, 4.75), PI)                           # south, back to the bedroom wall
	var through := _enemy(g, Vector2(4.2, 3.0))
	await frames(2)
	fow.refresh()
	check(fow.sensed == null and not fow.sees(through), "not through a wall (%s)" % fow.sensed)
	# Cost.
	var t0 := Time.get_ticks_usec()
	for i in 10:
		fow._cast(EYE + Vector2(0.3 * i, 0), 0.4 * i)
	var ms := (Time.get_ticks_usec() - t0) / 10000.0
	print("    fog of war at home: %.2f ms per cast, occlusion %.2f ms; %s" % [ms, float(fow.stats["occ_ms"]), fow.info()])
	check(ms < 40.0, "a cast stays cheap (%.2f ms)" % ms)
	# F10 and switching off.
	check("off" in fow.dev_toggle(), "F10 toggles it off")
	fow._process(0.016)
	vis.call("_update_enemies")
	check(through.rig.visible, "off: everyone shows")
	fow.dev_toggle()
	check("debug" in fow.dev_toggle_debug().to_lower() and fow.show_debug, "the debug overlay")
	fow.dev_toggle_debug()
	check("120" in fow.dev_set_cone(120.0) or fow.cone_deg == 120.0, "the cone slider")
	var m: DevMenu = g.debug_ui().dev_menu
	m.toggle()
	await frames(2)
	for b in ["Fog of war on/off", "Reveal all (dev)", "Reset discovered", "Vision debug overlay"]:
		check(m.button(b) != null, "F10 has \"%s\"" % b)
	var sl := m.find_child("ConeSlider", true, false) as HSlider
	check(sl != null, "F10 has the cone slider")
	if sl != null:
		sl.value = 180
		check(fow.cone_deg == 180.0, "the slider sets the cone (%d)" % int(fow.cone_deg))
	m.button("Reset discovered").pressed.emit()
	check(fow.is_discovered(Vector3(5, 0, 5)), "a reset keeps the home lot known")
	m.toggle()


func test_game_memory_save_and_door_stub() -> void:
	var g := await _boot()
	var fow: FogOfWar = g.visibility.fow
	g.debug_kill_enemies()
	_face(g, Vector2(17.5, 5.0), -PI * 0.5)                   # the east edge of the lot, looking out into the fog band
	fow.refresh()
	check(fow.is_discovered(Vector3(19.6, 0, 5.0)), "looking into the band discovers it")
	check(not fow.is_discovered(Vector3(-9.0, 0, 5.0)), "the west band stays undiscovered")
	fow._store_seen()
	g.home.call("_save")                                       # the home helper rewrites state.home: the memory stays
	check(g.state.home.has("seen"), "the memory is in state.home")
	var s2 := GameState.from_dict(JSON.parse_string(JSON.stringify(g.state.to_dict())))
	var back := FowGrid.new()
	check(back.load_seen(s2.home.get("seen"), "home"), "it survives the save format")
	check(back.is_discovered(Vector2(19.6, 5.0)) and not back.is_discovered(Vector2(-9.0, 5.0)), "with the right cells")
	# Doors in the cutaway: a low stub, not hidden.
	var door: WorldObject = null
	for o in g.world.objects:
		if o.kind == "door":
			door = o
			break
	check(door != null, "the house has a door")
	if door != null:
		door.set_cut(true)
		check(door.visual.visible and door.visual.scale.y < 0.5 and door.visual.scale.y > 0.2, "a cut door is a low stub (%.2f)" % door.visual.scale.y)
		var shown := door.visual.find_children("*", "GeometryInstance3D", true, false).filter(func(n): return (n as GeometryInstance3D).visible)
		check(not shown.is_empty(), "its meshes stay drawn")
		door.set_cut(false)
		check(is_equal_approx(door.visual.scale.y, 1.0), "back to full height")
	# The boundary: the walls stand past the band.
	var wall: StaticBody3D = g.boundary.walls[3]
	check(wall.position.x > FogBoundary.LOT.end.x + FogBand.HOME_DEPTH, "no invisible wall at the lot edge (%.1f)" % wall.position.x)
	check(g.player.move_band is FogBand, "the player slows in the band")
