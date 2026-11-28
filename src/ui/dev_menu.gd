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
##
## Exp 012 (A): tabs (TABS: Story, Player, World, Enemies, Building, POIs,
## Audio, Debug), one scrollable page each, built at once (so tests find any
## button by its text). _tab(name) returns a tab's page box; a section goes
## into a tab with `_build_x_section(_tab("World"))`. Sections still passed
## the old `box` land in a "More" tab. The last tab shown is remembered for
## the session (last_tab). The Debug tab shows FPS, frame times, render info,
## errors and status; the Audio tab what plays now.

const WIDTH := 372.0
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
		_finish_tabs()                 # Exp 012 (A): after every section, the agents' too
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
	_note_frame()                  # Exp 012 (A): the Debug tab's frame times
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
	if not is_open:
		return
	var tab := current_tab()
	if _inspect != null and tab == "Debug":
		_inspect.text = inspect_text()
	if tab == "Debug":
		_debug_refresh()          # Exp 012 (A)
	if tab == "Audio":
		_audio_refresh()          # Exp 005 (A)
		_audio_now_refresh()      # Exp 012 (A)


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
	_build_shell()

	# Player: cheats, supplies, needs, gear, Eli, skills
	_build_cheats_section(_tab("Player"))
	_build_supplies_section(_tab("Player"))
	_build_needs_section(_tab("Player"))
	_build_exp004_e(_tab("Player"))          # Experiment 004 (E): the car and the quick-access bar
	_build_character_section(_tab("Player"))     # Exp 010 (C)
	_build_research_section(_tab("Player"))     # Exp 006 (R)
	# World: time, difficulty, home, comfort, noise and visibility
	_build_time_section(_tab("World"))
	_build_difficulty_section(_tab("World"))
	_build_home_section(_tab("World"))     # Experiment 004 (H)
	_build_comfort_section(_tab("World"))     # Exp 005 (C)
	_build_noise_section(_tab("World"))     # Exp 007 (N)
	# Enemies: invasions, spawns, waves; the internal figure
	_build_threats_section(_tab("Enemies"))
	_build_internal_figure_section(_tab("Enemies"))     # Exp 011 (moved from Character)
	# Building: storeys, the house, structure, furniture, defences, security
	_build_levels_section(_tab("Building"))          # Experiment 004 (L)
	_build_house_section(_tab("Building"))      # Experiment 004
	_build_structure_section(_tab("Building"))     # Refinement 01 (S)
	_build_furniture_section(_tab("Building"))     # Exp 005 (F)
	_build_balance_section(_tab("Building"))     # Exp 006 (B)
	_build_defense_section(_tab("Building"))     # Exp 006 (D)
	_build_security_section(_tab("Building"))     # Exp 007 (S)
	_build_overview_section(_tab("Building"))     # Exp 007 (O)
	# POIs: missions, the place you're at, travel, the generator
	_build_missions_section(_tab("POIs"))
	_build_poi_section(_tab("POIs"))     # Exp 007 (P)
	_build_travel_section(_tab("POIs"))     # Exp 007 (T)
	_build_poigen_section(_tab("POIs"))     # Exp 009 (D)
	# Audio: the player, layers, the inbox; what plays now
	_build_audio_section(_tab("Audio"))     # Exp 005 (A)
	_build_audio_now_section(_tab("Audio"))     # Exp 012 (A)
	# Debug: performance, errors and status, the save, inspect
	_build_debug_section(_tab("Debug"))     # Exp 012 (A)

	# --- Exp 012: the other agents' sections -------------------------------------
	# Each agent appends ONE line below, e.g.
	#     _build_e12_s_section(box)   # Exp 012 (S) -> tab: Story
	# `box` collects unrouted sections in a "More" tab, so a line works as is.
	# The lead routes each into its tab by replacing `box` with _tab("<Tab>").
	var box := _unrouted
	box.set_meta("unrouted", true)
	_build_e12_e_section(_tab("Enemies"))   # Exp 012 (E)
	_build_e12_s_section(_tab("Story"))   # Exp 012 (S)
	_build_e12_s_audio_section(_tab("Audio"))   # Exp 012 (S)
	_build_e12_g_section(_tab("Enemies"))   # Exp 012 (G)
	_build_e12_l_section(_tab("POIs"))   # Exp 012 (L)
	_build_e12_v_section(_tab("Debug"))   # Exp 012 (V)


# --- Exp 012 (A): the tabbed shell --------------------------------------------

const TABS := ["Story", "Player", "World", "Enemies", "Building", "POIs", "Audio", "Debug"]
const TAB_COLUMNS := 4
const MORE_TAB := "More"
static var last_tab := "Player"          ## the tab shown on opening (remembered per session)

var _tabs := {}                          ## name -> {"button": Button, "page": ScrollContainer, "box": VBoxContainer}
var _tab_bar: GridContainer
var _pages: VBoxContainer
var _tab_group := ButtonGroup.new()
var _unrouted: VBoxContainer             ## sections not routed to a tab yet (shown as "More")
var _tabs_done := false


## The page of tab `name` (created on first use, after the standard tabs).
func _tab(name: String) -> VBoxContainer:
	if _tabs.has(name):
		return _tabs[name]["box"]
	var b := UiTheme.make_tab(name)
	b.name = "Tab_" + name.validate_node_name()
	b.button_group = _tab_group
	b.custom_minimum_size = Vector2(0, 28)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.FONT_SMALL))
	b.pressed.connect(select_tab.bind(name))
	_tab_bar.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.name = "Page_" + name.validate_node_name()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.visible = false
	_pages.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 12)
	scroll.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(box)
	_tabs[name] = {"button": b, "page": scroll, "box": box}
	return box


## Shows tab `name` (remembered for the next opening this session).
func select_tab(name: String) -> void:
	if not _tabs.has(name):
		return
	for n in _tabs:
		var on: bool = n == name
		(_tabs[n]["page"] as Control).visible = on
		(_tabs[n]["button"] as Button).set_pressed_no_signal(on)
	last_tab = name
	_refresh_t = 0.0


