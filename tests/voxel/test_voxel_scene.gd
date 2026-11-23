extends "res://tests/test_case.gd"
## Version A scene-level contracts: destruction calibration, shooting through
## holes, enemies bashing through walls, cutaway-aware aiming, roof hiding.

const SCENE := "res://src/voxel/voxel_demo.tscn"
const PATTERN := [Vector2(-0.3, 0.3), Vector2(0.0, 0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.75), Vector2(0.0, 0.75), Vector2(0.3, 0.75),
	Vector2(-0.3, 1.2), Vector2(0.0, 1.2), Vector2(0.3, 1.2), Vector2(-0.3, 1.6), Vector2(0.0, 1.6), Vector2(0.3, 1.6)]


func _load() -> Node:
	var v: Node = (load(SCENE) as PackedScene).instantiate()
	add(v)
	tree.current_scene = v
	await frames(3)
	v.debug_set_spawning(false)
	return v


## Shoots the smoke-test pattern at `hole` from `from` (offsets run along the
## wall); returns the number of shots until the nav cell is walkable (or 99).
func _open(v: Node, from: Vector2, hole: Vector2, vertical_wall := false) -> int:
	var nav: GridNav = v.debug_nav()
	v.debug_teleport_player(from)
	await frames(1)
	var shots := 0
	while shots < 60 and not nav.is_walkable(nav.cell_of(hole)):
		var o: Vector2 = PATTERN[shots % PATTERN.size()]
		v.debug_fire_at(hole + (Vector2(0, o.x) if vertical_wall else Vector2(o.x, 0)), o.y)
		shots += 1
		await frames(1)
	return shots if nav.is_walkable(nav.cell_of(hole)) else 99


func test_walk_through_holes_take_about_10_to_25_shots() -> void:
	var v: Node = await _load()
	var a: int = await _open(v, Vector2(3.6, 1.2), Vector2(4.0, 0.0))        # bedroom, north wall
	var b: int = await _open(v, Vector2(11.0, 7.4), Vector2(11.0, 9.0))      # utility, south wall
	var c: int = await _open(v, Vector2(1.6, 3.0), Vector2(0.0, 3.0), true)  # bedroom, west wall
	print("    walk-through holes opened in %d / %d / %d shots" % [a, b, c])
	for n in [a, b, c]:
		check(n >= 8 and n <= 30, "hole opened in a reasonable number of shots (%d, %d, %d)" % [a, b, c])
	check(not v.debug_blocked_at(Vector2(11.0, 9.0)), "collision follows the opened hole")


func test_shot_through_a_hole_continues_beyond_the_wall() -> void:
	var v: Node = await _load()
	await _open(v, Vector2(8.5, 7.6), Vector2(8.5, 9.0))
	var grid: VoxelGrid = v.grid
	var before := grid.solid_count
	v.debug_teleport_player(Vector2(8.5, 7.6))
	await frames(1)
	# Straight through the middle of the opening: nothing in the house is hit.
	var hit := grid.raycast(Vector3(8.5, 1.0, 7.6), Vector3(0, 0, 1), 6.0, v._bullet_skip)
	check(hit.is_empty() or (hit["pos"] as Vector3).z > 9.2, "the ray passes the hole")
	v.debug_fire_at(Vector2(8.5, 12.0), 1.0)
	await frames(1)
	check_eq(grid.solid_count, before, "a shot through the hole carves nothing in the wall")


func test_enemies_bash_through_a_wall_in_reasonable_time() -> void:
	var v: Node = await _load()
	v.debug_teleport_player(Vector2(3.7, 1.4))   # bedroom: the way round is long
	v.debug_spawn_enemy(Vector2(3.0, -1.6))
	v.debug_spawn_enemy(Vector2(4.4, -1.9))
	var t := 0.0
	var inside := false
	while t < 40.0 and not inside:
		await seconds(0.25)
		t += 0.25
		v.debug_teleport_player(Vector2(3.7, 1.4))
		for p in v.debug_enemy_positions():
			inside = inside or (p.y > 0.3 and p.y < 4.0 and p.x > 0.0 and p.x < 5.0)
	print("    two psychos got through the bedroom wall after %.1f s" % t)
	check(inside, "two psychos chew into the bedroom within 40 s (%.1f s)" % t)


func test_aim_ignores_cut_away_walls_and_roof_hides_inside() -> void:
	var v: Node = await _load()
	v.debug_teleport_player(Vector2(8.5, 8.0))   # just inside the south wall
	await frames(6)
	var cam: Camera3D = v.camera
	var player_px := cam.unproject_position(Vector3(8.5, 1.0, 8.0))
	var aim: Vector3 = v.aim_ray(cam.project_ray_origin(player_px), cam.project_ray_normal(player_px))
	check(aim.z < 8.6, "aiming at the player looks through the cut-away south wall (%s)" % aim)
	check(not v.yard.roof_visible(), "no roof while the player is inside")
	v.debug_teleport_player(Vector2(8.5, 12.0))
	await seconds(0.6)
	check(v.yard.roof_visible(), "roof back when outside")
