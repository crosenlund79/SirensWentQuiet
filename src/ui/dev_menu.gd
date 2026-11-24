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
## Experiment 003 (the game's `dev` helper, src/game/game_dev.gd, when it has
## the method, else the game itself): dev_spawn_type(kind), dev_wave(kinds),
## dev_instant_mission(id, approach), dev_reveal_map(), dev_set_difficulty(level),
## dev_fill_magazines(). Packs add weapons, shells, gear, stone and iron.
## The HUD shows the CHEATS ACTIVE badge while any cheat is on.

const WIDTH := 344.0
const NEED_LEVELS := [0, 25, 50, 100]
const SUPPLY_PACKS := {
	"food": {"canned_food": 3, "snacks": 2, "water": 4},
	"ammo": {"ammo": 10},
	"weapons": {"shotgun": 1, "shells": 10},
	"materials": {"wood": 20, "stone": 20, "iron": 10, "nails": 40, "scrap": 10},
	"medical": {"bandage": 2, "medkit": 1},
	"tools": {"hammer": 1, "crowbar": 1, "flashlight": 1, "backpack": 1},
	"gear": {"vest": 1, "backpack": 1, "flashlight": 1, "crowbar": 1},
	"wood": {"wood": 10}, "stone": {"stone": 10}, "iron": {"iron": 10}, "scrap": {"scrap": 10},
}
const WAVE_MAX := 4                     ## per kind in a chosen wave

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
var wave := {"psycho": 1, "runner": 0, "brute": 0, "bomber": 1}   ## the chosen composition
var _wave_buttons := {}
var _difficulty_buttons := {}
var _mission_place: OptionButton
var _mission_approach: OptionButton


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
		if Items.is_unique(id) and state.inventory.count(id) > 0:
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


func spawn_type(kind: String) -> void:
	if _call("dev_spawn_type", [kind]):
		_say("Spawned a %s" % EnemyDefs.get_def(kind)["name"].to_lower())


## Cycles the count of `kind` in the chosen wave (0 .. WAVE_MAX).
func bump_wave(kind: String) -> void:
	wave[kind] = (int(wave.get(kind, 0)) + 1) % (WAVE_MAX + 1)
	_sync()


## The chosen composition as spawn order (bombers last, as the director would).
func wave_kinds() -> Array:
	var out := []
	for k in ["psycho", "runner", "brute", "bomber"]:
		for i in int(wave.get(k, 0)):
			out.append(k)
	return out


func start_wave() -> void:
	var kinds := wave_kinds()
	if kinds.is_empty():
		_say("The wave is empty", true)
		return
	if _call("dev_wave", [kinds]):
		_say("Invasion: %s" % ", ".join(kinds))


func set_difficulty(level: String) -> void:
	if _call("dev_set_difficulty", [level]):
		_say("Difficulty %s" % Difficulty.name_of(level))
	elif state != null:
		state.set_difficulty(level)
	_sync()


func fill_magazines() -> void:
	if _call("dev_fill_magazines", []):
		_say("Magazines filled")


func reveal_map() -> void:
	if _call("dev_reveal_map", []):
		_say("All map locations revealed")


func run_mission(id := "", approach := "") -> void:
	if id == "" and _mission_place != null and _mission_place.selected >= 0:
		id = str(_mission_place.get_item_metadata(_mission_place.selected))
	if approach == "" and _mission_approach != null and _mission_approach.selected >= 0:
		approach = str(_mission_approach.get_item_metadata(_mission_approach.selected))
	if approach == "":
		approach = "general"
	if _call("dev_instant_mission", [id, approach]):
		_say("Mission: %s (%s)" % [RegionLocations.name_of(id), approach])


## The object that answers a dev method: the game's `dev` helper when it has
## it (Experiment 003), else the game root.
func _target(method: String) -> Object:
	if game == null or not is_instance_valid(game):
		return null
	var d = game.get("dev")
	if d is Object and is_instance_valid(d) and d.has_method(method):
		return d
	return game if game.has_method(method) else null