func current_tab() -> String:
	for n in _tabs:
		if (_tabs[n]["page"] as Control).visible:
			return n
	return ""


func tab_names() -> PackedStringArray:
	return PackedStringArray(_tabs.keys())


## The frame: title, the tab bar, the pages and the status line under them.
func _build_shell() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.theme()
	add_child(_root)
	_panel = UiTheme.make_panel()
	_panel.name = "Panel"
	var sb := UiTheme.panel_style()
	sb.set_content_margin_all(12)
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
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(UiTheme.make_title("Developer", 18))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	head.add_child(UiTheme.make_key_hint("F10", "close", UiTheme.FONT_SMALL, UiTheme.TEXT_FAINT))
	_tab_bar = GridContainer.new()
	_tab_bar.name = "Tabs"
	_tab_bar.columns = TAB_COLUMNS
	_tab_bar.add_theme_constant_override("h_separation", 3)
	_tab_bar.add_theme_constant_override("v_separation", 3)
	col.add_child(_tab_bar)
	_pages = VBoxContainer.new()
	_pages.name = "Pages"
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_pages)
	for t in TABS:
		_tab(t)
	_unrouted = VBoxContainer.new()
	_unrouted.add_theme_constant_override("separation", 7)
	_status = UiTheme.make_caption("", WIDTH - 40, UiTheme.GOOD)
	_status.name = "Status"
	col.add_child(HSeparator.new())
	col.add_child(_status)


## After _build(): the "More" tab for unrouted sections, a note on empty
## tabs, then the remembered tab.
func _finish_tabs() -> void:
	if _tabs_done:
		return
	_tabs_done = true
	if _unrouted != null and _unrouted.get_child_count() > 0:
		var more := _tab(MORE_TAB)
		for c in _unrouted.get_children():
			c.reparent(more, false)
	if _unrouted != null:
		_unrouted.queue_free()
		_unrouted = null
	for n in _tabs:
		var box: VBoxContainer = _tabs[n]["box"]
		if box.get_child_count() == 0:
			box.add_child(UiTheme.make_caption("Nothing here yet.", WIDTH - 52, UiTheme.TEXT_FAINT))
	var w := 0.0                   # one width for every tab (no jumping panel)
	for n in _tabs:
		w = maxf(w, (_tabs[n]["page"] as Control).get_combined_minimum_size().x)
	_pages.custom_minimum_size.x = w
	select_tab(last_tab if _tabs.has(last_tab) else "Player")


# --- the standard sections (each was inline in the single-page menu) ----------

func _build_cheats_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Cheats"))
	for k in [["invulnerable", "Invulnerable"], ["unlimited", "Unlimited resources"]]:
		var t := UiTheme.make_toggle(k[1])
		t.name = "Cheat_" + k[0]
		t.focus_mode = Control.FOCUS_NONE
		t.custom_minimum_size.y = 30
		var key: String = k[0]
		t.toggled.connect(func(on: bool): set_cheat(key, on))
		box.add_child(t)
		_toggles[k[0]] = t


func _build_supplies_section(box: VBoxContainer) -> void:
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


func _build_needs_section(box: VBoxContainer) -> void:
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


func _build_time_section(box: VBoxContainer) -> void:
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


func _build_difficulty_section(box: VBoxContainer) -> void:
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


func _build_threats_section(box: VBoxContainer) -> void:
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


func _build_missions_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Map and missions"))
	_mission_place = OptionButton.new()
	_mission_place.name = "MissionPlace"
	_mission_place.focus_mode = Control.FOCUS_NONE
	_mission_place.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.FONT_SMALL + 1))
	for id in RegionLocations.ids():
		_mission_place.add_item(RegionLocations.name_of(id))
		_mission_place.set_item_metadata(_mission_place.item_count - 1, id)
	_mission_approach = OptionButton.new()
	_mission_approach.name = "MissionApproach"
	_mission_approach.focus_mode = Control.FOCUS_NONE
	_mission_approach.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.FONT_SMALL + 1))
	for a in ExpeditionData.approaches():
		_mission_approach.add_item(str(a["name"]))
		_mission_approach.set_item_metadata(_mission_approach.item_count - 1, a["id"])
	for ob in [_mission_place, _mission_approach]:
		(ob as OptionButton).fit_to_longest_item = false      # keep the panel narrow
		(ob as OptionButton).clip_text = true
		(ob as OptionButton).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(ob)
	box.add_child(_grid(2, [["Run mission now", run_mission.bind("", "")], ["Reveal all places", reveal_map]]))


func _build_inspect_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Inspect"))
	_inspect = RichTextLabel.new()
	_inspect.name = "Inspect"
	_inspect.bbcode_enabled = true
	_inspect.fit_content = true
	_inspect.scroll_active = false
	_inspect.selection_enabled = true
	_inspect.focus_mode = Control.FOCUS_NONE
	_inspect.custom_minimum_size.x = WIDTH - 52
	_inspect.add_theme_font_size_override("normal_font_size", UiTheme.px(12))
	_inspect.add_theme_color_override("default_color", UiTheme.TEXT)
	box.add_child(_inspect)


## Exp 006 (R): Research — give each skill book, learn all, forget all, show
## skills (the game's `research` helper, src/research/game_research.gd).
func _build_research_section(box: VBoxContainer) -> void:
	var r: Node = game.get("research") if game != null else null
	if r == null or not r.has_method("dev_learn_all"):
		return
	box.add_child(UiTheme.make_section("Research"))
	var items := []
	for b in Research.books():
		items.append(["+ " + Items.name_of(b), func(): _say(r.dev_give_book(b))])
	items.append(["+ All books", func(): _say(r.dev_give_all_books())])
	items.append(["Show skills", func(): _say(r.dev_skills_text())])
	items.append(["Learn all", func(): _say(r.dev_learn_all())])
	items.append(["Forget all", func(): _say(r.dev_forget_all())])
	box.add_child(_grid(2, items))


