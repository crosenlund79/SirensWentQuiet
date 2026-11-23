class_name DevMenu
extends CanvasLayer
## Developer / cheat menu on F10 (SPEC §7.8). Owner: U.
## A compact, scrollable side panel on the right. It does not pause the game
## and does not take keyboard focus (its buttons are mouse-only), so WASD and
## the number keys keep working while it is open. The game root calls
## setup(state, game) once and toggle() on the dev_menu action (F10).
##
## Stats, inventory and cheats are edited directly on GameState; everything
## else goes through the game's duck-typed dev API, each call guarded by
## has_method: dev_spawn(n), dev_trigger_invasion(), dev_repair_house(),
## dev_advance(minutes), dev_skip_to(hour), dev_set_time_scale(x), dev_info().
## The HUD shows the CHEATS ACTIVE badge while any cheat is on.

const WIDTH := 344.0
const NEED_LEVELS := [0, 25, 50, 100]
const SUPPLY_PACKS := {
	"food": {"canned_food": 3, "snacks": 2, "water": 4},
	"ammo": {"ammo": 10},
	"materials": {"wood": 20, "nails": 40, "scrap": 10},
	"medical": {"bandage": 2, "medkit": 1},
	"tools": {"hammer": 1, "crowbar": 1, "flashlight": 1, "backpack": 1},
}

var state: GameState
var game: Node
var time_scale := 1.0
var is_open := false
var last_status := ""

var _root: Control
var _panel: PanelContainer
var _toggles := {}
var _speed_buttons := {}
var _inspect: RichTextLabel
var _status: Label
var _refresh_t := 0.0
var _save_info := {}
var _save_t := 0.0


func _init() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func setup(s: GameState, g: Node) -> void:
	state = s
	game = g
	if _root != null:
		_sync()


func toggle() -> void:
	set_open(not is_open)


func set_open(on: bool) -> void:
	if on and _root == null:
		_build()
	is_open = on
	visible = on
	Sfx.ui("ui/open" if on else "ui/close")
	if on:
		_save_t = 0.0
		_sync()
		_refresh_inspect()
		_root.modulate.a = 0.0
		UiTheme.fade(_root, 1.0)


# --- actions (also used by tests) ---------------------------------------------

func set_cheat(key: String, on: bool) -> void:
	if state == null:
		return
	state.cheats[key] = on
	state.changed.emit()
	_say("%s %s" % [GameHud.CHEAT_NAMES.get(key, key), "on" if on else "off"])
	_sync()


func add_pack(pack: String) -> void:
	if state == null or not SUPPLY_PACKS.has(pack):
		return
	var got := []
	var refused := false
	for id in SUPPLY_PACKS[pack]:
		var want: int = SUPPLY_PACKS[pack][id]
		if Items.category(id) == "tool" and state.inventory.count(id) > 0:
			continue
		var n := state.inventory.add(id, want)
		if n > 0:
			got.append("%d %s" % [n, Items.name_of(id).to_lower()])
		if n < want:
			refused = true
	var text := ("Added " + ", ".join(got)) if not got.is_empty() else "Nothing added"
	if refused:
		text += " (storage full)"
	_say(text)


func set_need(stat: String, value: float) -> void:
	if state == null or not stat in ["hunger", "hydration", "energy", "health"]:
		return
	state.set(stat, clampf(value, 0.0, 100.0))
	state.changed.emit()
	_say("%s set to %d" % [{"hunger": "Food", "hydration": "Water", "energy": "Energy", "health": "Health"}[stat], int(value)])


func set_speed(x: float) -> void:
	time_scale = x
	if _call("dev_set_time_scale", [x]):
		_say("Time ×%d" % int(x))
	_sync()


func advance_hour() -> void:
	if _call("dev_advance", [60.0]):
		_say("One hour passes")


func skip_to(hour: int) -> void:
	if _call("dev_skip_to", [hour]):
		_say("Skipped to %02d:00" % hour)


func trigger_invasion() -> void:
	if _call("dev_trigger_invasion", []):
		_say("Invasion triggered")


func spawn(n: int) -> void:
	if _call("dev_spawn", [n]):
		_say("Spawned %d psycho%s" % [n, "" if n == 1 else "s"])


func repair_house() -> void:
	if _call("dev_repair_house", []):
		_say("House repaired")


## Calls a game dev method if it exists. Returns false (and says so) if not.
func _call(method: String, args: Array) -> bool:
	if game == null or not is_instance_valid(game) or not game.has_method(method):
		_say("The game has no %s()" % method, true)
		return false
	game.callv(method, args)
	_refresh_inspect()
	return true


func _say(text: String, bad := false) -> void:
	last_status = text
	if _status != null:
		_status.text = text
		_status.add_theme_color_override("font_color", UiTheme.WARN if bad else UiTheme.GOOD)
	_refresh_inspect()