## Calls a game dev method if it exists. Returns false (and says so) if not.
func _call(method: String, args: Array) -> bool:
	var t := _target(method)
	if t == null:
		_say("The game has no %s()" % method, true)
		return false
	t.callv(method, args)
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
	for k in _wave_buttons:
		(_wave_buttons[k] as Button).text = "%s ×%d" % [EnemyDefs.get_def(k)["name"], int(wave.get(k, 0))]
	for lv in _difficulty_buttons:
		(_difficulty_buttons[lv] as Button).set_pressed_no_signal(lv == state.difficulty)


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
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # never past the right edge
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
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 12)
	scroll.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(box)

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
		["+ Food & water", add_pack.bind("food")], ["+ Medical", add_pack.bind("medical")],
		["+ 10 ammo", add_pack.bind("ammo")], ["+ Shotgun & shells", add_pack.bind("weapons")],
		["Fill magazines", fill_magazines], ["+ Vest & gear", add_pack.bind("gear")],
		["+ Materials", add_pack.bind("materials")], ["All tools", add_pack.bind("tools")],
	]))
	box.add_child(_grid(2, [
		["+10 planks", add_pack.bind("wood")], ["+10 stone", add_pack.bind("stone")],
		["+10 iron", add_pack.bind("iron")], ["+10 scrap", add_pack.bind("scrap")],
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

	box.add_child(UiTheme.make_section("Difficulty"))
	var dg := ButtonGroup.new()
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 5)
	for lv in Difficulty.LEVELS:
		var db := _small(Difficulty.name_of(lv), set_difficulty.bind(lv))
		db.name = "Difficulty_" + lv
		db.toggle_mode = true
		db.button_group = dg
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		drow.add_child(db)
		_difficulty_buttons[lv] = db
	box.add_child(drow)

	box.add_child(UiTheme.make_section("Threats"))
	box.add_child(_grid(2, [
		["Next invasion", trigger_invasion], ["Repair house", repair_house],
		["Spawn 1 psycho", spawn.bind(1)], ["Spawn 3 psychos", spawn.bind(3)],
	]))
	var spawn_items := []
	for k in EnemyDefs.KINDS:
		spawn_items.append(["+ " + EnemyDefs.get_def(k)["name"], spawn_type.bind(k)])
	box.add_child(_grid(2, spawn_items))
	box.add_child(UiTheme.make_caption("Invasion with a chosen wave (click a type to change its count):", WIDTH - 52, UiTheme.TEXT_FAINT))
	var wave_items := []
	for k in EnemyDefs.KINDS:
		wave_items.append(["%s ×%d" % [EnemyDefs.get_def(k)["name"], int(wave.get(k, 0))], bump_wave.bind(k)])
	var wg := _grid(2, wave_items)
	for i in EnemyDefs.KINDS.size():
		var wb := wg.get_child(i) as Button
		wb.name = "Wave_" + EnemyDefs.KINDS[i]
		_wave_buttons[EnemyDefs.KINDS[i]] = wb
	box.add_child(wg)
	box.add_child(_grid(1, [["Start this wave", start_wave]]))

	box.add_child(UiTheme.make_section("Map and missions"))
	_mission_place = OptionButton.new()
	_mission_place.name = "MissionPlace"
	_mission_place.focus_mode = Control.FOCUS_NONE
	_mission_place.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL + 1)
	for id in RegionLocations.ids():
		_mission_place.add_item(RegionLocations.name_of(id))
		_mission_place.set_item_metadata(_mission_place.item_count - 1, id)
	_mission_approach = OptionButton.new()
	_mission_approach.name = "MissionApproach"
	_mission_approach.focus_mode = Control.FOCUS_NONE
	_mission_approach.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL + 1)
	for a in ExpeditionData.approaches():
		_mission_approach.add_item(str(a["name"]))
		_mission_approach.set_item_metadata(_mission_approach.item_count - 1, a["id"])
	for ob in [_mission_place, _mission_approach]:
		(ob as OptionButton).fit_to_longest_item = false      # keep the panel narrow
		(ob as OptionButton).clip_text = true
		(ob as OptionButton).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(ob)
	box.add_child(_grid(2, [["Run mission now", run_mission.bind("", "")], ["Reveal all places", reveal_map]]))
	_build_levels_section(box)          # Experiment 004 (L)

	_build_house_section(box)      # Experiment 004
	_build_exp004_e(box)          # Experiment 004 (E): the car and the quick-access bar
	_build_home_section(box)     # Experiment 004 (H)
	_build_structure_section(box)     # Refinement 01 (S)

	_status = UiTheme.make_caption("", WIDTH - 52, UiTheme.GOOD)
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
	_inspect.custom_minimum_size.x = WIDTH - 52
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


# --- Experiment 004: house tools (furniture, doors, the fuse box, destruction) ------

const HouseDev := preload("res://src/world/house_dev.gd")