func _small(text: String, cb: Callable) -> Button:
	var b := UiTheme.make_button(text)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 30
	b.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.FONT_SMALL + 1))
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
		# Exp 005 (V): all five levels, teleports to each, repair on every level
		["Build all 5 levels", _levels_call.bind("dev_build_all", [], "+1, +2, -1, -2 with stairs")],
		["Go: level -2", _levels_call.bind("dev_goto", [-2], "Lower basement")],
		["Go: basement (-1)", _levels_call.bind("dev_goto", [-1], "Basement")],
		["Go: ground floor (0)", _levels_call.bind("dev_goto", [0], "Ground floor")],
		["Go: upper floor (+1)", _levels_call.bind("dev_goto", [1], "First upper floor")],
		["Go: level +2", _levels_call.bind("dev_goto", [2], "Second upper floor")],
		["Repair all levels", _levels_call.bind("dev_repair_levels", [], "Every level repaired")],
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


# --- Exp 005 (F): furniture and storage (methods on src/home/game_storage.gd) --------------

func _build_furniture_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Furniture"))
	box.add_child(_grid(2, [["Furniture kit", _storage_call.bind("dev_furniture_kit")],
		["Storage items", _storage_call.bind("dev_storage_items")],
		["Show containers", _storage_call.bind("dev_containers_text")]]))


func _storage_call(method: String) -> void:
	var h = game.get("storage") if game != null and is_instance_valid(game) else null
	if not (h is Object and is_instance_valid(h) and h.has_method(method)):
		_say("The game has no storage.%s()" % method, true)
		return
	_say(str(h.call(method)))


# --- Exp 005 (A): audio (the inbox, a sound player, ambience layers; src/audio/game_audio.gd) ---

var _audio_text: RichTextLabel
var _audio_pick: OptionButton
var _audio_inbox_details := false       ## Exp 012 (A): the full mapping list is shown on demand


func _build_audio_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Audio"))
	_audio_pick = OptionButton.new()
	_audio_pick.name = "AudioPick"
	_audio_pick.focus_mode = Control.FOCUS_NONE
	_audio_pick.fit_to_longest_item = false
	_audio_pick.clip_text = true
	_audio_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_audio_pick.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.FONT_SMALL + 1))
	for n in Sfx.all_names():
		var src := Sfx.source_of(n)
		_audio_pick.add_item("%s  (%s)" % [n, src if src != "" else "no file"])
		_audio_pick.set_item_metadata(_audio_pick.item_count - 1, n)
	box.add_child(_audio_pick)
	box.add_child(_grid(2, [["Play sound", audio_play_picked], ["Stop voice / music", audio_stop],
		["Outdoor layer", audio_call.bind("dev_toggle_layer", ["outdoor"])], ["Indoor layer", audio_call.bind("dev_toggle_layer", ["indoor"])],
		["Fireplace layer", audio_call.bind("dev_toggle_layer", ["fireplace"])], ["Details layer", audio_call.bind("dev_toggle_layer", ["details"])],
		["Threat layer", audio_call.bind("dev_toggle_layer", ["threat"])], ["Owl / wolf / creak", audio_details],
	]))
	_audio_text = RichTextLabel.new()
	_audio_text.name = "AudioInbox"
	_audio_text.bbcode_enabled = true
	_audio_text.fit_content = true
	_audio_text.scroll_active = false
	_audio_text.selection_enabled = true
	_audio_text.focus_mode = Control.FOCUS_NONE
	_audio_text.custom_minimum_size.x = WIDTH - 52
	_audio_text.add_theme_font_size_override("normal_font_size", UiTheme.px(11))
	_audio_text.add_theme_color_override("default_color", UiTheme.TEXT)
	box.add_child(_audio_text)
	_audio_refresh()


## The game's audio status plus the inbox: mapped files and unknown ones.
func _audio_refresh() -> void:
	if _audio_text == null:
		return
	var a = game.get("audio") if game != null and is_instance_valid(game) else null
	var head: String = a.dev_status() if a is Object and is_instance_valid(a) and a.has_method("dev_status") else ""
	var c := AudioInbox.counts()      # Exp 012 (A): counts first, the full list on demand
	var inbox := "[b]Audio inbox[/b]  %d files → %d sounds · %d unknown · %d story-only (held back)" % [
		c["files"], c["names"], c["unknown"], c["reserved"]]
	_audio_text.text = (head + "\n" if head != "" else "") + inbox + ("\n" + AudioInbox.report_text() if _audio_inbox_details else "")


## Plays the sound chosen in the list.
func audio_play_picked() -> void:
	if _audio_pick == null or _audio_pick.selected < 0:
		return
	audio_call("dev_play", [str(_audio_pick.get_item_metadata(_audio_pick.selected))])


func audio_stop() -> void:
	Voice.stop()
	Sfx.music("")
	_say("Voice and music stopped")
	_audio_refresh()


## One owl, one wolf and one creak now (each where it would happen).
func audio_details() -> void:
	var amb = game.get("ambience") if game != null and is_instance_valid(game) else null
	if not (amb is Ambience):
		_say("No ambience.", true)
		return
	var played := PackedStringArray()
	for id in ["owl", "wolf", "creak"]:
		if amb.play_detail(id):
			played.append(id)
	_say("Played: " + (", ".join(played) if not played.is_empty() else "nothing (no recordings)"))
	_audio_refresh()


func audio_call(method: String, args: Array) -> void:
	var a = game.get("audio") if game != null and is_instance_valid(game) else null
	if not (a is Object and is_instance_valid(a) and a.has_method(method)):
		_say("The game has no audio.%s()" % method, true)
		return
	_say(str(a.callv(method, args)))
	_audio_refresh()


