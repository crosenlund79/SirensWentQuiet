class_name RegionMapScreen
extends CanvasLayer
## The interactive region map (SPEC-003 §6). Owner: M.
##
## A full-screen CanvasLayer: the 3D miniature (RegionMapView) in its own
## SubViewport and World3D, the pin layer (MapMarkers), a list of known
## places, an info panel with the mission purpose picker and "Plan expedition",
## key hints and a legend. It reads GameState (region discovery, stock, plan,
## inventory, clock) and writes only the plan (RegionState.planned /
## planned_purpose). It pauses nothing itself; the game decides.
##
##   var map := RegionMapScreen.new()
##   add_child(map)
##   map.destination_selected.connect(_on_plan)   # (id, purpose)
##   map.closed.connect(_on_map_closed)
##   map.open(state)
##
## Keys while open: drag / WASD / arrows pan, wheel / + / - zoom, H your house,
## Tab / Shift+Tab next place, 1-4 mission purpose, Enter plan, Esc or M close.

signal closed
signal destination_selected(id: String, purpose: String)

const LIST_W := 272.0
const INFO_W := 384.0
const MARGIN := 18.0
const TOP := 78.0
const PAN_SPEED := 0.55          ## fraction of the camera distance per second

var is_open := false
var state: GameState
var view: RegionMapView
var markers: MapMarkers
var selected := ""
var approach := "general"
var target := ""
var layout_ok := true
var last_planned := ""           ## "id|purpose" of the last plan made on this screen

var _root: Control
var _viewport: SubViewport
var _container: SubViewportContainer
var _title_sub: Label
var _list_box: VBoxContainer
var _list_buttons := {}
var _info_panel: PanelContainer
var _info: VBoxContainer
var _approach_buttons := {}
var _plan_button: Button
var _status: Label
var _tween: Tween
var _summary := {}


func _init() -> void:
	layer = 65
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_build_ui()


# --- API --------------------------------------------------------------------------

## Opens the map for a run (`state` may be null: a fresh sample run).
func open(game_state: GameState) -> void:
	if _root == null:
		_build_ui()
	state = game_state if game_state != null else GameState.new()
	view.build()
	layout_ok = state.region.layout == RegionTerrain.LAYOUT_ID
	view.set_night(state.night_amount())
	_refresh_entries()
	_rebuild_list()
	_update_title()
	var pick := state.region.planned if _known(state.region.planned) else (selected if _known(selected) else "")
	select(pick, false)
	if pick != "":
		var sp := MapInfo.split_purpose(state.region.planned_purpose) if pick == state.region.planned else ["general", ""]
		_set_approach(sp[0], sp[1])
	var was_open := is_open
	is_open = true
	visible = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if not was_open:
		Sfx.ui("ui/open")
		if _tween != null and _tween.is_valid():
			_tween.kill()
		if is_inside_tree():
			_root.modulate.a = 0.0
			_tween = create_tween()
			_tween.tween_property(_root, "modulate:a", 1.0, UiTheme.FADE_IN)
		else:
			_root.modulate.a = 1.0


func close() -> void:
	if not is_open:
		return
	is_open = false
	Sfx.ui("ui/close")
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if is_inside_tree():
		_tween = create_tween()
		_tween.tween_property(_root, "modulate:a", 0.0, UiTheme.FADE_OUT)
		_tween.tween_callback(_hide_now)
	else:
		_hide_now()
	closed.emit()


func _hide_now() -> void:
	if is_open:
		return
	visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Selects a place (a discovered location id, MapInfo.HOME or "" for none).
## `fly` moves the camera to it.
func select(id: String, fly := true) -> void:
	if id != "" and not _known(id):
		id = ""
	selected = id
	markers.selected = id
	if id == "":
		markers.route_world = PackedVector3Array()
		view.set_selected(Vector3.INF)
		_show_info()
		return
	var anchor := view.terrain.anchor_of(id)
	view.set_selected(anchor)
	markers.route_world = _route(id)
	if fly:
		view.set_view(anchor, minf(view.distance_target, 72.0))
	_summary = MapInfo.summary(id, state)
	var sp := MapInfo.split_purpose(state.region.planned_purpose) if id == state.region.planned else ["general", ""]
	approach = sp[0]
	target = sp[1]
	_show_info()
	for k in _list_buttons:
		(_list_buttons[k] as Button).button_pressed = k == id


