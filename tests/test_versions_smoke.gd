extends "res://tests/test_case.gd"
## Shared smoke test run against every version through the same small debug
## contract (all positions in plan meters, see HousePlan). Each version's
## scene root implements:
##   debug_hud() -> DemoHud
##   debug_player_pos() -> Vector2
##   debug_teleport_player(p: Vector2) -> void
##   debug_fire_at(target: Vector2, height: float) -> void   one real shot now
##   debug_set_spawning(on: bool) -> void
##   debug_spawn_enemy(p: Vector2) -> Node
##   debug_living_enemies() -> int
##   debug_enemy_positions() -> PackedVector2Array            living enemies
##   debug_nav() -> GridNav
##   debug_blocked_at(p: Vector2) -> bool   real collision geometry blocks a
##                                          short horizontal probe through p
##                                          at waist height
##   debug_is_night() -> bool               the version's applied lighting state
##
## Run one version:  ... -s res://tests/run_tests.gd -- --filter=voxel

const LAUNCHER := "res://src/launcher/launcher.tscn"
const SCENES := {
	"voxel": "res://src/voxel/voxel_demo.tscn",
	"modular": "res://src/modular/modular_demo.tscn",
	"illustrated": "res://src/illustrated/illustrated_demo.tscn",
}
## A plain stretch of the south wall (between the living-room window and the
## utility wall): the test shoots a walk-through hole here.
const HOLE := Vector2(8.5, 9.0)


func test_launcher_lists_three_versions() -> void:
	var scene: PackedScene = load(LAUNCHER)
	var l := add(scene.instantiate())
	await frames(2)
	check_eq(l.VERSIONS.size(), 3, "three versions")
	for v in l.VERSIONS:
		check(v["scene"] in SCENES.values(), "%s scene path is the agreed one" % v["key"])


func test_voxel_smoke() -> void:
	await _smoke("voxel")


func test_modular_smoke() -> void:
	await _smoke("modular")


func test_illustrated_smoke() -> void:
	await _smoke("illustrated")


func _smoke(key: String) -> void:
	var path: String = SCENES[key]
	if not ResourceLoader.exists(path):
		skip("%s not built yet" % path)
		return
	var packed: PackedScene = load(path)
	var v: Node = packed.instantiate()
	add(v)
	tree.current_scene = v
	await frames(10)
	v.debug_set_spawning(false)

	# --- launches, player present ---------------------------------------------
	var start: Vector2 = v.debug_player_pos()
	check(start.distance_to(HousePlan.PLAYER_START) < 0.5, "player starts at PLAYER_START (%s)" % start)

	# --- movement -------------------------------------------------------------
	Input.action_press("move_left")
	await seconds(0.6)
	Input.action_release("move_left")
	await frames(2)
	var moved: Vector2 = v.debug_player_pos()
	check(start.x - moved.x > 1.2, "player moves with input (%s -> %s)" % [start, moved])

	# --- day / night ------------------------------------------------------------
	var hud: DemoHud = v.debug_hud()
	check(hud != null, "has the shared HUD")
	var ev := InputEventAction.new()
	ev.action = "toggle_day_night"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(3)
	check(hud.is_night and v.debug_is_night(), "N switches to night")
	hud.toggle_night()
	await frames(3)
	check(not hud.is_night and not v.debug_is_night(), "and back to day")

	# --- shooting kills an enemy --------------------------------------------------
	v.debug_teleport_player(HousePlan.PLAYER_START)
	var e: Node = v.debug_spawn_enemy(Vector2(6.5, 5.6))
	await frames(5)
	check(e != null and v.debug_living_enemies() == 1, "enemy spawned")
	var shots := 0
	while v.debug_living_enemies() > 0 and shots < 12:
		var ps: PackedVector2Array = v.debug_enemy_positions()
		if ps.size() > 0:
			v.debug_fire_at(ps[0], 1.2)
		shots += 1
		await seconds(Tuning.FIRE_INTERVAL + 0.05)
	check_eq(v.debug_living_enemies(), 0, "enemy killed by gunfire (%d shots)" % shots)

	# --- wall destruction -----------------------------------------------------------
	var nav: GridNav = v.debug_nav()
	check(v.debug_blocked_at(HOLE), "south wall blocks before damage")
	check(not nav.is_walkable(nav.cell_of(HOLE)), "nav blocked before damage")
	v.debug_teleport_player(Vector2(HOLE.x, 7.6))
	await frames(2)
	var pattern := [Vector2(-0.3, 0.3), Vector2(0.0, 0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.75), Vector2(0.0, 0.75), Vector2(0.3, 0.75),
		Vector2(-0.3, 1.2), Vector2(0.0, 1.2), Vector2(0.3, 1.2), Vector2(-0.3, 1.6), Vector2(0.0, 1.6), Vector2(0.3, 1.6)]
	shots = 0
	while shots < 150 and not nav.is_walkable(nav.cell_of(HOLE)):
		var o: Vector2 = pattern[shots % pattern.size()]
		v.debug_fire_at(Vector2(HOLE.x + o.x, HOLE.y), o.y)
		shots += 1
		await frames(2)
	await frames(5)
	check(nav.is_walkable(nav.cell_of(HOLE)), "nav opens after shooting the wall (%d shots)" % shots)
	check(not v.debug_blocked_at(HOLE), "collision removed where the wall was destroyed")

	# --- player walks through the new opening ------------------------------------------
	v.debug_teleport_player(Vector2(HOLE.x, 8.1))
	await frames(2)
	Input.action_press("move_down")
	await seconds(1.0)
	Input.action_release("move_down")
	check(v.debug_player_pos().y > 9.5, "player walks out through the hole (%s)" % v.debug_player_pos())

	# --- an enemy uses the new opening ------------------------------------------------
	v.debug_teleport_player(Vector2(HOLE.x, 7.0))
	await frames(2)
	v.debug_spawn_enemy(Vector2(HOLE.x, 12.0))
	var min_x_outside := 99.0
	var inside := false
	var t := 0.0
	while t < 10.0 and not inside:
		await seconds(0.1)
		t += 0.1
		var ps: PackedVector2Array = v.debug_enemy_positions()
		if ps.is_empty():
			break
		if ps[0].y > 9.3:
			min_x_outside = minf(min_x_outside, ps[0].x)
		inside = ps[0].y < 8.7
	check(inside, "enemy comes inside (%.1f s)" % t)
	check(min_x_outside > 6.5, "enemy used the new hole, not the front door (min x outside %.2f)" % min_x_outside)

	# --- reset and return to the launcher ------------------------------------------------
	var hud2: DemoHud = v.debug_hud()
	hud2.reset_level()
	await frames(6)
	var reloaded := tree.current_scene
	check(reloaded != null and reloaded != v and reloaded.scene_file_path == path, "R reloads the version")
	if reloaded != null:
		reloaded.debug_hud().back_to_launcher()
		await frames(6)
		check(tree.current_scene != null and tree.current_scene.scene_file_path == LAUNCHER, "Esc returns to the launcher")
