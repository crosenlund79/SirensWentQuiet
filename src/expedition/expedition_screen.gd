class_name ExpeditionScreen
extends CanvasLayer
## Destination, plan (approach and gear), events and the return report
## (SPEC-002 §7.7, SPEC-003 §3). Owner: X.
##
## Flow: list -> gear ("Plan the trip": approach, target, gear) -> confirm ->
## (travel) -> event -> outcome [-> event -> outcome] -> report. "Turn back"
## on the list emits `cancelled`; "Return home" on the report emits
## `finished(result)` exactly once. The screen only reads the GameState: the
## game applies the result with `GameState.apply_expedition` and
## `ExpeditionData.apply_region`. The list shows discovered places only,
## grouped by category, and preselects the map's plan
## (`state.region.planned` / `planned_purpose`).
## process_mode ALWAYS (the game pauses the world while it is open). Keyboard:
## arrows/Tab move, Enter chooses, Esc steps back (list: turns back), 1-3
## answer events.

signal finished(result: Dictionary)
signal cancelled

const D := preload("res://src/expedition/expedition_data.gd")
const VEIL_SHADER := preload("res://src/expedition/shaders/fog_veil.gdshader")
const FADE_IN := 0.7
const FADE_OUT := 0.45
const STEP_FADE := 0.16
const TRAVEL_HOLD := 1.1
const PANEL_WIDTH := 1080.0
const LIST_WIDTH := 360.0
const LIST_HEIGHT := 560.0
const PLAN_LEFT := 560.0
const VEIL_DAY := [Color(0.42, 0.45, 0.49), Color(0.62, 0.65, 0.69)]
const VEIL_NIGHT := [Color(0.05, 0.06, 0.09), Color(0.13, 0.16, 0.22)]

var is_open := false
var step := ""                    ## "", list, gear, confirm, travel, event, outcome, report ("wait" while fading)
var state: GameState
var selected := ""
var approach := "general"
var target := ""                  ## targeted collection: the item gone for
var gear := {}
var run: ExpeditionRun
var result := {}
var instant := false              ## tests: no fades or travel pause
var preselected_plan := false     ## the list opened on the map's planned destination

## Exposed for tests and the preview driver.
var destination_buttons := {}     ## id -> Button (discovered places only)
var approach_buttons := {}        ## approach id -> Button (plan step)
var target_buttons := {}          ## item id -> Button (plan step, targeted)
var option_buttons: Array[Button] = []
var primary_button: Button
var back_button: Button
var ammo_slider: HSlider
var shells_slider: HSlider
var tool_boxes := {}              ## gear id -> CheckBox
var last_outcome := {}

var _root: Control
var _veil: ColorRect
var _veil_mat: ShaderMaterial
var _center: CenterContainer
var _panel: PanelContainer
var _box: VBoxContainer
var _travel_label: Label
var _detail_box: VBoxContainer
var _gear_summary: VBoxContainer
var _approach_desc: Label
var _list_scroll: ScrollContainer
var _tween: Tween
var _veil_tween: Tween
var _veil_amount := 0.0
var _emitted := false


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_veil = ColorRect.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil_mat = ShaderMaterial.new()
	_veil_mat.shader = VEIL_SHADER
	_veil_mat.set_shader_parameter("noise_tex", FogBoundary.noise_texture())
	_veil.material = _veil_mat
	_root.add_child(_veil)
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_center)
	_travel_label = UiTheme.make_label("", 22, UiTheme.TEXT)
	_travel_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_travel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_travel_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_travel_label.modulate.a = 0.0
	_root.add_child(_travel_label)


# --- public API -------------------------------------------------------------------------

func open(s: GameState) -> void:
	if not is_inside_tree():
		push_warning("ExpeditionScreen.open: add the screen to the tree first")
		return
	state = s
	selected = ""
	approach = "general"
	target = ""
	gear = {}
	run = null
	result = {}
	_emitted = false
	last_outcome = {}
	preselected_plan = false
	is_open = true
	visible = true
	if s != null and s.region != null and s.region.planned != "" and s.region.is_discovered(s.region.planned) and D.has_destination(s.region.planned):
		selected = s.region.planned
		var p := D.parse_purpose(s.region.planned_purpose)
		approach = p["approach"]
		target = p["target"]
		preselected_plan = true
	_kill_tween()
	if _veil_tween != null and _veil_tween.is_valid():
		_veil_tween.kill()
	var night := s.night_amount() if s != null else 0.0
	_veil_mat.set_shader_parameter("fog_dark", (VEIL_DAY[0] as Color).lerp(VEIL_NIGHT[0], night))
	_veil_mat.set_shader_parameter("fog_light", (VEIL_DAY[1] as Color).lerp(VEIL_NIGHT[1], night))
	var vs := _root.get_viewport_rect().size
	_veil_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	_sfx("ui/open")
	_show_list()
	if instant:
		_set_veil(1.0)
		_panel.modulate.a = 1.0
	else:
		_set_veil(0.0)
		_panel.modulate.a = 0.0
		_veil_to(1.0, FADE_IN)
		_tween = create_tween()
		_tween.tween_interval(FADE_IN * 0.6)
		_tween.tween_method(_set_panel_alpha, 0.0, 1.0, 0.3)


