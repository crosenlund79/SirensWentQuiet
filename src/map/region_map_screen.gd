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
## Tab / Shift+Tab next place, Enter travel, C on foot / by car, Esc or M close.
##
## Exp 007 (T): the info panel is the travel panel (travel time on foot and by
## car, route, what might be found, danger, fuel, carrying capacity, whether
## there is daylight for the round trip) with a "Travel" button that emits
## `travel_requested(id, by_car)`; the game decides (src/travel/travel_flow.gd).
## The dialogue-expedition purpose picker and "Plan expedition" are gone from
## the panel (plan_selected() stays as an API). `play_travel()` animates a tiny
## voxel Eli (or the car) along the road route (MapTraveller), with the clock
## running in a card, in a few real seconds; Space or Enter skips it.
##
## Exp 008 (T): travel from where Eli is. `origin` is home or the POI he is
## at (the game sets it with `car_here`, `boot` and `pack_line` before
## open()): the list's times, the route, the panel and Travel are from there,
## and at a POI "Your house" is a destination too (Travel then goes home).
## The panel, top down: what the place is good for (MapInfo.good_for), the
## danger, whether he has been there and how picked-over it is; then the
## travel section: on foot and by car side by side with their times, the
## arrival, the stay and the way home from there, fuel (TravelRules.leg_fuel),
## "Back home by 18:40" or "You'd get home after dark", the pack and the car's
## boot; then what might be found and the gear. At a POI the mode is the one
## he came with (the car stays with him). play_leg() animates any leg; its
## card shows the clock, a progress bar and the arrival time.
##
## Exp 009 (D): today's places (DailySites). An overrun place stays on the
## map, dimmed and crossed out (MapMarkers), "overrun" in the list, and its
## panel says "Overrun — too many hostiles to approach safely." with Travel
## disabled (TravelRules); the "Today" row says how long a place has been
## open and whether it may be gone tomorrow. The title counts today's
## approachable places.

signal closed
signal destination_selected(id: String, purpose: String)
signal travel_requested(id: String, by_car: bool)     # Exp 007 (T)
signal travel_finished                                # Exp 007 (T): play_travel() is done

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
var _left: VBoxContainer
var _viewport: SubViewport
var _container: SubViewportContainer
var _title_sub: Label
var _list_box: VBoxContainer
var _list_buttons := {}
var _info_panel: PanelContainer
var _info_scroll: ScrollContainer
var _info: VBoxContainer
var _approach_buttons := {}
var _plan_button: Button
var _status: Label
var _tween: Tween
var _summary := {}

# Exp 007 (T): travel
var travel_enabled := true       ## the Travel button (false at a POI: leave through an exit)
var travel_note := ""            ## shown instead of the button when travel is disabled
var by_car := false              ## the chosen travel mode
var travelling := false          ## play_travel() is running (input is held)
var _travel := {}                ## {"pts", "t", "seconds", "from", "minutes", "label"}
var _traveller: MapTraveller
var _travel_card: PanelContainer
var _travel_title: Label
var _travel_clock: Label
var _travel_bar: ProgressBar
var _travel_button: Button
var _travel_status: Label

# Exp 008 (T): travel from where Eli is
var origin := MapInfo.HOME       ## home, or the POI Eli is at (times, routes and Travel start here)
var car_here := false            ## at a POI: the car came along (he drives on; else he walks on)
var boot := {}                   ## at a POI by car: the boot's contents (the POI helper's live record; read only)
var pack_line := ""              ## at a POI: the pack readout ("Pack: 18 / 30")


func _init() -> void:
	layer = 65
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_build_ui()


# --- API --------------------------------------------------------------------------

## Builds and caches the region and its meshes (about a second, once per
## session) so the first open() doesn't hitch. Optional; call while loading.
static func prewarm() -> void:
	RegionMapMesher.build(RegionTerrain.shared())
	RegionMapView.cloud_texture()