# --- Exp 005 (C): comfort and mood (methods on src/home/game_comfort.gd) ----------------

func _build_comfort_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Comfort & mood"))
	box.add_child(_grid(3, [["Show comfort", _comfort_call.bind("dev_show", [])], ["Recompute", _comfort_call.bind("dev_recompute", [])],
		["Home panel", _comfort_home_panel],
		["Mood low", _comfort_call.bind("dev_mood", ["low"])], ["Mood normal", _comfort_call.bind("dev_mood", ["normal"])],
		["Mood high", _comfort_call.bind("dev_mood", ["high"])]]))


func _comfort_call(method: String, args: Array) -> void:
	var h = game.get("comfort") if game != null and is_instance_valid(game) else null
	if not (h is Object and is_instance_valid(h) and h.has_method(method)):
		_say("The game has no comfort.%s()" % method, true)
		return
	_say(str(h.callv(method, args)))


func _comfort_home_panel() -> void:
	var h = game.get("comfort") if game != null and is_instance_valid(game) else null
	if not (h is Object and is_instance_valid(h) and h.has_method("dev_open_panel")):
		_say("No Home panel here.", true)
		return
	set_open(false)
	_say(str(h.call("dev_open_panel")))


# --- Exp 006 (B): House & balance (methods on src/home/game_balance.gd) ---------------------

func _build_balance_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("House & balance"))
	var rows := [["Aurora: old / subtle", _balance_call.bind("dev_aurora_preview", [])],
		["Remove window here", _balance_call.bind("dev_remove_window", [])],
		["TV / radio on/off", _balance_call.bind("dev_toggle_media", [])], ["Place a radio", _balance_call.bind("dev_place_radio", [])],
		["Foundation kit", _balance_call.bind("dev_foundation_kit", [])], ["Fill a chest", _balance_call.bind("dev_fill_chest", [])],
		["Show supply", _balance_call.bind("dev_supply_text", [])]]
	for k in EnemyDefs.KINDS:
		rows.append(["Spawn %s" % k, _balance_call.bind("dev_spawn", [k])])
	box.add_child(_grid(2, rows))


func _balance_call(method: String, args: Array) -> void:
	var h = game.get("balance") if game != null and is_instance_valid(game) else null
	if not (h is Object and is_instance_valid(h) and h.has_method(method)):
		_say("The game has no balance.%s()" % method, true)
		return
	_say(str(h.callv(method, args)))
# --- Exp 006 (D): defences (trenches, moats, drawbridges, spikes; src/defense/game_defense.gd) ---

func _build_defense_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Defences"))
	box.add_child(_grid(2, [["Shovel, water, wood", _defense_call.bind("dev_defense_kit", "")],
		["Moat ring + bridge", _defense_call.bind("dev_moat_ring", "")],
		["Fill the moat", _defense_call.bind("dev_fill_moat", "")],
		["Raise / lower bridges", _defense_call.bind("dev_toggle_bridges", "")],
		["Psycho at the moat", _defense_call.bind("dev_spawn_at_moat", "psycho")],
		["Brute at the moat", _defense_call.bind("dev_spawn_at_moat", "brute")],
		["Defence info", _defense_call.bind("dev_defense_text", "")]]))


## Exp 007 (S): Security — components, the research, a sensor or a loaded
## turret where you stand, ammunition, the nearest sensor triggered, power.
func _build_security_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Security"))
	box.add_child(_grid(2, [["Components, iron, scrap", _security_call.bind("dev_give_components")],
		["Unlock security research", _security_call.bind("dev_unlock")],
		["Sensor here", _security_call.bind("dev_place_sensor")],
		["Turret here (handgun)", _security_call.bind("dev_place_turret")],
		["Supply ammo", _security_call.bind("dev_supply_ammo")],
		["Trigger nearest sensor", _security_call.bind("dev_trigger_nearest")],
		["Restore power", _security_call.bind("dev_restore_power")],
		["Security info", _security_call.bind("dev_info")]]))


func _security_call(method: String) -> void:
	var h = game.get("security") if game != null and is_instance_valid(game) else null
	if not (h is Object and is_instance_valid(h) and h.has_method(method)):
		_say("The game has no security.", true)
		return
	_say(str(h.call(method)))


## Exp 007 (P): POI — at a destination (the game's `poi` helper,
## src/poi/game_poi.gd): restore its loot, a straggler, reveal containers,
## the visit's state. Travel buttons are agent T's.
func _build_poi_section(box: VBoxContainer) -> void:
	var p: Variant = game.get("poi") if game != null else null
	if not (p is Object and is_instance_valid(p) and p.has_method("dev_state_text")):
		return
	box.add_child(UiTheme.make_section("POI"))
	box.add_child(_grid(2, [["Restore this POI's loot", _poi_call.bind("dev_restore_loot")],
		["Spawn a straggler here", _poi_call.bind("dev_spawn_straggler")],
		["Reveal containers", _poi_call.bind("dev_reveal")],
		["POI state", _poi_call.bind("dev_state_text")]]))


## Exp 012 (L): looting, POIs and travel (src/travel/dev_looting.gd).
func _build_e12_l_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Looting & routes"))
	box.add_child(_grid(3, [["Route debug", func(): _say(DevLooting.route_text(game))],
		["Mark POI 80 % searched", func(): _say(DevLooting.mark_mostly(game))],
		["Fill pack / supplies", func(): _say(DevLooting.fill_pack(game))]]))


func _poi_call(method: String) -> void:
	var p: Variant = game.get("poi") if game != null and is_instance_valid(game) else null
	if not (p is Object and is_instance_valid(p) and p.has_method(method)):
		_say("Not at a POI.", true)
		return
	_say(str(p.call(method)))


