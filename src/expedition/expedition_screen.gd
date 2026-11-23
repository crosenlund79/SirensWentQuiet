class_name ExpeditionScreen
extends CanvasLayer
## Destination choice, gear, events and the return report (SPEC §7.7). Owner: E.
##
## Flow: list -> gear -> confirm -> (travel) -> event -> outcome [-> event ->
## outcome] -> report. "Turn back" on the list emits `cancelled`; "Return home"
## on the report emits `finished(result)` exactly once. The screen only reads
## the GameState: the game applies the result with `GameState.apply_expedition`.
## process_mode ALWAYS (the game pauses the world while it is open). Keyboard:
## arrows/Tab move, Enter chooses, Esc steps back (list: turns back).

signal finished(result: Dictionary)
signal cancelled

const D := preload("res://src/expedition/expedition_data.gd")
const VEIL_SHADER := preload("res://src/expedition/shaders/fog_veil.gdshader")
const FADE_IN := 0.7
const FADE_OUT := 0.45
const STEP_FADE := 0.16
const TRAVEL_HOLD := 1.1
const PANEL_WIDTH := 940.0
const VEIL_DAY := [Color(0.42, 0.45, 0.49), Color(0.62, 0.65, 0.69)]
const VEIL_NIGHT := [Color(0.05, 0.06, 0.09), Color(0.13, 0.16, 0.22)]

var is_open := false
var step := ""                    ## "", list, gear, confirm, travel, event, outcome, report ("wait" while fading)
var state: GameState
var selected := ""
var gear := {}
var run: ExpeditionRun
var result := {}
var instant := false              ## tests: no fades or travel pause

## Exposed for tests and the preview driver.
var destination_buttons := {}     ## id -> Button
var option_buttons: Array[Button] = []
var primary_button: Button
var back_button: Button
var ammo_slider: HSlider
var tool_boxes := {}              ## id -> CheckBox
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
var _tween: Tween
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
	gear = {}
	run = null
	result = {}
	_emitted = false
	last_outcome = {}
	is_open = true
	visible = true
	_kill_tween()
	var night := s.night_amount() if s != null else 0.0
	_veil_mat.set_shader_parameter("fog_dark", (VEIL_DAY[0] as Color).lerp(VEIL_NIGHT[0], night))
	_veil_mat.set_shader_parameter("fog_light", (VEIL_DAY[1] as Color).lerp(VEIL_NIGHT[1], night))
	var vs := _root.get_viewport_rect().size
	_veil_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	_sfx("ui/open")
	_show_list()
	if instant:
		_veil_mat.set_shader_parameter("amount", 1.0)
		_panel.modulate.a = 1.0
	else:
		_veil_mat.set_shader_parameter("amount", 0.0)
		_panel.modulate.a = 0.0
		_tween = create_tween()
		_tween.tween_method(_set_veil, 0.0, 1.0, FADE_IN).set_trans(Tween.TRANS_SINE)
		_tween.tween_property(_panel, "modulate:a", 1.0, 0.3)


## List: highlight a destination and show its details.
func select_destination(id: String) -> void:
	if step != "list" or not D.DESTINATIONS.has(id):
		return
	selected = id
	for k in destination_buttons:
		_mark(destination_buttons[k], k == id)
	_fill_details()


func available(id: String) -> Dictionary:
	return D.availability(state, id)


## List -> gear (only for an available destination).
func to_gear() -> void:
	if step == "confirm":
		_go(_show_gear)
		return
	if step != "list" or selected == "":
		return
	if not available(selected)["ok"]:
		_sfx("ui/error")
		return
	_sfx("ui/click")
	if gear.is_empty() or gear.get("_dest", "") != selected:
		gear = D.default_gear(state, selected)
		gear["_dest"] = selected
	_go(_show_gear)


func set_ammo(n: int) -> void:
	gear["ammo"] = clampi(n, 0, state.inventory.count("ammo"))
	if ammo_slider != null and int(ammo_slider.value) != gear["ammo"]:
		ammo_slider.set_value_no_signal(gear["ammo"])
	_refresh_gear_summary()


func set_tool(id: String, on: bool) -> void:
	if state.inventory.count(id) <= 0 or id in D.destination(selected).get("requires", []):
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


func to_confirm() -> void:
	if step != "gear":
		return
	_sfx("ui/click")
	_go(_show_confirm)


