class_name SleepDialog
extends UiModal
## Sleep options at the bed (SPEC §7.8). Owner: U.
## "Sleep until morning" emits sleep_chosen(-1) (the game sleeps until 06:00),
## "Rest 2 hours" emits sleep_chosen(120); Cancel / Esc emits closed. A sleep
## choice closes the dialog and emits only sleep_chosen.
## If GameState has can_sleep() and it returns a reason, the sleep buttons are
## disabled and the reason is shown.

signal sleep_chosen(minutes: float)
signal closed

const REST_MINUTES := 120.0

var state: GameState
var block_reason := ""


func _init() -> void:
	super()
	layer = 70


func open(s: GameState) -> void:
	state = s
	block_reason = _block_reason(s)
	var box := _begin("Rest", 460)
	if s != null:
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		head.add_child(UiTheme.make_icon("moon" if s.is_night() else "sun", 18))
		head.add_child(UiTheme.make_label(UiTheme.day_time_text(s.day(), s.clock_text()), UiTheme.FONT_BODY))
		box.add_child(head)
		var energy := UiTheme.make_stat_bar("energy", "Energy")
		energy.custom_minimum_size.x = 424
		energy.set_value(s.energy, true)
		box.add_child(energy)
		box.add_child(UiTheme.make_caption(_energy_words(s.energy), 424))
	box.add_child(UiTheme.make_spacer(4))

	var morning := _menu_button("Sleep until morning")
	morning.name = "UntilMorning"
	var rest := _menu_button("Rest 2 hours")
	rest.name = "Rest"
	if s != null:
		var m_plan := _plan(s, s.until_morning_minutes())
		UiTheme.set_caption(morning, "wake %s · %s" % [_wake(s, m_plan["minutes"]), UiTheme.duration_text(m_plan["minutes"])])
		var r_plan := _plan(s, REST_MINUTES)
		UiTheme.set_caption(rest, "wake %s" % _wake(s, r_plan["minutes"]))
		if m_plan["interrupted"] and m_plan["minutes"] > 0.0:
			box.add_child(_warning("You'll be woken at %s. Something is coming." % _wake(s, m_plan["minutes"])))
		elif s.invasion_due_soon():
			box.add_child(_warning("Something is coming tonight. You may be woken."))
	morning.pressed.connect(_choose.bind(-1.0))
	rest.pressed.connect(_choose.bind(REST_MINUTES))
	morning.disabled = block_reason != ""
	rest.disabled = block_reason != ""
	if block_reason != "":
		box.add_child(_warning(block_reason))
	box.add_child(morning)
	box.add_child(rest)
	var cancel := _menu_button("Cancel")
	cancel.name = "Cancel"
	cancel.pressed.connect(_cancel)
	box.add_child(cancel)
	_show()


func _warning(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Warning"
	row.add_theme_constant_override("separation", 8)
	var icon := UiTheme.make_icon("warn", 16, UiTheme.WARN)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	row.add_child(UiTheme.make_caption(text, 396, UiTheme.WARN))
	return row


static func _block_reason(s: GameState) -> String:
	if s == null or not s.has_method("can_sleep"):
		return ""
	var r = s.call("can_sleep")
	if typeof(r) == TYPE_STRING:
		return r
	if typeof(r) == TYPE_BOOL and not r:
		return "You can't sleep right now."
	return ""


static func _plan(s: GameState, minutes: float) -> Dictionary:
	var p: Dictionary = s.plan_sleep(minutes)
	return {"minutes": float(p.get("minutes", minutes)), "interrupted": bool(p.get("interrupted", false))}


static func _wake(s: GameState, minutes: float) -> String:
	return UiTheme.clock_from_minutes(s.minute_of_day() + minutes)


static func _energy_words(e: float) -> String:
	if e <= 0.0:
		return "You can barely stand."
	if e <= SurvivalTuning.WARN_LEVEL:
		return "You're exhausted."
	if e < 50.0:
		return "You're tired."
	if e < 85.0:
		return "You could rest."
	return "You're wide awake."


func _choose(minutes: float) -> void:
	if not is_open or block_reason != "":
		return
	close()
	sleep_chosen.emit(minutes)


func _cancel() -> void:
	if not is_open:
		return
	close()
	closed.emit()


func _on_cancel() -> void:
	_cancel()
