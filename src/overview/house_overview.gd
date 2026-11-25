extends Node
## Exp 007 (O): the structural house overview (`game.overview`), a modal view
## of the real house (one simulation: it only reads and shows the house state).
##
##   key       O opens it at home (not in build mode or a panel); O or Esc
##             leaves. The world pauses while it is open, like the map.
##   modes     1 complete house (walls and the roof, when the top storey is
##             viewed), 2 roofless (full walls, no roof), 3 cutaway (walls in
##             the camera-facing half of the house cut down to 1 m above the
##             viewed storey's floor), 4 blueprint (a top-down plan drawn from
##             the house data: blueprint_view.gd, OverviewPlan).
##   levels    PgUp / PgDn step through the storeys that exist (-2..+2); the
##             viewed storey and those under it show (above ground), storeys
##             above it are hidden; underground only the viewed storey shows,
##             cut at 1 m (a plan of the dug space) in every 3D mode.
##   camera    pulled out over the house centre (26 m), Z / C turn it in
##             quarter turns (the blueprint turns with it), +/- or the wheel
##             zoom. Leaving restores the follow camera.
##   shown     walls (with their real damage), floors, doors, barricades,
##             boards, stairs, foundations, observation holes; the blueprint
##             adds integrity colours, knocked-out sections, floor holes,
##             collapsed and strained roof zones.
##   hidden    Eli, enemies, furniture, lamps, yard props, the car, the map
##             table, the fireplace, storage, loot, security devices and other
##             clutter (visibility toggles, restored on leaving; nothing is
##             rebuilt). Daylight lighting while it is open.
##   cost      nothing while closed (no process work; the blueprint is drawn
##             only in mode 4).
##   away      at a POI (game.is_home() false) it says so and stays closed.

const Blueprint := preload("res://src/overview/blueprint_view.gd")

const MODES := ["complete", "roofless", "cutaway", "blueprint"]
const MODE_NAMES := {"complete": "Complete house", "roofless": "Roofless", "cutaway": "Cutaway", "blueprint": "Blueprint"}
const DISTANCE := 26.0
const CUT_HEIGHT := 1.0                ## m above the viewed storey's floor (cutaway, underground)
const KEEP_OBJECTS := ["door", "barricade", "boards"]
const DAY_LIGHT := 0.15                ## the night amount at most while open

var game: Node                         ## SurvivalGame
var is_open := false
var mode := "complete"
var storey := 0
var plan := {}                         ## OverviewPlan of the viewed storey (refreshed on open, level, mode)
var opened := 0                        ## times opened (tests)
var last_text := ""

var _ui: CanvasLayer
var _card: PanelContainer
var _title: Label
var _modes: Label
var _levels_line: Label
var _summary: Label
var _blueprint: Control
var _pivot: Node3D
var _hidden: Array = []                ## [node, was visible]
var _saved := {}


func setup(g: Node) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	for a in OS.get_cmdline_user_args():       # screenshots: --overview=<mode> [--overview-demo]
		if a.begins_with("--overview="):
			_shot_args(a.trim_prefix("--overview="), OS.get_cmdline_user_args().has("--overview-demo"))


func _shot_args(m: String, demo: bool) -> void:
	await get_tree().create_timer(0.6).timeout
	if demo:
		var w: HouseWorld = game.world
		w.explode(Vector3(13.2, 1.2, 2.0), 1.6, 1.0)          # a blast at the kitchen's east wall
		w.explode(Vector3(3.0, 1.0, 9.3), 1.2, 0.8)           # and at the bedroom side of the front
		var h: Node = game.get("holes")
		if h != null:
			game.debug_teleport_player(Vector2(6.5, 2.0))
			h.dev_hole_here()
			game.debug_teleport_player(Vector2(5.0, 8.4))
			h.dev_hole_here()
	open_overview(m)


# --- open / close --------------------------------------------------------------------------