## Discovered places in display order (grouped by category).
func listed_ids() -> Array:
	var out := []
	for id in D.ORDER:
		if D.has_destination(id) and (state == null or state.region == null or state.region.is_discovered(id)):
			out.append(id)
	return out


## List: highlight a destination and show its details.
func select_destination(id: String) -> void:
	if step != "list" or not destination_buttons.has(id):
		return
	if id != selected:
		gear = {}
		if approach == "targeted" and not target in D.targets(id):
			target = ""
	selected = id
	for k in destination_buttons:
		_mark(destination_buttons[k], k == id)
	if _list_scroll != null:
		_list_scroll.call_deferred("ensure_control_visible", destination_buttons[id])
	_fill_details()


func available(id: String) -> Dictionary:
	return D.availability(state, id)


## List -> plan (only for an available destination).
func to_gear() -> void:
	if step != "list" or selected == "":
		return
	if not available(selected)["ok"]:
		_sfx("ui/error")
		return
	_sfx("ui/click")
	if gear.is_empty() or gear.get("_dest", "") != selected:
		gear = D.default_gear(state, selected)
		gear["_dest"] = selected
	if approach == "targeted" and not target in D.targets(selected):
		target = str(D.targets(selected)[0]) if not D.targets(selected).is_empty() else ""
	_go(_show_gear)


## Plan step: choose the mission approach (general, targeted, careful, raid).
func select_approach(id: String) -> void:
	if not D.APPROACHES.has(id):
		return
	approach = id
	if approach == "targeted" and not target in D.targets(selected):
		target = str(D.targets(selected)[0]) if not D.targets(selected).is_empty() else ""
	if step == "gear":
		_show_gear()
		if approach_buttons.has(id):
			_focus(approach_buttons[id])


## Plan step: the resource for targeted collection.
func set_target(item: String) -> void:
	if not item in D.targets(selected):
		return
	target = item
	if step == "gear":
		_show_gear()
		if target_buttons.has(item):
			_focus(target_buttons[item])


func set_ammo(n: int) -> void:
	gear["ammo"] = clampi(n, 0, D.rounds_owned(state, "ammo"))
	if ammo_slider != null and int(ammo_slider.value) != gear["ammo"]:
		ammo_slider.set_value_no_signal(gear["ammo"])
	_refresh_gear_summary()


func set_shells(n: int) -> void:
	gear["shells"] = clampi(n, 0, D.rounds_owned(state, "shells"))
	if shells_slider != null and int(shells_slider.value) != gear["shells"]:
		shells_slider.set_value_no_signal(gear["shells"])
	_refresh_gear_summary()


func set_tool(id: String, on: bool) -> void:
	if not D.owns(state, id) or id in D.destination(selected).get("requires", []):
		return
	if on:
		gear[id] = 1
	else:
		gear.erase(id)
	if tool_boxes.has(id):
		(tool_boxes[id] as CheckBox).set_pressed_no_signal(on)
	_refresh_gear_summary()


func brought_gear() -> Dictionary:
	var g := gear.duplicate()
	g.erase("_dest")
	return D.sanitize_gear(state, selected, g)


## {"ok", "reason"} for the chosen approach with the chosen gear.
func plan_state() -> Dictionary:
	return D.approach_state(state, selected, approach, brought_gear())


func to_confirm() -> void:
	if step != "gear":
		return
	if not plan_state()["ok"]:
		_sfx("ui/error")
		return
	_sfx("ui/click")
	_go(_show_confirm)


## Confirm -> the expedition starts (events, then the report).
func depart() -> void:
	if step != "confirm":
		return
	run = ExpeditionRun.create(state, selected, brought_gear(), approach, target)
	if run == null:
		_sfx("ui/error")
		_go(_show_list)
		return
	_sfx("ui/click")
	step = "travel"
	if instant:
		_next_event()
		return
	_kill_tween()
	_travel_label.text = "You walk into the fog."
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 0.0, STEP_FADE * 1.5)
	_tween.tween_property(_travel_label, "modulate:a", 1.0, 0.45)
	_tween.tween_interval(TRAVEL_HOLD)
	_tween.tween_property(_travel_label, "modulate:a", 0.0, 0.4)
	_tween.tween_callback(_next_event)


## Event: answer option i.
func choose_option(i: int) -> void:
	if step != "event" or run == null:
		return
	var st := run.option_state(i)
	if not st["ok"]:
		_sfx("ui/error")
		return
	_sfx("ui/click")
	last_outcome = run.choose(i)
	_go(_show_outcome)


## Outcome -> next event or the report.
func continue_on() -> void:
	if step != "outcome":
		return
	_sfx("ui/click")
	_next_event()


## Report -> emits finished(result) once and closes.
func return_home() -> void:
	if step != "report" or _emitted:
		return
	_emitted = true
	_sfx("ui/close")
	var r := result.duplicate(true)
	_close()
	finished.emit(r)


## Turn back from the list (or Esc on the list): emits cancelled.
func cancel() -> void:
	if not is_open or step != "list":
		return
	_sfx("ui/close")
	_close()
	cancelled.emit()


## Esc: one step back where that makes sense.
func back() -> void:
	match step:
		"list":
			cancel()
		"gear":
			_sfx("ui/click")
			_go(_show_list)
		"confirm":
			_sfx("ui/click")
			_go(_show_gear)


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		back()