func _build_house_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("House (Exp. 004)"))
	box.add_child(_grid(2, [["Destroy furniture", house_tool.bind("destroy_furniture")], ["Damage all doors", house_tool.bind("damage_doors")],
		["Toggle fuse box", house_tool.bind("toggle_fuse")], ["Destroy fuse box", house_tool.bind("destroy_fuse")],
		["10 debris blasts", house_tool.bind("blasts")], ["Repair everything", repair_house]]))


## Runs a HouseDev tool on the game's house.
func house_tool(what: String) -> void:
	var w: Variant = game.get("world") if game != null and is_instance_valid(game) else null
	if not (w is HouseWorld):
		_say("No house.", true)
		return
	_say(HouseDev.run(w, what))


# --- Experiment 004: storeys (owner L; methods on src/levels/game_levels.gd) -------------

func _build_levels_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Levels"))
	box.add_child(_grid(2, [
		["Give shovel", _levels_call.bind("dev_give_shovel", [], "A shovel")],
		["Build upper floor", _levels_call.bind("dev_build_upper", [], "Upper floor built")],
		["Dig 3×3 basement", _levels_call.bind("dev_dig_basement", [], "Basement dug")],
		["Go: basement", _levels_call.bind("dev_goto", [-1], "Basement")],
		["Go: ground floor", _levels_call.bind("dev_goto", [0], "Ground floor")],
		["Go: upper floor", _levels_call.bind("dev_goto", [1], "Upper floor")],
	]))


func _levels_call(method: String, args: Array, said: String) -> void:
	var l = game.get("levels") if game != null and is_instance_valid(game) else null
	if not (l is Object) or not is_instance_valid(l) or not l.has_method(method):
		_say("The game has no levels.%s()" % method, true)
		return
	l.callv(method, args)
	_say(said)
# --- Experiment 004 (E): the car and the quick-access bar -----------------------

func _build_exp004_e(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Car and quick bar"))
	box.add_child(_grid(2, [["Car parts", _exp004_e_call.bind("car", "dev_give_parts", "Car parts and fuel added")],
		["Repair car now", _exp004_e_call.bind("car", "dev_repair", "The car runs")],
		["Bar test kit", _exp004_e_kit]]))


func _exp004_e_call(helper: String, method: String, said: String) -> void:
	var h = game.get(helper) if game != null and is_instance_valid(game) else null
	if not (h is Object and is_instance_valid(h) and h.has_method(method)):
		_say("The game has no %s.%s()" % [helper, method], true)
		return
	h.call(method)
	_say(said)


## Gear and supplies to try every kind of bar item.
func _exp004_e_kit() -> void:
	if state == null:
		return
	for id in ["flashlight", "crowbar", "shovel", "hammer", "medkit", "bandage", "water", "canned_food", "snacks"]:
		state.inventory.add(id, 1 if Items.is_unique(id) else 2)
	_say("Bar test kit added")

# --- Experiment 004 (H): the Home section --------------------------------------

## Fireplace, lights, northern lights, night and snow, on the game's `home`
## helper (src/home/game_home.gd).
func _build_home_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Home"))
	box.add_child(_grid(2, [
		["Toggle fireplace", home_call.bind("dev_toggle_fire", [])], ["Northern lights tonight", home_call.bind("dev_force_aurora", [])],
		["All lights on", home_call.bind("dev_all_lights", [true])], ["All lights off", home_call.bind("dev_all_lights", [false])],
		["Time 23:00", home_call.bind("dev_night", [])], ["Snow on/off", home_call.bind("dev_snow", [])],
	]))


## Calls a method on the game's home helper and shows what it returns.
func home_call(method: String, args: Array) -> void:
	var h = game.get("home") if game != null and is_instance_valid(game) else null
	if not (h is Object and is_instance_valid(h) and h.has_method(method)):
		_say("The game has no home.%s()" % method, true)
		return
	_say(str(h.callv(method, args)))


# --- Refinement 01 (S): structural support (methods on src/world/game_support.gd) ------

func _build_structure_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Structure"))
	box.add_child(_grid(2, [["Show support", _support_call.bind("dev_show_support")],
		["Collapse test", _support_call.bind("dev_collapse_test")]]))


func _support_call(method: String) -> void:
	var h = game.get("support") if game != null and is_instance_valid(game) else null
	if not (h is Object and is_instance_valid(h) and h.has_method(method)):
		_say("The game has no support.%s()" % method, true)
		return
	_say(str(h.call(method)))