## Plans an expedition to the selected place with the chosen purpose.
## Returns false if nothing plannable is selected.
func plan_selected() -> bool:
	if selected == "" or selected == MapInfo.HOME or not RegionLocations.has(selected):
		return false
	var a := _approach_def(approach)
	if not a.is_empty() and not a.get("available", true):
		return false
	var purpose := approach
	if approach == "targeted" and target != "":
		purpose = "targeted:" + target
	MapInfo.plan(state, selected, purpose)
	last_planned = selected + "|" + purpose
	markers.planned = selected
	_rebuild_list()
	_show_info()
	destination_selected.emit(selected, purpose)
	return true


## Ids of the places shown on the map (discovered ones, plus HOME).
func shown_ids() -> Array:
	var out := []
	for e in markers.entries:
		out.append(e["id"])
	return out


func find_home() -> void:
	select(MapInfo.HOME, false)
	view.set_view(view.terrain.anchor_of(MapInfo.HOME), 34.0)


# --- input -------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_open or not visible:
		return
	if UiModal.is_cancel_event(event) or (event.is_action_pressed("open_map") and not event.is_echo()):
		get_viewport().set_input_as_handled()
		close()
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	var handled := true
	match k.physical_keycode:
		KEY_H:
			find_home()
		KEY_TAB:
			_cycle(-1 if k.shift_pressed else 1)
		KEY_ENTER, KEY_KP_ENTER:
			plan_selected()
		KEY_1, KEY_2, KEY_3, KEY_4:
			var i := k.physical_keycode - KEY_1
			if selected != "" and selected != MapInfo.HOME and i < _summary.get("approaches", []).size():
				_set_approach(_summary["approaches"][i]["id"], "")
		KEY_EQUAL, KEY_KP_ADD, KEY_PAGEUP:
			view.zoom_by(0.8)
		KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN:
			view.zoom_by(1.25)
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open:
		return
	var v := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_up", "move_down"))
	if v != Vector2.ZERO:
		var d := v.limit_length(1.0) * view.distance * PAN_SPEED * delta
		view.pan(Vector3(d.x, 0.0, d.y).rotated(Vector3.UP, view.yaw))
	var cursor := markers.get_local_mouse_position() if markers.get_global_rect().has_point(markers.get_global_mouse_position()) else Vector2.INF
	view.set_clear_points(cursor, view.terrain.anchor_of(selected) if selected != "" else Vector3.INF)


func _cycle(dir: int) -> void:
	var ids := _sorted_ids()
	if ids.is_empty():
		return
	var i := ids.find(selected)
	i = (i + dir + ids.size()) % ids.size() if i >= 0 else (0 if dir > 0 else ids.size() - 1)
	select(ids[i], true)


# --- data -------------------------------------------------------------------------

func _known(id: String) -> bool:
	if id == MapInfo.HOME:
		return true
	return id != "" and RegionLocations.has(id) and state != null and state.region.is_discovered(id)


func _sorted_ids() -> Array:
	var ids := []
	for id in RegionLocations.ids():
		if _known(id):
			ids.append(id)
	ids.sort_custom(func(a, b): return RegionLocations.travel_minutes(a) < RegionLocations.travel_minutes(b) or (RegionLocations.travel_minutes(a) == RegionLocations.travel_minutes(b) and a < b))
	return ids


func _refresh_entries() -> void:
	var t := view.terrain
	var list := []
	var ids := _sorted_ids()
	ids.push_front(MapInfo.HOME)
	for id in ids:
		var ground := t.anchor_of(id)
		var top_y := maxf(float(t.loc_top.get(id, ground.y)), ground.y) + 0.25
		var cat := MapInfo.HOME if id == MapInfo.HOME else str(RegionLocations.get_def(id)["category"])
		var name := "Your house" if id == MapInfo.HOME else RegionLocations.name_of(id)
		var sub := "Home" if id == MapInfo.HOME else "%s · about %s" % [RegionLocations.CATEGORIES.get(cat, cat), UiTheme.duration_text(RegionLocations.travel_minutes(id))]
		list.append({"id": id, "name": name, "cat": cat, "ground": ground, "top": Vector3(ground.x, top_y, ground.z), "sub": sub})
	markers.entries = list
	markers.planned = state.region.planned if _known(state.region.planned) else ""