# --- building blocks ----------------------------------------------------------------------

func _sfx(n: String) -> void:
	Sfx.ui(n)


func _set_veil(a: float) -> void:
	_veil_amount = a
	_veil_mat.set_shader_parameter("amount", a)


## The veil has its own tween, so step transitions never cut a fade short.
func _veil_to(target_amount: float, time: float, then := Callable()) -> void:
	if _veil_tween != null and _veil_tween.is_valid():
		_veil_tween.kill()
	_veil_tween = create_tween()
	_veil_tween.tween_method(_set_veil, _veil_amount, target_amount, time).set_trans(Tween.TRANS_SINE)
	if then.is_valid():
		_veil_tween.tween_callback(then)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _close() -> void:
	is_open = false
	step = ""
	_kill_tween()
	if instant or not is_inside_tree():
		if _veil_tween != null and _veil_tween.is_valid():
			_veil_tween.kill()
		_set_veil(0.0)
		visible = false
		return
	if _panel != null:
		_tween = create_tween()
		_tween.tween_property(_panel, "modulate:a", 0.0, STEP_FADE)
	_veil_to(0.0, FADE_OUT, func(): visible = is_open)


## Fades the panel out, rebuilds it with `build`, fades it back in.
func _go(build: Callable) -> void:
	if instant or _panel == null:
		build.call()
		return
	step = "wait"              # ignore input until the next step is built
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 0.0, STEP_FADE)
	_tween.tween_callback(build)
	_tween.tween_method(_set_panel_alpha, 0.0, 1.0, STEP_FADE)


func _set_panel_alpha(a: float) -> void:
	if _panel != null:
		_panel.modulate.a = a


func _begin(title: String, sub := "") -> void:
	var a := 1.0 if _panel == null else _panel.modulate.a
	if _panel != null:
		_center.remove_child(_panel)
		_panel.queue_free()
	option_buttons.clear()
	destination_buttons.clear()
	approach_buttons.clear()
	target_buttons.clear()
	tool_boxes.clear()
	ammo_slider = null
	shells_slider = null
	primary_button = null
	back_button = null
	_detail_box = null
	_gear_summary = null
	_approach_desc = null
	_list_scroll = null
	_panel = UiTheme.make_panel()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.modulate.a = a
	_center.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_box)
	var head := HBoxContainer.new()
	head.add_child(UiTheme.make_title(title))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(UiTheme.make_label(sub if sub != "" else _clock_text(), 15, UiTheme.TEXT_DIM))
	_box.add_child(head)
	_box.add_child(_rule())


func _clock_text(total := -1.0) -> String:
	if state == null:
		return ""
	var t := state.total_minutes if total < 0.0 else total
	return "Day %d  ·  %s" % [int(floor(t / 1440.0)) + 1, D.clock(fposmod(t, 1440.0))]


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = UiTheme.LINE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _text(text: String, size := 16, color := UiTheme.TEXT, width := 0.0) -> Label:
	var l := UiTheme.make_label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if width > 0.0:
		l.custom_minimum_size.x = width
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := UiTheme.make_button(text)
	b.pressed.connect(cb)
	return b


func _footer(buttons: Array, note := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if note != "":
		var l := UiTheme.make_label(note, 14, UiTheme.TEXT_DIM)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	for b in buttons:
		row.add_child(b)
	_box.add_child(_rule())
	_box.add_child(row)
	return row


func _mark(b: Button, on: bool) -> void:
	if on:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiTheme.ACCENT, 0.16)
		sb.border_color = UiTheme.ACCENT
		sb.set_border_width_all(1)
		sb.border_width_left = 3
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		b.add_theme_stylebox_override("normal", sb)
	else:
		b.remove_theme_stylebox_override("normal")


func _focus(c: Control) -> void:
	if c != null and c.is_inside_tree() and c.is_visible_in_tree():
		c.grab_focus()
	elif c != null:
		c.call_deferred("grab_focus")


func _risk_color(name: String) -> Color:
	match name:
		"Low":
			return UiTheme.GOOD
		"Moderate":
			return UiTheme.WARN
	return UiTheme.BAD


func _approx(minutes: float) -> String:
	return "about %s" % D.duration(minutes)


## "2 h 30" (list captions).
func _short_time(minutes: int) -> String:
	if minutes < 60:
		return "%d min" % minutes
	return "%d h %02d" % [minutes / 60, minutes % 60] if minutes % 60 != 0 else "%d h" % (minutes / 60)


func _row(label: String, value: String, w: float, color := UiTheme.TEXT) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := UiTheme.make_label(label.to_upper(), 13, UiTheme.TEXT_DIM)
	l.custom_minimum_size.x = 118
	h.add_child(l)
	h.add_child(_text(value, 15, color, w - 128))
	return h


func _warnings() -> Array:
	var out := []
	if state.health < 35.0:
		out.append("You're badly hurt (health %d). An injury out there could finish you." % int(state.health))
	if state.energy <= D.LOW_ENERGY:
		out.append("You're exhausted. Everything out there is more dangerous.")
	return out


func _approach_label(a: String, t := "") -> String:
	var n: String = D.APPROACHES[a]["name"]
	if a == "targeted" and t != "":
		n += ": " + D.reward_name(t)
	return n