## O. Returns "" or why it didn't open.
func open_overview(m := "") -> String:
	if is_open:
		if m != "":
			set_mode(m)
		return ""
	if game.has_method("is_home") and not game.is_home():
		return _refuse("The house overview only works at home.")
	if not game.get("_ok") or game.state.dead:
		return "The game is not ready."
	if game.debug_modal() != "":
		return _refuse("Close the open panel first.")
	var holes: Node = game.get("holes")
	if holes != null and holes.has_method("busy") and holes.busy():
		return _refuse("Not while you're drilling or looking through a hole.")
	if game.build != null and game.build.active:
		game._set_build(false)
	var lv: Node = game.get("levels")
	storey = int(lv.player_storey) if lv != null else 0
	if m in MODES:
		mode = m
	_save_view()
	game._set_modal("overview", true)       # the world pauses, the cursor is an arrow, the prompt hides
	if game.hud != null:
		game.hud.set_mode("hidden")
	_pivot = Node3D.new()
	_pivot.name = "OverviewPivot"
	game.add_child(_pivot)
	var cam: VoxelCamera = game.camera
	cam.process_mode = Node.PROCESS_MODE_ALWAYS
	cam.target = _pivot
	cam.lift = 0.0
	cam.set("_goal_distance", DISTANCE)
	game.lighting.set_amount(minf(game.lighting.night_amount, DAY_LIGHT))
	_hide_clutter()
	_build_ui()
	is_open = true
	opened += 1
	set_process(true)
	_apply()
	Sfx.ui("ui/click")
	return ""


func close_overview() -> void:
	if not is_open:
		return
	is_open = false
	set_process(false)
	for e in _hidden:
		if is_instance_valid(e[0]):
			(e[0] as Node3D).visible = e[1]
	_hidden.clear()
	if is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null
	_blueprint = null
	var cam: VoxelCamera = game.camera
	cam.target = game.player
	cam.lift = float(_saved.get("lift", 0.0))
	cam.set("_goal_distance", float(_saved.get("distance", 20.0)))
	cam.process_mode = int(_saved.get("cam_mode", Node.PROCESS_MODE_INHERIT))
	var lv: Node = game.get("levels")
	if lv != null:
		lv.view_storey = int(_saved.get("view", lv.player_storey))
		lv.roofs_hidden = bool(_saved.get("roofs_hidden", false))
		lv._update_visibility()
		lv._apply_roof_hide()
	var yard: VoxelYard = game.world.yard
	if yard != null and yard.roof != null:
		yard.roof.visible = bool(_saved.get("roof_visible", true))
	game.lighting.set_amount(float(_saved.get("night", game.lighting.night_amount)))
	if is_instance_valid(_pivot):
		_pivot.queue_free()
	_pivot = null
	if game.hud != null:
		game.hud.set_mode(str(_saved.get("hud", "play")))
	if game.debug_modal() == "overview":
		game._set_modal("", false)
	_saved = {}


func _refuse(text: String) -> String:
	last_text = text
	game.toast(text, "warn")
	return text


func _save_view() -> void:
	var cam: VoxelCamera = game.camera
	var lv: Node = game.get("levels")
	var yard: VoxelYard = game.world.yard
	_saved = {"lift": cam.lift, "distance": float(cam.get("_goal_distance")), "cam_mode": cam.process_mode,
		"view": int(lv.view_storey) if lv != null else 0, "roofs_hidden": bool(lv.roofs_hidden) if lv != null else false,
		"roof_visible": yard.roof.visible if yard != null and yard.roof != null else true,
		"night": game.lighting.night_amount, "hud": str(game.hud.mode) if game.hud != null else "play"}


# --- modes and levels ----------------------------------------------------------------------

func set_mode(m: String) -> void:
	if not (m in MODES):
		return
	mode = m
	if is_open:
		_apply()


## The storeys that exist (sorted).
func storeys() -> Array:
	var lv: Node = game.get("levels")
	return lv.storeys() if lv != null else [0]


## PgUp (+1) / PgDn (-1): the next existing storey. Returns the message.
func step_level(dir: int) -> String:
	var list := storeys()
	var target := storey
	if dir > 0:
		for s in list:
			if s > storey:
				target = s
				break
	else:
		for k in range(list.size() - 1, -1, -1):
			if list[k] < storey:
				target = list[k]
				break
	if target == storey:
		last_text = "Nothing %s %s." % ["above" if dir > 0 else "below", Levels.label(storey)]
		_flash(last_text)
		return last_text
	set_storey(target)
	return last_text


func set_storey(s: int) -> void:
	if not (s in storeys()):
		return
	storey = s
	last_text = Levels.label(s)
	if is_open:
		_apply()


