extends SceneTree
## Experiment 002 integrated playtest (the user's §18 scenario) through REAL
## input events (keys, mouse motion, clicks on the actual buttons) and the real
## renderer under Xvfb + software Vulkan. Run it with tools/survival_playtest.sh,
## which starts two separate processes:
##   part 1: New Game from the main menu → wake on Day 1 → inventory → walk the
##           house and yard → fog edge (E) → expedition → eat and drink → build →
##           night → sleep → invasion → damage → repair → save and quit;
##   part 2: Continue from the main menu → verify the house, supplies and stats
##           against part 1's JSON → cheats → audio override fallback.
## The game's debug API is used to READ state, and to act only where input
## can't reasonably reach; every such use is named in the step's line.
## Rendering is switched off between screenshots to save CPU (--render-always
## keeps it on). One line per step: PASS / FAIL / SKIP <step>: <detail>.
##   godot --path . --resolution 1600x900 --fixed-fps 30 -s res://tools/survival_playtest.gd -- --part=1 --out=/abs/dir

const MENU := "res://src/menu/main_menu.tscn"
const GAME := "res://src/game/game.tscn"
const BACK := "turn back|cancel|^back$|close|not now|^stay|^no\\b|leave it"
const FPS := 30.0
const DT := 1.0 / FPS

## Walking routes in plan metres (bedroom door x 2..3 at y 4, front door x 4..5 at y 9).
const BED_TO_YARD := [Vector2(2.5, 3.4), Vector2(2.5, 4.7), Vector2(2.8, 5.0), Vector2(2.8, 8.3), Vector2(4.5, 8.3), Vector2(4.5, 9.7), Vector2(4.5, 10.8)]
const YARD_TO_LIVING := [Vector2(4.5, 10.8), Vector2(4.5, 9.7), Vector2(4.5, 8.3), Vector2(6.5, 8.3)]
const LIVING_TO_BED := [Vector2(4.5, 8.3), Vector2(2.8, 8.3), Vector2(2.8, 5.0), Vector2(2.5, 4.7), Vector2(2.5, 3.4), Vector2(2.0, 2.7)]
const LIVING_TO_YARD := [Vector2(4.5, 8.3), Vector2(4.5, 9.7), Vector2(4.5, 10.8)]
const FOG_EDGE := Vector2(4.5, 12.25)
const FRONT_YARD := Vector2(9.0, 10.8)
const WALL_SPOT := Vector2(9.5, 9.0)            ## middle of the solid south-wall section x 9..10
const BARRICADE_SPOT := Vector2(13.0, 10.5)     ## a 1 m barricade on the line x = 13 in the front yard
const SHOOT_SPOT := Vector2(10.4, 11.0)         ## where the player shoots it from

var _part := 1
var _out := ""
var _render_always := false
var _fails := 0
var _passes := 0
var _skips := 0
var _notes: Array[String] = []
var _held := {}
var _finished := false
var _invasion_shot := false
var _doors_opened: Array[String] = []
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