# --- step: destinations ---------------------------------------------------------------------

func _show_list() -> void:
	step = "list"
	_begin("Into the fog")
	_box.add_child(_text("The fog starts where the lawn ends. Somewhere past it the town is still standing. Where do you go?", 16, UiTheme.TEXT_DIM, PANEL_WIDTH - 40))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	_box.add_child(cols)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_WIDTH, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	cols.add_child(scroll)
	_list_scroll = scroll
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)
	var ids := listed_ids()
	for cat in D.CATEGORY_ORDER:
		var in_cat := ids.filter(func(id): return D.destination(id)["category"] == cat)
		if in_cat.is_empty():
			continue
		var sec := UiTheme.make_section(str(RegionLocations.CATEGORIES.get(cat, cat)))
		sec.custom_minimum_size.y = 24
		sec.set_meta("category", cat)
		list.add_child(sec)
		for id in in_cat:
			var d := D.destination(id)
			var av := available(id)
			var cap := "%s · %s" % [_short_time(D.nominal_minutes(id)), D.risk_name(D.danger_for(state, id, D.default_gear(state, id)))] if av["ok"] else "unavailable"
			if preselected_plan and id == state.region.planned:
				cap = "planned · " + cap
			var b := UiTheme.make_button(str(d["name"]), cap)
			b.custom_minimum_size.y = 36
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if not av["ok"]:
				b.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
				b.add_theme_color_override("font_focus_color", UiTheme.TEXT_DIM)
				b.add_theme_color_override("font_hover_color", UiTheme.TEXT_DIM)
				b.tooltip_text = av["reason"]
			b.focus_entered.connect(select_destination.bind(id))
			b.mouse_entered.connect(select_destination.bind(id))
			b.pressed.connect(func():
				select_destination(id)
				to_gear())
			list.add_child(b)
			destination_buttons[id] = b
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 7)
	cols.add_child(_detail_box)
	back_button = _button("Turn back", cancel)
	primary_button = _button("Plan the trip  >", to_gear)
	_footer([back_button, primary_button], "%d of %d places known. Careful exploration finds more." % [ids.size(), D.ORDER.size()])
	if not destination_buttons.has(selected):
		selected = ""
		for id in ids:
			if selected == "" and available(id)["ok"]:
				selected = id
		if selected == "" and not ids.is_empty():
			selected = ids[0]
	if selected != "":
		select_destination(selected)
		_focus(destination_buttons[selected])


func _fill_details() -> void:
	if _detail_box == null:
		return
	for c in _detail_box.get_children():
		_detail_box.remove_child(c)
		c.queue_free()
	var d := D.destination(selected)
	var sm := D.location_summary(selected, state)
	var av := available(selected)
	var w := PANEL_WIDTH - LIST_WIDTH - 22 - 40
	_detail_box.add_child(UiTheme.make_title(d["name"], 19))
	_detail_box.add_child(UiTheme.make_label("%s  ·  %s" % [sm["category_name"], RegionLocations.DISTRICTS.get(d["district"], d["district"])], 13, UiTheme.TEXT_DIM))
	_detail_box.add_child(_text(d["desc"], 16, UiTheme.TEXT, w))
	if preselected_plan and selected == state.region.planned:
		_detail_box.add_child(_text("Planned on the map: %s." % _approach_label(approach, target).to_lower(), 15, UiTheme.ACCENT, w))
	var mins := int(sm["minutes"])
	_detail_box.add_child(_row("Time", "%s (%d min each way), back around %s" % [_approx(mins), sm["travel_minutes"], D.clock(state.minute_of_day() + mins)], w))
	var risk_txt: String = sm["risk_name"] + " with what you'd bring"
	if sm["risk_bare_name"] != sm["risk_name"]:
		risk_txt += "  ·  %s bare-handed" % sm["risk_bare_name"].to_lower()
	_detail_box.add_child(_row("Risk", risk_txt, w, _risk_color(sm["risk_name"])))
	_detail_box.add_child(_row("Might find", d["rewards"], w))
	if not (sm["notes"] as Array).is_empty():
		_detail_box.add_child(_row("Known", " ".join(sm["notes"]), w, UiTheme.WARN if float(sm["stock"]) < 0.5 else UiTheme.TEXT))
	var req: Array = d.get("requires", [])
	if not req.is_empty():
		var parts := []
		for id in req:
			parts.append("%s (%s)" % [Items.name_of(id), "you have one" if D.owns(state, id) else "you have none"])
		_detail_box.add_child(_row("Needs", ", ".join(parts), w))
	var gear_lines := []
	for e in sm["equipment"]:
		if e["required"] or e["id"] == "backpack":
			continue
		gear_lines.append("%s%s: %s" % [e["name"], " (have)" if e["have"] else "", e["effect"]])
		if gear_lines.size() >= 3:
			break
	if not gear_lines.is_empty():
		_detail_box.add_child(_row("Gear", "\n".join(gear_lines), w))
	var ap_lines := []
	for a in sm["approaches"]:
		if a["available"]:
			ap_lines.append("%s  ·  %s  ·  %s risk" % [a["name"], _short_time(a["minutes"]), a["risk_name"].to_lower()])
		else:
			ap_lines.append("%s  ·  %s" % [a["name"], _short_reason(a["reason"]).to_lower()])
	_detail_box.add_child(_row("Approaches", "\n".join(ap_lines), w))
	if not av["ok"]:
		_detail_box.add_child(_text(av["reason"], 16, UiTheme.BAD, w))
	else:
		for wtxt in _warnings():
			_detail_box.add_child(_text(wtxt, 15, UiTheme.WARN, w))
	if primary_button != null:
		primary_button.disabled = not av["ok"]
		primary_button.tooltip_text = av["reason"]


