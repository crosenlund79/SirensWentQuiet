extends SceneTree
## Experiment 003 acceptance playtest (ASSIGNMENT §13, all 20 steps) through
## REAL input events (keys, mouse motion, wheel, drags, clicks on the actual
## buttons and map pins) and the real renderer under Xvfb + software Vulkan.
## Run it with tools/survival_playtest.sh, which starts two processes:
##   part 1: main menu → New Game → Hard → wake → stats and equipment → the
##           shotgun (F10), equip, switch (1/2/Q), fire both, reload → build
##           with wood, stone and iron → the region map at the dining table
##           (clouds at two times, pan, zoom) → plan the quarry → the fog →
##           targeted stone → a stone wall from it → the clinic with gear-
##           dependent choices → sleep → psycho, runner (open door), brute
##           (3 strikes a swing) → a bomber at a wall → the breach → repair →
##           plan a trip on the map (M) → save and quit;
##   part 2: Continue after a real application restart → the house (voxel hash,
##           objects), inventory, equipment, weapons, difficulty and the region
##           map (discovered, stock, plan) against part 1's JSON.
## The game's debug API is used to READ state, and to act only where input
## can't reasonably reach; every such use is named in the step's line (F10
## dev-menu buttons are real clicks and are named too). Rendering and the HUD
## are off between screenshots (software Vulkan redraws everything for any HUD
## change). One line per step: PASS / FAIL / SKIP <step>: <detail>.
##   godot --path . --resolution 1600x900 --fixed-fps 30 -s res://tools/survival_playtest.gd -- --part=1 --out=/abs/dir

const MENU := "res://src/menu/main_menu.tscn"
const GAME := "res://src/game/game.tscn"
const BACK := "turn back|cancel|^back$|close|not now|^stay|^no\\b|leave it"
const FPS := 30.0
const DT := 1.0 / FPS
const LEVEL := "hard"

## Walking routes in plan metres (bedroom door x 2..3 at y 4, front door x 4..5 at y 9).
const BED_TO_YARD := [Vector2(2.5, 3.4), Vector2(2.5, 4.7), Vector2(2.8, 5.0), Vector2(2.8, 8.3), Vector2(4.5, 8.3), Vector2(4.5, 9.7), Vector2(4.5, 10.8)]
const YARD_TO_LIVING := [Vector2(4.5, 10.8), Vector2(4.5, 9.7), Vector2(4.5, 8.3), Vector2(6.5, 8.3)]
const LIVING_TO_BED := [Vector2(4.5, 8.3), Vector2(2.8, 8.3), Vector2(2.8, 5.0), Vector2(2.5, 4.7), Vector2(2.5, 3.4), Vector2(2.0, 2.7)]
const LIVING_TO_TABLE := [Vector2(6.5, 8.3), Vector2(7.8, 7.6), Vector2(7.8, 6.75)]
const TABLE_TO_YARD := [Vector2(7.8, 7.6), Vector2(6.5, 8.3), Vector2(4.5, 8.3), Vector2(4.5, 9.7), Vector2(4.5, 10.8)]
const LIVING_TO_BACK := [Vector2(6.5, 7.6), Vector2(9.4, 7.5), Vector2(10.7, 7.5), Vector2(12.6, 6.6), Vector2(13.35, 6.5)]
const BACK_TO_LIVING := [Vector2(12.6, 6.6), Vector2(10.7, 7.5), Vector2(9.4, 7.5), Vector2(6.5, 7.6)]
const FOG_EDGE := Vector2(4.5, 12.25)
const FRONT_YARD := Vector2(9.0, 10.8)
const BUILD_SPOT := Vector2(-0.4, 12.0)
const IN_LIVING := Vector2(6.5, 7.6)
const INSIDE_FRONT_DOOR := Vector2(4.5, 8.3)
const INSIDE_BACK_DOOR := Vector2(13.35, 6.5)
const FRONT_DOOR := Vector2(4.5, 9.0)
const BACK_DOOR := Vector2(14.0, 6.5)
const WALL_SPOT := Vector2(9.5, 9.0)            ## middle of the solid south-wall section x 9..10
const PLATE_SPOT := Vector2(10.5, 9.0)          ## the section x 10..11 that gets iron plating
const SHOOT_SPOT := Vector2(10.4, 11.0)
const BOMBER_WATCH := Vector2(12.6, 11.6)

var _part := 1
var _out := ""
var _render_always := false
var _fails := 0
var _passes := 0
var _skips := 0
var _notes: Array[String] = []
var _held := {}
var _finished := false
var _doors_opened: Array[String] = []
var _strikes := {}                     ## kind -> roster wall_swing signals (strikes)
var _fired := []                       ## [weapon id, pellets] of every trigger pull that fired
var g: Node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--part="):
			_part = int(a.trim_prefix("--part="))
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a == "--render-always":
			_render_always = true
	SaveGame.path_override = (_out if _out != "" else OS.get_user_data_dir()).path_join("playtest_save.dat")
	_run()


# --- reporting -------------------------------------------------------------------------

func _step(name: String, ok: bool, detail := "") -> void:
	print("%s  %s: %s" % ["PASS" if ok else "FAIL", name, detail])
	if ok:
		_passes += 1
	else:
		_fails += 1


func _skip(name: String, detail: String) -> void:
	print("SKIP  %s: %s" % [name, detail])
	_skips += 1


func _note(text: String) -> void:
	_notes.append(text)
	print("      note: " + text)


func _finish() -> void:
	_finished = true
	print("PLAYTEST part %d %s: %d passed, %d failed, %d skipped" % [_part, "PASSED" if _fails == 0 else "FAILED", _passes, _fails, _skips])
	for n in _notes:
		print("  - " + n)


# --- time, rendering, screenshots ----------------------------------------------------------

func _frames(n := 1) -> void:
	for i in n:
		await process_frame


func _wait(s: float) -> void:
	await _frames(maxi(int(ceil(s * FPS)), 1))


func _render(on: bool) -> void:
	RenderingServer.render_loop_enabled = on or _render_always
	# Under software Vulkan any HUD change (the clock, the bars) forces a full
	# 3D redraw even with the render loop off (measured: about 0.9 s per frame),
	# so the HUD layer is hidden between screenshots. Steps read state through
	# the game's debug API, never from the HUD, so this changes no result.
	if not _render_always and g != null and is_instance_valid(g) and g.get("hud") != null:
		(g.hud as CanvasLayer).visible = on


func _shot(name: String) -> void:
	if _out == "" or name == "":
		return
	_render(true)
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png(_out.path_join(name))
		print("      shot  " + name)
	_render(false)


## Mean absolute difference (0..255) of two screenshots inside `rect` (sampled every 6 px).
func _image_diff(a: String, b: String, rect: Rect2i) -> float:
	var ia := Image.load_from_file(_out.path_join(a))
	var ib := Image.load_from_file(_out.path_join(b))
	if ia == null or ib == null or ia.get_size() != ib.get_size():
		return -1.0
	var sum := 0.0
	var n := 0
	for y in range(rect.position.y, mini(rect.end.y, ia.get_height()), 6):
		for x in range(rect.position.x, mini(rect.end.x, ia.get_width()), 6):
			var ca := ia.get_pixel(x, y)
			var cb := ib.get_pixel(x, y)
			sum += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			n += 1
	return 255.0 * sum / maxf(n, 1)


# --- input -----------------------------------------------------------------------------

func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(code: Key) -> void:
	_key(code, true)
	await _frames(2)
	_key(code, false)
	await _frames(2)


func _hold(code: Key, seconds: float) -> void:
	_key(code, true)
	await _wait(seconds)
	_key(code, false)
	await _frames(2)