func _to_window(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _move_mouse(p: Vector2) -> void:
	var w := _to_window(p)
	Input.warp_mouse(w)
	var mm := InputEventMouseMotion.new()
	mm.position = w
	mm.global_position = w
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
	var t: String = b.text if b is Button else b.name
	await _click_control(b)
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
			if str(g.debug_prompt()).to_lower().contains("open") and tries <= 4:
				_set_moves({})
				_doors_opened.append(str(g.debug_prompt()))
				await _tap(KEY_E)
				await _wait(0.6)
			elif tries <= 6:
				# sidestep a snag, perpendicular to the main direction
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


func _threats() -> int:
	return g.debug_living_enemies()


func _nearest_threat() -> Vector2:
	var best := Vector2.INF
	for q in g.debug_enemy_positions():
		if best == Vector2.INF or q.distance_to(_pos()) < best.distance_to(_pos()):
			best = q
	return best


## Line of fire from the muzzle to a psycho (the world's own aim ray).
func _clear_shot(target: Vector2) -> bool:
	var from := Vector3(_pos().x, Tuning.MUZZLE_HEIGHT, _pos().y)
	var to := Vector3(target.x, 1.1, target.y)
	var hit: Vector3 = _world().aim_ray(from, (to - from).normalized())
	return hit.distance_to(from) >= from.distance_to(to) - 0.45


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


## Aims the real mouse at the nearest psycho and holds LMB while there is a clear
## shot, until no threats remain or `limit` game seconds pass. Returns the game
## seconds spent.
func _fight(limit: float, shot_name := "") -> float:
	var t := 0.0
	var held := false
	var shot_taken := shot_name == ""
	while t < limit and _threats() > 0 and not _state().dead:
		var e := _nearest_threat()
		var fire := e != Vector2.INF and e.distance_to(_pos()) < 11.0 and _clear_shot(e)
		if not shot_taken and fire:
			shot_taken = true          # the screenshot before the first shot, psycho on screen
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
		if _state().inventory.count("ammo") == 0 and _threats() > 0 and not _state().cheats.get("unlimited", false):
			if held:
				_mouse_button(_screen_of(e), false)
				held = false
			await _cheat_on("unlimited", "out of ammo with %d psycho(s) left" % _threats())
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


func _materials() -> int:
	var inv := _state().inventory
	return inv.count("wood") + inv.count("nails") + inv.count("scrap")


func _object_counts() -> Dictionary:
	var out := {}
	for k in ["crate", "barricade", "door", "rain_collector", "wall"]:
		out[k] = _world().count_objects(k)
	return out


func _voxel_hash() -> String:
	var w := _world()
	if w.grid == null:
		return ""
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(w.grid.mat)
	return c.finish().hex_encode()


func _world_hash() -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(var_to_bytes(_world().save_data()))
	return c.finish().hex_encode()


func _object_positions() -> Array:
	var out := []
	for n in _world().interactables():
		if is_instance_valid(n) and n is Node3D:
			var q: Vector3 = n.global_position
			var kind: String = str(n.get("kind")) if n.get("kind") != null else (n.get_script().resource_path.get_file().get_basename() if n.get_script() != null else n.get_class())
			out.append("%s@%.2f,%.2f" % [kind, q.x, q.z])
	out.sort()
	return out


func _snapshot() -> Dictionary:
	var s := _state()
	return {
		"day": s.day(), "clock": s.clock_text(), "total_minutes": s.total_minutes,
		"health": s.health, "hunger": s.hunger, "hydration": s.hydration, "energy": s.energy,
		"inventory": s.inventory.counts.duplicate(), "cheats": s.cheats.duplicate(),
		"damage": _world().damage_summary(), "voxel_hash": _voxel_hash(), "world_hash": _world_hash(),
		"objects": _object_counts(), "object_positions": _object_positions(),
		"player": [_pos().x, _pos().y],
	}


# --- scenario ------------------------------------------------------------------------------

func _run() -> void:
	_render(false)
	print("SURVIVAL PLAYTEST part %d (out: %s)" % [_part, _out])
	if _part == 1:
		SaveGame.delete_save()
		GameLaunch.seed = 1123        # deterministic run (expedition rolls, stragglers)
		await _part1()
	else:
		await _part2()
	if not _finished:
		_finish()
	quit(1 if _fails > 0 else 0)


func _open_game_from_menu(button: String) -> bool:
	change_scene_to_file(MENU)
	await _wait(1.5)
	if current_scene == null or current_scene.scene_file_path != MENU:
		return false
	await _shot("01_main_menu.png" if _part == 1 else "13_main_menu_continue.png")
	var clicked := await _click_button(current_scene, "^" + button)
	if clicked == "":
		print("      no '%s' button on the menu" % button)
		return false
	for i in 40:
		await _wait(0.25)
		if current_scene != null and current_scene.scene_file_path == GAME:
			break
		# A confirmation (e.g. "overwrite the saved run?") answered yes.
		var yes := _buttons(root, "^(yes|overwrite|start|confirm|ok)", BACK)
		if not yes.is_empty():
			await _click_control(yes[0])
	g = current_scene
	return g != null and g.scene_file_path == GAME and g.has_method("debug_state")


func _part1() -> void:
	# 1. New game from the main menu, wake on Day 1.
	var ok := await _open_game_from_menu("new game")
	if not ok:
		_step("1 new game from the main menu", false, "the game scene did not open")
		return
	var t := 0.0
	while g.debug_modal() == "intro" and t < 40.0:
		await _wait(0.5)
		t += 0.5
		if is_equal_approx(t, 2.5):
			await _shot("01b_intro.png")
		if t > 14.0 and int(t * 2) % 10 == 0:
			await _tap(KEY_SPACE)
	var bed: Vector3 = _world().bed_position()
	var near_bed := _pos().distance_to(Vector2(bed.x, bed.z)) < 2.2
	_step("1 new game from the main menu, wake on Day 1", g.debug_modal() == "" and _state().day() == 1 and near_bed,
		"Day %d %s, modal '%s', %.1f m from the bed, intro %.1f s, initial save %s" % [_state().day(), _state().clock_text(), g.debug_modal(),
		_pos().distance_to(Vector2(bed.x, bed.z)), t, "yes" if SaveGame.info()["valid"] else "no"])
	await _shot("02_wake_day1.png")

	# 2. Inspect food, water and inventory (I).
	await _tap(KEY_I)
	await _wait(0.3)
	var inv_open: bool = g.debug_modal() == "inventory"
	await _shot("03_inventory.png")
	var inv := _state().inventory
	await _tap(KEY_I)
	await _wait(0.2)
	_step("2 inspect food, water and inventory", inv_open and g.debug_modal() == "",
		"I opened the panel (%s); food %d canned + %d snacks, water %d, ammo %d; hunger %d, hydration %d, energy %d" % [inv_open, inv.count("canned_food"),
		inv.count("snacks"), inv.count("water"), inv.count("ammo"), _state().hunger, _state().hydration, _state().energy])

	# 3. Move around the house and yard (WASD).
	var p0 := _pos()
	var walked := await _walk(BED_TO_YARD)
	walked = walked and await _walk_to(Vector2(8.0, 11.0))
	walked = walked and await _walk_to(Vector2(4.5, 11.2))
	await _shot("04_day_house.png")
	_step("3 move around the house and yard", walked and _pos().y > 9.5, "bedroom → living room → front door → yard (%s → %s); doors opened with E: %s" % [p0, _pos(), _doors_opened])

	# 4. Enter the fog at the edge (E).
	var at_edge := await _walk_to(FOG_EDGE)
	await _wait(0.3)
	var prompt := str(g.debug_prompt())
	await _shot("05_fog_boundary.png")
	await _tap(KEY_E)
	await _wait(0.5)
	_step("4 enter the fog at the edge (E)", at_edge and prompt != "" and g.debug_modal() == "expedition", "prompt '%s', modal '%s'" % [prompt, g.debug_modal()])

	# 5. Select an expedition and resolve an event (clicks on the screen's buttons, keys 1-3).
	var before := _state().inventory.counts.duplicate()
	var t_before := _state().total_minutes
	var clicks := []
	var answered := ""
	var scr: Node = _ui().expedition
	var shots_done := {}
	var names := {"list": "06_expedition_selection.png", "gear": "06b_expedition_gear.png", "confirm": "06c_expedition_confirm.png",
		"event": "06d_expedition_event.png", "outcome": "06e_expedition_outcome.png", "report": "06f_expedition_report.png"}
	t = 0.0
	while g.debug_modal() == "expedition" and t < 120.0:
		var st := str(scr.get("step"))
		if names.has(st) and not shots_done.has(st):
			shots_done[st] = true
			await _shot(names[st])
		var pb = scr.get("primary_button")
		match st:
			"list":
				if str(scr.get("selected")) == "" and scr.get("destination_buttons") is Dictionary:
					for id in scr.destination_buttons:
						if scr.available(id).get("ok", false):
							clicks.append(id)
							await _click_control(scr.destination_buttons[id])
							break
				elif pb is Button and _shown(pb):
					clicks.append(pb.text)
					await _click_control(pb)
			"event":
				var opts: Array = scr.get("option_buttons") if scr.get("option_buttons") != null else []
				for i in opts.size():
					var b: Button = opts[i]
					if is_instance_valid(b) and not b.disabled:
						answered = b.text
						if i < 3:
							await _tap(KEY_1 + i)          # the option's number key
						else:
							await _click_control(b)
						break
			"gear", "confirm", "outcome", "report":
				if pb is Button and _shown(pb) and not pb.disabled:
					clicks.append(pb.text)
					await _click_control(pb)
		await _wait(0.4)
		t += 0.4
	if scr.get("step") == null and g.debug_modal() == "expedition":
		# the foundation stub screen: click through its buttons
		for i in 14:
			if g.debug_modal() != "expedition":
				break
			var b := await _click_button(scr, "", BACK)
			if b != "":
				clicks.append(b)
			await _wait(0.6)
	var exp: Dictionary = g.last_expedition
	var res: Dictionary = exp.get("result", {})
	_step("5a select an expedition", not res.is_empty(), "%s; clicked %s" % [res.get("name", "?"), clicks])
	if scr.get("step") == null:
		_skip("5b resolve an event", "the expedition screen offered no event (foundation stub)")
	else:
		_step("5b resolve an event", answered != "" and not res.get("events", []).is_empty(), "answered '%s' with its number key; events %s" % [answered.replace("\n", " "), res.get("events", [])])

	# 6. Return with usable resources; time advanced exactly once.
	var gained := []
	for id in _state().inventory.counts:
		if _state().inventory.count(id) > int(before.get(id, 0)):
			gained.append("%s +%d" % [id, _state().inventory.count(id) - int(before.get(id, 0))])
	var once := absf((_state().total_minutes - t_before) - float(res.get("minutes", -1))) < 1.0
	_step("6 return with usable resources", not gained.is_empty() and once and FogBoundary.LOT.has_point(_pos()) and g.debug_modal() == "",
		"gained %s; %s min away (result %s); back at %s; autosave %s" % [gained, int(_state().total_minutes - t_before), res.get("minutes", "?"), _pos(), "expedition" in g.autosave_log])

	# 7. Eat and drink (inventory panel buttons).
	var h0 := _state().hunger
	var w0 := _state().hydration
	await _tap(KEY_I)
	await _wait(0.3)
	var inv_panel: Node = _ui().inventory
	var ate := ""
	var drank := ""
	if inv_panel.has_method("use_button"):
		for id in ["canned_food", "snacks"]:
			var b: Button = inv_panel.use_button(id)
			if b != null and _shown(b) and not b.disabled and ate == "":
				ate = "Use " + Items.name_of(id)
				await _click_control(b)
		await _wait(0.3)
		var wb: Button = inv_panel.use_button("water")
		if wb != null and _shown(wb) and not wb.disabled:
			drank = "Use " + Items.name_of("water")
			await _click_control(wb)
	else:
		ate = await _click_button(inv_panel, "eat|" + Items.name_of("canned_food") + "|" + Items.name_of("snacks"), BACK)
		await _wait(0.2)
		drank = await _click_button(inv_panel, "drink|" + Items.name_of("water"), BACK)
	await _wait(0.3)
	await _shot("03b_inventory_used.png")
	await _tap(KEY_I)
	await _wait(0.2)
	_step("7 eat and drink", _state().hunger > h0 and _state().hydration > w0,
		"clicked '%s' and '%s': hunger %d → %d, hydration %d → %d" % [ate, drank, h0, _state().hunger, w0, _state().hydration])

	# 8. Build a barricade: B, key 2, the mouse on the ground, LMB.
	var m0 := _materials()
	var o0 := _object_counts()
	await _walk_to(Vector2(11.5, 11.6))
	await _tap(KEY_B)
	await _wait(0.3)
	var build_on: bool = g.build.active
	var real_build: bool = g.build.has_method("select")
	var built := ""
	if build_on and real_build:
		await _tap(KEY_2)
		_move_mouse(_screen_of(BARRICADE_SPOT, 0.0))
		await _wait(0.6)                          # the ghost follows the mouse
		await _shot("07_construction_mode.png")
		var why := str(g.build.last_eval.get("reason", ""))
		await _click(_screen_of(BARRICADE_SPOT, 0.0))
		await _wait(0.5)
		if _object_counts()["barricade"] > o0["barricade"]:
			built = "'%s' at %s" % [g.build.piece_id(), BARRICADE_SPOT]
		elif why != "":
			built = ""
			print("      build refused: " + why)
		await _settle_meshes()
		await _shot("07b_built.png")
	else:
		await _shot("07_construction_mode.png")
	await _tap(KEY_ESCAPE)
	await _wait(0.2)
	if not real_build:
		_skip("8 build or repair a barricade or wall", "build mode is the foundation stub ('%s')" % g.last_toast)
	else:
		_step("8 build a barricade", built != "" and _materials() < m0 and not g.build.active,
			"B, 2, LMB: %s, toast '%s'; barricades %d → %d; materials %d → %d; Esc left build mode %s" % [built if built != "" else "nothing placed",
			g.last_toast, o0["barricade"], _object_counts()["barricade"], m0, _materials(), not g.build.active])

	# 9. Advance into night (dev menu: Night 20:00, then ×10 until dark, then ×1).
	var how := await _to_night()
	await _shot("08_night_house.png")
	_step("9 advance into night", _state().night_amount() > 0.9, "%s → Day %d %s, night %.2f" % [how, _state().day(), _state().clock_text(), _state().night_amount()])

	# 10. Sleep where safe (walk to the bed, E, click a sleep option).
	var to_bed := await _walk([Vector2(4.5, 11.2)] + YARD_TO_LIVING + LIVING_TO_BED)
	await _tap(KEY_E)
	await _wait(0.3)
	var dialog: bool = g.debug_modal() == "sleep"
	var e0 := _state().energy
	var t0 := _state().total_minutes
	var chosen := ""
	if dialog:
		chosen = await _click_button(_ui().sleep_dialog, "morning|sleep|hour", BACK)
		t = 0.0
		while g.debug_modal() != "" and t < 20.0:
			await _wait(0.2)
			t += 0.2
	_step("10 sleep where safe", to_bed and dialog and _state().total_minutes > t0 + 60.0 and g.debug_modal() == "",
		"walked to the bed %s, E opened the dialog %s, chose '%s': %s → Day %d %s, energy %d → %d, autosave %s" % [to_bed, dialog, chosen,
		SurvivalGame._hhmm(t0), _state().day(), _state().clock_text(), e0, _state().energy, "wake" in g.autosave_log])

	# 11. Trigger and survive an invasion (dev menu button; shoot with the mouse).
	if _state().night_amount() < 0.9:
		_note("step 11 back to night: " + await _to_night())
	await _walk(BED_TO_YARD)
	await _walk_to(FRONT_YARD)
	g.debug_set_spawn_gap(Vector2(3.0, 5.0))
	_note("step 11 shortened the invasion spawn gaps to 3-5 s (debug API) to keep the run short")
	var trig := await _dev_click("^Next invasion|invasion")
	if not g.debug_director().active:
		g.dev_trigger_invasion()
		_note("step 11 triggered the invasion through the dev API (no dev-menu button matched)")
	var size: int = g.debug_director().total
	var shots0: int = g.shots_fired
	t = 0.0
	while g.debug_director().active and t < 300.0 and not _state().dead:
		if _threats() > 0:
			t += await _fight(20.0, "" if _invasion_shot else "09_invasion.png")
			_invasion_shot = true
		await _wait(0.3)
		t += 0.3
	if g.debug_director().active:
		g.debug_kill_enemies()
		_note("step 11 fallback: debug_kill_enemies after %.0f s" % t)
		await _wait(1.0)
	_step("11 trigger and survive an invasion", not g.debug_director().active and not _state().dead and not _state().run.get("invasion_active", true),
		"trigger '%s', %d invaders, %d shots, health %d, invasions_done %d, toast '%s', autosave %s" % [trig, size, g.shots_fired - shots0, _state().health,
		int(_state().run.get("invasions_done", 0)), g.last_toast, "invasion_end" in g.autosave_log])

	# 12. Observe structural damage, then repair or rebuild.
	await _fight(30.0)
	var dmg0: Dictionary = _world().damage_summary()
	var shot_wall := 0
	# A known damaged section for the repair tool: shoot the south wall.
	await _walk_to(SHOOT_SPOT)                  # beside, not in front of, the hole-to-be
	if _state().inventory.count("ammo") < 6:
		await _cheat_on("unlimited", "rounds to shoot a wall for the damage check")
	var wall_aim := _screen_of(WALL_SPOT, 1.0)
	for i in 10:
		var off := Vector2((i % 3 - 1) * 14.0, (i / 3 - 1) * 16.0)
		await _click(wall_aim + off)
		await _wait(0.25)
		shot_wall += 1
	if _state().cheats.get("unlimited", false):
		await _dev_click("^Unlimited")            # the repair must cost materials
	var dmg1: Dictionary = _world().damage_summary()
	await _wait(1.5)                            # debris settles
	await _settle_meshes()
	await _shot("10_damaged_house.png")
	_step("12a observe structural damage", int(dmg1.get("missing_voxels", 0)) > 0 or int(dmg1.get("damaged_objects", 0)) > 0,
		"after the invasion %s, after %d wall shots %s" % [dmg0, shot_wall, dmg1])
	var repaired := ""
	var repair_why := ""
	await _tap(KEY_B)
	await _wait(0.2)
	if g.build.active and g.build.has_method("select"):
		await _tap(KEY_7)
		var aim := _screen_of(WALL_SPOT, 1.95)        # intact boards above the hole
		_move_mouse(aim)
		await _wait(0.6)
		repair_why = str(g.build.last_eval.get("reason", ""))
		if repair_why.begins_with("Needs"):
			await _tap(KEY_ESCAPE)
			var add := await _dev_click("^\\+ Materials")
			_note("step 12: '%s' → dev menu '%s'" % [repair_why, add])
			await _tap(KEY_B)
			await _tap(KEY_7)
			_move_mouse(aim)
			await _wait(0.6)
			repair_why = str(g.build.last_eval.get("reason", ""))
		await _shot("10b_repair_mode.png")
		var before_missing := int(_world().damage_summary().get("missing_voxels", 0))
		await _click(aim)
		await _wait(0.5)
		if int(_world().damage_summary().get("missing_voxels", 0)) < before_missing:
			repaired = "build mode repair (B, 7, LMB on the section)"
		await _tap(KEY_ESCAPE)
	await _settle_meshes()
	var dmg2: Dictionary = _world().damage_summary()
	await _shot("11_repaired_house.png")
	_step("12b repair or rebuild", repaired != "" and int(dmg2.get("missing_voxels", 0)) < int(dmg1.get("missing_voxels", 0)),
		"%s (evaluation '%s', toast '%s'): %s → %s" % [repaired if repaired != "" else "not repaired", repair_why, g.last_toast, dmg1, dmg2])

	# 13. Save (pause menu) and quit (main menu → Quit).
	await _fight(60.0)
	# Leave some visible damage for part 2 to verify.
	if int(_world().damage_summary().get("missing_voxels", 0)) == 0:
		await _walk_to(SHOOT_SPOT)
		if _state().inventory.count("ammo") < 3:
			await _cheat_on("unlimited", "rounds to leave damage for part 2 to verify")
		for i in 3:
			await _click(_screen_of(WALL_SPOT, 1.0) + Vector2(i * 10.0, 0))
			await _wait(0.25)
	# Cheats off before saving, so part 2 starts from a clean slate.
	for c in ["invulnerable", "unlimited"]:
		if _state().cheats.get(c, false):
			await _dev_click("^Invulnerable" if c == "invulnerable" else "^Unlimited")
			if _state().cheats.get(c, false):
				_state().cheats[c] = false
	await _tap(KEY_ESCAPE)
	await _wait(0.3)
	var paused: bool = g.debug_modal() == "pause"
	await _shot("12_pause_menu.png")
	var saved_click := await _click_button(_ui().pause_menu, "^save$")
	await _wait(0.3)
	var info := SaveGame.info()
	var snap: Dictionary = JSON.parse_string(JSON.stringify(_snapshot()))
	var f := FileAccess.open(_out.path_join("part1_state.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(snap, "  "))
	f.close()
	_step("13a save", paused and saved_click != "" and info["valid"], "pause menu %s, clicked '%s', toast '%s', save valid %s, %s" % [paused, saved_click, g.last_toast, info["valid"], snap["damage"]])
	var left := await _click_button(_ui().pause_menu, "main menu")
	for i in 12:
		await _wait(0.25)
		if current_scene != null and current_scene.scene_file_path == MENU:
			break
		for layer in root.get_children():
			if layer is CanvasLayer or layer == current_scene:
				var yes := _buttons(layer, "yes|leave|main menu|quit", BACK)
				if not yes.is_empty():
					await _click_control(yes[0])
					break
	var at_menu: bool = current_scene != null and current_scene.scene_file_path == MENU
	_step("13b quit to the main menu", at_menu, "clicked '%s'" % left)
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
		_step("P2 part 1 results", false, "no part1_state.json in " + _out)
		return
	# 1. Continue from the main menu.
	var ok := await _open_game_from_menu("continue")
	if not ok:
		_step("P2.1 continue from the main menu", false, "the game did not open (notice '%s')" % GameLaunch.notice)
		return
	await _wait(0.5)
	_step("P2.1 continue from the main menu", g.debug_modal() == "" and g.left_to == "", "Day %d %s" % [_state().day(), _state().clock_text()])
	await _shot("14_continued.png")
	# 2. Structure, supplies and survival state persist.
	var have: Dictionary = JSON.parse_string(JSON.stringify(_snapshot()))   # same number types as part 1's file
	var same_house: bool = have["voxel_hash"] == want["voxel_hash"] and str(have["damage"]) == str(want["damage"]) \
		and str(have["objects"]) == str(want["objects"]) and str(have["object_positions"]) == str(want["object_positions"])
	_step("P2.2 structural changes persist", same_house,
		"voxel hash %s, damage %s, objects %s, %d object positions; world data hash %s" % ["same" if have["voxel_hash"] == want["voxel_hash"] else "DIFFERENT",
		have["damage"], have["objects"], (have["object_positions"] as Array).size(), "same" if have["world_hash"] == want["world_hash"] else "different"])
	var inv_same := true
	for id in want["inventory"]:
		if int(want["inventory"][id]) != _state().inventory.count(id):
			inv_same = false
	inv_same = inv_same and _state().inventory.counts.size() == (want["inventory"] as Dictionary).size()
	var stats_same := absf(_state().total_minutes - float(want["total_minutes"])) < 2.0
	for k in ["health", "hunger", "hydration", "energy"]:
		stats_same = stats_same and absf(float(_state().get(k)) - float(want[k])) < 0.5
	var pos_same := _pos().distance_to(Vector2(want["player"][0], want["player"][1])) < 0.3
	_step("P2.3 supplies and survival state persist", inv_same and stats_same and pos_same,
		"inventory %s, Day %d %s (saved %s), health %d hunger %d hydration %d energy %d, player %s" % ["same" if inv_same else str(_state().inventory.counts),
		_state().day(), _state().clock_text(), want["clock"], _state().health, _state().hunger, _state().hydration, _state().energy, "same place" if pos_same else str(_pos())])
	# 3. Cheat controls through the dev menu.
	var inv_btn := await _dev_click("^Invulnerable")
	var invuln: bool = _state().cheats.get("invulnerable", false)
	var h0 := _state().health
	var spawn_btn := await _dev_click("^Spawn 1|spawn")
	if _threats() == 0:
		g.dev_spawn(1)
		_note("P2.3 spawned the psycho through the dev API (no dev-menu spawn button)")
	var t := 0.0
	var hits := 0
	var hp_min := h0
	while t < 40.0 and _threats() > 0:
		var e := _nearest_threat()
		if e != Vector2.INF and e.distance_to(_pos()) < 1.0:
			hits += 1
		hp_min = minf(hp_min, _state().health)
		if hits > 20:
			break
		await _wait(0.2)
		t += 0.2
	_step("P2.4a invulnerable cheat", inv_btn != "" and invuln and hits >= 8 and hp_min >= h0 - 0.01,
		"clicked '%s' → %s; clicked '%s'; psycho in reach for %.1f s, health %d → min %d" % [inv_btn, invuln, spawn_btn, hits * 0.2, h0, hp_min])
	var unl_btn := await _dev_click("^Unlimited")
	var ammo0 := _state().inventory.count("ammo")
	var shots0: int = g.shots_fired
	await _fight(20.0)
	for i in 3:
		await _click(_screen_of(_pos() + Vector2(0, 2.5), 0.0))
		await _wait(0.25)
	_step("P2.4b unlimited cheat", unl_btn != "" and _state().cheats.get("unlimited", false) and _state().inventory.count("ammo") == ammo0 and g.shots_fired > shots0,
		"clicked '%s'; %d shots, ammo %d → %d; psychos left %d" % [unl_btn, g.shots_fired - shots0, ammo0, _state().inventory.count("ammo"), _threats()])
	await _dev_click("^Invulnerable")
	await _dev_click("^Unlimited")
	_step("P2.4c cheats switch off again", not _state().cheats.get("invulnerable", true) and not _state().cheats.get("unlimited", true), str(_state().cheats))
	# 4. Audio override fallback.
	var resolver: GDScript = load("res://src/common/asset_resolver.gd")
	if not resolver.get_script_method_list().any(func(m): return m["name"] == "get_audio"):
		_skip("P2.5 audio override fallback", "AssetResolver.get_audio does not exist yet")
	else:
		var dir := _out.path_join("override_test")
		DirAccess.make_dir_recursive_absolute(dir.path_join("audio/weapon"))
		var bad := FileAccess.open(dir.path_join("audio/weapon/handgun_fire.ogg"), FileAccess.WRITE)
		bad.store_string("this is not an ogg file")
		bad.close()
		AssetResolver.set_override_root(dir)
		AssetResolver.clear_cache()
		var stream: Resource = resolver.call("get_audio", "weapon/handgun_fire")
		AssetResolver.set_override_root("")
		AssetResolver.clear_cache()
		var path := stream.resource_path if stream != null else ""
		_step("P2.5 audio override fallback", stream != null and path.contains("template_handgun_fire"), "corrupt override → %s" % (path if path != "" else str(stream)))