func _route(id: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	if id == MapInfo.HOME:
		return out
	for p in view.terrain.route_from_home(id):
		out.append(view.terrain.world_of(p) + Vector3(0, 0.12, 0))
	return out


func _approach_def(id: String) -> Dictionary:
	for a in _summary.get("approaches", []):
		if a["id"] == id:
			return a
	return {}


# --- UI -----------------------------------------------------------------------------

func _build_ui() -> void:
	if _root != null:
		return
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.theme()
	add_child(_root)
	_container = SubViewportContainer.new()
	_container.name = "MapViewport"
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_container.add_child(_viewport)
	view = RegionMapView.new()
	view.name = "RegionMapView"
	_viewport.add_child(view)
	markers = MapMarkers.new()
	markers.name = "Markers"
	markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	markers.view = view
	_root.add_child(markers)
	markers.place_clicked.connect(_on_place_clicked)
	_build_top()
	_build_list()
	_build_info()
	_build_footer()


func _build_top() -> void:
	var card := UiTheme.make_card()
	card.position = Vector2(MARGIN, MARGIN)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(UiTheme.make_title("Region map", UiTheme.FONT_TITLE))
	_title_sub = UiTheme.make_caption("")
	box.add_child(_title_sub)
	card.add_child(box)
	_root.add_child(card)
	var right_card := UiTheme.make_card()
	right_card.mouse_filter = Control.MOUSE_FILTER_PASS
	right_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_card.offset_right = -MARGIN
	right_card.offset_top = MARGIN
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", UiTheme.GAP)
	var home := UiTheme.make_button("Find my house", "H")
	home.custom_minimum_size.x = 190
	home.focus_mode = Control.FOCUS_NONE
	home.pressed.connect(find_home)
	right.add_child(home)
	var close_b := UiTheme.make_button("Close", "Esc")
	close_b.custom_minimum_size.x = 130
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.pressed.connect(close)
	right.add_child(close_b)
	right_card.add_child(right)
	_root.add_child(right_card)


func _build_list() -> void:
	var panel := UiTheme.make_panel()
	panel.name = "Places"
	panel.position = Vector2(MARGIN, TOP + 8)
	panel.custom_minimum_size = Vector2(LIST_W, 0)
	var sb := UiTheme.panel_style()
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(UiTheme.make_section("Known places"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_W - 24, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 3)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)
	box.add_child(scroll)
	panel.add_child(box)
	_root.add_child(panel)


func _rebuild_list() -> void:
	for c in _list_box.get_children():
		_list_box.remove_child(c)
		c.queue_free()
	_list_buttons.clear()
	var ids := _sorted_ids()
	ids.push_front(MapInfo.HOME)
	for id in ids:
		var is_home: bool = id == MapInfo.HOME
		var name := "Your house" if is_home else RegionLocations.name_of(id)
		var cap := "" if is_home else UiTheme.duration_text(RegionLocations.travel_minutes(id))
		if id == state.region.planned:
			cap = "planned"
		var b := UiTheme.make_button("    " + name, cap)
		b.custom_minimum_size.y = 32
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL + 1)
		b.clip_text = true
		var cat := MapInfo.HOME if is_home else str(RegionLocations.get_def(id)["category"])
		var dot := ColorRect.new()
		dot.color = MapInfo.category_color(cat)
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size = Vector2(8, 8)
		dot.position = Vector2(12, 12)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(dot)
		var cl: Label = b.get_node_or_null("Caption")
		if cl != null and id == state.region.planned:
			cl.add_theme_color_override("font_color", UiTheme.ACCENT)
		b.pressed.connect(select.bind(id, true))
		_list_box.add_child(b)
		_list_buttons[id] = b
		b.button_pressed = id == selected


func _build_info() -> void:
	_info_panel = UiTheme.make_panel()
	_info_panel.name = "Info"
	_info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_info_panel.offset_left = -MARGIN - INFO_W
	_info_panel.offset_right = -MARGIN
	_info_panel.offset_top = TOP + 8
	_info_panel.custom_minimum_size = Vector2(INFO_W, 0)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 8)
	_info_panel.add_child(_info)
	_root.add_child(_info_panel)