func _defense_call(method: String, arg: String) -> void:
	var h = game.get("defense") if game != null and is_instance_valid(game) else null
	if not (h is Object and is_instance_valid(h) and h.has_method(method)):
		_say("The game has no defences.%s()" % method, true)
		return
	_say(str(h.call(method, arg) if arg != "" else h.call(method)))


# --- Exp 007 (N): noise, calm stragglers, room visibility ---------------------------------

func _build_noise_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Noise & visibility"))
	box.add_child(_grid(3, [["Noise: low", _noise_call.bind("noise", "dev_sample", "low")],
		["Noise: high", _noise_call.bind("noise", "dev_sample", "high")],
		["Noise: extreme", _noise_call.bind("noise", "dev_sample", "extreme")],
		["Last noises", _noise_call.bind("noise", "dev_log_text", "")],
		["Calm straggler", _noise_call.bind("noise", "dev_spawn_calm", "psycho")],
		["Calm runner", _noise_call.bind("noise", "dev_spawn_calm", "runner")],
		["Room boundaries", _noise_call.bind("visibility", "dev_toggle_bounds", "")],
		["Visibility diagnostics", _noise_call.bind("visibility", "dev_toggle_diagnostics", "")],
		["Reveal all", _noise_call.bind("visibility", "dev_toggle_reveal", "")]]))


func _noise_call(helper: String, method: String, arg: String) -> void:
	var h = game.get(helper) if game != null and is_instance_valid(game) else null
	if not (h is Object and is_instance_valid(h) and h.has_method(method)):
		_say("The game has no %s.%s()" % [helper, method], true)
		return
	_say(str(h.call(method, arg) if arg != "" else h.call(method)))


# --- Exp 007 (O): the house overview and observation holes (src/overview/, src/holes/) -------

func _build_overview_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Overview & holes"))
	box.add_child(_grid(2, [["Open the overview", _overview_call.bind("overview", "dev_open")],
		["Give a drill", _overview_call.bind("holes", "dev_give_drill")],
		["Hole in the nearest wall", _overview_call.bind("holes", "dev_hole_here")],
		["List holes", _overview_call.bind("holes", "dev_list_holes")]]))


func _overview_call(helper: String, method: String) -> void:
	var h = game.get(helper) if game != null and is_instance_valid(game) else null
	if not (h is Object and is_instance_valid(h) and h.has_method(method)):
		_say("The game has no %s.%s()" % [helper, method], true)
		return
	_say(str(h.call(method)))


# --- Exp 007 (T): travel (methods on src/travel/travel_flow.gd) ------------------------

var _travel_place: OptionButton


func _build_travel_section(box: VBoxContainer) -> void:
	var t: Variant = game.get("travel") if game != null else null
	if not (t is Object) or not t.has_method("dev_travel_to"):
		return
	box.add_child(UiTheme.make_section("Travel"))
	var items := []
	for id in ["forest", "convenience", "library"]:
		items.append(["Go: " + RegionLocations.name_of(id), _travel_call.bind("dev_travel_to", [id], "Off to " + RegionLocations.name_of(id))])
	items.append(["Return home", _travel_call.bind("dev_return_home", [], "Home")])
	box.add_child(_grid(2, items))
	_travel_place = OptionButton.new()
	_travel_place.name = "TravelPlace"
	_travel_place.focus_mode = Control.FOCUS_NONE
	_travel_place.fit_to_longest_item = false
	_travel_place.clip_text = true
	_travel_place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_travel_place.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.FONT_SMALL + 1))
	for id in RegionLocations.ids():
		_travel_place.add_item(RegionLocations.name_of(id))
		_travel_place.set_item_metadata(_travel_place.item_count - 1, id)
	box.add_child(_travel_place)
	box.add_child(_grid(2, [["Go to this place", _travel_to_chosen], ["+3 fuel", _travel_call.bind("dev_give_fuel", [], "")],
		["Repair car", _travel_call.bind("dev_repair_car", [], "")], ["Skip travel anim", _travel_call.bind("dev_toggle_skip", [], "")]]))


func _travel_to_chosen() -> void:
	if _travel_place == null or _travel_place.selected < 0:
		return
	var id := str(_travel_place.get_item_metadata(_travel_place.selected))
	_travel_call("dev_travel_to", [id], "Off to " + RegionLocations.name_of(id))


## Travel calls may wait for a scene change: the status says what was asked.
func _travel_call(method: String, args: Array, said: String) -> void:
	var t: Variant = game.get("travel") if game != null and is_instance_valid(game) else null
	if not (t is Object and is_instance_valid(t) and t.has_method(method)):
		_say("The game has no travel.%s()" % method, true)
		return
	var r: Variant = t.callv(method, args)
	_say(said if said != "" or typeof(r) != TYPE_STRING else str(r))


# --- Exp 009 (D): the POI generator (actions in src/poigen/dev_poigen.gd) ------------------

## Today's places and the next day, a site's setup, a generated test site
## by archetype (instant travel), dormant psychos (P), the stash (G), the
## layout's diagnostics, home.
func _build_poigen_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("POI generator"))
	var pick := func(nm: String, items: Array) -> OptionButton:
		var ob := OptionButton.new()
		ob.name = nm
		ob.focus_mode = Control.FOCUS_NONE
		ob.fit_to_longest_item = false
		ob.clip_text = true
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.FONT_SMALL + 1))
		for it in items:
			ob.add_item(str(it[1]))
			ob.set_item_metadata(ob.item_count - 1, it[0])
		box.add_child(ob)
		return ob
	var meta := func(ob: OptionButton) -> String:
		return str(ob.get_item_metadata(ob.selected)) if ob.selected >= 0 else ""
	box.add_child(_grid(2, [["Today's places", func(): _say(DevPoigen.today_text(game))],
		["Next day (00:00)", func(): _say(DevPoigen.next_day(game))]]))
	var sites: OptionButton = pick.call("PoigenSite", ExpeditionData.ORDER.map(func(id): return [id, RegionLocations.name_of(id)]))
	box.add_child(_grid(1, [["Inspect setup", func(): _say(DevPoigen.inspect(game, meta.call(sites)))]]))
	var arch: OptionButton = pick.call("PoigenArchetype", DailySites.test_archetypes().map(func(a): return [a, str(a).replace("_", " ")]))
	box.add_child(_grid(1, [["Generate test site", func(): _say(DevPoigen.generate(game, meta.call(arch)))]]))
	var beh: OptionButton = pick.call("PoigenBehaviour", DevPoigen.BEHAVIOURS.map(func(b): return [b, "behaviour: " + b]))
	box.add_child(_grid(2, [["Dormant psycho", func(): _say(DevPoigen.spawn_dormant(game, meta.call(beh)))],
		["Force behaviour", func(): _say(DevPoigen.force_behaviour(game, meta.call(beh)))],
		["Reveal stash", func(): _say(DevPoigen.reveal_stash(game))],
		["Diagnostics", func(): _say(DevPoigen.diagnostics(game))],
		["Return home (POI gen)", func(): _say(DevPoigen.return_home(game))]]))


