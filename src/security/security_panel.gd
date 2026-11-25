class_name SecurityPanel
extends UiModal
## Exp 007 (S): the compact settings panel of one motion sensor or turret
## mount (E on it; UiTheme styling). Every button calls a SecuritySystem
## act_* method and shows its answer on the feedback line.
##   sensor  status (power, HP, last movement), Enabled, Alarm (audible /
##           silent), Reacts to (hostile only / any movement), the linked
##           turret (cycle, or Link nearest), Turn
##   turret  status (gun, loaded, ammo box, reload mode and state, power, HP,
##           enabled, linked sensors), Install <gun> / Remove gun, Add 10 /
##           Fill box / Take ammo out / Reload now, Enabled, Wait for sensor,
##           Turn, Install auto-loader
## Closes with E, Esc or Close (emits closed).

signal closed

const WIDTH := 640

var system: Node                       ## SecuritySystem
var object: WorldObject
var last_text := ""
var _feedback: Label


func _init() -> void:
	super()
	layer = 72


func open(sys: Node, o: WorldObject) -> void:
	system = sys
	object = o
	last_text = ""
	_render()
	_show()


func _render() -> void:
	if object == null or not is_instance_valid(object):
		close_and_emit()
		return
	var had := is_open
	var o := object
	var c := Security.config(o)
	var box := _begin(Security.title(o), WIDTH)
	var power: bool = system.powered() if system != null else true
	if o.kind == "motion_sensor":
		var ago := ""
		if system != null:
			var rt: Dictionary = system._runtime(o)
			var s := float(system.time) - float(rt["last"])
			ago = " · last movement %s" % ("%d s ago" % int(s) if s < 600.0 else "a while ago") if s < 1e8 else " · no movement yet"
		box.add_child(_line("Power %s · HP %d/%d%s" % ["on" if power else "OFF", o.hp, o.max_hp, ago], power))
		box.add_child(UiTheme.make_caption("Watches a %d° cone in front of it up to %d m, never through walls or closed doors. Needs the house's power." % [int(Security.SENSOR_ARC), int(Security.SENSOR_RANGE)], WIDTH - 40, UiTheme.TEXT_FAINT))
		var t: WorldObject = system.turret_by_uid(str(c["link"])) if system != null else null
		box.add_child(_row([
			_btn("Enabled: %s" % ("on" if c["on"] else "off"), "On", _act.bind("toggle", "on")),
			_btn("Alarm: %s" % ("audible" if c["alarm"] else "silent"), "Alarm", _act.bind("toggle", "alarm")),
			_btn("Reacts to: %s" % ("hostiles" if c["hostile"] else "any movement"), "Hostile", _act.bind("toggle", "hostile")),
		]))
		box.add_child(_row([
			_btn("Turret: %s" % (Security.title(t) if t != null else "none"), "Link", _act.bind("link_next", null)),
			_btn("Link nearest", "LinkNearest", _act.bind("link_nearest", null)),
			_btn("Turn", "Turn", _act.bind("turn", null)),
		]))
	else:
		var id := Security.gun(o)
		var a := Security.ammo_type(o)
		var reload := "Auto-loader" if c["auto"] else "Reload by hand"
		if system != null and float(system.reload_left(o)) > 0.0:
			reload += " (reloading…)"
		var links := []
		if system != null:
			for s in system.sensors_of(o):
				links.append(Security.title(s))
		var gun_line := "No gun" if id == "" else "%s · %d/%d loaded · box %d %s" % [WeaponDefs.name_of(id), Security.mag(o), WeaponDefs.capacity(id), Security.box(o), Items.name_of(a).to_lower()]
		box.add_child(_line(gun_line, id != "" and Security.mag(o) > 0))
		box.add_child(_line("%s · Power %s · HP %d/%d · %s" % [reload, "on" if power else "OFF", o.hp, o.max_hp, "enabled" if c["on"] else "switched off"], power and bool(c["on"])))
		box.add_child(UiTheme.make_caption("Linked sensor: %s. Arc %d° · range %d m · fires only what is loaded." % [", ".join(links) if not links.is_empty() else "none",
			int(Security.TURRET_ARC), int(Security.turret_range(id)) if id != "" else int(Security.TURRET_RANGE_CAP)], WIDTH - 40, UiTheme.TEXT_FAINT))
		var guns := []
		if id != "":
			guns.append(_btn("Remove the %s" % WeaponDefs.name_of(id).to_lower(), "Remove", _act.bind("remove", null)))
		else:
			var st: GameState = system._state() if system != null else null
			for g in Security.guns_carried(st):
				guns.append(_btn("Install the %s (%d min)" % [WeaponDefs.name_of(g).to_lower(), int(Security.GUN_MINUTES)], "Install_" + g, _act.bind("install", g)))
			if guns.is_empty():
				box.add_child(UiTheme.make_caption("Carry a firearm (handgun, shotgun) to install it.", WIDTH - 40, UiTheme.WARN))
		if not guns.is_empty():
			box.add_child(_row(guns))
		var ammo_row := [_btn("Add 10", "Add10", _act.bind("fill", 10)), _btn("Fill box", "Fill", _act.bind("fill", Security.BOX_CAP)),
			_btn("Take ammo out", "Take", _act.bind("take", null)), _btn("Reload now", "Reload", _act.bind("reload", null))]
		for b in ammo_row:
			(b as Button).disabled = id == "" and b.name != "Take"
		box.add_child(_row(ammo_row))
		var up := _btn("Auto-loader fitted" if c["auto"] else "Install auto-loader (%s · %d min)" % [BuildPieces.cost_text(Security.AUTO_COST), int(Security.AUTO_MINUTES)], "Upgrade", _act.bind("upgrade", null))
		up.disabled = bool(c["auto"])
		box.add_child(_row([
			_btn("Enabled: %s" % ("on" if c["on"] else "off"), "On", _act.bind("toggle", "on")),
			_btn("Wait for sensor: %s" % ("yes" if c["standby"] else "no"), "Standby", _act.bind("toggle", "standby")),
			_btn("Turn", "Turn", _act.bind("turn", null)),
		]))
		box.add_child(_row([up]))
	_feedback = UiTheme.make_label(last_text, UiTheme.FONT_BODY - 1, UiTheme.GOOD)
	_feedback.name = "Feedback"
	_feedback.custom_minimum_size.y = 22
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size.x = WIDTH - 40
	box.add_child(_feedback)
	var close_b := UiTheme.make_button("Close")
	close_b.name = "Close"
	close_b.pressed.connect(close_and_emit)
	box.add_child(_footer("E / Esc", "Close", [close_b]))
	if had:
		_root.modulate.a = 1.0
		_focus()


