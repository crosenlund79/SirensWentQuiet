extends SceneTree
## Scripted end-to-end playtest through REAL input events and the real
## renderer (needs a display; use tools/playtest.sh). Unlike the smoke test it
## goes through the launcher keys, WASD, an actual mouse position + held LMB,
## and the N / R / Esc keys.
##   godot --path . --fixed-fps 10 -s res://tools/playtest.gd -- --version=2 --out=/abs/dir

const LAUNCHER := "res://src/launcher/launcher.tscn"
const SCENES := ["res://src/voxel/voxel_demo.tscn", "res://src/modular/modular_demo.tscn", "res://src/illustrated/illustrated_demo.tscn"]
const PX_PER_M_2D := 64.0

var _version := 1
var _out := ""
var _fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--version="):
			_version = int(a.trim_prefix("--version="))
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_run()


func _check(cond: bool, msg: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + msg)
	if not cond:
		_fails += 1


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(code: Key) -> void:
	_key(code, true)
	await process_frame
	await process_frame
	_key(code, false)
	await process_frame


func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)


func _screen_of(p: Vector2) -> Vector2:
	var cam := root.get_camera_3d()
	if cam != null:
		return cam.unproject_position(Vector3(p.x, 1.1, p.y))
	return root.get_canvas_transform() * (p * PX_PER_M_2D)


func _shot(name: String) -> void:
	if _out == "":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png(_out.path_join(name))


func _run() -> void:
	var path: String = SCENES[_version - 1]
	print("PLAYTEST version %d (%s)" % [_version, path])
	change_scene_to_file(LAUNCHER)
	await _wait(1.0)
	_check(current_scene != null and current_scene.scene_file_path == LAUNCHER, "launcher is up")
	await _tap(KEY_1 + _version - 1)
	await _wait(2.0)
	var v := current_scene
	_check(v != null and v.scene_file_path == path, "key %d opens the version" % _version)
	if v == null or v.scene_file_path != path:
		quit(1)
		return
	v.debug_set_spawning(false)

	# WASD (route: east along the living room, then a little north; stays clear of furniture and doorways)
	var p0: Vector2 = v.debug_player_pos()
	_key(KEY_D, true)
	await _wait(0.5)
	_key(KEY_D, false)
	await _wait(0.2)
	var p1: Vector2 = v.debug_player_pos()
	_check(p1.x - p0.x > 1.5, "D walks east (%.2f m)" % (p1.x - p0.x))
	_key(KEY_W, true)
	await _wait(0.2)
	_key(KEY_W, false)
	await _wait(0.2)
	var p2: Vector2 = v.debug_player_pos()
	_check(p1.y - p2.y > 0.5, "W walks north (%.2f m)" % (p1.y - p2.y))

	# Mouse aim + held LMB at a real enemy
	v.debug_spawn_enemy(Vector2(9.3, 5.0))
	await _wait(0.3)
	var n0: int = v.debug_living_enemies()
	var held := false
	var t := 0.0
	while t < 4.0 and v.debug_living_enemies() >= n0:
		var ps: PackedVector2Array = v.debug_enemy_positions()
		if ps.is_empty():
			break
		var me: Vector2 = v.debug_player_pos()
		var target := ps[0]
		for q in ps:
			if q.distance_to(me) < target.distance_to(me):
				target = q
		var sp := _screen_of(target)
		Input.warp_mouse(sp)
		var mm := InputEventMouseMotion.new()
		mm.position = sp
		mm.global_position = sp
		Input.parse_input_event(mm)
		if not held:
			_mouse_button(sp, true)
			held = true
		if t > 0.15 and t < 0.25:
			await _shot("playtest_v%d_firing.png" % _version)
		await _wait(0.1)
		t += 0.1
	if held:
		_mouse_button(_screen_of(v.debug_player_pos()), false)
	_check(v.debug_living_enemies() < n0, "aiming the mouse at the nearest enemy and holding LMB kills it (%.1f s)" % t)

	# Zoom keys
	await _tap(KEY_MINUS)
	await _wait(0.3)

	# N: night
	await _tap(KEY_N)
	await _wait(1.0)
	_check(v.debug_is_night(), "N switches to night")
	await _shot("playtest_v%d_night.png" % _version)

	# R: reset
	await _tap(KEY_R)
	await _wait(2.0)
	var v2 := current_scene
	_check(v2 != null and v2 != v and v2.scene_file_path == path and not v2.debug_is_night(), "R resets the version (fresh scene, back to day)")

	# Esc: launcher
	await _tap(KEY_ESCAPE)
	await _wait(1.0)
	_check(current_scene != null and current_scene.scene_file_path == LAUNCHER, "Esc returns to the launcher")
	print("PLAYTEST %s: %d failure(s)" % ["PASSED" if _fails == 0 else "FAILED", _fails])
	quit(0 if _fails == 0 else 1)