# --- Exp 010 (C): the character -------------------------------------------------------------

## Original figure / experimental Eli (live, saved in the settings), Eli's
## next look, and the character showroom over the game (Esc closes it).
func _build_character_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Character"))
	box.add_child(_grid(2, [["Experimental Eli", func(): _set_character("eli")],
		["Original character", func(): _set_character("original")],
		["Next Eli look", func():
			GameSettings.set_value("eli_variant", (int(GameSettings.get_value("eli_variant")) + 1) % EliSculpt.variant_count())
			GameSettings.save_settings()
			_say("Eli: " + EliSculpt.variant_name(int(GameSettings.get_value("eli_variant"))))],
		["Character showroom", func():
			set_open(false)
			EliShowroom.open_overlay(get_tree())]]))


## Exp 011: the Architect's figure (an internal name; developer tools only).
## Exp 012 (A): its own labelled section in the Enemies tab, never a spawn.
func _build_internal_figure_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Internal (development only)", "-"))
	box.add_child(_grid(2, [["Show Architect (internal)", func(): _show_architect()],
		["Remove Architect", func():
			_say("Architect figure removed" if ArchitectFigure.remove(game) else "No Architect figure here")]]))
	box.add_child(UiTheme.make_caption("A silent, non-hostile preview figure. Not an enemy, never spawned, not saved.", WIDTH - 52, UiTheme.TEXT_FAINT))


## Exp 011: a non-hostile preview figure near Eli (not an enemy, not saved).
func _show_architect() -> void:
	var p: Variant = game.get("player") if game != null and is_instance_valid(game) else null
	if not (p is Node3D):
		_say("No player here", true)
		return
	var f := ArchitectFigure.show_near(game, p as Node3D)
	_say("Architect (internal) beside Eli: he turns, then observes" if f != null else "Could not place the figure", f == null)


func _set_character(which: String) -> void:
	GameSettings.set_value("character", which)
	GameSettings.save_settings()
	_say("Character: " + ("experimental Eli (%s)" % EliSculpt.variant_name(int(GameSettings.get_value("eli_variant"))) if which == "eli" else "original"))


# --- Exp 012 (A): the Audio tab's generic part (what plays now, buses, the inbox) -------

const NOW_LINES := 14
var _now_text: RichTextLabel


func _build_audio_now_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Playing now"))
	box.add_child(_grid(3, [["Stop story audio", func():
			_say("Story audio stopped (%d players)" % StoryAudioGuard.stop_all(get_tree()))
			_audio_now_refresh()],
		["Inbox details", func():
			_audio_inbox_details = not _audio_inbox_details
			_audio_refresh()],
		["Refresh", func():
			AudioInbox.scan(true)
			_audio_refresh()
			_audio_now_refresh()]]))
	_now_text = _text_block("AudioNow", 11)
	box.add_child(_now_text)
	_audio_now_refresh()


## A small read-only text block for the live pages.
func _text_block(node_name: String, size: int) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.name = node_name
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.selection_enabled = true
	t.focus_mode = Control.FOCUS_NONE
	t.custom_minimum_size.x = WIDTH - 52
	t.add_theme_font_size_override("normal_font_size", UiTheme.px(size))
	t.add_theme_color_override("default_color", UiTheme.TEXT)
	return t


func _audio_now_refresh() -> void:
	if _now_text == null or not is_inside_tree():
		return
	_now_text.text = audio_now_text()


## Every audio player playing now (file, bus, level; story ones marked), the
## buses, Sfx's counters, the voices and the inbox's counts.
func audio_now_text() -> String:
	var dim := UiTheme.TEXT_DIM.to_html(false)
	var lines := PackedStringArray()
	var players := []
	if is_inside_tree():
		_collect_players(get_tree().root, players, false)
	var rows := PackedStringArray()
	for e in players:
		var p: Node = e[0]
		var s: AudioStream = p.get("stream")
		var path := AudioInbox.path_of_stream(s)
		if path == "" and s != null:
			path = s.resource_path
		var label := path.get_file().get_basename() if path != "" else ("(%s)" % s.get_class() if s != null else "(none)")
		rows.append("%s%s  [color=#%s]%s · %+.0f dB%s[/color]" % ["[color=#e0a060]story[/color] " if e[1] else "", label, dim,
			str(p.get("bus")), float(p.get("volume_db")), " · 3D" if p is AudioStreamPlayer3D else ""])
	lines.append("[b]Players[/b] %d playing" % players.size())
	for i in mini(rows.size(), NOW_LINES):
		lines.append("  " + rows[i])
	if rows.size() > NOW_LINES:
		lines.append("  [color=#%s]+%d more[/color]" % [dim, rows.size() - NOW_LINES])
	var buses := PackedStringArray()
	for i in AudioServer.bus_count:
		var peak := maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0))
		buses.append("%s %+.0f%s%s" % [AudioServer.get_bus_name(i), AudioServer.get_bus_volume_db(i),
			" muted" if AudioServer.is_bus_mute(i) else "", " ▮" if peak > -60.0 else ""])
	lines.append("[b]Buses[/b] " + " · ".join(buses))
	lines.append("[b]Sfx[/b] played %d · skipped %d · stolen %d · music %s" % [int(Sfx.stats["played"]), int(Sfx.stats["skipped"]),
		int(Sfx.stats["stolen"]), Sfx.current_music() if Sfx.current_music() != "" else "none"])
	lines.append("[b]Voices[/b] Eli: %s · psycho voices %d (started %d, held %d) · story players %d" % [
		Voice.last_line if Voice.last_line != "" else "none yet", PsychoVoice.active(), PsychoVoice.started, PsychoVoice.refused,
		StoryAudioGuard.playing_count(get_tree() if is_inside_tree() else null)])
	var c := AudioInbox.counts()
	lines.append("[b]Inbox[/b] %d files → %d sounds · %d unknown · %d story-only · refused at play %d" % [
		c["files"], c["names"], c["unknown"], c["reserved"], AudioInbox.refused])
	return "\n".join(lines)