## Opens the map for a run (`state` may be null: a fresh sample run).
func open(game_state: GameState) -> void:
	if _root == null:
		_build_ui()
	state = game_state if game_state != null else GameState.new()
	by_car = TravelRules.can_drive(state) if origin == MapInfo.HOME else car_here    # Exp 007 (T); Exp 008: at a POI, as he came
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
	view.process_mode = Node.PROCESS_MODE_INHERIT
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
	view.process_mode = Node.PROCESS_MODE_DISABLED


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
	if travelling:                       # Exp 007 (T): Space / Enter skip; nothing else while travelling
		if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			skip_travel()
		if event is InputEventKey or event is InputEventAction or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
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
			request_travel()                 # Exp 007 (T): was "plan"
		KEY_C:
			set_by_car(not by_car)           # Exp 007 (T)
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
	if travelling:
		_step_travel(delta)
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
	ids.sort_custom(func(a, b): return _mins(a) < _mins(b) or (_mins(a) == _mins(b) and a < b))
	return ids


## Exp 008 (T): on-foot minutes from where Eli is (`origin`) to `id`.
func _mins(id: String) -> int:
	return TravelRules.minutes_between(origin, id) if origin != MapInfo.HOME else RegionLocations.travel_minutes(id)


## The list's caption for a place: its time from here, "here", or "planned".
func _caption(id: String) -> String:
	if id == origin and origin != MapInfo.HOME:
		return "here"
	if id == MapInfo.HOME:
		return "" if origin == MapInfo.HOME else UiTheme.duration_text(_mins(id))
	return UiTheme.duration_text(_mins(id))


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
		var sub := "Home" if id == MapInfo.HOME else "%s · about %s" % [RegionLocations.CATEGORIES.get(cat, cat), UiTheme.duration_text(_mins(id))]
		var overrun: bool = id != MapInfo.HOME and id != origin and DailySites.is_overrun(state, id)      # Exp 009 (D)
		if id == origin and origin != MapInfo.HOME:
			sub = "You are here"
		elif id == MapInfo.HOME and origin != MapInfo.HOME:
			sub = "Home · about %s from here" % UiTheme.duration_text(_mins(id))
		elif overrun:
			sub = "Overrun today: too many hostiles"
		list.append({"id": id, "name": name, "cat": cat, "ground": ground, "top": Vector3(ground.x, top_y, ground.z), "sub": sub,
			"overrun": overrun})
	markers.entries = list
	markers.planned = state.region.planned if _known(state.region.planned) else ""


## The road from where Eli is to `id` (Exp 008: from `origin`).
func _route(id: String) -> PackedVector3Array:
	return _route_between(origin, id)


## Exp 008 (T): the road between two places (either may be home), on the map.
func _route_between(a: String, b: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	if a == b:
		return out
	for p in view.terrain.route_between(a, b):
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
	_left = VBoxContainer.new()
	_left.name = "Left"
	_left.position = Vector2(MARGIN, MARGIN)
	_left.add_theme_constant_override("separation", 8)
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_left)
	var card := UiTheme.make_card()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size.x = LIST_W
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(UiTheme.make_title("Region map", UiTheme.FONT_TITLE))
	_title_sub = UiTheme.make_caption("", LIST_W - 24)
	box.add_child(_title_sub)
	card.add_child(box)
	_left.add_child(card)
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
	_left.add_child(panel)


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
		var cap := _caption(id)                       # Exp 008 (T): from where Eli is
		var overrun: bool = not is_home and id != origin and DailySites.is_overrun(state, id)      # Exp 009 (D)
		if overrun:
			cap = "overrun"
		elif id == state.region.planned and origin == MapInfo.HOME:
			cap = "planned"
		var b := UiTheme.make_button("    " + name, cap)
		b.custom_minimum_size.y = 32
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.FONT_SMALL + 1))
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
		if overrun:                                   # Exp 009 (D): dimmed, still listed
			b.modulate = Color(1, 1, 1, 0.55)
			dot.color = dot.color.darkened(0.45)
			if cl != null:
				cl.add_theme_color_override("font_color", UiTheme.BAD)
			b.tooltip_text = DailySites.OVERRUN_LINE
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
	_info_scroll = ScrollContainer.new()
	_info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_info_scroll.custom_minimum_size = Vector2(INFO_W - 2 * UiTheme.PAD, 0)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 8)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_scroll.add_child(_info)
	_info_panel.add_child(_info_scroll)
	_root.add_child(_info_panel)