func _build_footer() -> void:
	var hint_card := UiTheme.make_card()
	hint_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_card.offset_left = MARGIN
	hint_card.offset_bottom = -MARGIN
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", 16)
	for h in [["Drag / WASD", "Pan"], ["Wheel", "Zoom"], ["H", "House"], ["Tab", "Next place"], ["1-4", "Purpose"], ["Enter", "Plan"], ["Esc", "Close"]]:
		hints.add_child(UiTheme.make_key_hint(h[0], h[1]))
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_card.add_child(hints)
	_root.add_child(hint_card)
	var legend := UiTheme.make_card()
	legend.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	legend.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	legend.offset_right = -MARGIN
	legend.offset_bottom = -MARGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for cat in [MapInfo.HOME, "food", "medical", "construction", "weapons", "residential"]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		var dot := ColorRect.new()
		dot.color = MapInfo.category_color(cat)
		dot.custom_minimum_size = Vector2(9, 9)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(dot)
		var names := {MapInfo.HOME: "Home", "food": "Food", "medical": "Medical", "construction": "Building", "weapons": "Weapons", "residential": "Houses"}
		item.add_child(UiTheme.make_label(names[cat], UiTheme.FONT_SMALL, UiTheme.TEXT_DIM))
		row.add_child(item)
	legend.add_child(row)
	_root.add_child(legend)


func _update_title() -> void:
	var known := 0
	for id in RegionLocations.ids():
		if state.region.is_discovered(id):
			known += 1
	var t := "%s  ·  %d of %d places known" % [UiTheme.day_time_text(state.day(), state.clock_text()), known, RegionLocations.LOCATIONS.size()]
	if not layout_ok:
		t += "  ·  saved on another map layout (%s)" % state.region.layout
	if _known(state.region.planned) and state.region.planned != MapInfo.HOME:
		t += "\nPlanned: %s, %s" % [RegionLocations.name_of(state.region.planned), MapInfo.purpose_text(state.region.planned_purpose).to_lower()]
	_title_sub.text = t


func _clear_info() -> void:
	for c in _info.get_children():
		_info.remove_child(c)
		c.queue_free()
	_approach_buttons.clear()
	_plan_button = null
	_status = null


func _show_info() -> void:
	_clear_info()
	_update_title()
	_info_panel.visible = selected != ""
	if selected == "":
		return
	var s := _summary if selected != MapInfo.HOME else MapInfo.home_summary()
	if selected == MapInfo.HOME:
		_summary = s
	_info.add_child(UiTheme.make_title(s["name"], UiTheme.FONT_LARGE))
	var sub := UiTheme.make_caption("%s  ·  %s" % [s["category_name"], s["district_name"]], 0, MapInfo.category_color(s["category"]))
	_info.add_child(sub)
	_info.add_child(UiTheme.make_caption(s["desc"], INFO_W - 40, UiTheme.TEXT))
	if selected == MapInfo.HOME:
		if state.region.planned != "":
			_info.add_child(UiTheme.make_caption("Planned: %s, %s." % [RegionLocations.name_of(state.region.planned), MapInfo.purpose_text(state.region.planned_purpose).to_lower()], INFO_W - 40, UiTheme.ACCENT))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	var travel := "about %s each way  ·  %.1f km" % [UiTheme.duration_text(s["travel_minutes"]), s["km"]]
	_row(grid, "Travel", travel, UiTheme.TEXT)
	var risk_text: String = s["risk_name"] if s["risk_name"] != "" else "Unknown"
	_row(grid, "Risk", risk_text, MapInfo.risk_color(s["risk_tier"]))
	_row(grid, "Stock", "%s  ·  %d %% left" % [s["stock_text"], int(round(s["stock"] * 100.0))], UiTheme.TEXT if s["stock"] >= 0.5 else UiTheme.WARN)
	_info.add_child(grid)
	if s["resources_text"] != "":
		_info.add_child(UiTheme.make_section("Might find"))
		_info.add_child(UiTheme.make_caption(s["resources_text"], INFO_W - 40, UiTheme.TEXT))
	if not s["equipment"].is_empty():
		_info.add_child(UiTheme.make_section("Equipment"))
		for e in s["equipment"]:
			var line := "%s %s%s" % ["✓" if e["have"] else "✗", e["name"], (": " + e["effect"]) if e["effect"] != "" else ""]
			if e.get("required", false):
				line += " (required)"
			_info.add_child(UiTheme.make_caption(line, INFO_W - 40, UiTheme.GOOD if e["have"] else (UiTheme.BAD if e.get("required", false) else UiTheme.TEXT_DIM)))
	for n in s.get("notes", []):
		_info.add_child(UiTheme.make_caption(str(n), INFO_W - 40, UiTheme.WARN))
	_info.add_child(UiTheme.make_section("Mission purpose"))
	var ag := GridContainer.new()
	ag.columns = 2
	ag.add_theme_constant_override("h_separation", 6)
	ag.add_theme_constant_override("v_separation", 6)
	var group := ButtonGroup.new()
	var i := 0
	for a in s["approaches"]:
		i += 1
		var b := UiTheme.make_button("%d  %s" % [i, a["name"]])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2((INFO_W - 42) * 0.5, 34)
		b.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
		b.clip_text = true
		b.disabled = not a["available"]
		b.tooltip_text = a["reason"] if not a["available"] else a["desc"]
		b.pressed.connect(_set_approach.bind(a["id"], ""))
		ag.add_child(b)
		_approach_buttons[a["id"]] = b
	_info.add_child(ag)
	var desc := UiTheme.make_caption("", INFO_W - 40)
	desc.name = "ApproachDesc"
	_info.add_child(desc)
	var targets := HFlowContainer.new()
	targets.name = "Targets"
	targets.add_theme_constant_override("h_separation", 6)
	targets.add_theme_constant_override("v_separation", 6)
	_info.add_child(targets)
	_plan_button = UiTheme.make_button("Plan expedition", "Enter")
	_plan_button.focus_mode = Control.FOCUS_NONE
	_plan_button.pressed.connect(plan_selected)
	_info.add_child(_plan_button)
	_status = UiTheme.make_caption("", INFO_W - 40, UiTheme.ACCENT)
	_info.add_child(_status)
	_set_approach(approach, target)