func _to_window(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _move_mouse(p: Vector2) -> void:
	var w := _to_window(p)
	Input.warp_mouse(w)
	var mm := InputEventMouseMotion.new()
	mm.position = w
	mm.global_position = w
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0
	Input.parse_input_event(mm)


func _mouse_button(p: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var w := _to_window(p)
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = w
	e.global_position = w
	e.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	Input.parse_input_event(e)


func _click(p: Vector2) -> void:
	_move_mouse(p)
	await _frames(2)
	_mouse_button(p, true)
	await _frames(2)
	_mouse_button(p, false)
	await _frames(3)


func _click_control(c: Control) -> void:
	await _click(c.get_global_transform_with_canvas() * (c.size * 0.5))


## A left-button drag from a to b in screen space (steps of mouse motion).
func _drag(a: Vector2, b: Vector2, steps := 8) -> void:
	_move_mouse(a)
	await _frames(2)
	_mouse_button(a, true)
	await _frames(2)
	for i in range(1, steps + 1):
		_move_mouse(a.lerp(b, float(i) / steps))
		await _frames(2)
	_mouse_button(b, false)
	await _frames(3)


func _wheel(at: Vector2, up: bool, n := 1) -> void:
	_move_mouse(at)
	await _frames(1)
	var w := _to_window(at)
	for i in n:
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
			e.pressed = pressed
			e.factor = 1.0
			e.position = w
			e.global_position = w
			Input.parse_input_event(e)
		await _frames(2)


static func _shown(n: Node) -> bool:
	var p := n
	while p != null:
		if p is CanvasItem and not (p as CanvasItem).visible:
			return false
		if p is CanvasLayer and not (p as CanvasLayer).visible:
			return false
		p = p.get_parent()
	return true


## Visible, enabled buttons under `under` whose text matches `pattern` (case-insensitive) and not `exclude`.
func _buttons(under: Node, pattern := "", exclude := "") -> Array:
	var out := []
	if under == null:
		return out
	var re := RegEx.create_from_string("(?i)" + pattern) if pattern != "" else null
	var ex := RegEx.create_from_string("(?i)" + exclude) if exclude != "" else null
	_collect(under, out, re, ex)
	return out


func _collect(n: Node, out: Array, re: RegEx, ex: RegEx) -> void:
	if n is BaseButton and not (n as BaseButton).disabled and _shown(n):
		var t: String = n.text if n is Button else ""
		if (re == null or re.search(t) != null) and (ex == null or ex.search(t) == null):
			out.append(n)
	for c in n.get_children():
		_collect(c, out, re, ex)


func _click_button(under: Node, pattern: String, exclude := "") -> String:
	var bs := _buttons(under, pattern, exclude)
	if bs.is_empty():
		return ""
	var b: BaseButton = bs[0]
	var t: String = b.text if b is Button else str(b.name)
	await _click_control(b)
	return t


func _click_named(under: Node, node_name: String) -> String:
	var b := under.find_child(node_name, true, false) as BaseButton
	if b == null or not _shown(b) or b.disabled:
		return ""
	var t: String = b.text if b is Button else str(b.name)
	await _click_control(b)          # the click may rebuild the panel (and free the button)
	return t


# --- world helpers -----------------------------------------------------------------------

func _pos() -> Vector2:
	return g.debug_player_pos()


func _state() -> GameState:
	return g.debug_state()


func _world() -> HouseWorld:
	return g.debug_world()


func _ui() -> Node:
	return g.debug_ui()


func _weapons() -> WeaponHandler:
	return g.combat.weapons


func _screen_of(p: Vector2, h := 1.1) -> Vector2:
	return root.get_camera_3d().unproject_position(Vector3(p.x, h, p.y))


func _set_moves(want: Dictionary) -> void:
	for k in [KEY_W, KEY_A, KEY_S, KEY_D]:
		if want.has(k) != _held.has(k):
			_key(k, want.has(k))
			if want.has(k):
				_held[k] = true
			else:
				_held.erase(k)


## Walks with WASD to `target` (closed loop on the player's position). Opens a
## door with E when stuck in front of one.
func _walk_to(target: Vector2, timeout := 15.0) -> bool:
	var t := 0.0
	var still := 0.0
	var last := _pos()
	var tries := 0
	while t < timeout:
		var p := _pos()
		var d := target - p
		if d.length() < 0.22:
			_set_moves({})
			await _frames(3)
			return true
		var v: Vector3 = g.debug_player().velocity
		var want := {}
		if absf(d.x) > 0.1 and not (absf(d.x) < 0.7 and v.x * signf(d.x) > 1.3):
			want[KEY_D if d.x > 0.0 else KEY_A] = true
		if absf(d.y) > 0.1 and not (absf(d.y) < 0.7 and v.z * signf(d.y) > 1.3):
			want[KEY_S if d.y > 0.0 else KEY_W] = true
		_set_moves(want)
		await _frames(1)
		t += DT
		still = still + DT if _pos().distance_to(last) < 0.004 and not want.is_empty() else 0.0
		last = _pos()
		if still > 0.6:
			still = 0.0
			tries += 1
			if str(g.debug_prompt()).to_lower().contains("open door") and tries <= 4:
				_set_moves({})
				_doors_opened.append(str(g.debug_prompt()))
				await _tap(KEY_E)
				await _wait(0.6)
			elif tries <= 6:
				var side: Key
				if absf(d.y) > absf(d.x):
					side = KEY_A if tries % 2 == 0 else KEY_D
				else:
					side = KEY_W if tries % 2 == 0 else KEY_S
				_set_moves({side: true})
				await _wait(0.15)
	_set_moves({})
	return false


func _walk(route: Array) -> bool:
	for p in route:
		if not await _walk_to(p):
			print("      walk: stuck near %s on the way to %s" % [_pos(), p])
			return false
	return true


func _door(at: Vector2) -> WorldObject:
	for o in _world().objects:
		if o.kind == "door" and o.pos.distance_to(at) < 0.8:
			return o
	return null


## Stands at `stand` and presses E until the door at `at` is open (or closed).
func _set_door(at: Vector2, stand: Vector2, want_open: bool) -> String:
	await _walk_to(stand)
	var d := _door(at)
	if d == null:
		return "no door"
	for i in 3:
		if d.open == want_open:
			break
		await _tap(KEY_E)
		await _wait(0.5)
	return "%s door %s" % ["front" if at == FRONT_DOOR else "back", "open" if d.open else "closed"]


func _threats() -> int:
	return g.debug_living_enemies()


func _nearest_threat() -> Vector2:
	var best := Vector2.INF
	for q in g.debug_enemy_positions():
		if best == Vector2.INF or q.distance_to(_pos()) < best.distance_to(_pos()):
			best = q
	return best


func _enemy_of(kind: String) -> AIEnemy:
	for e in g.debug_roster().threats():
		if e is AIEnemy and (e as AIEnemy).kind == kind:
			return e
	return null


## Line of fire from the muzzle to a target (the world's own aim ray).
func _clear_shot(target: Vector2) -> bool:
	var from := Vector3(_pos().x, Tuning.MUZZLE_HEIGHT, _pos().y)
	var to := Vector3(target.x, 1.1, target.y)
	var hit: Vector3 = _world().aim_ray(from, (to - from).normalized())
	return hit.distance_to(from) >= from.distance_to(to) - 0.45


## Rounds the weapon in hand can still fire (loaded + reserve).
func _ammo_left() -> int:
	var c := _weapons().current()
	if c.get("unlimited", false):
		return 999
	return int(c.get("loaded", 0)) + int(c.get("reserve", 0))


## Opens the developer menu with F10, scrolls the button into view with the
## mouse wheel, clicks it and closes the menu again. Returns the button text.
func _dev_click(pattern: String) -> String:
	var dev: Node = _ui().dev_menu
	if not dev.visible:
		await _tap(KEY_F10)
		await _wait(0.3)
	var bs := _buttons(dev, pattern)
	var t := ""
	if not bs.is_empty():
		await _scroll_into_view(bs[0])
		t = bs[0].text
		await _click_control(bs[0])
	await _tap(KEY_F10)
	return t


func _scroll_into_view(c: Control) -> void:
	var sc: ScrollContainer = null
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			sc = p
			break
		p = p.get_parent()
	if sc == null:
		return
	for i in 60:
		var r := Rect2(sc.get_global_transform_with_canvas().origin, sc.size)
		var cr := Rect2(c.get_global_transform_with_canvas().origin, c.size)
		if r.encloses(cr):
			return
		var at := r.get_center()
		_move_mouse(at)
		var w := _to_window(at)
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_WHEEL_DOWN if cr.position.y > r.position.y else MOUSE_BUTTON_WHEEL_UP
			e.pressed = pressed
			e.factor = 1.0
			e.position = w
			e.global_position = w
			Input.parse_input_event(e)
		await _frames(2)


func _cheat_on(which: String, why: String) -> void:
	if _state().cheats.get(which, false):
		return
	var t := await _dev_click("^Invulnerable" if which == "invulnerable" else "^Unlimited")
	if not _state().cheats.get(which, false):
		_state().cheats[which] = true
		_note("cheat '%s' switched on through the debug API (no dev-menu button): %s" % [which, why])
	else:
		_note("cheat '%s' switched on with the dev menu button '%s': %s" % [which, t, why])


## Rounds for the fight: the other weapon (Q) first, then F10 "+ 10 ammo".
func _ensure_ammo() -> void:
	if _ammo_left() > 0:
		return
	await _tap(KEY_Q)
	await _wait(0.4)
	if _ammo_left() > 0:
		return
	var t := await _dev_click("^\\+ 10 ammo$")
	_note("out of rounds in both weapons: F10 '%s'" % t)
	if _weapons().current_id() != "handgun":
		await _tap(KEY_1)
	await _wait(0.3)


## Aims the real mouse at the nearest threat and holds LMB while there is a
## clear shot, until no threats remain or `limit` game seconds pass. Returns
## the game seconds spent. `shot_name`: a screenshot before the first shot.
func _fight(limit: float, shot_name := "", max_range := 11.0) -> float:
	var t := 0.0
	var held := false
	var shot_taken := shot_name == ""
	while t < limit and _threats() > 0 and not _state().dead:
		var e := _nearest_threat()
		var fire := e != Vector2.INF and e.distance_to(_pos()) < max_range and _clear_shot(e)
		if not shot_taken and fire:
			shot_taken = true
			_move_mouse(_screen_of(e))
			await _shot(shot_name)
		if e != Vector2.INF:
			var sp := _screen_of(e)
			_move_mouse(sp)
			if fire and not held:
				_mouse_button(sp, true)
				held = true
			elif not fire and held:
				_mouse_button(sp, false)
				held = false
		if _ammo_left() == 0 and _threats() > 0:
			if held:
				_mouse_button(_screen_of(e), false)
				held = false
			await _ensure_ammo()
		if _state().health < 35.0:
			await _cheat_on("invulnerable", "health fell to %d" % int(_state().health))
		await _frames(3)
		t += 3 * DT
	if held:
		_mouse_button(_screen_of(_pos()), false)
	if not shot_taken:
		await _shot(shot_name)
	return t


## Chunk meshes rebuild under a per-frame budget: wait for the queue to drain
## before a screenshot (reads VoxelWorld's queue when it has one).
func _settle_meshes(limit := 10.0) -> void:
	var t := 0.0
	await _wait(0.3)
	while t < limit:
		var q = _world().chunks.get("_dirty") if _world().chunks != null else null
		if typeof(q) != TYPE_DICTIONARY:
			await _wait(2.0)
			return
		if (q as Dictionary).is_empty():
			return
		await _frames(3)
		t += 3 * DT


## Dev menu: "Night 20:00", "×10" until dark, "×1". Falls back to dev_skip_to.
func _to_night() -> String:
	var a := await _dev_click("^Night 20")
	var b := await _dev_click("^×10$")
	var t := 0.0
	while _state().night_amount() < 0.95 and t < 30.0:
		await _wait(0.5)
		t += 0.5
	var c := await _dev_click("^×1$")
	if a == "" or b == "" or _state().night_amount() < 0.9:
		g.dev_skip_to(21.25)
		g.dev_set_time_scale(1.0)
		_note("dev menu night buttons not found; used dev_skip_to(21.25)")
		return "dev_skip_to(21.25)"
	return "clicked '%s', '%s', '%s'" % [a, b, c]


func _wait_modal(want: String, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		if g.debug_modal() == want:
			return true
		await _frames(3)
		t += 3 * DT
	return g.debug_modal() == want


## Build mode: press a class key until `piece` is selected (keys cycle materials).
func _select_piece(key: Key, piece: String) -> bool:
	for i in 4:
		await _tap(key)
		await _wait(0.1)
		if g.build.piece_id() == piece:
			return true
	return g.build.piece_id() == piece


## Build mode: drag a run (walls, foundations) on the ground from plan a to b.
func _build_run(a: Vector2, b: Vector2, shot_name := "") -> String:
	_move_mouse(_screen_of(a, 0.0))
	await _wait(0.3)
	_mouse_button(_screen_of(a, 0.0), true)
	await _frames(3)
	for i in range(1, 7):
		_move_mouse(_screen_of(a.lerp(b, i / 6.0), 0.0))
		await _frames(3)
	await _wait(0.4)
	var why := str(g.build.last_eval.get("reason", ""))
	var ok := bool(g.build.last_eval.get("ok", false))
	if shot_name != "":
		await _shot(shot_name)
	_mouse_button(_screen_of(b, 0.0), false)
	await _wait(0.4)
	return "ok" if ok else why


## The map: zoom out to the whole region (wheel), click the place's pin; its
## list entry (scrolled into view) if the pin can't be hit. Returns how.
func _map_select(screen: RegionMapScreen, id: String) -> String:
	var mk: MapMarkers = screen.markers
	var c := mk.get_global_transform_with_canvas() * (mk.size * 0.5)
	await _wheel(c, false, 14)
	await _wait(1.5)
	var how := ""
	var pin := mk.head_position(id)
	if pin != Vector2.INF and Rect2(Vector2(60, 60), mk.size - Vector2(120, 120)).has_point(pin):
		await _click(mk.get_global_transform_with_canvas() * pin)
		how = "wheel out, clicked the %s pin" % RegionLocations.name_of(id)
	if screen.selected != id:
		var lb: Button = screen.get("_list_buttons").get(id)
		if lb != null:
			await _scroll_into_view(lb)
			await _click_control(lb)
			how += (", then " if how != "" else "") + "clicked its list entry"
	await _wait(1.2)
	return how + (" → selected '%s'" % screen.selected)


func _section_center(s: Vector3i) -> Vector2:
	return Vector2(s.z + 0.5, s.y) if s.x == 0 else Vector2(s.y, s.z + 0.5)


## Wall sections that miss voxels now.
func _damaged_sections() -> Array:
	var out := []
	var w := _world()
	for s in w.sections:
		var info: Dictionary = w.sections[s]
		if int(info.get("current", 0)) < int(info.get("design", 0)):
			out.append(s)
	return out


func _missing() -> int:
	return int(_world().damage_summary().get("missing_voxels", 0))


# --- snapshots ---------------------------------------------------------------------------

func _voxel_hash() -> String:
	var w := _world()
	if w.grid == null:
		return ""
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(w.grid.mat)
	c.update(w.grid.col.to_byte_array())
	return c.finish().hex_encode()


func _world_hash() -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(var_to_bytes(_world().save_data()))
	return c.finish().hex_encode()


func _objects() -> Array:
	var out := []
	for o in _world().objects:
		out.append("%s/%s@%.2f,%.2f hp %d%s" % [o.kind, o.mat, o.pos.x, o.pos.y, o.hp, " open" if o.open else ""])
	out.sort()
	return out


func _snapshot() -> Dictionary:
	var s := _state()
	var w := _world()
	var stock := {}
	for id in s.region.stock:
		stock[id] = snappedf(float(s.region.stock[id]), 0.0001)
	var visits := {}
	for id in RegionLocations.ids():
		if s.region.visits(id) > 0:
			visits[id] = s.region.visits(id)
	var disc: Array = s.region.discovered.keys()
	disc.sort()
	var mags := {}
	for id in WeaponDefs.ids():
		mags[id] = s.magazine(id)
	return {
		"day": s.day(), "clock": s.clock_text(), "total_minutes": s.total_minutes,
		"health": s.health, "hunger": s.hunger, "hydration": s.hydration, "energy": s.energy,
		"inventory": s.inventory.counts.duplicate(), "cheats": s.cheats.duplicate(),
		"difficulty": s.difficulty, "equipment": s.equipment.duplicate(), "magazines": mags,
		"active_weapon": s.active_weapon_slot,
		"region": {"discovered": disc, "stock": stock, "visits": visits, "planned": s.region.planned,
			"purpose": s.region.planned_purpose, "layout": s.region.layout},
		"damage": w.damage_summary(), "voxel_hash": _voxel_hash(), "world_hash": _world_hash(),
		"objects": _objects(), "built": w.built.size(), "foundations": w.foundations.size(),
		"upgraded": w.upgraded.size(), "player": [_pos().x, _pos().y],
	}


# --- scenario ------------------------------------------------------------------------------

func _run() -> void:
	_render(false)
	print("SURVIVAL PLAYTEST (Experiment 003) part %d (out: %s)" % [_part, _out])
	if _part == 1:
		SaveGame.delete_save()
		GameLaunch.seed = 1123        # deterministic run (expedition rolls, stragglers)
		await _part1()
	else:
		await _part2()
	if not _finished:
		_finish()
	quit(1 if _fails > 0 else 0)


func _open_menu(shot_name: String) -> bool:
	change_scene_to_file(MENU)
	await _wait(1.5)
	if current_scene == null or current_scene.scene_file_path != MENU:
		return false
	await _shot(shot_name)
	return true


func _wait_for_game() -> bool:
	for i in 60:
		await _wait(0.25)
		if current_scene != null and current_scene.scene_file_path == GAME:
			break
	g = current_scene
	return g != null and g.scene_file_path == GAME and g.has_method("debug_state")


## Runs the expedition screen to the end with real clicks and number keys.
## `dest`: the place to pick on the list ("" = keep the preselected one).
## `prefer_gear`: answer events with an option that needs equipment when one
## is available. Returns {"clicks", "answers", "gear_options", "gear_choice",
## "locked", "preselected", "approach", "target"}.
func _expedition(dest: String, shots: Dictionary, prefer_gear := false) -> Dictionary:
	var out := {"clicks": [], "answers": [], "gear_options": [], "gear_choice": "", "locked": [], "preselected": false, "approach": "", "target": ""}
	var scr: Node = _ui().expedition
	out["preselected"] = scr.get("preselected_plan") == true
	var done := {}
	var t := 0.0
	while g.debug_modal() == "expedition" and t < 160.0:
		var st := str(scr.get("step"))
		if shots.has(st) and not done.has(st):
			done[st] = true
			await _shot(shots[st])
		var pb = scr.get("primary_button")
		match st:
			"list":
				if dest != "" and str(scr.get("selected")) != dest and scr.destination_buttons.has(dest):
					out["clicks"].append(dest)
					await _scroll_into_view(scr.destination_buttons[dest])
					await _click_control(scr.destination_buttons[dest])
				elif pb is Button and _shown(pb) and not pb.disabled:
					out["clicks"].append(pb.text)
					await _click_control(pb)
			"gear":
				out["approach"] = str(scr.get("approach"))
				out["target"] = str(scr.get("target"))
				if pb is Button and _shown(pb) and not pb.disabled:
					out["clicks"].append(pb.text)
					await _click_control(pb)
			"event":
				var run: ExpeditionRun = scr.get("run")
				var ev := run.current_event()
				var opts: Array = ev.get("options", [])
				var pick := -1
				for i in opts.size():
					var needs: Dictionary = opts[i].get("needs", {})
					var gear_ids := needs.keys().filter(func(k): return k in ["flashlight", "crowbar", "backpack", "vest"])
					var stt := run.option_state(i)
					if not gear_ids.is_empty():
						out["gear_options"].append("%s [%s]: %s" % [opts[i].get("label", "?"), ", ".join(gear_ids), "available" if stt["ok"] else stt["reason"]])
						if stt["ok"] and prefer_gear and pick < 0:
							pick = i
							out["gear_choice"] = "%s (needs %s)" % [opts[i].get("label", "?"), ", ".join(gear_ids)]
					if not stt["ok"]:
						out["locked"].append("%s: %s" % [opts[i].get("label", "?"), stt["reason"]])
				if pick < 0:
					pick = run.first_available_option()
				var bs: Array = scr.get("option_buttons") if scr.get("option_buttons") != null else []
				if pick >= 0 and pick < bs.size():
					out["answers"].append(str(opts[pick].get("label", "?")))
					if pick < 3:
						await _tap(KEY_1 + pick)          # the option's number key
					else:
						await _click_control(bs[pick])
			"confirm", "outcome", "report":
				if pb is Button and _shown(pb) and not pb.disabled:
					out["clicks"].append(pb.text)
					await _click_control(pb)
		await _wait(0.4)
		t += 0.4
	return out


func _part1() -> void:
	# 1. Start a game with a selected difficulty (main menu → New Game → Hard).
	if not await _open_menu("01_main_menu.png"):
		_step("1 start a game with a selected difficulty", false, "the main menu did not open")
		return
	var clicked := await _click_button(current_scene, "^new game")
	await _wait(0.6)
	var dlg: Node = current_scene.difficulty_dialog() if current_scene.has_method("difficulty_dialog") else null
	var dlg_open: bool = dlg != null and dlg.is_open
	await _shot("01b_new_game_difficulty.png")
	var chose := await _click_named(dlg, "Difficulty_" + LEVEL) if dlg_open else ""
	if not await _wait_for_game():
		_step("1 start a game with a selected difficulty", false, "the game scene did not open (clicked '%s', dialog %s, chose '%s')" % [clicked, dlg_open, chose])
		return
	# The intro overlay animates (about 9 s); under software Vulkan every frame
	# of it is a full redraw (about 1 s each), so it is skipped with a key after
	# its first second, as a player may (any key skips it).
	var t := 0.0
	while g.debug_modal() == "intro" and t < 40.0:
		await _wait(0.5)
		t += 0.5
		if t >= 1.0 and int(t * 2) % 4 == 0:
			await _tap(KEY_SPACE)
	_step("1 start a game with a selected difficulty", g.debug_modal() == "" and _state().difficulty == LEVEL and dlg_open,
		"clicked '%s', the difficulty dialog listed Easy/Normal/Hard with descriptions, clicked '%s' → GameState difficulty '%s' (first invasion Day %d, %d rounds in the handgun); intro skipped with Space after %.1f s" % [
		clicked, chose, _state().difficulty, _state().first_invasion_day(), _state().magazine("handgun"), t])

	# 2. Wake in the existing house.
	var bed: Vector3 = _world().bed_position()
	var near_bed := _pos().distance_to(Vector2(bed.x, bed.z)) < 2.2
	await _shot("02_wake_hud.png")
	_step("2 wake in the existing house", _state().day() == 1 and near_bed,
		"Day %d %s, %.1f m from the bed, initial save %s, HUD weapon card '%s %s %s'" % [_state().day(), _state().clock_text(), _pos().distance_to(Vector2(bed.x, bed.z)),
		"yes" if SaveGame.info()["valid"] else "no", g.hud.debug_texts()["weapon"], g.hud.debug_texts()["ammo"], g.hud.debug_texts()["ammo_cap"]])

	# 3. Inspect survival stats and equipment (I, then the Equipment tab).
	await _tap(KEY_I)
	await _wait(0.3)
	var inv_open: bool = g.debug_modal() == "inventory"
	var panel: InventoryPanel = _ui().inventory
	await _shot("03_inventory_supplies.png")
	var tab := await _click_named(panel, "Tab_equipment")
	await _wait(0.3)
	var primary := panel.slot_text("primary")
	await _shot("03b_inventory_equipment.png")
	await _tap(KEY_I)
	await _wait(0.2)
	var s := _state()
	_step("3 inspect survival stats and equipment", inv_open and tab != "" and primary == "Handgun" and g.debug_modal() == "",
		"I opened Supplies (health %d, food %d, water %d, energy %d; %d canned, %d water), clicked '%s': primary slot '%s', body '%s'" % [s.health, s.hunger, s.hydration, s.energy,
		s.inventory.count("canned_food"), s.inventory.count("water"), tab, primary, Items.name_of(s.equipped("body")) if s.equipped("body") != "" else "empty"])

	# 4. Equip and switch weapons: the shotgun via F10, Unequip/Equip in the panel, 2 / R / LMB / 1 / Q.
	await _walk(BED_TO_YARD)
	await _walk_to(FRONT_YARD)
	var pack := await _dev_click("^\\+ Shotgun & shells$")
	var auto := s.equipped("secondary")
	await _tap(KEY_I)
	await _wait(0.3)
	await _click_named(panel, "Tab_equipment")
	await _wait(0.2)
	var unequip := ""
	var equip := ""
	var b: Button = panel.use_button("shotgun")
	if b != null:
		unequip = b.text
		await _click_control(b)
		await _wait(0.2)
		var off := s.equipped("secondary") == ""
		b = panel.use_button("shotgun")
		equip = b.text if b != null else ""
		if b != null:
			await _click_control(b)
		await _wait(0.2)
		unequip += " (slot empty: %s)" % off
	await _shot("04_equipment_shotgun.png")
	await _tap(KEY_I)
	await _wait(0.2)
	var w := _weapons()
	w.fired.connect(func(id, hits): _fired.append([id, (hits as Array).size()]))
	var seq := []
	await _tap(KEY_2)
	seq.append("2→" + w.current_id())
	await _tap(KEY_R)
	await _wait(3.0)                           # shell by shell
	var shells_loaded := s.magazine("shotgun")
	var ground := _screen_of(FRONT_YARD + Vector2(0.4, 2.6), 0.0)
	var shots0 := w.shots
	await _click(ground)
	await _wait(0.05)
	await _shot("04b_shotgun_fired.png")
	var pellets := int(_fired.back()[1]) if not _fired.is_empty() and _fired.back()[0] == "shotgun" else 0
	await _wait(1.0)
	await _tap(KEY_1)
	seq.append("1→" + w.current_id())
	await _wait(0.4)
	var hg0 := s.magazine("handgun")
	await _click(ground + Vector2(40, 0))
	await _wait(0.3)
	var hg1 := s.magazine("handgun")
	await _tap(KEY_Q)
	seq.append("Q→" + w.current_id())
	await _tap(KEY_Q)
	seq.append("Q→" + w.current_id())
	await _shot("04c_hud_weapons.png")
	_step("4 equip and switch weapons", auto == "shotgun" and equip == "Equip" and s.equipped("secondary") == "shotgun" and shells_loaded == 5
		and pellets == 6 and hg1 == hg0 - 1 and seq == ["2→shotgun", "1→handgun", "Q→shotgun", "Q→handgun"],
		"F10 '%s' (auto-equipped: %s); panel buttons '%s' then '%s'; keys %s; R loaded %d shells one by one; LMB: one blast of %d pellets (%d trigger pulls), handgun %d → %d" % [
		pack, auto, unequip, equip, seq, shells_loaded, pellets, w.shots - shots0, hg0, hg1])

	# 5. Build with wood, stone and iron (F10 materials; B; 0 foundation, 1 stone wall, 1 wood wall, 8 iron plating).
	var mat0 := await _dev_click("^\\+ Materials$")
	var inv0 := s.inventory.counts.duplicate()
	await _walk_to(Vector2(1.0, 12.0))
	await _walk_to(BUILD_SPOT)
	await _tap(KEY_B)
	await _wait(0.3)
	var res := {}
	if g.build.active:
		await _select_piece(KEY_0, "foundation")
		res["foundation"] = await _build_run(Vector2(-2.7, 11.0), Vector2(0.7, 11.0))
		await _select_piece(KEY_1, "stone_wall")
		res["stone_wall"] = await _build_run(Vector2(-2.7, 11.0), Vector2(-1.3, 11.0), "05_construction_stone_ghost.png")
		await _select_piece(KEY_1, "wall")
		res["wood_wall"] = await _build_run(Vector2(1.3, 11.0), Vector2(2.7, 11.0))
		await _walk_to(Vector2(9.6, 11.2))
		Research.learn_all(s)      # Exp 006 (R): iron plating needs research now
		await _select_piece(KEY_8, "upgrade")
		_move_mouse(_screen_of(PLATE_SPOT, 1.5))
		await _wait(0.4)
		res["plating_eval"] = str(g.build.last_eval.get("reason", "")) if not g.build.last_eval.get("ok", false) else "ok"
		await _click(_screen_of(PLATE_SPOT, 1.5))
		await _wait(0.3)
		await _tap(KEY_ESCAPE)
		await _wait(0.2)
	await _walk_to(Vector2(3.2, 12.0))
	await _settle_meshes()
	await _shot("05b_built_wood_stone_iron.png")
	var stones := 0
	var woods := 0
	for sg in _world().built:
		if _world().sections.has(sg):
			if _world().sections[sg].get("material", "") == "stone":
				stones += 1
			elif _world().sections[sg].get("material", "") == "wood":
				woods += 1
	var used := []
	for id in ["wood", "nails", "stone", "iron"]:
		used.append("%s %d→%d" % [id, int(inv0.get(id, 0)), s.inventory.count(id)])
	_step("5 build with wood, stone and iron", _world().foundations.size() >= 4 and stones >= 2 and woods >= 2 and _world().upgraded.has(Vector3i(0, 9, 10)),
		"F10 '%s'; foundation %s (%d tiles), stone wall %s (%d m), wooden wall %s (%d m), iron plating on the house wall x 10..11 %s; %s" % [mat0, res.get("foundation", "?"),
		_world().foundations.size(), res.get("stone_wall", "?"), stones, res.get("wood_wall", "?"), woods, res.get("plating_eval", "?"), ", ".join(used)])

	# 6-8. The region map at the dining table: open it, explore it, watch the clouds.
	var reveal := await _dev_click("^Reveal all places$")
	_note("step 6 revealed every place with F10 '%s' (discovery otherwise needs careful-exploration trips); %d of %d known" % [reveal, s.region.discovered.size(), RegionLocations.ids().size()])
	await _walk([Vector2(4.5, 11.2)] + YARD_TO_LIVING + LIVING_TO_TABLE)
	var prompt := str(g.debug_prompt())
	await _tap(KEY_E)
	await _wait(1.2)
	var screen: RegionMapScreen = g.map.screen
	var view: RegionMapView = screen.view
	var map_open: bool = g.debug_modal() == "map" and screen.is_open
	_step("6 open the voxel city map", map_open and prompt == "[E] Study the region map" and paused,
		"prompt '%s' at the dining table, E → modal '%s', world paused %s, the game's 3D view off %s" % [prompt, g.debug_modal(), paused, root.disable_3d])
	var ct0 := view.cloud_time
	await _shot("06_map_overview.png")
	await _wait(20.0)
	var ct1 := view.cloud_time
	await _shot("06b_map_clouds_20s_later.png")
	var mrect := Rect2i(Vector2i(int(RegionMapScreen.LIST_W + 40), 90), Vector2i(1600 - int(RegionMapScreen.LIST_W) - 80, 760))
	var cloud_diff := _image_diff("06_map_overview.png", "06b_map_clouds_20s_later.png", mrect)
	# explore: zoom at the docks with the wheel, drag to pan, WASD, H for the house
	var mk: MapMarkers = screen.markers
	var d0 := view.distance
	var docks := mk.get_global_transform_with_canvas() * view.project(view.terrain.anchor_of("restaurant"))
	await _wheel(docks, true, 7)
	await _wait(1.5)
	var d1 := view.distance
	await _shot("06c_map_zoom_bay_docks.png")
	var f0 := view.focus
	var c := mk.get_global_transform_with_canvas() * (mk.size * 0.5)
	await _drag(c, c + Vector2(260, 120))
	await _wait(1.0)
	var f1 := view.focus
	await _hold(KEY_A, 0.8)
	await _wait(0.8)
	await _shot("06d_map_pan_centre.png")
	var f2 := view.focus
	await _tap(KEY_H)
	await _wait(1.5)
	await _shot("06e_map_home.png")
	await _wheel(c, false, 6)
	await _wait(1.5)
	_step("7 explore hills, river, bay, roads and districts", d1 < d0 * 0.6 and f1.distance_to(f0) > 2.0 and f2.distance_to(f1) > 1.0,
		"wheel ×7 at the harbour: camera distance %.0f → %.0f; drag: focus moved %.1f; A held: %.1f more; H flew home (selected '%s')" % [d0, d1, f1.distance_to(f0), f2.distance_to(f1), screen.selected])
	_step("8 watch clouds move over the landscape", ct1 - ct0 > 15.0 and cloud_diff > 1.0,
		"cloud time %.1f → %.1f s (%.1f world units of drift); the two frames differ by %.2f / 255 on average over the map" % [ct0, ct1, (ct1 - ct0) * RegionMapView.CLOUD_SPEED.length(), cloud_diff])

	# 9. Select a scavenging location: the quarry's pin, targeted collection (key 2), Plan expedition.
	var how := await _map_select(screen, "quarry")
	await _wait(1.2)
	await _tap(KEY_2)
	await _wait(0.5)
	await _shot("07_map_quarry_info_targeted.png")
	var planb: Button = screen.get("_plan_button")
	if planb != null and not planb.disabled:
		await _click_control(planb)
	await _wait(0.4)
	await _shot("07b_map_planned.png")
	var planned := "%s|%s" % [s.region.planned, s.region.planned_purpose]
	var toast: String = g.last_toast
	await _tap(KEY_M)
	await _wait(0.4)
	_step("9 select a scavenging location", planned == "quarry|targeted:stone" and toast.begins_with("Planned:") and g.debug_modal() == "",
		"%s, 2 → '%s' (%s), clicked '%s' → plan %s, toast '%s', M closed the map, autosave %s" % [how, screen.approach, screen.target, planb.text if planb != null else "?", planned, toast, g.autosave_log.has("plan")])

	# 10-11. Enter the fog; targeted collection of stone at the quarry.
	var before := s.inventory.counts.duplicate()
	await _walk(TABLE_TO_YARD)
	await _walk_to(FOG_EDGE)
	await _wait(0.3)
	var edge_prompt := str(g.debug_prompt())
	await _tap(KEY_E)
	await _wait(0.6)
	var ex1 := {}
	if g.debug_modal() == "expedition":
		ex1 = await _expedition("", {"list": "08_expedition_list_plan.png", "gear": "08b_expedition_targeted_approach.png", "event": "08c_expedition_event.png", "report": "08d_expedition_report.png"})
	var r1: Dictionary = g.last_expedition.get("result", {})
	_step("10 enter the fog and begin a simulated expedition", str(r1.get("location", "")) == "quarry" and ex1.get("preselected", false),
		"prompt '%s', E → the screen preselected the map's plan (%s, %s: %s); clicked %s; answered %s" % [edge_prompt, ex1.get("preselected"), ex1.get("approach"), ex1.get("target"),
		ex1.get("clicks"), ex1.get("answers")])
	var stone_gain := s.inventory.count("stone") - int(before.get("stone", 0))
	_step("11 collect targeted construction resources", str(r1.get("approach", "")) == "targeted" and stone_gain > 0 and g.last_expedition.get("region_applied", false),
		"%s, %s: gained %s; stone %d → %d; %d min away; region: quarry visits %d, stock %.2f, plan used up '%s'" % [r1.get("name", "?"), r1.get("approach", "?"), r1.get("gained", {}),
		int(before.get("stone", 0)), s.inventory.count("stone"), int(r1.get("minutes", 0)), s.region.visits("quarry"), s.region.stock_of("quarry"), s.region.planned])

	# 12. Return home and use them: a stone wall from the quarry's stone.
	var stone0 := s.inventory.count("stone")
	var built0 := _world().built.size()
	await _walk_to(Vector2(1.0, 12.0))
	await _walk_to(BUILD_SPOT)
	await _tap(KEY_B)
	await _wait(0.3)
	var r12 := ""
	if g.build.active:
		await _select_piece(KEY_1, "stone_wall")
		r12 = await _build_run(Vector2(-0.7, 11.0), Vector2(0.7, 11.0))
		await _tap(KEY_ESCAPE)
	await _walk_to(Vector2(1.5, 12.1))
	await _settle_meshes()
	await _shot("09_stone_wall_from_the_quarry.png")
	_step("12 return home and use them", _world().built.size() >= built0 + 2 and s.inventory.count("stone") == stone0 - 12,
		"B, 1, drag x -1..1 on the foundation: %s; stone %d → %d; built sections %d → %d" % [r12, stone0, s.inventory.count("stone"), built0, _world().built.size()])

	# 13-14. A riskier destination (the clinic: medicine) with equipment-dependent decisions.
	var av0 := ExpeditionData.availability(s, "clinic")
	var gear := await _dev_click("^\\+ Vest & gear$")
	var av1 := ExpeditionData.availability(s, "clinic")
	var med0 := s.inventory.count("bandage") + s.inventory.count("medkit")
	var hp0 := s.health
	await _walk_to(FOG_EDGE)
	await _tap(KEY_E)
	await _wait(0.6)
	var ex2 := {}
	if g.debug_modal() == "expedition":
		ex2 = await _expedition("clinic", {"gear": "10_clinic_plan_gear.png", "event": "10b_clinic_event_gear_options.png", "report": "10c_clinic_report.png"}, true)
	var r2: Dictionary = g.last_expedition.get("result", {})
	var med1 := s.inventory.count("bandage") + s.inventory.count("medkit")
	_step("13 visit a riskier destination for medical supplies", str(r2.get("location", "")) == "clinic",
		"%s (risk %s on %s): gained %s, medical %d → %d, health %d → %d (vest worn), %d min" % [r2.get("name", "?"), ExpeditionData.risk_name(ExpeditionData.danger_for(s, "clinic")), LEVEL,
		r2.get("gained", {}), med0, med1, hp0, s.health, int(r2.get("minutes", 0))])
	_step("14 experience equipment-dependent mission decisions", not bool(av0["ok"]) and bool(av1["ok"]) and str(ex2.get("gear_choice", "")) != "",
		"before F10 '%s' the clinic said '%s'; after: available %s; gear options seen %s; chose '%s'; locked options %s" % [gear, av0["reason"], av1["ok"],
		ex2.get("gear_options", []), ex2.get("gear_choice", ""), ex2.get("locked", [])])

	# 15. Sleep and advance the clock.
	var how_night := await _to_night()
	await _shot("11_night_house.png")
	var to_bed := await _walk([Vector2(4.5, 11.2)] + YARD_TO_LIVING + LIVING_TO_BED)
	var slept := ""
	var t0 := s.total_minutes
	var e0 := s.energy
	for attempt in 2:
		await _tap(KEY_E)
		await _wait(0.3)
		if g.debug_modal() == "sleep":
			slept += await _click_button(_ui().sleep_dialog, "morning|sleep|hour", BACK)
			t = 0.0
			while g.debug_modal() != "" and t < 20.0:
				await _wait(0.2)
				t += 0.2
		var plan: Dictionary = g.last_sleep.get("plan", {})
		if not plan.get("interrupted", false) or _threats() == 0:
			break
		_note("step 15: sleep interrupted (%s); fighting first" % plan.get("reason", "?"))
		await _fight(60.0)
	_step("15 sleep and advance the clock", to_bed and slept != "" and s.total_minutes > t0 + 300.0 and s.day() == 2,
		"%s; walked to the bed %s, E, clicked '%s': %s → Day %d %s, energy %d → %d, autosave %s" % [how_night, to_bed, slept, SurvivalGame._hhmm(t0), s.day(), s.clock_text(), e0, s.energy, "wake" in g.autosave_log])

	# 16. Fight enemies with distinct AI behaviours (F10 spawns): psycho, runner, brute.
	g.debug_roster().wall_swing.connect(func(e, _target): _strikes[e.kind if e is AIEnemy else "psycho"] = int(_strikes.get(e.kind if e is AIEnemy else "psycho", 0)) + 1)
	await _walk(BED_TO_YARD)
	await _walk_to(FRONT_YARD)
	if _state().cheats.get("invulnerable", false):
		await _dev_click("^Invulnerable")
	var notes16 := []
	# a. the psycho: the baseline, straight at the player
	var sp := await _dev_click("^\\+ Psycho$")
	var psycho_seen := _enemy_of("psycho") != null
	var hp_a := s.health
	var tf := await _fight(60.0, "12a_psycho.png")
	notes16.append("'%s': a psycho walked at the player and was shot down in %.0f s (health %d → %d)" % [sp, tf, hp_a, s.health])
	# b. the runner: back door open, front door closed, the player in the living room
	var doors := []
	await _walk(YARD_TO_LIVING)
	doors.append(await _set_door(FRONT_DOOR, INSIDE_FRONT_DOOR, false))
	await _walk_to(IN_LIVING)
	await _walk(LIVING_TO_BACK)
	doors.append(await _set_door(BACK_DOOR, INSIDE_BACK_DOOR, true))
	await _walk(BACK_TO_LIVING)
	await _tap(KEY_2)
	var sr := await _dev_click("^\\+ Runner$")
	var runner := _enemy_of("runner")
	var runner_seen := runner != null
	var through_door := false
	var runner_shot := false
	t = 0.0
	while runner != null and is_instance_valid(runner) and runner.alive and t < 40.0:
		var rp := runner.plan_pos()
		if rp.x > 13.4 and rp.x < 14.7 and rp.y > 5.9 and rp.y < 7.1:
			through_door = true
			if not runner_shot:
				runner_shot = true
				await _shot("12b_runner_through_the_open_door.png")
		if HousePlan.FOOTPRINT.has_point(rp) and (rp.x < 13.2 or rp.distance_to(_pos()) < 4.0):
			break                              # inside the house and close (not through a wall)
		await _frames(3)
		t += 3 * DT
	var runner_walls := int(runner.swings["wall"]) if runner != null and is_instance_valid(runner) else -1
	if not runner_shot:
		await _shot("12b_runner_through_the_open_door.png")
	tf = await _fight(40.0)
	notes16.append("'%s' with %s: the runner came in through the open back door %s, wall swings %d, shotgun (2) %.0f s" % [sr, doors, through_door, runner_walls, tf])
	# c. the brute: back door closed too; it bashes in, three strikes per swing
	await _walk(LIVING_TO_BACK)
	doors.append(await _set_door(BACK_DOOR, INSIDE_BACK_DOOR, false))
	await _walk(BACK_TO_LIVING)
	var miss0 := _missing()
	var door_hp0 := (_door(FRONT_DOOR).hp if _door(FRONT_DOOR) != null else -1) + (_door(BACK_DOOR).hp if _door(BACK_DOOR) != null else -1)
	var str0 := int(_strikes.get("brute", 0))
	var sb := await _dev_click("^\\+ Brute$")
	var brute := _enemy_of("brute")
	var brute_seen := brute != null
	var brute_shot := false
	t = 0.0
	while brute != null and is_instance_valid(brute) and brute.alive and t < 60.0:
		if int(brute.swings["wall"]) >= 2 and not brute_shot:
			brute_shot = true
			await _shot("12c_brute_bashing.png")
		if brute.plan_pos().distance_to(_pos()) < 3.0 or (int(brute.swings["wall"]) >= 3 and _clear_shot(brute.plan_pos())):
			break
		await _frames(3)
		t += 3 * DT
	var brute_swings := int(brute.swings["wall"]) if brute != null and is_instance_valid(brute) else 0
	var brute_strikes := int(_strikes.get("brute", 0)) - str0
	var door_hp1 := (_door(FRONT_DOOR).hp if _door(FRONT_DOOR) != null else 0) + (_door(BACK_DOOR).hp if _door(BACK_DOOR) != null else 0)
	var miss1 := _missing()
	if not brute_shot:
		await _shot("12c_brute_bashing.png")
	tf = await _fight(60.0, "", 14.0)
	notes16.append("'%s': %d wall swings = %d strikes (%.1f a swing); door HP %d → %d, house voxels missing %d → %d; shot down in %.0f s, health %d" % [sb, brute_swings,
		brute_strikes, float(brute_strikes) / maxf(brute_swings, 1), door_hp0, door_hp1, miss0, miss1, tf, s.health])
	_step("16 fight enemies with distinct AI behaviours", psycho_seen and runner_seen and brute_seen and through_door and runner_walls == 0
		and brute_swings > 0 and brute_strikes == 3 * brute_swings and _threats() == 0, "; ".join(notes16))

	# 17. A suicide bomber deliberately attacks a wall (both doors open, one wall section weakened).
	await _walk(LIVING_TO_BACK)
	await _set_door(BACK_DOOR, INSIDE_BACK_DOOR, true)
	await _walk(BACK_TO_LIVING)
	await _walk_to(Vector2(5.2, 8.0))
	await _set_door(FRONT_DOOR, INSIDE_FRONT_DOOR, true)
	await _walk_to(Vector2(4.5, 9.9))
	await _walk_to(SHOOT_SPOT)
	await _tap(KEY_1)
	if s.magazine("handgun") + s.reserve("handgun") < 8:
		_note("step 17: F10 '%s' for rounds to weaken the wall" % await _dev_click("^\\+ 10 ammo$"))
	var aim := _screen_of(WALL_SPOT, 1.0)
	for i in 8:
		await _click(aim + Vector2((i % 3 - 1) * 12.0, (i / 3 - 1) * 14.0))
		await _wait(0.25)
	var miss_before := _missing()
	await _walk_to(BOMBER_WATCH)
	var ranks := []
	for wp in _world().weak_points(Vector2(20.0, 14.2), _pos()).slice(0, 3):
		ranks.append("%s %s %.2f" % [wp["kind"], wp.get("material", ""), float(wp["score"])])
	var h_b := s.health
	var sbm := await _dev_click("^\\+ Bomber$")
	var bomber := _enemy_of("bomber")
	var beh = bomber.behaviour if bomber != null else null
	var min_d := 99.0
	var fuse_seen := false
	var alert := ""
	var markers := 0
	var blasts0: int = g.debug_roster().blasts
	t = 0.0
	while bomber != null and t < 60.0 and g.debug_roster().blasts == blasts0:
		if is_instance_valid(bomber) and bomber.alive:
			min_d = minf(min_d, bomber.plan_pos().distance_to(_pos()))
		if beh != null and beh.state == "fuse" and not fuse_seen:
			fuse_seen = true
			alert = str(g.hud.debug_texts()["alert"])
			markers = g.combat.markers().size()
			await _shot("13a_bomber_fuse_at_the_wall.png")
		await _frames(2)
		t += 2 * DT
	var target: Dictionary = beh.target if beh != null else {}
	var lb2: Dictionary = beh.last_blast if beh != null else {}
	var cb: Dictionary = g.combat.last_blast
	await _wait(2.5)
	await _settle_meshes()
	await _shot("13b_bomber_breach.png")
	var miss_after := _missing()
	_step("17 watch a suicide bomber deliberately attack a wall", target.get("kind", "") == "wall" and fuse_seen and bool(lb2.get("breach", false)),
		"top weak points %s; F10 '%s'; it walked to the %s %s at %s (never to the player: closest %.1f m, the player %.1f m from the target); fuse: HUD '%s', %d ground marker; blast: breach %s, %d voxels, opened %d nav cells; player %.1f m away took %.1f (health %d → %d)" % [
		ranks, sbm, target.get("kind", "?"), target.get("material", ""), target.get("target", "?"), min_d, _pos().distance_to(target.get("target", _pos())), alert, markers,
		lb2.get("breach", false), int(lb2.get("voxels", 0)), (lb2.get("opened", []) as Array).size(), float(cb.get("dist", -1.0)), float(cb.get("taken", 0.0)), h_b, s.health])

	# 18. Persistent damage, then repair it (B, 7, LMB on each damaged section).
	var damaged := _damaged_sections()
	await _walk_to(Vector2(9.4, 11.4))
	await _tap(KEY_B)
	await _wait(0.2)
	var fixed := 0
	var tried := []
	if g.build.active and await _select_piece(KEY_7, "repair"):
		var first := true
		for sec in damaged.slice(0, 6):
			var cpt := _section_center(sec)
			for off in [Vector3(0, 2.3, 0), Vector3(0.38, 1.9, 0), Vector3(-0.38, 1.9, 0), Vector3(0.38, 0.5, 0), Vector3(-0.38, 0.5, 0), Vector3(0, 1.2, 0)]:
				var p := cpt + (Vector2(off.x, 0) if sec.x == 0 else Vector2(0, off.x))
				_move_mouse(_screen_of(p, off.y))
				await _wait(0.35)
				if str(g.build.last_eval.get("reason", "")).begins_with("Needs") and not tried.has("materials"):
					tried.append("materials")
					await _tap(KEY_ESCAPE)
					_note("step 18: '%s' → F10 '%s'" % [g.build.last_eval.get("reason", ""), await _dev_click("^\\+ Materials$")])
					await _tap(KEY_B)
					await _select_piece(KEY_7, "repair")
					_move_mouse(_screen_of(p, off.y))
					await _wait(0.35)
				if g.build.last_eval.get("ok", false):
					if first:
						first = false
						await _shot("14a_repair_mode.png")
					var m0 := _missing()
					await _click(_screen_of(p, off.y))
					await _wait(0.3)
					if _missing() < m0:
						fixed += 1
					break
			tried.append(str(sec))
		await _tap(KEY_ESCAPE)
	await _settle_meshes()
	await _walk_to(Vector2(9.0, 11.8))
	await _shot("14b_repaired.png")
	var miss_fixed := _missing()
	_step("18 experience persistent damage and repair it", miss_after > miss_before and fixed > 0 and miss_fixed < miss_after,
		"house voxels missing: %d before the blast, %d after (persistent; %d damaged sections); B, 7, LMB repaired %d section(s) → %d missing; toast '%s'; planks %d, nails %d" % [
		miss_before, miss_after, damaged.size(), fixed, miss_fixed, g.last_toast, s.inventory.count("wood"), s.inventory.count("nails")])

	# 19. Save and leave: plan one more trip on the map (M) so part 2 can check the plan, then Esc → Save → Main Menu → Save and quit → Quit.
	await _tap(KEY_M)
	await _wait(1.0)
	var how19 := await _map_select(screen, "police")
	if screen.selected == "police":
		await _wait(1.0)
		await _tap(KEY_3)
		await _wait(0.3)
		var pb3: Button = screen.get("_plan_button")
		if pb3 != null and not pb3.disabled:
			await _click_control(pb3)
		await _wait(0.3)
	var plan_note := "%s|%s" % [s.region.planned, s.region.planned_purpose]
	await _tap(KEY_M)
	await _wait(0.3)
	for ch in ["invulnerable", "unlimited"]:
		if s.cheats.get(ch, false):
			await _dev_click("^Invulnerable" if ch == "invulnerable" else "^Unlimited")
			if s.cheats.get(ch, false):
				s.cheats[ch] = false
	await _fight(30.0)
	await _tap(KEY_ESCAPE)
	await _wait(0.3)
	var in_pause: bool = g.debug_modal() == "pause"
	await _shot("15_pause_menu.png")
	var saved_click := await _click_button(_ui().pause_menu, "^save$")
	await _wait(0.3)
	var info := SaveGame.info()
	var snap: Dictionary = JSON.parse_string(JSON.stringify(_snapshot()))
	var f := FileAccess.open(_out.path_join("part1_state.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(snap, "  "))
	f.close()
	var left := await _click_button(_ui().pause_menu, "main menu")
	await _wait(0.3)
	var sq := await _click_button(_ui().pause_menu, "^save and quit")
	for i in 12:
		await _wait(0.25)
		if current_scene != null and current_scene.scene_file_path == MENU:
			break
	var at_menu: bool = current_scene != null and current_scene.scene_file_path == MENU
	_step("19 save and leave the game", in_pause and saved_click != "" and info["valid"] and info["schema"] == SaveGame.SCHEMA and at_menu and plan_note == "police|careful",
		"M, %s, 3 (careful), Plan: planned %s; Esc → pause '%s', clicked '%s' (schema %d, %s), '%s' → '%s' → main menu %s" % [how19, plan_note, _ui().pause_menu.subtitle if is_instance_valid(g) else "?",
		saved_click, int(info["schema"]), UiTheme.save_summary_text(info.get("summary", {})), left, sq, at_menu])
	_finish()
	if at_menu:
		var quit_buttons := _buttons(current_scene, "^quit")
		if not quit_buttons.is_empty():
			print("      clicking '%s' on the main menu: the application quits" % quit_buttons[0].text)
			await _click_control(quit_buttons[0])
			await _wait(1.0)
			print("      FAIL-NOTE: still running after Quit")


func _part2() -> void:
	var f := FileAccess.open(_out.path_join("part1_state.json"), FileAccess.READ)
	var want: Dictionary = JSON.parse_string(f.get_as_text()) if f != null else {}
	if want.is_empty():
		_step("20 part 1 results", false, "no part1_state.json in " + _out)
		return
	# 20. Continue from the main menu after a real application restart.
	if not await _open_menu("16_main_menu_continue.png"):
		_step("20a continue from the main menu", false, "no main menu")
		return
	var cont: Button = current_scene.button("Continue")
	var caption := UiTheme.caption_of(cont) if cont != null else ""
	var clicked := await _click_button(current_scene, "^continue")
	if not await _wait_for_game():
		_step("20a continue from the main menu", false, "the game did not open (notice '%s')" % GameLaunch.notice)
		return
	await _wait(0.6)
	await _shot("17_continued.png")
	_step("20a continue from the main menu", g.debug_modal() == "" and g.left_to == "", "clicked '%s' (%s) → Day %d %s" % [clicked, caption, _state().day(), _state().clock_text()])
	var have: Dictionary = JSON.parse_string(JSON.stringify(_snapshot()))   # same number types as part 1's file
	var s := _state()
	# the house
	var same_house: bool = have["voxel_hash"] == want["voxel_hash"] and str(have["damage"]) == str(want["damage"]) and str(have["objects"]) == str(want["objects"]) \
		and have["built"] == want["built"] and have["foundations"] == want["foundations"] and have["upgraded"] == want["upgraded"]
	_step("20b the house persists", same_house,
		"voxel + colour hash %s, damage %s, %d objects %s, built sections %d, foundations %d, plated %d; world data hash %s" % [
		"same" if have["voxel_hash"] == want["voxel_hash"] else "DIFFERENT", have["damage"], (have["objects"] as Array).size(),
		"same" if str(have["objects"]) == str(want["objects"]) else "DIFFERENT", have["built"], have["foundations"], have["upgraded"],
		"same" if have["world_hash"] == want["world_hash"] else "different (the clock ran a few frames; see note)"])
	# inventory, equipment, weapons, difficulty
	var inv_same := str(have["inventory"]) == str(want["inventory"])
	var gear_same: bool = str(have["equipment"]) == str(want["equipment"]) and str(have["magazines"]) == str(want["magazines"]) and have["active_weapon"] == want["active_weapon"]
	_step("20c inventory, equipment and difficulty persist", inv_same and gear_same and have["difficulty"] == want["difficulty"] and have["difficulty"] == LEVEL,
		"inventory %s; equipment %s; magazines %s, in hand %s; difficulty '%s' (HUD '%s')" % ["same" if inv_same else str(have["inventory"]), have["equipment"], have["magazines"],
		have["active_weapon"], have["difficulty"], g.hud.debug_texts()["period"]])
	# the region map
	var reg_same := str(have["region"]) == str(want["region"])
	await _tap(KEY_M)
	await _wait(1.2)
	var map_ok: bool = g.debug_modal() == "map" and g.map.screen.selected == str(want["region"]["planned"])
	await _shot("18_map_after_restart.png")
	await _tap(KEY_M)
	await _wait(0.3)
	_step("20d the regional map state persists", reg_same and map_ok,
		"%d places known, stock %s, visits %s, plan %s (%s) preselected on the map %s, layout %s" % [(have["region"]["discovered"] as Array).size(), have["region"]["stock"],
		have["region"]["visits"], have["region"]["planned"], have["region"]["purpose"], map_ok, have["region"]["layout"]])
	var stats_same := absf(float(have["total_minutes"]) - float(want["total_minutes"])) < 2.0
	for k in ["health", "hunger", "hydration", "energy"]:
		stats_same = stats_same and absf(float(have[k]) - float(want[k])) < 0.5
	var pos_same := Vector2(have["player"][0], have["player"][1]).distance_to(Vector2(want["player"][0], want["player"][1])) < 0.3
	_step("20e the clock, needs and position persist", stats_same and pos_same,
		"Day %d %s (saved %s), health %d hunger %d hydration %d energy %d, player %s" % [s.day(), s.clock_text(), want["clock"], s.health, s.hunger, s.hydration, s.energy,
		"same place" if pos_same else str(_pos())])
	# the weapons still work after the restart
	var w := _weapons()
	await _tap(KEY_2)
	var other := w.current_id()
	await _tap(KEY_1)
	_step("20f weapons work after the restart", other != "" and w.current_id() == "handgun", "2 → %s, 1 → %s" % [other, w.current_id()])