func _build_footer() -> void:
	var hint_card := UiTheme.make_card()
	hint_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_card.offset_left = MARGIN
	hint_card.offset_bottom = -MARGIN
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", 16)
	for h in [["Drag / WASD", "Pan"], ["Wheel", "Zoom"], ["H", "House"], ["Tab", "Next place"], ["C", "Foot / car"], ["Enter", "Travel"], ["Esc", "Close"]]:
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
	for cat in [MapInfo.HOME, "food", "medical", "construction", "weapons", "residential", "knowledge"]:   # Exp 006 (R): knowledge
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		var dot := ColorRect.new()
		dot.color = MapInfo.category_color(cat)
		dot.custom_minimum_size = Vector2(9, 9)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(dot)
		var names := {MapInfo.HOME: "Home", "food": "Food", "medical": "Medical", "construction": "Building", "weapons": "Weapons", "residential": "Houses", "knowledge": "Books"}
		item.add_child(UiTheme.make_label(names[cat], UiTheme.FONT_SMALL, UiTheme.TEXT_DIM))
		row.add_child(item)
	legend.add_child(row)
	_root.add_child(legend)


func _update_title() -> void:
	var known := 0
	for id in RegionLocations.ids():
		if state.region.is_discovered(id):
			known += 1
	var t := "%s\n%d of %d places known" % [UiTheme.day_time_text(state.day(), state.clock_text()), known, RegionLocations.LOCATIONS.size()]
	var open_n := 0                                   # Exp 009 (D)
	for id in RegionLocations.ids():
		if state.region.is_discovered(id) and not DailySites.is_overrun(state, id):
			open_n += 1
	t += "\n%d approachable today" % open_n
	if not layout_ok:
		t += "\nSaved on another map layout (%s)" % state.region.layout
	if _known(state.region.planned) and state.region.planned != MapInfo.HOME:
		t += "\nPlanned: %s" % RegionLocations.name_of(state.region.planned)
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
	var home_sel := selected == MapInfo.HOME
	var s := _summary if not home_sel else MapInfo.home_summary()
	if home_sel:
		_summary = s
	_info.add_child(UiTheme.make_title(s["name"], UiTheme.FONT_LARGE))
	var sub := UiTheme.make_caption("%s  ·  %s" % [s["category_name"], s["district_name"]], 0, MapInfo.category_color(s["category"]))
	_info.add_child(sub)
	if selected == origin and not home_sel:   # Exp 008 (T): the POI Eli is at
		_add_here_section()
		_fit_info.call_deferred()
		return
	var away := origin != MapInfo.HOME
	var desc: String = s["desc"]
	if home_sel and away:
		desc = "Home. What you carry and the car's boot go into the house when you get there, not before."
	_info.add_child(UiTheme.make_caption(desc, INFO_W - 40, UiTheme.TEXT))
	if home_sel:
		if away:
			_add_travel_section()          # Exp 008 (T): home from here
		_fit_info.call_deferred()
		return
	# Exp 008 (T): what it is good for, how dangerous, been there, how picked-over
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	var good := MapInfo.good_for(selected)
	_row(grid, "Good for", ", ".join(good) if not good.is_empty() else str(s["category_name"]), UiTheme.TEXT)
	var risk_text: String = s["risk_name"] if s["risk_name"] != "" else "Unknown"
	_row(grid, "Danger", risk_text, MapInfo.risk_color(s["risk_tier"]))
	var visits := state.region.visits(selected)
	_row(grid, "Been there", MapInfo.visit_text(state, selected), UiTheme.TEXT if visits > 0 else UiTheme.TEXT_DIM)
	_row(grid, "Stock", "%s  ·  %d %% left" % [s["stock_text"], int(round(s["stock"] * 100.0))], UiTheme.TEXT if s["stock"] >= 0.5 else UiTheme.WARN)
	var overrun := DailySites.is_overrun(state, selected)      # Exp 009 (D): today's availability
	_row(grid, "Today", DailySites.availability_text(state, selected), UiTheme.BAD if overrun else UiTheme.GOOD)
	_info.add_child(grid)
	if overrun:
		var ol := UiTheme.make_caption(DailySites.OVERRUN_LINE, INFO_W - 40, UiTheme.BAD)
		ol.name = "Overrun"
		_info.add_child(ol)
	_add_travel_section()              # Exp 007 (T): replaces the mission purpose; Exp 008: right under the facts
	if s["resources_text"] != "":
		_info.add_child(UiTheme.make_section("Might find"))
		_info.add_child(UiTheme.make_caption(s["resources_text"], INFO_W - 40, UiTheme.TEXT))
	if not s["equipment"].is_empty():
		_info.add_child(UiTheme.make_section("Equipment"))
		for e in s["equipment"]:
			# one line each; the full effect is the tooltip
			var on: bool = e["have"] and e.get("equipped", true)
			var mark := "✓" if on else ("○" if e["have"] else "✗")
			var head := "%s %s%s%s" % [mark, e["name"], " (required)" if e.get("required", false) else "", "" if on or not e["have"] else " (not equipped)"]
			var col := UiTheme.GOOD if on else (UiTheme.TEXT if e["have"] else (UiTheme.BAD if e.get("required", false) else UiTheme.TEXT_DIM))
			var l := UiTheme.make_caption(head + ((":  " + e["effect"]) if e["effect"] != "" else ""), 0, col)
			l.custom_minimum_size.x = INFO_W - 40
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			l.clip_text = true
			l.tooltip_text = head + ("\n" + e["effect"] if e["effect"] != "" else "")
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			_info.add_child(l)
	for n in s.get("notes", []):
		_info.add_child(UiTheme.make_caption(str(n), INFO_W - 40, UiTheme.WARN))
	_set_approach(approach, target)
	_fit_info.call_deferred()