func _short_reason(reason: String) -> String:
	if reason.contains("coming back in the dark"):
		return "Unavailable: you'd be back after dark"
	if reason.contains("still dark"):
		return "Unavailable: too dark to set out"
	if reason.contains("loaded weapon"):
		return "Needs a loaded weapon"
	if reason.contains("flashlight"):
		return "Unavailable: needs a flashlight"
	if reason.contains("outside"):
		return "Unavailable: not now"
	return "Unavailable"


# --- step: plan (approach, target, gear) ------------------------------------------------------

func _show_gear() -> void:
	step = "gear"
	var d := D.destination(selected)
	_begin("Plan the trip", d["name"])
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	_box.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = PLAN_LEFT
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	var g := brought_gear()
	# approach
	left.add_child(UiTheme.make_section("Approach"))
	for a in D.APPROACH_ORDER:
		var st := D.approach_state(state, selected, a, g)
		var cap := "%s · %s risk" % [_short_time(D.nominal_minutes(selected, a)), D.risk_name(D.danger_for(state, selected, g, a)).to_lower()] if st["ok"] else _short_reason(st["reason"]).to_lower()
		var b := UiTheme.make_button(D.APPROACHES[a]["name"], cap)
		b.custom_minimum_size.y = 34
		b.tooltip_text = st["reason"] if not st["ok"] else D.APPROACHES[a]["desc"]
		if not st["ok"]:
			b.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		b.pressed.connect(select_approach.bind(a))
		_mark(b, a == approach)
		left.add_child(b)
		approach_buttons[a] = b
	_approach_desc = _text(_approach_text(), 13, UiTheme.TEXT_DIM, PLAN_LEFT)
	left.add_child(_approach_desc)
	if approach == "targeted":
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		flow.custom_minimum_size.x = PLAN_LEFT
		for item in D.targets(selected):
			var tb := UiTheme.make_button(Items.name_of(item))
			tb.custom_minimum_size.y = 30
			tb.pressed.connect(set_target.bind(item))
			_mark(tb, item == target)
			flow.add_child(tb)
			target_buttons[item] = tb
		left.add_child(flow)
	# rounds
	left.add_child(UiTheme.make_section("Bring"))
	ammo_slider = _rounds_row(left, "9 mm rounds", "ammo", "AmmoCount")
	if D.owns(state, "shotgun") or state.inventory.count("shells") > 0:
		shells_slider = _rounds_row(left, "Shells", "shells", "ShellCount")
	if D.rounds_owned(state, "ammo") + D.rounds_owned(state, "shells") <= 0:
		left.add_child(_text("No loaded weapon to bring." if not (D.owns(state, "handgun") or D.owns(state, "shotgun")) else "You have no rounds to bring.", 13, UiTheme.TEXT_DIM, PLAN_LEFT))
	else:
		left.add_child(_text(D.gear_effect("ammo", selected) + (" A shell counts as %d rounds." % D.SHELL_SHOTS if shells_slider != null else ""), 13, UiTheme.TEXT_DIM, PLAN_LEFT))
	# gear
	var req: Array = d.get("requires", [])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	left.add_child(grid)
	for id in D.BRINGABLE_GEAR:
		var have := D.owns(state, id)
		var cb := CheckBox.new()
		cb.text = Items.name_of(id) + (" (required)" if id in req and have else "")
		cb.button_pressed = have and int(g.get(id, 0)) > 0
		cb.disabled = not have or id in req
		cb.custom_minimum_size.x = 190
		cb.toggled.connect(func(on: bool): set_tool(id, on))
		_flat_check(cb)
		grid.add_child(cb)
		tool_boxes[id] = cb
		var eff := _text(D.gear_effect(id, selected) if have else "You don't have one.", 13, UiTheme.TEXT_DIM, PLAN_LEFT - 200)
		eff.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(eff)
	if D.owns(state, "hammer"):
		left.add_child(_text("The hammer stays home: you need it to build.", 13, UiTheme.TEXT_DIM, PLAN_LEFT))
	_gear_summary = VBoxContainer.new()
	_gear_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gear_summary.add_theme_constant_override("separation", 7)
	cols.add_child(_gear_summary)
	back_button = _button("<  Back", back)
	primary_button = _button("Continue  >", to_confirm)
	_footer([back_button, primary_button])
	_refresh_gear_summary()
	_focus(approach_buttons.get(approach))