## [player, is_story] for every playing audio player under `n`.
func _collect_players(n: Node, out: Array, story: bool) -> void:
	var st := story or n.is_in_group(StoryAudioGuard.GROUP)
	if (n is AudioStreamPlayer or n is AudioStreamPlayer3D or n is AudioStreamPlayer2D) and n.get("playing"):
		out.append([n, st])
	for c in n.get_children():
		_collect_players(c, out, st)


# --- Exp 012 (A): the Debug tab (performance, render info, errors and status) ----------

const FRAME_WINDOW := 3.0                ## s of frame times for avg / max
var _frames: Array = []                  ## [ticks_usec, frame_ms]
var _frame_last := 0
var _perf_text: RichTextLabel
var _err_text: RichTextLabel
static var _errors: DevErrorLog


func _build_debug_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Performance"))
	_perf_text = _text_block("Performance", 12)
	box.add_child(_perf_text)
	box.add_child(_grid(2, [["FPS overlay", _toggle_fps_overlay], ["Copy stats", func():
			DisplayServer.clipboard_set(debug_text().replace("[b]", "").replace("[/b]", ""))
			_say("Stats copied")],
		["Save now", _debug_game_call.bind("debug_save", "Saved")], ["Reload save", _debug_game_call.bind("debug_reload", "Reloading from the save")]]))
	box.add_child(UiTheme.make_section("Errors & status"))
	_err_text = _text_block("Errors", 11)
	box.add_child(_err_text)
	box.add_child(_grid(1, [["Clear errors", func():
			if _errors != null:
				_errors.clear()
			_debug_refresh()]]))
	_build_inspect_section(box)
	if _errors == null:
		_errors = DevErrorLog.new()
		OS.add_logger(_errors)
	_debug_refresh()


## Exp 012: the lead wires this to the FPS overlay (agent C). Until then it
## asks the game (dev_toggle_fps_overlay) or toggles a node in the group
## "fps_overlay".
func _toggle_fps_overlay() -> void:
	for target in [game, game.get("hud") if game != null and is_instance_valid(game) else null]:
		if target is Object and is_instance_valid(target) and target.has_method("dev_toggle_fps_overlay"):
			_say(str(target.call("dev_toggle_fps_overlay")))
			return
	var nodes: Array = get_tree().get_nodes_in_group("fps_overlay") if is_inside_tree() else []
	if nodes.is_empty():
		_say("No FPS overlay in this build", true)
		return
	var on := not bool(nodes[0].get("visible"))
	for n in nodes:
		n.set("visible", on)
	_say("FPS overlay " + ("on" if on else "off"))


func _debug_game_call(method: String, said: String) -> void:
	if game == null or not is_instance_valid(game) or not game.has_method(method):
		_say("The game has no %s()" % method, true)
		return
	var r: Variant = game.call(method)
	_say(str(r) if typeof(r) == TYPE_STRING and str(r) != "" else said)


func _note_frame() -> void:
	var now := Time.get_ticks_usec()
	if _frame_last > 0:
		_frames.append([now, (now - _frame_last) / 1000.0])
	_frame_last = now
	while not _frames.is_empty() and now - int(_frames[0][0]) > int(FRAME_WINDOW * 1e6):
		_frames.pop_front()


## {"avg", "max"} frame time in ms over the last FRAME_WINDOW seconds.
func frame_stats() -> Dictionary:
	if _frames.is_empty():
		return {"avg": 0.0, "max": 0.0}
	var total := 0.0
	var top := 0.0
	for f in _frames:
		total += float(f[1])
		top = maxf(top, float(f[1]))
	return {"avg": total / _frames.size(), "max": top}


func debug_text() -> String:
	var fs := frame_stats()
	var mb := func(bytes: float) -> String: return "%.0f MB" % (bytes / 1048576.0)
	var rs := RenderingServer
	var lines := PackedStringArray()
	lines.append("[b]%d FPS[/b] · frame %.1f ms avg · %.1f ms max (last %ds) · process %.1f ms · physics %.1f ms" % [
		Engine.get_frames_per_second(), fs["avg"], fs["max"], int(FRAME_WINDOW),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	lines.append("draw calls %d · primitives %d · objects %d" % [
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	lines.append("video memory %s (textures %s, buffers %s) · static memory %s" % [
		mb.call(float(rs.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))),
		mb.call(float(rs.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))),
		mb.call(float(rs.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED))),
		mb.call(Performance.get_monitor(Performance.MEMORY_STATIC))])
	lines.append("nodes %d · orphans %d · objects %d · time ×%s · %s" % [
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)), str(Engine.time_scale), rs.get_video_adapter_name()])
	return "\n".join(lines)