func _line(text: String, good: bool) -> Label:
	return UiTheme.make_label(text, UiTheme.FONT_BODY, UiTheme.TEXT if good else UiTheme.WARN)


func _row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for b in buttons:
		(b as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	return row


func _btn(text: String, nm: String, cb: Callable) -> Button:
	var b := UiTheme.make_button(text)
	b.name = nm
	b.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.FONT_SMALL + 1))
	b.pressed.connect(cb)
	return b


## Runs one action (tests call it too). Returns the answer.
func act(what: String, arg: Variant = null) -> String:
	return _act(what, arg)


func _act(what: String, arg: Variant) -> String:
	if system == null or object == null or not is_instance_valid(object):
		return ""
	var t := ""
	match what:
		"toggle":
			t = system.act_toggle(object, str(arg))
		"link_next":
			t = system.act_link_next(object)
		"link_nearest":
			t = system.act_link_nearest(object)
		"turn":
			t = system.act_turn(object)
		"install":
			t = system.act_install(object, str(arg))
		"remove":
			t = system.act_remove(object)
		"fill":
			t = system.act_fill(object, int(arg))
		"take":
			t = system.act_take(object)
		"reload":
			t = system.act_reload(object)
		"upgrade":
			t = system.act_upgrade(object)
	last_text = t
	if is_open:
		_render()
	elif t != "" and system.has_method("_toast"):
		system._toast(t, "info")         # the panel closed for a timed job (mounting, the auto-loader)
	return t


func close_and_emit() -> void:
	if not is_open:
		return
	close()
	closed.emit()


func _on_cancel() -> void:
	close_and_emit()


func _input(event: InputEvent) -> void:
	if is_open and visible and not event.is_echo() and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close_and_emit()
		return
	super._input(event)