func _rounds_row(parent: Control, label: String, ammo_id: String, count_name: String) -> HSlider:
	var owned := D.rounds_owned(state, ammo_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var al := UiTheme.make_label(label, 15)
	al.custom_minimum_size.x = 120
	row.add_child(al)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = owned
	s.step = 1
	s.value = int(gear.get(ammo_id, 0))
	s.custom_minimum_size = Vector2(230, 22)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.editable = owned > 0
	if ammo_id == "ammo":
		s.value_changed.connect(func(v: float): set_ammo(int(v)))
	else:
		s.value_changed.connect(func(v: float): set_shells(int(v)))
	row.add_child(s)
	var count := UiTheme.make_label("", 15, UiTheme.ACCENT)
	count.name = count_name
	row.add_child(count)
	parent.add_child(row)
	return s


func _approach_text() -> String:
	var a: Dictionary = D.APPROACHES[approach]
	var s: String = a["desc"]
	if approach == "targeted" and target != "":
		s += " Going for %s." % D.reward_name(target)
	return s


## CheckBoxes would inherit the theme's filled Button styles; keep them flat
## with a thin accent outline on hover and focus.
func _flat_check(cb: CheckBox) -> void:
	for state_name in ["normal", "pressed", "hover", "hover_pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.04) if state_name in ["hover", "hover_pressed"] else Color(0, 0, 0, 0)
		sb.border_color = UiTheme.ACCENT if state_name in ["hover", "hover_pressed", "focus"] else Color(0, 0, 0, 0)
		sb.set_border_width_all(1 if state_name in ["hover", "hover_pressed", "focus"] else 0)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 6
		sb.content_margin_right = 8
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		cb.add_theme_stylebox_override(state_name, sb)
	cb.add_theme_color_override("font_color", UiTheme.TEXT)
	cb.add_theme_color_override("font_pressed_color", UiTheme.TEXT)
	cb.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.88))
	cb.add_theme_color_override("font_hover_pressed_color", Color(1, 0.95, 0.88))
	cb.add_theme_color_override("font_focus_color", UiTheme.TEXT)
	cb.add_theme_color_override("font_disabled_color", UiTheme.TEXT_DIM)


func _refresh_gear_summary() -> void:
	if _gear_summary == null:
		return
	var g := brought_gear()
	for pair in [["AmmoCount", "ammo"], ["ShellCount", "shells"]]:
		var c := _panel.find_child(pair[0], true, false) as Label
		if c != null:
			c.text = "%d of %d" % [int(g.get(pair[1], 0)), D.rounds_owned(state, pair[1])]
	for a in approach_buttons:
		var st := D.approach_state(state, selected, a, g)
		UiTheme.set_caption(approach_buttons[a], "%s · %s risk" % [_short_time(D.nominal_minutes(selected, a)), D.risk_name(D.danger_for(state, selected, g, a)).to_lower()] if st["ok"] else _short_reason(st["reason"]).to_lower())
		approach_buttons[a].tooltip_text = st["reason"] if not st["ok"] else D.APPROACHES[a]["desc"]
	for ch in _gear_summary.get_children():
		_gear_summary.remove_child(ch)
		ch.queue_free()
	var w := PANEL_WIDTH - PLAN_LEFT - 26 - 40
	var ps := plan_state()
	var base := D.risk_name(D.danger_for(state, selected, D.sanitize_gear(state, selected, {}), approach))
	var now := D.risk_name(D.danger_for(state, selected, g, approach))
	_gear_summary.add_child(UiTheme.make_label("RISK", 13, UiTheme.TEXT_DIM))
	_gear_summary.add_child(UiTheme.make_label(now + ("" if now == base else "  (bare-handed: %s)" % base.to_lower()), 19, _risk_color(now)))
	var mins := D.nominal_minutes(selected, approach)
	_gear_summary.add_child(UiTheme.make_label("TIME", 13, UiTheme.TEXT_DIM))
	_gear_summary.add_child(_text("%s, back around %s (%s searching)" % [_approx(mins), D.clock(state.minute_of_day() + mins), D.duration(D.search_minutes(selected, approach))], 15, UiTheme.TEXT, w))
	_gear_summary.add_child(UiTheme.make_label("EXPECT", 13, UiTheme.TEXT_DIM))
	_gear_summary.add_child(_text(_expect_text(), 15, UiTheme.TEXT, w))
	_gear_summary.add_child(UiTheme.make_label("BRINGING", 13, UiTheme.TEXT_DIM))
	_gear_summary.add_child(_text(_gear_text(g), 15, UiTheme.TEXT, w))
	var missing := []
	for id in D.destination(selected).get("recommends", []):
		if id == "ammo":
			if D.shots_of(g) < 3:
				missing.append("a loaded weapon")
		elif int(g.get(id, 0)) <= 0:
			missing.append("a " + Items.name_of(id).to_lower())
	if not missing.is_empty():
		_gear_summary.add_child(_text("Recommended: %s." % ", ".join(missing), 14, UiTheme.WARN, w))
	if not ps["ok"]:
		_gear_summary.add_child(_text(ps["reason"], 15, UiTheme.BAD, w))
	for wtxt in _warnings():
		_gear_summary.add_child(_text(wtxt, 14, UiTheme.WARN, w))
	if primary_button != null:
		primary_button.disabled = not ps["ok"]
		primary_button.tooltip_text = ps["reason"]
	if _approach_desc != null:
		_approach_desc.text = _approach_text()