## Sizes the info panel to its content, at most down to the key hints.
func _fit_info() -> void:
	if _info_scroll == null or _root == null:
		return
	var avail := maxf(_root.size.y - (TOP + 8.0) - 2.0 * UiTheme.PAD - 76.0, 200.0)
	_info_scroll.custom_minimum_size.y = minf(_info.get_combined_minimum_size().y, avail)


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
	var tl: Array = _summary.get("targets", [])
	if id == "targeted" and not tl.is_empty() and (target == "" or not target in tl):
		target = tl[0]                     # Exp 007 (T): also without the purpose buttons
	if _approach_buttons.is_empty():
		return
	for k in _approach_buttons:
		(_approach_buttons[k] as Button).set_pressed_no_signal(k == id)
	var desc: Label = _info.get_node_or_null("ApproachDesc")
	if desc != null:
		var extra := ""
		if int(a.get("minutes", 0)) > 0:
			extra = "  About %s in all%s." % [UiTheme.duration_text(a["minutes"]), (", risk " + str(a["risk_name"]).to_lower()) if str(a.get("risk_name", "")) != "" else ""]
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
				b.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.FONT_SMALL))
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


# --- Exp 007 (T): travel ------------------------------------------------------------------

## The travel part of the info panel (Exp 008: from `origin`): on foot and
## by car side by side with their times, distance, arrival, the stay and the
## way home from there, fuel, the daylight check, the pack and the boot, and
## the Travel button (or why not).
func _add_travel_section() -> void:
	_travel_button = null
	_travel_status = null
	var to_home := selected == MapInfo.HOME
	var away := origin != MapInfo.HOME
	_info.add_child(UiTheme.make_section("Travel" if not away else "Travel from here"))
	var foot_why := TravelRules.mode_reason(state, origin, false, car_here)
	var car_why := TravelRules.mode_reason(state, origin, true, car_here)
	if by_car and car_why != "":
		by_car = false
	elif not by_car and foot_why != "" and car_why == "":
		by_car = true
	var modes := HBoxContainer.new()
	modes.name = "Modes"
	modes.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for m in [[false, "On foot"], [true, "By car"]]:
		var b := UiTheme.make_button(m[1], UiTheme.duration_text(TravelRules.minutes_between(origin, selected, m[0])))
		b.name = "ByCar" if m[0] else "OnFoot"
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2((INFO_W - 42) * 0.5, 32)
		b.set_pressed_no_signal(by_car == m[0])
		var why: String = car_why if m[0] else foot_why
		b.disabled = why != ""
		b.tooltip_text = why
		b.pressed.connect(set_by_car.bind(m[0]))
		modes.add_child(b)
	_info.add_child(modes)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	var tm := TravelRules.leg_timing(state, origin, selected, by_car)
	var km := TravelRules.km_between(origin, selected) * RegionLocations.ROAD_FACTOR
	_row(grid, "Distance", "about %.1f km by road" % km, UiTheme.TEXT_DIM)
	_row(grid, "Arrive", "around %s  (%s %s)" % [TravelRules.clock(tm["arrive_at"]), UiTheme.duration_text(tm["minutes"]), "by car" if by_car else "on foot"], UiTheme.TEXT)
	if not to_home:
		_row(grid, "Stay", "about %s to look around" % UiTheme.duration_text(tm["stay"]), UiTheme.TEXT_DIM)
		_row(grid, "Then home", "about %s from there" % UiTheme.duration_text(tm["home_minutes"]), UiTheme.TEXT_DIM)
	if by_car:
		var have := state.inventory.count("fuel")
		var need := TravelRules.leg_fuel(origin, selected, true)
		var free := bool(state.cheats.get("unlimited", false))
		var ft := ""
		if not away:
			ft = "%d can, there and back (you have %d)" % [need, have]
		elif need > 0:
			ft = "%d more can for this stop (you have %d)" % [need, have]
		else:
			ft = "None: the way home is paid"
		_row(grid, "Fuel", ft, UiTheme.TEXT if have >= need or free else UiTheme.BAD)
	else:
		var ct := "At home" if away else (car_why if car_why != "" else "Left at home")
		_row(grid, "Car", ct, UiTheme.TEXT_DIM)
	_info.add_child(grid)
	_info.add_child(UiTheme.make_caption(tm["text"], INFO_W - 40, UiTheme.GOOD if tm["before_dark"] else UiTheme.WARN))
	if away and pack_line != "":
		_info.add_child(UiTheme.make_caption(pack_line + "  ·  nothing is unloaded until you're home", INFO_W - 40, UiTheme.TEXT_DIM))
	elif not away:
		_info.add_child(UiTheme.make_caption("Carry: " + TravelRules.capacity_text(state, by_car), INFO_W - 40, UiTheme.TEXT_DIM))
	if by_car:
		_info.add_child(UiTheme.make_caption(boot_text(), INFO_W - 40, UiTheme.TEXT_DIM))
	if not travel_enabled:
		_info.add_child(UiTheme.make_caption(travel_note if travel_note != "" else "You can't set out from here.", INFO_W - 40, UiTheme.TEXT_DIM))
		return
	var block := TravelRules.leg_block_reason(state, origin, selected, by_car, car_here)
	_travel_button = UiTheme.make_button("Go home" if to_home else "Travel", "Enter")
	_travel_button.name = "Travel"
	_travel_button.focus_mode = Control.FOCUS_NONE
	_travel_button.disabled = block != ""
	_travel_button.pressed.connect(request_travel)
	_info.add_child(_travel_button)
	if block == DailySites.OVERRUN_LINE:              # Exp 009 (D): the line above already says why
		block = "Not today. Pick an open place, or try another day."
	_travel_status = UiTheme.make_caption(block, INFO_W - 40, UiTheme.WARN)
	_info.add_child(_travel_status)