func _row(grid: GridContainer, key: String, value: String, col: Color) -> void:
	var k := UiTheme.make_label(key.to_upper(), 12, UiTheme.TEXT_DIM)
	k.add_theme_font_override("font", UiTheme.tracked_font(2))
	grid.add_child(k)
	grid.add_child(UiTheme.make_label(value, UiTheme.FONT_SMALL + 1, col))


func _set_approach(id: String, tgt: String) -> void:
	var a := _approach_def(id)
	if a.is_empty() or not a.get("available", true):
		id = "general"
		a = _approach_def(id)
	approach = id
	target = tgt
	if _approach_buttons.is_empty():
		return
	for k in _approach_buttons:
		(_approach_buttons[k] as Button).set_pressed_no_signal(k == id)
	var desc: Label = _info.get_node_or_null("ApproachDesc")
	if desc != null:
		var extra := ""
		if int(a.get("minutes", 0)) > 0:
			extra = "  About %s there and back%s." % [UiTheme.duration_text(a["minutes"]), (", risk " + str(a["risk_name"]).to_lower()) if str(a.get("risk_name", "")) != "" else ""]
		desc.text = str(a.get("desc", "")) + extra
	var flow: HFlowContainer = _info.get_node_or_null("Targets")
	if flow != null:
		for c in flow.get_children():
			flow.remove_child(c)
			c.queue_free()
		if id == "targeted" and not _summary.get("targets", []).is_empty():
			if target == "" or not target in _summary["targets"]:
				target = _summary["targets"][0]
			var group := ButtonGroup.new()
			for item in _summary["targets"]:
				var b := UiTheme.make_button(Items.name_of(item))
				b.toggle_mode = true
				b.button_group = group
				b.focus_mode = Control.FOCUS_NONE
				b.custom_minimum_size.y = 28
				b.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
				b.set_pressed_no_signal(item == target)
				b.pressed.connect(func(): target = item; _update_plan_button())
				flow.add_child(b)
	_update_plan_button()


func _update_plan_button() -> void:
	if _plan_button == null:
		return
	var purpose := approach + (":" + target if approach == "targeted" and target != "" else "")
	var is_planned := state.region.planned == selected and state.region.planned_purpose == purpose
	_plan_button.text = "Planned" if is_planned else "Plan expedition"
	UiTheme.set_caption(_plan_button, "" if is_planned else "Enter")
	if _status != null:
		if state.region.planned == selected:
			_status.text = "Planned: %s. Walk into the fog at the edge of your lot to set out." % MapInfo.purpose_text(state.region.planned_purpose)
		elif state.region.planned != "":
			_status.text = "Currently planned: %s. Planning here replaces it." % RegionLocations.name_of(state.region.planned)
		else:
			_status.text = "Leaving still happens at the fog: the plan preselects this place."


func _on_place_clicked(id: String) -> void:
	if id != "":
		select(id, false)