## One line on what the approach changes.
func _expect_text() -> String:
	var a: Dictionary = D.APPROACHES[approach]
	var stock := D.stock_now(state, selected)
	var parts := []
	match approach:
		"general":
			parts.append("A normal search.")
		"targeted":
			parts.append("Much more %s, little else." % (D.reward_name(target) if target != "" else "of one thing"))
		"careful":
			parts.append("Safer and a little less loot. Good odds of finding new places.")
		"raid":
			parts.append("More loot in less time, far more danger. The place will be guarded afterwards.")
	if stock < 0.85:
		parts.append("%s: about %d %% of the loot is left." % [D.stock_text(stock, state.region.visits(selected)), int(round(stock * 100.0))])
	var dl := D.loot_scale(state)
	if dl != 1.0:
		parts.append("Difficulty: loot x%.2f." % dl)
	return " ".join(parts)


func _gear_text(g: Dictionary) -> String:
	var parts := []
	if int(g.get("ammo", 0)) > 0:
		parts.append("%d round%s" % [g["ammo"], "" if g["ammo"] == 1 else "s"])
	if int(g.get("shells", 0)) > 0:
		parts.append("%d shell%s" % [g["shells"], "" if g["shells"] == 1 else "s"])
	for id in D.BRINGABLE_GEAR:
		if int(g.get(id, 0)) > 0:
			parts.append(Items.name_of(id).to_lower())
	if parts.is_empty():
		return "Nothing but your hands."
	var s := ", ".join(parts) + "."
	return s.substr(0, 1).to_upper() + s.substr(1)


# --- step: confirm --------------------------------------------------------------------------

func _show_confirm() -> void:
	step = "confirm"
	var d := D.destination(selected)
	_begin("Set out?", d["name"])
	var g := brought_gear()
	var mins := D.nominal_minutes(selected, approach)
	var back_at := state.minute_of_day() + mins
	var w := PANEL_WIDTH - 40
	_box.add_child(_text("%s You'll be gone %s and back around %s." % [d["desc"], _approx(mins), D.clock(back_at)], 17, UiTheme.TEXT, w))
	_box.add_child(_row("Approach", _approach_label(approach, target), w))
	_box.add_child(_row("Bringing", _gear_text(g), w))
	var rn := D.risk_name(D.danger_for(state, selected, g, approach))
	_box.add_child(_row("Risk", rn, w, _risk_color(rn)))
	for wtxt in _warnings():
		_box.add_child(_text(wtxt, 15, UiTheme.WARN, w))
	_box.add_child(_text("Hunger, thirst and tiredness don't stop while you're gone. Nothing is guarded while you're away.", 14, UiTheme.TEXT_DIM, w))
	back_button = _button("<  Back", back)
	primary_button = _button("Head into the fog", depart)
	_footer([back_button, primary_button])
	_focus(primary_button)


# --- step: events -----------------------------------------------------------------------------

func _next_event() -> void:
	if run == null:
		return
	if run.is_finished():
		result = run.result()
		_go(_show_report)
		return
	if instant or _panel == null or _panel.modulate.a < 0.01:
		_show_event()
		if not instant:
			_kill_tween()
			_tween = create_tween()
			_tween.tween_method(_set_panel_alpha, 0.0, 1.0, 0.35)
	else:
		_go(_show_event)


func _event_clock(done: int) -> String:
	var n := run.event_ids.size()
	var at := run.depart_at + float(run.nominal_minutes) * float(done) / float(n + 1)
	return "%s  ·  around %s" % [run.dest["name"], D.clock(fposmod(at, 1440.0))]