## Exp 008 (T): the car's boot as a line: "Boot: 12 / 60 · 4 planks, 2 stones"
## (empty at home: the trip starts with an empty boot).
func boot_text() -> String:
	var t := "Boot: %s / %s" % [PoiState._num(PoiState.load_of(boot)), PoiState._num(PoiState.CARGO_CAP)]
	return t + ("  ·  empty" if boot.is_empty() else "  ·  " + ExpeditionData.items_text(boot))


## Exp 008 (T): the panel for the POI Eli is at: the pack, the car and its
## boot, and how to go on.
func _add_here_section() -> void:
	_info.add_child(UiTheme.make_caption("You are here.", INFO_W - 40, UiTheme.ACCENT))
	if pack_line != "":
		_info.add_child(UiTheme.make_caption(pack_line, INFO_W - 40, UiTheme.TEXT))
	_info.add_child(UiTheme.make_caption(boot_text() if car_here else "The car is at home.", INFO_W - 40, UiTheme.TEXT_DIM))
	_info.add_child(UiTheme.make_caption("Pick another place to travel on from here, or your house to go home. Nothing is unloaded until you're home; E at an exit goes straight home.", INFO_W - 40, UiTheme.TEXT_DIM))


## A line under the Travel button (the game's refusals).
func show_travel_status(text: String) -> void:
	if _travel_status != null:
		_travel_status.text = text