# --- inspect ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_open:
		return
	_refresh_t -= delta
	_save_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.5
		_sync()
		_refresh_inspect()


func inspect_text() -> String:
	if state == null:
		return "No game state."
	var s := state
	var lines := PackedStringArray()
	lines.append("[color=#%s]%s[/color]   night %.2f" % [UiTheme.ACCENT.to_html(false), UiTheme.day_time_text(s.day(), s.clock_text()), s.night_amount()])
	lines.append("health %.1f  food %.1f  water %.1f  energy %.1f" % [s.health, s.hunger, s.hydration, s.energy])
	lines.append("speed ×%.2f   days survived %d%s" % [s.move_speed_scale(), s.days_survived(), "   DEAD (%s)" % s.death_cause if s.dead else ""])
	var inv := PackedStringArray()
	var ids: Array = s.inventory.counts.keys()
	ids.sort()
	for id in ids:
		var cap := s.inventory.cap(id)
		inv.append("%s %d%s" % [id, s.inventory.count(id), "/%d" % cap if cap > 0 else ""])
	lines.append("[color=#%s]inventory[/color] %s  ·  crates %d" % [UiTheme.TEXT_DIM.to_html(false), ", ".join(inv) if not inv.is_empty() else "empty", s.inventory.storage_crates])
	lines.append("[color=#%s]next invasion[/color] %s" % [UiTheme.TEXT_DIM.to_html(false), next_invasion_text()])
	var run := s.run
	lines.append("[color=#%s]run[/color] invasions done %d · active %s · expeditions %d · seed %s" % [UiTheme.TEXT_DIM.to_html(false),
		int(run.get("invasions_done", 0)), "yes" if run.get("invasion_active", false) else "no", int(run.get("expeditions", 0)), str(run.get("seed", "?"))])
	var cheats := GameHud.active_cheats(s)
	lines.append("[color=#%s]cheats[/color] %s · time ×%s" % [UiTheme.TEXT_DIM.to_html(false), ", ".join(cheats) if not cheats.is_empty() else "none", str(time_scale)])
	if _save_t <= 0.0 or _save_info.is_empty():
		_save_t = 4.0
		_save_info = SaveGame.info()
	lines.append("[color=#%s]save[/color] %s" % [UiTheme.TEXT_DIM.to_html(false), save_text(_save_info)])
	if game != null and is_instance_valid(game) and game.has_method("dev_info"):
		var gi := str(game.call("dev_info"))
		if gi != "":
			lines.append("[color=#%s]game[/color] %s" % [UiTheme.TEXT_DIM.to_html(false), gi])
	return "\n".join(lines)


func next_invasion_text() -> String:
	if state == null:
		return "?"
	if state.has_method("next_invasion_text"):
		return str(state.call("next_invasion_text"))
	if state.run.get("invasion_active", false):
		return "in progress (size %d)" % state.invasion_size()
	var at := float(state.run.get("next_invasion_at", -1.0))
	if at < 0.0:
		return "none scheduled"
	var d := int(floor(at / 1440.0)) + 1
	var left := maxf(at - state.total_minutes, 0.0)
	var t := "Day %d %s (in %s) · %d psychos" % [d, UiTheme.clock_from_minutes(at), UiTheme.duration_text(left), state.invasion_size()]
	if state.has_method("invasion_index"):
		t += " · #%d" % int(state.call("invasion_index"))
	return t


static func save_text(info: Dictionary) -> String:
	if not info.get("exists", false):
		return "none"
	var t := "valid" if info.get("valid", false) else "INVALID (%s)" % info.get("error", "?")
	var sm = info.get("summary", {})
	if typeof(sm) == TYPE_DICTIONARY and not sm.is_empty():
		t += " · " + UiTheme.save_summary_text(sm)
	var at := int(info.get("saved_at", 0))
	if at > 0:
		t += " · saved " + Time.get_datetime_string_from_unix_time(at, true)
	return t


func _refresh_inspect() -> void:
	if _inspect != null and is_open:
		_inspect.text = inspect_text()


func _sync() -> void:
	if state == null or _toggles.is_empty():
		return
	for k in _toggles:
		(_toggles[k] as UiToggle).set_pressed_no_signal(bool(state.cheats.get(k, false)))
		(_toggles[k] as UiToggle).queue_redraw()
	for x in _speed_buttons:
		var b: Button = _speed_buttons[x]
		b.set_pressed_no_signal(is_equal_approx(float(x), time_scale))