func _show_event() -> void:
	step = "event"
	var ev := run.current_event()
	_begin(ev["title"], _event_clock(run.step + 1))
	var w := PANEL_WIDTH - 40
	_box.add_child(_text(ev["text"], 18, UiTheme.TEXT, w))
	var opts := VBoxContainer.new()
	opts.add_theme_constant_override("separation", 8)
	_box.add_child(opts)
	var first: Button = null
	for i in (ev["options"] as Array).size():
		var o: Dictionary = ev["options"][i]
		var st := run.option_state(i)
		var label: String = o["label"]
		var extra := _option_hint(o)
		if not st["ok"]:
			label += "   (%s)" % st["reason"].to_lower()
		elif extra != "":
			label += "   (%s)" % extra
		var b := _button("%d.  %s" % [i + 1, label], choose_option.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not st["ok"]
		b.tooltip_text = st["reason"]
		opts.add_child(b)
		option_buttons.append(b)
		if first == null and st["ok"]:
			first = b
	_box.add_child(_rule())
	_box.add_child(_text(_carry_text(), 14, UiTheme.TEXT_DIM, w))
	_focus(first)


func _option_hint(o: Dictionary) -> String:
	var parts := []
	var shots := int(o.get("shots", 0))
	if shots > 0:
		parts.append("%d round%s" % [shots, "" if shots == 1 else "s"] if run.shells_left() <= 0 else D.shots_text(shots))
	var m := int(o.get("minutes", 0))
	if m >= 10:
		parts.append("+%d min" % m)
	elif m <= -10:
		parts.append("cuts the trip short")
	return ", ".join(parts)


func _carry_text() -> String:
	var parts := []
	if run.ammo_left() > 0:
		parts.append("%d round%s" % [run.ammo_left(), "" if run.ammo_left() == 1 else "s"])
	if run.shells_left() > 0:
		parts.append("%d shell%s" % [run.shells_left(), "" if run.shells_left() == 1 else "s"])
	for id in D.BRINGABLE_GEAR:
		if run.has_tool(id):
			parts.append(Items.name_of(id).to_lower())
	return "You carry: " + (", ".join(parts) if not parts.is_empty() else "nothing but your hands") + ".   %s.   Keys 1-3 choose." % _approach_label(run.approach, run.target)


func _show_outcome() -> void:
	step = "outcome"
	_begin(D.event(run.event_ids[run.step - 1])["title"], _event_clock(run.step))
	var w := PANEL_WIDTH - 40
	_box.add_child(_text(last_outcome.get("text", ""), 18, UiTheme.TEXT, w))
	var conseq := []
	if float(last_outcome.get("hurt", 0.0)) >= 0.5:
		conseq.append(["Hurt: -%d health" % int(round(last_outcome["hurt"])), UiTheme.BAD])
	if int(last_outcome.get("ammo", 0)) > 0:
		conseq.append(["%d round%s used" % [last_outcome["ammo"], "" if last_outcome["ammo"] == 1 else "s"], UiTheme.WARN])
	if int(last_outcome.get("shells", 0)) > 0:
		conseq.append(["%d shell%s used" % [last_outcome["shells"], "" if last_outcome["shells"] == 1 else "s"], UiTheme.WARN])
	for id in last_outcome.get("lost", []):
		conseq.append(["Lost: %s" % Items.name_of(id).to_lower(), UiTheme.BAD])
	for c in conseq:
		_box.add_child(UiTheme.make_label(c[0], 16, c[1]))
	primary_button = _button("Continue  >" if not run.is_finished() else "Head home  >", continue_on)
	_footer([primary_button])
	_focus(primary_button)


# --- step: report --------------------------------------------------------------------------------

func _show_report() -> void:
	step = "report"
	var r := result
	_begin("Back home", _clock_text(float(r.get("return_at", state.total_minutes + r["minutes"]))))
	var w := PANEL_WIDTH - 40
	var back_m := fposmod(float(r.get("return_at", 0.0)), 1440.0)
	_box.add_child(_text(r["summary"], 18, UiTheme.TEXT, w))
	_box.add_child(_row("Time away", "%s (left %s, back %s)" % [D.duration(r["minutes"]), D.clock(fposmod(float(r.get("depart_at", 0.0)), 1440.0)), D.clock(back_m)], w))
	if back_m >= SurvivalTuning.EXPEDITION_RETURN_BY or back_m < SurvivalTuning.EXPEDITION_DEPART_FROM:
		_box.add_child(_text("You got back after dark.", 15, UiTheme.WARN, w))
	_box.add_child(_row("Approach", "%s at %s" % [_approach_label(str(r.get("approach", "general")), str(r.get("target", ""))), r["name"]], w))
	_box.add_child(_report_row("Found", D.items_text(r["gained"]), "Nothing worth carrying.", UiTheme.GOOD, w))
	if not r["consumed"].is_empty():
		_box.add_child(_report_row("Used", D.items_text(r["consumed"]), "", UiTheme.WARN, w))
	if not r["lost"].is_empty():
		_box.add_child(_report_row("Lost", D.items_text(r["lost"]), "", UiTheme.BAD, w))
	var dmg := float(r["damage"])
	_box.add_child(_report_row("Injuries", "-%d health" % int(round(dmg)) if dmg >= 0.5 else "", "Unhurt.", UiTheme.BAD if dmg >= 0.5 else UiTheme.GOOD, w))
	if not r["left_behind"].is_empty():
		_box.add_child(_report_row("Left behind", D.items_text(r["left_behind"]) + " (storage full)", "", UiTheme.WARN, w))
	var disc: Array = r.get("discovered", [])
	if not disc.is_empty():
		_box.add_child(_report_row("New places", ", ".join(disc.map(func(id): return RegionLocations.name_of(id))) + " (now on your map)", "", UiTheme.ACCENT, w))
	if r.has("stock_after"):
		var sa := float(r["stock_after"])
		_box.add_child(_row("The place", "%s (%d %% left)" % [D.stock_text(sa, 1), int(round(sa * 100.0))], w, UiTheme.WARN if sa < 0.5 else UiTheme.TEXT))
	var lines: Array = r.get("events", [])
	if not lines.is_empty():
		_box.add_child(UiTheme.make_label("WHAT HAPPENED", 13, UiTheme.TEXT_DIM))
		for l in lines:
			_box.add_child(_text("-  " + str(l), 15, UiTheme.TEXT_DIM, w))
	primary_button = _button("Return home", return_home)
	_footer([primary_button])
	_focus(primary_button)


func _report_row(label: String, value: String, empty: String, color: Color, w: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := UiTheme.make_label(label.to_upper(), 13, UiTheme.TEXT_DIM)
	l.custom_minimum_size.x = 118
	h.add_child(l)
	h.add_child(_text(value if value != "" else empty, 16, color if value != "" or empty == "Unhurt." else UiTheme.TEXT_DIM, w - 128))
	return h


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_open or step != "event" or not event.is_pressed() or event.is_echo():
		return
	var k := (event as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_3:
		var i := int(k - KEY_1)
		if i < option_buttons.size():
			get_viewport().set_input_as_handled()
			choose_option(i)
