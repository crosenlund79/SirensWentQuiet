extends SceneTree
## Renders the SAME scripted situation in one version, from its own game camera,
## for side-by-side comparison (docs/experiment-001/screenshots/compare_*).
## Uses only the shared debug contract, so all three versions get identical
## shots, enemy spawns and player positions. Use tools/compare.sh.
##   godot --path . --fixed-fps 30 -s res://tools/compare.gd -- --version=2 --out=/abs/dir

const SCENES := {"voxel": "res://src/voxel/voxel_demo.tscn", "modular": "res://src/modular/modular_demo.tscn", "illustrated": "res://src/illustrated/illustrated_demo.tscn"}
const KEYS := ["voxel", "modular", "illustrated"]
const PX_PER_M_2D := 64.0
const HOLE := Vector2(8.5, 9.0)          # same south-wall spot as the smoke test
const PATTERN := [Vector2(-0.3, 0.3), Vector2(0.0, 0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.75), Vector2(0.0, 0.75), Vector2(0.3, 0.75),
	Vector2(-0.3, 1.2), Vector2(0.0, 1.2), Vector2(0.3, 1.2), Vector2(-0.3, 1.6), Vector2(0.0, 1.6), Vector2(0.3, 1.6)]

var _key := "voxel"
var _out := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--version="):
			_key = KEYS[int(a.trim_prefix("--version=")) - 1]
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_run()


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _screen_of(p: Vector2) -> Vector2:
	var cam := root.get_camera_3d()
	if cam != null:
		return cam.unproject_position(Vector3(p.x, 1.1, p.y))
	return root.get_canvas_transform() * (p * PX_PER_M_2D)


func _aim(p: Vector2) -> void:
	var sp := _screen_of(p)
	Input.warp_mouse(sp)
	var mm := InputEventMouseMotion.new()
	mm.position = sp
	mm.global_position = sp
	Input.parse_input_event(mm)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := _out.path_join("compare_%s_%s.png" % [_key, name])
	img.save_png(path)
	print("COMPARE saved ", path)


func _run() -> void:
	change_scene_to_file(SCENES[_key])
	await _wait(1.5)
	var v := current_scene
	v.debug_set_spawning(false)
	var nav: GridNav = v.debug_nav()

	# 1. Blow a walk-through hole in the south wall (same pattern as the smoke test).
	v.debug_teleport_player(Vector2(HOLE.x, 7.6))
	await _wait(0.2)
	var shots := 0
	while shots < 150 and not nav.is_walkable(nav.cell_of(HOLE)):
		var o: Vector2 = PATTERN[shots % PATTERN.size()]
		v.debug_fire_at(Vector2(HOLE.x + o.x, HOLE.y), o.y)
		shots += 1
		await process_frame
		await process_frame
	# 2. Break the east living-room window and chip the bedroom/living wall.
	v.debug_teleport_player(Vector2(5.0, 6.6))
	await _wait(0.2)
	for i in 2:
		v.debug_fire_at(Vector2(7.0, 9.0), 1.5)
		await process_frame
	for i in 4:
		v.debug_fire_at(Vector2(3.6 + 0.15 * i, 4.0), 1.0 + 0.2 * (i % 2))
		await process_frame
	print("COMPARE %s: hole opened after %d shots" % [_key, shots])

	# 3. Same psychos from the same places; the player stands in the living room.
	v.debug_teleport_player(Vector2(6.2, 6.8))
	v.debug_spawn_enemy(Vector2(HOLE.x, 12.0))
	v.debug_spawn_enemy(Vector2(2.0, 12.5))
	v.debug_spawn_enemy(Vector2(16.5, 7.5))
	_aim(Vector2(HOLE.x, 10.0))
	await _wait(2.0)
	_aim(Vector2(HOLE.x, 10.0))
	await _wait(0.5)
	await _shot("day")

	v.debug_hud().set_night(true)
	await _wait(1.2)
	_aim(Vector2(HOLE.x, 10.0))
	await _wait(0.3)
	await _shot("night")
	quit(0)