# --- construction -------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.theme()
	add_child(_root)
	_panel = UiTheme.make_panel()
	_panel.name = "Panel"
	var sb := UiTheme.panel_style()
	sb.set_content_margin_all(14)
	sb.border_color = Color(UiTheme.ACCENT, 0.35)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -WIDTH - 20.0
	_panel.offset_right = -20.0
	_panel.offset_top = 80.0
	_panel.offset_bottom = -20.0
	_root.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(UiTheme.make_title("Developer", 18))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	head.add_child(UiTheme.make_key_hint("F10", "close", UiTheme.FONT_SMALL, UiTheme.TEXT_FAINT))
	col.add_child(UiTheme.make_caption("Cheats and test tools. The game keeps running.", 0, UiTheme.TEXT_FAINT))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	box.add_child(UiTheme.make_section("Cheats"))
	for k in [["invulnerable", "Invulnerable"], ["unlimited", "Unlimited resources"]]:
		var t := UiTheme.make_toggle(k[1])
		t.name = "Cheat_" + k[0]
		t.focus_mode = Control.FOCUS_NONE
		t.custom_minimum_size.y = 32
		var key: String = k[0]
		t.toggled.connect(func(on: bool): set_cheat(key, on))
		box.add_child(t)
		_toggles[k[0]] = t

	box.add_child(UiTheme.make_section("Supplies"))
	box.add_child(_grid(2, [
		["+ Food & water", add_pack.bind("food")], ["+ 10 ammo", add_pack.bind("ammo")],
		["+ Materials", add_pack.bind("materials")], ["+ Medical", add_pack.bind("medical")],
		["All tools", add_pack.bind("tools")],
	]))

	box.add_child(UiTheme.make_section("Needs"))
	for st in [["hunger", "Food"], ["hydration", "Water"], ["energy", "Energy"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var l := UiTheme.make_label(st[1], UiTheme.FONT_SMALL + 1, UiTheme.TEXT_DIM)
		l.custom_minimum_size.x = 62
		row.add_child(l)
		for v in NEED_LEVELS:
			var b := _small(str(v), set_need.bind(st[0], float(v)))
			b.name = "Need_%s_%d" % [st[0], v]
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b)
		box.add_child(row)

	box.add_child(UiTheme.make_section("Time"))
	box.add_child(_grid(3, [["+1 hour", advance_hour], ["Night 20:00", skip_to.bind(20)], ["Morning 06:00", skip_to.bind(6)]]))
	var speed := HBoxContainer.new()
	speed.add_theme_constant_override("separation", 5)
	var sl := UiTheme.make_label("Speed", UiTheme.FONT_SMALL + 1, UiTheme.TEXT_DIM)
	sl.custom_minimum_size.x = 62
	speed.add_child(sl)
	var group := ButtonGroup.new()
	for x in [1, 4, 10]:
		var b := _small("×%d" % x, set_speed.bind(float(x)))
		b.name = "Speed_%d" % x
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		speed.add_child(b)
		_speed_buttons[x] = b
	box.add_child(speed)

	box.add_child(UiTheme.make_section("Threats"))
	box.add_child(_grid(2, [
		["Next invasion", trigger_invasion], ["Repair house", repair_house],
		["Spawn 1 psycho", spawn.bind(1)], ["Spawn 3 psychos", spawn.bind(3)],
	]))

	_status = UiTheme.make_caption("", WIDTH - 40, UiTheme.GOOD)
	_status.name = "Status"
	box.add_child(_status)

	box.add_child(UiTheme.make_section("Inspect"))
	_inspect = RichTextLabel.new()
	_inspect.name = "Inspect"
	_inspect.bbcode_enabled = true
	_inspect.fit_content = true
	_inspect.scroll_active = false
	_inspect.selection_enabled = true
	_inspect.focus_mode = Control.FOCUS_NONE
	_inspect.custom_minimum_size.x = WIDTH - 40
	_inspect.add_theme_font_size_override("normal_font_size", 12)
	_inspect.add_theme_color_override("default_color", UiTheme.TEXT)
	box.add_child(_inspect)


func _small(text: String, cb: Callable) -> Button:
	var b := UiTheme.make_button(text)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 30
	b.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL + 1)
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var sb := UiTheme.button_style(st)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	return b


func _grid(columns: int, items: Array) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 5)
	g.add_theme_constant_override("v_separation", 5)
	for it in items:
		var b := _small(it[0], it[1])
		b.name = (it[0] as String).validate_node_name().replace(" ", "_")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)
	return g


## Test access: a button by its visible text.
func button(text: String) -> BaseButton:
	return _find_button(_root, text) if _root != null else null


static func _find_button(n: Node, text: String) -> BaseButton:
	for c in n.get_children():
		if c is BaseButton and (c as BaseButton).get("text") == text:
			return c
		var r := _find_button(c, text)
		if r != null:
			return r
	return null