func _top() -> int:
	var lv: Node = game.get("levels")
	return int(lv.roof_storey()) if lv != null else 0


## Storey visibility, the roof, the pivot, the plan and the card for the current mode and level.
func _apply() -> void:
	var lv: Node = game.get("levels")
	if lv != null:
		lv.view_storey = storey
		lv.roofs_hidden = true                    # storeys above the viewed one stay hidden
		lv._update_visibility()                   # storeys, stairs, the underground lid
	for e in _hidden:                             # it also shows the body, the map table, the fireplace
		if is_instance_valid(e[0]):
			(e[0] as Node3D).visible = false
	game.player.visible = false
	var yard: VoxelYard = game.world.yard
	if yard != null and yard.roof != null:
		var roof_on := mode == "complete" and storey >= Levels.GROUND and storey >= _top()
		yard.roof.visible = roof_on
		if roof_on:
			yard.roof_mat.set_shader_parameter("fade", 1.0)
			yard.roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_pivot.global_position = Vector3(HousePlan.FOOTPRINT.get_center().x, Levels.base_y(storey), HousePlan.FOOTPRINT.get_center().y)
	plan = OverviewPlan.collect(game, storey)
	if _blueprint != null:
		_blueprint.visible = mode == "blueprint"
		if mode == "blueprint":
			_blueprint.show_plan(plan, game.camera.goal_yaw())
	_update_cut()
	_update_card()


## The cutaway for the mode: none (1, 2), the camera-facing half above 1 m (3),
## or the whole storey above 1 m (underground).
func _update_cut() -> void:
	var cam: VoxelCamera = game.camera
	var c := HousePlan.FOOTPRINT.get_center()
	var base := Levels.base_y(storey)
	var back := cam.back_dir()
	var flat := Vector3(back.x, 0.0, back.z).normalized()
	var lv: Node = game.get("levels")
	var list: Array = [game.world]
	if lv != null:
		for s in lv.worlds:
			if lv.worlds[s] != null:
				list.append(lv.worlds[s])
	for w in list:
		if not (w as HouseWorld).visible:
			continue
		if storey < Levels.GROUND:
			var o := Vector3(c.x, base + CUT_HEIGHT, c.y) - back * 40.0
			w.set_cut_view(o, back, 80.0, base + CUT_HEIGHT)
		elif mode == "cutaway":
			w.set_cut_view(Vector3(c.x, base + CUT_HEIGHT, c.y) - flat * 0.45, flat, 200.0, base + CUT_HEIGHT)
		else:
			w.set_cut_view(Vector3(0, -100, 0), Vector3.UP, 0.0, 0.45)


## Hides Eli, enemies, furniture and clutter (restored on leaving).
func _hide_clutter() -> void:
	_hidden.clear()
	var lv: Node = game.get("levels")
	var keep: Array = [game.lighting, game.world, game.camera, game.boundary, game.build, _pivot]
	if lv != null:
		for s in lv.worlds:
			keep.append(lv.worlds[s])
	var home: Node = game.get("home")
	var home_root: Node = null
	if home != null and home.get("fireplace") is Node:
		home_root = (home.fireplace as Node).get_parent()
	for n in game.get_children():
		if n is Node3D and not keep.has(n) and n != home_root:
			_hide(n)
	if home_root != null:
		var sky: Variant = home.get("sky")
		for n in home_root.get_children():
			if n != sky:
				_hide(n)
	var worlds: Array = [game.world]
	if lv != null:
		for s in lv.worlds:
			if lv.worlds[s] != null:
				worlds.append(lv.worlds[s])
	for w in worlds:
		var hw := w as HouseWorld
		var keep_w: Array = [hw.chunks, hw.yard, hw.defense, hw.fx, hw.get("_scar_root")]
		for n in hw.get_children():
			if keep_w.has(n):
				continue
			if n is WorldObject and (n as WorldObject).kind in KEEP_OBJECTS:
				continue
			_hide(n)
		if hw.yard != null:
			for n in hw.yard.get_children():
				if n != hw.yard.roof and str(n.name) == "GrassTufts":
					_hide(n)


func _hide(n: Node) -> void:
	if n is Node3D and (n as Node3D).visible:
		_hidden.append([n, true])
		(n as Node3D).visible = false