## Confirm -> the expedition starts (events, then the report).
func depart() -> void:
	if step != "confirm":
		return
	run = ExpeditionRun.create(state, selected, brought_gear())
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
	_veil_mat.set_shader_parameter("amount", a)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _close() -> void:
	is_open = false
	step = ""
	_kill_tween()
	if instant or not is_inside_tree():
		visible = false
		return
	_tween = create_tween()
	if _panel != null:
		_tween.tween_property(_panel, "modulate:a", 0.0, STEP_FADE)
	_tween.tween_method(_set_veil, float(_veil_mat.get_shader_parameter("amount")), 0.0, FADE_OUT)
	_tween.tween_callback(func(): visible = is_open)


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
	tool_boxes.clear()
	ammo_slider = null
	primary_button = null
	back_button = null
	_detail_box = null
	_gear_summary = null
	_panel = UiTheme.make_panel()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.modulate.a = a
	_center.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
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


func _footer(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
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


# --- step: destinations ---------------------------------------------------------------------

func _show_list() -> void:
	step = "list"
	_begin("Into the fog")
	_box.add_child(_text("The fog starts where the lawn ends. Somewhere past it the town is still standing. Where do you go?", 16, UiTheme.TEXT_DIM, PANEL_WIDTH - 40))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	_box.add_child(cols)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 330
	list.add_theme_constant_override("separation", 8)
	cols.add_child(list)
	for id in D.ORDER:
		var d := D.destination(id)
		var av := available(id)
		var sub := "%s  ·  %s risk" % [_approx(d["minutes"]), D.risk_name(D.danger(id, {}, state.energy))] if av["ok"] else _short_reason(av["reason"])
		var b := UiTheme.make_button("%s\n%s" % [d["name"], sub])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 58
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
	_detail_box.add_theme_constant_override("separation", 8)
	cols.add_child(_detail_box)
	back_button = _button("Turn back", cancel)
	primary_button = _button("Choose gear  >", to_gear)
	_footer([back_button, primary_button])
	var first := ""
	for id in D.ORDER:
		if first == "" and available(id)["ok"]:
			first = id
	if selected == "":
		selected = first if first != "" else D.ORDER[0]
	select_destination(selected)
	_focus(destination_buttons[selected])


func _short_reason(reason: String) -> String:
	if reason.contains("coming back in the dark"):
		return "Unavailable: you'd be back after dark"
	if reason.contains("still dark"):
		return "Unavailable: too dark to set out"
	if reason.contains("flashlight"):
		return "Unavailable: needs a flashlight"
	if reason.contains("outside"):
		return "Unavailable: not now"
	return "Unavailable"


func _approx(minutes: float) -> String:
	return "about %s" % D.duration(minutes)


func _fill_details() -> void:
	if _detail_box == null:
		return
	for c in _detail_box.get_children():
		_detail_box.remove_child(c)
		c.queue_free()
	var d := D.destination(selected)
	var av := available(selected)
	var w := PANEL_WIDTH - 330 - 22 - 40
	_detail_box.add_child(UiTheme.make_title(d["name"], 19))
	_detail_box.add_child(_text(d["desc"], 16, UiTheme.TEXT, w))
	var back_at := state.minute_of_day() + float(d["minutes"])
	_detail_box.add_child(_row("Time", "%s, back around %s" % [_approx(d["minutes"]), D.clock(back_at)], w))
	var risk := D.risk_name(D.danger(selected, {}, state.energy))
	var best := D.risk_name(D.danger(selected, _best_gear(), state.energy))
	_detail_box.add_child(_row("Risk", risk + ("" if best == risk else " (%s with the right gear)" % best.to_lower()), w))
	_detail_box.add_child(_row("Might find", d["rewards"], w))
	var req: Array = d.get("requires", [])
	if not req.is_empty():
		var parts := []
		for id in req:
			parts.append("%s (%s)" % [Items.name_of(id), "you have one" if state.inventory.count(id) > 0 else "you have none"])
		_detail_box.add_child(_row("Needs", ", ".join(parts), w))
	var rec: Array = d.get("recommends", [])
	if not rec.is_empty():
		var parts := []
		for id in rec:
			var have := state.inventory.count(id) > 0
			parts.append("%s%s" % [Items.name_of(id) if id != "ammo" else "Ammo", " (have)" if have else ""])
		_detail_box.add_child(_row("Recommended", ", ".join(parts), w))
	if not av["ok"]:
		_detail_box.add_child(_text(av["reason"], 16, UiTheme.BAD, w))
	else:
		for wtxt in _warnings():
			_detail_box.add_child(_text(wtxt, 15, UiTheme.WARN, w))
	if primary_button != null:
		primary_button.disabled = not av["ok"]
		primary_button.tooltip_text = av["reason"]


func _row(label: String, value: String, w: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := UiTheme.make_label(label.to_upper(), 13, UiTheme.TEXT_DIM)
	l.custom_minimum_size.x = 118
	h.add_child(l)
	h.add_child(_text(value, 16, UiTheme.TEXT, w - 128))
	return h


func _best_gear() -> Dictionary:
	return {"ammo": 6, "crowbar": 1, "flashlight": 1, "backpack": 1}


func _warnings() -> Array:
	var out := []
	if state.health < 35.0:
		out.append("You're badly hurt (health %d). An injury out there could finish you." % int(state.health))
	if state.energy <= D.LOW_ENERGY:
		out.append("You're exhausted. Everything out there is more dangerous.")
	return out


# --- step: gear ----------------------------------------------------------------------------

func _show_gear() -> void:
	step = "gear"
	var d := D.destination(selected)
	_begin("What do you bring?", d["name"])
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	_box.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 520
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	# ammo
	var owned := state.inventory.count("ammo")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var al := UiTheme.make_label("9 mm rounds", 16)
	al.custom_minimum_size.x = 140
	row.add_child(al)
	ammo_slider = HSlider.new()
	ammo_slider.min_value = 0
	ammo_slider.max_value = owned
	ammo_slider.step = 1
	ammo_slider.value = int(gear.get("ammo", 0))
	ammo_slider.custom_minimum_size = Vector2(230, 24)
	ammo_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ammo_slider.editable = owned > 0
	ammo_slider.value_changed.connect(func(v: float): set_ammo(int(v)))
	row.add_child(ammo_slider)
	var count := UiTheme.make_label("", 16, UiTheme.ACCENT)
	count.name = "AmmoCount"
	row.add_child(count)
	left.add_child(row)
	left.add_child(_text(D.gear_effect("ammo", selected) if owned > 0 else "You have no rounds to bring.", 14, UiTheme.TEXT_DIM, 520))
	left.add_child(_rule())
	# tools
	var req: Array = d.get("requires", [])
	for id in D.BRINGABLE_TOOLS:
		var have := state.inventory.count(id) > 0
		var cb := CheckBox.new()
		cb.text = Items.name_of(id) + (" (required)" if id in req and have else ("" if have else ": you don't have one"))
		cb.button_pressed = have and int(gear.get(id, 0)) > 0
		cb.disabled = not have or id in req
		cb.toggled.connect(func(on: bool): set_tool(id, on))
		left.add_child(cb)
		tool_boxes[id] = cb
		if have:
			left.add_child(_text(D.gear_effect(id, selected), 14, UiTheme.TEXT_DIM, 520))
	if state.inventory.count("hammer") > 0:
		left.add_child(_text("The hammer stays home: you need it to build.", 14, UiTheme.TEXT_DIM, 520))
	_gear_summary = VBoxContainer.new()
	_gear_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gear_summary.add_theme_constant_override("separation", 8)
	cols.add_child(_gear_summary)
	back_button = _button("<  Back", back)
	primary_button = _button("Continue  >", to_confirm)
	_footer([back_button, primary_button])
	_refresh_gear_summary()
	_focus(ammo_slider if ammo_slider.editable else primary_button)


func _refresh_gear_summary() -> void:
	if _gear_summary == null:
		return
	var c := _panel.find_child("AmmoCount", true, false) as Label
	if c != null:
		c.text = "%d of %d" % [int(gear.get("ammo", 0)), state.inventory.count("ammo")]
	for ch in _gear_summary.get_children():
		_gear_summary.remove_child(ch)
		ch.queue_free()
	var g := brought_gear()
	var w := PANEL_WIDTH - 520 - 26 - 40
	var base := D.risk_name(D.danger(selected, {}, state.energy))
	var now := D.risk_name(D.danger(selected, g, state.energy))
	_gear_summary.add_child(UiTheme.make_label("RISK", 13, UiTheme.TEXT_DIM))
	var rl := UiTheme.make_label(now + ("" if now == base else "  (bare-handed: %s)" % base.to_lower()), 18, _risk_color(now))
	_gear_summary.add_child(rl)
	_gear_summary.add_child(UiTheme.make_label("BRINGING", 13, UiTheme.TEXT_DIM))
	_gear_summary.add_child(_text(_gear_text(g), 16, UiTheme.TEXT, w))
	var rec: Array = D.destination(selected).get("recommends", [])
	var missing := []
	for id in rec:
		if id == "ammo":
			if int(g.get("ammo", 0)) < 3:
				missing.append("a few rounds")
		elif int(g.get(id, 0)) <= 0:
			missing.append("a " + Items.name_of(id).to_lower())
	if not missing.is_empty():
		_gear_summary.add_child(_text("Recommended: %s." % ", ".join(missing), 15, UiTheme.WARN, w))


func _risk_color(name: String) -> Color:
	match name:
		"Low":
			return UiTheme.GOOD
		"Moderate":
			return UiTheme.WARN
	return UiTheme.BAD


func _gear_text(g: Dictionary) -> String:
	var parts := []
	if int(g.get("ammo", 0)) > 0:
		parts.append("%d round%s" % [g["ammo"], "" if g["ammo"] == 1 else "s"])
	for id in D.BRINGABLE_TOOLS:
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
	var back_at := state.minute_of_day() + float(d["minutes"])
	var w := PANEL_WIDTH - 40
	_box.add_child(_text("%s You'll be gone %s and back around %s." % [d["desc"], _approx(d["minutes"]), D.clock(back_at)], 17, UiTheme.TEXT, w))
	_box.add_child(_row("Bringing", _gear_text(g), w))
	_box.add_child(_row("Risk", D.risk_name(D.danger(selected, g, state.energy)), w))
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


func _event_clock() -> String:
	var n := run.event_ids.size()
	var at := run.depart_at + float(run.dest["minutes"]) * float(run.step + 1) / float(n + 1)
	return "%s  ·  around %s" % [run.dest["name"], D.clock(fposmod(at, 1440.0))]


func _show_event() -> void:
	step = "event"
	var ev := run.current_event()
	_begin(ev["title"], _event_clock())
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
	if int(o.get("ammo", 0)) > 0:
		parts.append("%d round%s" % [o["ammo"], "" if o["ammo"] == 1 else "s"])
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
	for id in D.BRINGABLE_TOOLS:
		if run.has_tool(id):
			parts.append(Items.name_of(id).to_lower())
	return "You carry: " + (", ".join(parts) if not parts.is_empty() else "nothing but your hands") + ".   Keys 1-3 choose."


func _show_outcome() -> void:
	step = "outcome"
	_begin(run.current_event().get("title", "") if not run.is_finished() else D.event(run.event_ids[run.step - 1])["title"], _event_clock_after())
	var w := PANEL_WIDTH - 40
	_box.add_child(_text(last_outcome.get("text", ""), 18, UiTheme.TEXT, w))
	var conseq := []
	if float(last_outcome.get("hurt", 0.0)) >= 0.5:
		conseq.append(["Hurt: -%d health" % int(round(last_outcome["hurt"])), UiTheme.BAD])
	if int(last_outcome.get("ammo", 0)) > 0:
		conseq.append(["%d round%s used" % [last_outcome["ammo"], "" if last_outcome["ammo"] == 1 else "s"], UiTheme.WARN])
	for id in last_outcome.get("lost", []):
		conseq.append(["Lost: %s" % Items.name_of(id).to_lower(), UiTheme.BAD])
	for c in conseq:
		_box.add_child(UiTheme.make_label(c[0], 16, c[1]))
	primary_button = _button("Continue  >" if not run.is_finished() else "Head home  >", continue_on)
	_footer([primary_button])
	_focus(primary_button)


func _event_clock_after() -> String:
	var n := run.event_ids.size()
	var at := run.depart_at + float(run.dest["minutes"]) * float(run.step) / float(n + 1)
	return "%s  ·  around %s" % [run.dest["name"], D.clock(fposmod(at, 1440.0))]


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
	_box.add_child(_report_row("Found", D.items_text(r["gained"]), "Nothing worth carrying.", UiTheme.GOOD, w))
	if not r["consumed"].is_empty():
		_box.add_child(_report_row("Used", D.items_text(r["consumed"]), "", UiTheme.WARN, w))
	if not r["lost"].is_empty():
		_box.add_child(_report_row("Lost", D.items_text(r["lost"]), "", UiTheme.BAD, w))
	var dmg := float(r["damage"])
	_box.add_child(_report_row("Injuries", "-%d health" % int(round(dmg)) if dmg >= 0.5 else "", "Unhurt.", UiTheme.BAD if dmg >= 0.5 else UiTheme.GOOD, w))
	if not r["left_behind"].is_empty():
		_box.add_child(_report_row("Left behind", D.items_text(r["left_behind"]) + " (storage full)", "", UiTheme.WARN, w))
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