## On foot or by car (C). The car needs to run and have fuel; at a POI the
## mode is the one Eli came with (Exp 008).
func set_by_car(on: bool) -> void:
	if TravelRules.mode_reason(state, origin, on, car_here) != "":
		return
	if on == by_car:
		return
	by_car = on
	if selected != "" and (selected != MapInfo.HOME or origin != MapInfo.HOME):
		_show_info()


## The Travel button / Enter: asks the game to set out for the selected place
## (Exp 008: from `origin`; at a POI the house too). Returns false when
## nothing travellable is selected or the rules say no.
func request_travel() -> bool:
	if travelling or not travel_enabled or selected == "" or selected == origin:
		return false
	if selected != MapInfo.HOME and not RegionLocations.has(selected):
		return false
	var why := TravelRules.leg_block_reason(state, origin, selected, by_car, car_here)
	if why != "":
		if _travel_status != null:
			_travel_status.text = why
		return false
	travel_requested.emit(selected, by_car)
	return true


## Animates travel along the road route between the house and `id` (outbound:
## house -> id; else id -> house) in `seconds` real seconds, while the card's
## clock runs from `from_total` over `minutes` game minutes. The map must be
## open. Emits travel_finished (also when `seconds` <= 0, at once).
func play_travel(id: String, car: bool, outbound: bool, seconds: float, from_total: float, minutes: float) -> void:
	if outbound:
		play_leg(MapInfo.HOME, id, car, seconds, from_total, minutes)
	else:
		play_leg(id, MapInfo.HOME, car, seconds, from_total, minutes)