# --- frame and input ----------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not is_open:
		return
	if game.state.dead or game.debug_modal() != "overview":
		close_overview()
		return
	_update_cut()
	if _blueprint != null and _blueprint.visible:
		_blueprint.set_yaw(game.camera.goal_yaw())


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("dev_menu"):
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := (event as InputEventMouseButton).button_index
		if mb == MOUSE_BUTTON_WHEEL_UP or mb == MOUSE_BUTTON_WHEEL_DOWN:
			game.camera.zoom(-1.0 if mb == MOUSE_BUTTON_WHEEL_UP else 1.0)
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey):
		return
	get_viewport().set_input_as_handled()
	var ke := event as InputEventKey
	if not ke.pressed or ke.echo:
		return
	var k := ke.physical_keycode
	if event.is_action_pressed("pause") or k == KEY_O:
		close_overview()
	elif k >= KEY_1 and k <= KEY_4:
		set_mode(MODES[k - KEY_1])
	elif k == KEY_PAGEUP:
		step_level(1)
	elif k == KEY_PAGEDOWN:
		step_level(-1)
	elif event.is_action_pressed("camera_left") or event.is_action_pressed("camera_right"):
		game.camera.turn(-1 if event.is_action_pressed("camera_left") else 1)
	elif event.is_action_pressed("zoom_in"):
		game.camera.zoom(-1.0)
	elif event.is_action_pressed("zoom_out"):
		game.camera.zoom(1.0)


## O outside the overview (at home, no panel, not in build mode).
func _unhandled_input(event: InputEvent) -> void:
	if is_open or not (event is InputEventKey):
		return
	var ke := event as InputEventKey
	if not ke.pressed or ke.echo or ke.physical_keycode != KEY_O:
		return
	if game.debug_modal() != "" or (game.build != null and game.build.active):
		return
	get_viewport().set_input_as_handled()
	open_overview()


# --- the card ------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "OverviewUI"
	_ui.layer = 5
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.theme()
	_ui.add_child(root)
	_blueprint = Blueprint.new()
	_blueprint.name = "Blueprint"
	_blueprint.visible = false
	root.add_child(_blueprint)
	_card = UiTheme.make_card()
	_card.name = "OverviewCard"
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.offset_top = 14
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_card.add_child(box)
	_title = UiTheme.make_label("", UiTheme.FONT_LARGE, UiTheme.TEXT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_modes = UiTheme.make_label("", UiTheme.FONT_SMALL, UiTheme.ACCENT)
	_modes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_modes)
	_levels_line = UiTheme.make_label("", UiTheme.FONT_SMALL, UiTheme.FROST)
	_levels_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_levels_line)
	_summary = UiTheme.make_caption("", 760, UiTheme.TEXT_DIM)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_summary)
	var keys := UiTheme.make_label("1-4 mode · PgUp / PgDn level · Z / C turn · + / - zoom · O or Esc: back", UiTheme.FONT_SMALL, UiTheme.TEXT_FAINT)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(keys)


func _update_card() -> void:
	if _title == null:
		return
	_title.text = "House overview · %s" % Levels.label(storey)
	var parts := PackedStringArray()
	for k in MODES.size():
		var m: String = MODES[k]
		parts.append(("[%d %s]" if m == mode else "%d %s") % [k + 1, MODE_NAMES[m]])
	_modes.text = "   ".join(parts)
	var lv_parts := PackedStringArray()
	for s in storeys():
		lv_parts.append(("[%s]" if s == storey else "%s") % Levels.number(s))
	_levels_line.text = "Levels: " + "  ".join(lv_parts)
	_summary.text = OverviewPlan.summary(plan)


func _flash(text: String) -> void:
	if _summary != null:
		_summary.text = text + "  ·  " + OverviewPlan.summary(plan)


# --- F10 ------------------------------------------------------------------------------------

func dev_open() -> String:
	var dm: Variant = game.ui.get("dev_menu") if game.ui != null else null
	if dm is Object and is_instance_valid(dm) and dm.has_method("set_open"):
		dm.set_open(false)
	var why := open_overview()
	return "Overview open (1-4 modes, PgUp / PgDn, Esc)." if why == "" else why


func info() -> String:
	return "Overview %s · mode %s · level %s" % ["open" if is_open else "closed", mode, Levels.number(storey)]