func _debug_refresh() -> void:
	if _perf_text != null:
		_perf_text.text = debug_text()
	if _err_text != null:
		var errs := _errors.lines() if _errors != null else PackedStringArray()
		var t := "[b]Status[/b] %s" % (last_status if last_status != "" else "—")
		t += "\n[b]Errors and warnings[/b] %s" % ("none since start" if errs.is_empty() else "(%d, newest first)" % (_errors.total if _errors != null else 0))
		for i in range(errs.size() - 1, -1, -1):
			t += "\n  " + errs[i]
		_err_text.text = t


## The last errors and warnings of this session (any thread), for the Debug tab.
class DevErrorLog extends Logger:
	const KEEP := 10
	var total := 0
	var _lock := Mutex.new()
	var _lines := PackedStringArray()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array) -> void:
		var kind := "warning" if error_type == Logger.ERROR_TYPE_WARNING else "error"
		var color := "e0a060" if kind == "warning" else "e06050"
		var text := (rationale if rationale != "" else code).replace("[", "(").replace("]", ")")
		_lock.lock()
		total += 1
		_lines.append("[color=#%s]%s[/color] %s [color=#777777](%s:%d %s)[/color]" % [color, kind, text.left(160), file.get_file(), line, function])
		if _lines.size() > KEEP:
			_lines.remove_at(0)
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func lines() -> PackedStringArray:
		_lock.lock()
		var out := _lines.duplicate()
		_lock.unlock()
		return out

	func clear() -> void:
		_lock.lock()
		_lines.clear()
		total = 0
		_lock.unlock()


# --- Exp 012 (E): Enemies (names, reactions, corpses; src/ai/game_corpses.gd) ---------------

func _build_e12_e_section(box: VBoxContainer) -> void:
	var h: Variant = game.get("corpses") if game != null else null
	if not (h is Object and is_instance_valid(h) and h.has_method("dev_list_text")):
		return
	box.add_child(UiTheme.make_section("Enemies: reactions and bodies"))
	box.add_child(_grid(2, [["Psycho near (calm)", _e12_e_call.bind("dev_spawn_near", ["psycho"])],
		["Runner near (calm)", _e12_e_call.bind("dev_spawn_near", ["runner"])],
		["Brute near (calm)", _e12_e_call.bind("dev_spawn_near", ["brute"])],
		["Bomber near (calm)", _e12_e_call.bind("dev_spawn_near", ["bomber"])],
		["Kill nearest (leave corpse)", _e12_e_call.bind("dev_kill_nearest", [])],
		["Nearest one screams", _e12_e_call.bind("dev_shout", [])],
		["List living enemies", _e12_e_call.bind("dev_list_text", [])],
		["Toggle perception debug", _e12_e_call.bind("dev_toggle_debug", [])],
		["Clear looted corpses", _e12_e_call.bind("dev_clear_looted", [])]]))


func _e12_e_call(method: String, args: Array) -> void:
	var h: Variant = game.get("corpses") if game != null and is_instance_valid(game) else null
	if not (h is Object and is_instance_valid(h) and h.has_method(method)):
		_say("The game has no corpse helper.", true)
		return
	_say(str(h.callv(method, args)))

# --- Exp 012 (S): the story (Chapter One) and its sounds (src/story/story_dev.gd) ---------

func _build_e12_s_section(box: VBoxContainer) -> void:
	StoryDev.build_story(self, box)


func _build_e12_s_audio_section(box: VBoxContainer) -> void:
	StoryDev.build_audio(self, box)


# --- Exp 012 (G): hordes and sieges (src/siege/siege_director.gd, `game.siege`) ---

func _build_e12_g_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_section("Hordes & sieges"))
	box.add_child(_grid(2, [["Invasion (whole group)", _siege_call.bind("dev_invasion")],
		["Spawn horde", _siege_call.bind("dev_horde")],
		["Coordinated siege now", _siege_call.bind("dev_siege")],
		["Siege tactics", _siege_call.bind("dev_text")],
		["Tactic markers", _siege_call.bind("dev_toggle_markers")],
		["Enemy barricade here", _siege_call.bind("dev_barricade_nearest")],
		["Clear enemy barricades", _siege_call.bind("dev_clear_barricades")]]))


func _siege_call(method: String) -> void:
	var h = game.get("siege") if game != null and is_instance_valid(game) else null
	if not (h is Object and is_instance_valid(h) and h.has_method(method)):
		_say("Sieges only happen at home.", true)
		return
	_say(str(h.call(method)))


# --- Exp 012 (V): the fog of war (src/visibility/fog_of_war.gd, game.visibility.fow) ------------

func _build_e12_v_section(box: VBoxContainer) -> void:
	var vis = game.get("visibility") if game != null else null
	if vis == null or vis.get("fow") == null:
		return
	var fow: FogOfWar = vis.fow
	box.add_child(UiTheme.make_section("Fog of war & vision"))
	box.add_child(_grid(2, [["Fog of war on/off", func(): _say(fow.dev_toggle())],
		["Reveal all (dev)", func(): _say(fow.dev_reveal_all())],
		["Reset discovered", func(): _say(fow.dev_reset())],
		["Vision debug overlay", func(): _say(fow.dev_toggle_debug())],
		["Fog of war info", func(): _say(fow.info())]]))
	var row := HBoxContainer.new()
	var lab := UiTheme.make_caption("Vision cone %d°" % int(fow.cone_deg), 150, UiTheme.TEXT)
	row.add_child(lab)
	var sl := HSlider.new()
	sl.name = "ConeSlider"
	sl.min_value = 60
	sl.max_value = 360
	sl.step = 10
	sl.value = fow.cone_deg
	sl.focus_mode = Control.FOCUS_NONE
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(v: float):
		fow.dev_set_cone(v)
		lab.text = "Vision cone %d°" % int(v))
	row.add_child(sl)
	box.add_child(row)