## Exp 008 (T): any leg `from` -> `to` (either may be home), as play_travel.
func play_leg(from: String, to: String, car: bool, seconds: float, from_total: float, minutes: float) -> void:
	if not is_open:
		open(state)
	select(to, false)
	_info_panel.visible = false
	var pts := _route_between(from, to)
	if pts.size() < 2:
		pts = PackedVector3Array([view.terrain.anchor_of(from) + Vector3(0, 0.12, 0), view.terrain.anchor_of(to) + Vector3(0, 0.12, 0)])
	markers.route_world = pts
	var verb := ("Driving" if car else "Walking") + (" home from " + RegionLocations.name_of(from) if to == MapInfo.HOME else " to " + RegionLocations.name_of(to))
	_travel = {"pts": pts, "t": 0.0, "seconds": maxf(seconds, 0.0), "from": from_total, "minutes": minutes, "label": verb}
	travelling = true
	if _traveller != null and is_instance_valid(_traveller):
		_traveller.queue_free()
	_traveller = MapTraveller.new()
	_traveller.name = "Traveller"
	_traveller.setup(car)
	view.add_child(_traveller)
	_traveller.follow(pts, 0.0)
	markers.traveller_world = pts[0]
	markers.traveller_label = "Eli" if not car else "Eli, by car"
	view.set_view(pts[0], 44.0, true)
	_show_travel_card(true)
	_update_travel_card(0.0)
	if seconds <= 0.0 or not is_inside_tree():
		_finish_travel.call_deferred()


## Space / Enter while travelling: arrive now.
func skip_travel() -> void:
	if travelling:
		_travel["t"] = float(_travel.get("seconds", 0.0))


func _step_travel(delta: float) -> void:
	_travel["t"] = float(_travel["t"]) + delta
	var dur := float(_travel["seconds"])
	var f := clampf(float(_travel["t"]) / dur, 0.0, 1.0) if dur > 0.0 else 1.0
	var e := f * f * (3.0 - 2.0 * f) * 0.35 + f * 0.65          # a gentle start and stop
	if _traveller != null and is_instance_valid(_traveller):
		_traveller.follow(_travel["pts"], e)
		view.set_view(_traveller.position, 44.0)
		markers.traveller_world = _traveller.position
		view.set_clear_points(Vector2.INF, _traveller.position)     # the clouds part over him
	_update_travel_card(e)
	if f >= 1.0:
		_finish_travel()


func _finish_travel() -> void:
	if not travelling:
		return
	travelling = false
	_update_travel_card(1.0)
	_show_travel_card(false)
	if _traveller != null and is_instance_valid(_traveller):
		_traveller.queue_free()
	_traveller = null
	markers.traveller_world = Vector3.INF
	_travel = {}
	travel_finished.emit()


func _show_travel_card(on: bool) -> void:
	if _travel_card == null:
		_travel_card = UiTheme.make_card()
		_travel_card.name = "TravelCard"
		_travel_card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_travel_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_travel_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_travel_card.offset_bottom = -MARGIN - 64.0
		_travel_card.custom_minimum_size.x = 420.0
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		_travel_title = UiTheme.make_title("", UiTheme.FONT_LARGE)
		box.add_child(_travel_title)
		_travel_clock = UiTheme.make_caption("", 0, UiTheme.TEXT)
		box.add_child(_travel_clock)
		_travel_bar = ProgressBar.new()
		_travel_bar.min_value = 0.0
		_travel_bar.max_value = 1.0
		_travel_bar.show_percentage = false
		_travel_bar.custom_minimum_size = Vector2(396, 10)
		box.add_child(_travel_bar)
		box.add_child(UiTheme.make_key_hint("Space", "Skip", UiTheme.FONT_SMALL, UiTheme.TEXT_FAINT))
		_travel_card.add_child(box)
		_root.add_child(_travel_card)
	_travel_card.visible = on


func _update_travel_card(f: float) -> void:
	if _travel_title == null or _travel.is_empty():
		return
	var t := float(_travel["from"]) + float(_travel["minutes"]) * f
	_travel_title.text = str(_travel["label"])
	var left := float(_travel["minutes"]) * (1.0 - f)
	_travel_clock.text = "%s  ·  %s  ·  arriving %s" % [TravelRules.day_clock(t), UiTheme.duration_text(left) + " to go" if f < 1.0 else "there",
		TravelRules.clock(float(_travel["from"]) + float(_travel["minutes"]))]      # Exp 008 (T): the arrival time
	_travel_bar.value = f
