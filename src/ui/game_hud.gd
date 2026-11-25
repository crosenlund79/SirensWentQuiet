class_name GameHud
extends CanvasLayer
## In-game HUD (SPEC §7.8). Owner: U. Small and legible over day and night.
##
## Top left: clock card (sun/moon glyph, "Day N · HH:MM", period and
## difficulty) with four stat bars, warning words and the construction
## resources (wood, stone, iron). Top centre: banner (invasions), an alert line
## (a bomber's fuse) and stacked toasts. Top right: the CHEATS ACTIVE badge.
## Bottom centre: interaction prompt ("[E] Sleep" becomes a key chip). Bottom
## right: the weapon in hand (name, magazine / capacity, reserve, a reload
## bar, the other weapon). Bottom left: controls hint and the F3 frame-rate
## line (off by default).
##
## API: setup(state), set_weapons(handler), set_prompt(text), toast(text, kind),
## set_banner(text), alert(text, seconds), set_mode("play" | "build" | "hidden"),
## flash_damage(), toggle_fps(), toggle_help(). The HUD handles F3
## (toggle_stats) and H/F1 (toggle_help) itself. In build mode the bottom
## centre stays clear for the build palette.

const TOAST_MAX := 4
const TOAST_LIFE := 3.2
const CHEAT_NAMES := {"invulnerable": "Invulnerable", "unlimited": "Unlimited resources"}
const HELP := [
	["W A S D", "Move"], ["LMB", "Shoot / use"], ["R", "Reload"], ["1-8 / Q", "Quick bar"], ["X", "Empty hands"],
	["Wheel", "Zoom"], ["E", "Interact"], ["I / Tab", "Inventory"], ["M", "Region map"],
	["B", "Build"], ["Esc", "Pause"], ["F10", "Developer"],
	["Shift", "Sprint"], ["Z / C", "Turn view"], ["V", "Roof on / off"],
	["PgUp / PgDn", "Level (build)"],      # Exp 005 (V)
]
const MATERIALS := [["wood", "Wood"], ["stone", "Stone"], ["iron", "Iron"]]

var state: GameState
var weapons: Node                       ## WeaponHandler (duck-typed: current()); null = read the state
var mode := "play"
var show_fps := false

var _root: Control
var _flash: TextureRect
var _status_card: PanelContainer
var _sun: UiIcon
var _moon: UiIcon
var _clock: Label
var _period: Label
var _bars := {}
var _warn_box: VBoxContainer
var _banner: PanelContainer
var _banner_label: Label
var _toasts: VBoxContainer
var _badge: PanelContainer
var _badge_list: Label
var _ammo_card: PanelContainer
var _ammo_icon: UiIcon
var _ammo_count: Label
var _ammo_cap: Label
var _ammo_note: Label
var _weapon_name: Label
var _weapon_other: Label
var _reload_bar: ProgressBar
var _materials: Label
var _alert: PanelContainer
var _alert_label: Label
var _alert_t := 0.0
var _prompt_card: PanelContainer
var _prompt_holder: HBoxContainer
var _bottom_left: VBoxContainer
var _help_hint: Control
var _help_card: PanelContainer
var _fps: Label

var _prompt_text := "~"
var _clock_key := ""
var _warn_key := "~"
var _cheat_key := "~"
var _ammo_key := "~"
var _mat_key := "~"
var _last_health := -1.0
var _flash_tween: Tween
var _mode_tween: Tween
var _banner_t := 0.0
var _pending := []
var _home_room: Label                   # Exp 005 (C): "Living room · Comfortable" (set_home_line)
var _home_mood: Label                   # Exp 005 (C): "Mood: Content"


func _init() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build()
	set_prompt("")
	set_mode(mode)
	_refresh(true)
	for t in _pending:
		toast(t[0], t[1])
	_pending.clear()


func setup(s: GameState) -> void:
	state = s
	_last_health = s.health if s != null else -1.0
	_clock_key = ""
	_warn_key = "~"
	_cheat_key = "~"
	_ammo_key = "~"
	_mat_key = "~"
	if _root != null:
		_refresh(true)


## The weapon runtime to read (WeaponHandler.current()); null reads the state.
func set_weapons(handler: Node) -> void:
	weapons = handler
	_ammo_key = "~"


# --- public API ---------------------------------------------------------------

func set_prompt(text: String) -> void:
	if text == _prompt_text or _prompt_holder == null:
		return
	_prompt_text = text
	for c in _prompt_holder.get_children():
		_prompt_holder.remove_child(c)
		c.queue_free()
	if text == "":
		_prompt_card.visible = false
		return
	var key := ""
	var body := text
	var m := RegEx.create_from_string("^\\[([^\\]]+)\\]\\s*(.*)$").search(text)
	if m != null:
		key = m.get_string(1)
		body = m.get_string(2)
	if key != "":
		_prompt_holder.add_child(UiTheme.make_key_chip(key))
	var l := UiTheme.make_hud_label(body, UiTheme.FONT_BODY + 1)
	l.name = "Text"
	_prompt_holder.add_child(l)
	_prompt_card.visible = mode == "play"


## Stacked toast; kind is info | good | warn | bad. A repeat of the newest
## toast refreshes it and counts (×2, ×3) instead of stacking.
func toast(text: String, kind := "info") -> void:
	if text == "":
		return
	if _toasts == null:
		_pending.append([text, kind])
		return
	var col: Color = UiTheme.KIND_COLORS.get(kind, UiTheme.TEXT)
	var n := _toasts.get_child_count()
	if n > 0:
		var last := _toasts.get_child(n - 1)
		if last.get_meta("text", "") == text and last.get_meta("kind", "") == kind and not last.get_meta("dying", false):
			var count: int = last.get_meta("count", 1) + 1
			last.set_meta("count", count)
			last.set_meta("life", _life_for(text))
			(last.get_node("Row/Text") as Label).text = "%s  ×%d" % [text, count]
			return
	while _toasts.get_child_count() >= TOAST_MAX:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var card := PanelContainer.new()
	var sb := UiTheme.card_style()
	sb.bg_color = Color(0.03, 0.032, 0.04, 0.74)
	sb.border_color = Color(col, 0.95)
	sb.set_border_width_all(0)
	sb.border_width_left = 3
	sb.corner_radius_top_left = 0
	sb.corner_radius_bottom_left = 0
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.set_meta("text", text)
	card.set_meta("kind", kind)
	card.set_meta("count", 1)
	card.set_meta("life", _life_for(text))
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var l := UiTheme.make_hud_label(text, UiTheme.FONT_BODY - 1, col if kind != "info" else UiTheme.TEXT)
	l.name = "Text"
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(l)
	card.modulate.a = 0.0
	_toasts.add_child(card)
	card.create_tween().tween_property(card, "modulate:a", 1.0, 0.15)


## Big line at the top centre (e.g. "They're coming"); "" hides it.
func set_banner(text: String) -> void:
	if _banner == null:
		return
	if text == "":
		_banner.visible = false
		_banner_label.text = ""
		return
	var was := _banner.visible and _banner_label.text != ""
	_banner_label.text = text.to_upper()
	_banner.visible = true
	if not was:
		_banner.modulate.a = 0.0
		_banner.create_tween().tween_property(_banner, "modulate:a", 1.0, 0.3)


## A pulsing warning line under the banner for `seconds` (a bomber's fuse);
## "" hides it at once.
func alert(text: String, seconds := 3.0) -> void:
	if _alert == null:
		return
	if text == "":
		_alert.visible = false
		_alert_t = 0.0
		return
	_alert_label.text = text.to_upper()
	_alert_t = maxf(seconds, 0.5)
	_alert.visible = true
	_alert.modulate.a = 1.0


## "play" (default), "build" (stats dimmed; prompt, ammo and hints hidden so
## the bottom centre is free for the build palette) or "hidden".
func set_mode(m: String) -> void:
	mode = m
	if _root == null:
		return
	_root.visible = m != "hidden"
	var build := m == "build"
	if _mode_tween != null and _mode_tween.is_valid():
		_mode_tween.kill()
	_mode_tween = create_tween().set_parallel(true)
	_mode_tween.tween_property(_status_card, "modulate:a", 0.55 if build else 1.0, 0.2)
	_prompt_card.visible = not build and _prompt_text != ""
	_ammo_card.visible = not build
	_help_hint.visible = not build
	if build:
		_help_card.visible = false


## A short red vignette pulse (the player was hurt).
func flash_damage(strength := 1.0) -> void:
	if _flash == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash.modulate.a = clampf(0.55 + 0.35 * strength, 0.0, 0.95)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func toggle_fps() -> void:
	show_fps = not show_fps
	_fps.visible = show_fps


func toggle_help() -> void:
	_help_card.visible = not _help_card.visible and mode == "play"


## Test access: the texts the HUD currently shows.
func debug_texts() -> Dictionary:
	var toasts := []
	for c in _toasts.get_children():
		toasts.append((c.get_node("Row/Text") as Label).text)
	var warns := []
	for c in _warn_box.get_children():
		var t := c.get_node_or_null("Text") as Label
		if t != null:
			warns.append(t.text)
	return {
		"clock": _clock.text, "period": _period.text, "night_glyph": _moon.modulate.a > 0.5,
		"ammo": _ammo_count.text, "ammo_note": _ammo_note.text, "ammo_cap": _ammo_cap.text,
		"weapon": _weapon_name.text, "weapon_other": _weapon_other.text, "reloading": _reload_bar.visible,
		"materials": _materials.text, "alert": _alert_label.text if _alert.visible else "",
		"prompt": _prompt_text, "prompt_visible": _prompt_card.visible,
		"banner": _banner_label.text if _banner.visible else "",
		"cheats_visible": _badge.visible, "cheats": _badge_list.text,
		"warnings": warns, "toasts": toasts, "fps_visible": _fps.visible,
		"bars": _bars.keys().map(func(k): return [k, (_bars[k] as UiStatBar).value]),
		"flash": _flash.modulate.a,
		"home_room": _home_room.text if _home_room != null else "",       # Exp 005 (C)
		"home_mood": _home_mood.text if _home_mood != null else "",
	}


## Exp 005 (C): the room and mood line under the materials, in the status card.
## `level`: the room's comfort level 0..4 (-1 outdoors); `band`: the mood band 0..4.
func set_home_line(room_text: String, level: int, mood_text: String, band: int) -> void:
	if _materials == null:
		return
	if _home_room == null:
		var col := _materials.get_parent()
		_home_room = UiTheme.make_hud_label("", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
		_home_room.name = "HomeRoom"
		col.add_child(_home_room)
		_home_mood = UiTheme.make_hud_label("", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
		_home_mood.name = "HomeMood"
		col.add_child(_home_mood)
	var tone := func(i: int) -> Color:
		return UiTheme.BAD if i == 0 else (UiTheme.WARN if i == 1 else (UiTheme.GOOD if i >= 3 else UiTheme.TEXT_DIM))
	_home_room.text = room_text
	_home_room.add_theme_color_override("font_color", tone.call(level) if level >= 0 else UiTheme.TEXT_DIM)
	_home_mood.text = mood_text
	_home_mood.add_theme_color_override("font_color", tone.call(band))


# --- input and update ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("toggle_stats"):
		toggle_fps()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_help"):
		toggle_help()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_tick_toasts(delta)
	if _banner != null and _banner.visible:
		_banner_t += delta
		var sb := _banner.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			sb.border_color.a = 0.45 + 0.35 * (0.5 + 0.5 * sin(_banner_t * 3.0))
	if show_fps and _fps != null:
		_fps.text = "%d fps" % Engine.get_frames_per_second()
	if _alert != null and _alert.visible:
		_alert_t -= delta
		_alert.modulate.a = 0.6 + 0.4 * (0.5 + 0.5 * sin(_alert_t * 14.0))
		if _alert_t <= 0.0:
			_alert.visible = false
	_refresh(false)


func _refresh(force: bool) -> void:
	if _root == null:
		return
	if state == null:
		_status_card.visible = false
		_ammo_card.visible = false
		_badge.visible = false
		return
	_status_card.visible = true
	_ammo_card.visible = mode != "build"
	# clock
	var key := "%d %s %s" % [state.day(), state.clock_text(), state.difficulty]
	var n := state.night_amount()
	if key != _clock_key or force:
		_clock_key = key
		_clock.text = UiTheme.day_time_text(state.day(), state.clock_text())
		_period.text = "%s · %s" % [period_name(state.minute_of_day()), Difficulty.name_of(state.difficulty)]
	_sun.modulate.a = 1.0 - n
	_moon.modulate.a = n
	# stats
	for k in _bars:
		(_bars[k] as UiStatBar).set_value(float(state.get(k)), force)
	if _last_health >= 0.0 and state.health < _last_health - 3.5:
		flash_damage(clampf((_last_health - state.health) / 20.0, 0.3, 1.0))
	_last_health = state.health
	# warnings
	var warns := warnings_for(state)
	var wkey := str(warns)
	if wkey != _warn_key or force:
		_warn_key = wkey
		_set_warnings(warns)
	# the weapon in hand
	_refresh_weapon(force)
	# construction resources
	var mats := PackedStringArray()
	for m in MATERIALS:
		mats.append("%s %d" % [m[1], state.inventory.count(m[0])])
	var mkey := " · ".join(mats)
	if mkey != _mat_key or force:
		_mat_key = mkey
		_materials.text = mkey
	# cheats
	var cheats := active_cheats(state)
	var ckey := ", ".join(cheats)
	if ckey != _cheat_key or force:
		_cheat_key = ckey
		_badge.visible = not cheats.is_empty()
		_badge_list.text = " · ".join(cheats)


## The weapon in hand: WeaponHandler.current() when set, else from the state.
func weapon_info() -> Dictionary:
	if weapons != null and is_instance_valid(weapons) and weapons.has_method("current"):
		return weapons.current()
	var id := state.active_weapon()
	var ammo_id := WeaponDefs.ammo_of(id)
	return {"id": id, "name": WeaponDefs.name_of(id), "loaded": state.magazine(id), "capacity": WeaponDefs.capacity(id),
		"reserve": state.reserve(id), "ammo": ammo_id, "ammo_name": Items.name_of(ammo_id) if ammo_id != "" else "",
		"reloading": false, "reload_progress": 0.0, "unlimited": bool(state.cheats.get("unlimited", false))}


func _refresh_weapon(force: bool) -> void:
	var w := weapon_info()
	var other := ""
	for slot in Equipment.WEAPON_SLOTS:
		var id := state.equipped(slot)
		if id != "" and id != str(w.get("id", "")):
			other = WeaponDefs.name_of(id)
	var reloading := bool(w.get("reloading", false))
	var akey := "%s %d %d %d %s %s %s %.2f" % [w.get("id", ""), int(w.get("loaded", 0)), int(w.get("capacity", 0)), int(w.get("reserve", 0)),
		w.get("unlimited", false), other, reloading, float(w.get("reload_progress", 0.0)) if reloading else 0.0]
	if akey == _ammo_key and not force:
		return
	_ammo_key = akey
	var loaded := int(w.get("loaded", 0))
	var reserve := int(w.get("reserve", 0))
	var unlimited := bool(w.get("unlimited", false))
	var has_weapon := str(w.get("id", "")) != ""
	_weapon_name.text = str(w.get("name", "")) if has_weapon else "Unarmed"
	_ammo_count.text = str(loaded)
	_ammo_cap.text = "/ %d" % int(w.get("capacity", 0)) if has_weapon else ""
	_weapon_other.text = ("Q  %s" % other) if other != "" else ""
	_weapon_other.visible = other != ""
	var col := UiTheme.TEXT
	var note := "%d spare %s" % [reserve, _spare_name(str(w.get("ammo", "")), reserve)]
	if unlimited:
		note = "unlimited"
		col = UiTheme.ACCENT
	elif not has_weapon:
		note = "no weapon"
		col = UiTheme.TEXT_DIM
	elif loaded <= 0 and reserve <= 0:
		col = UiTheme.BAD
		note = "out of ammo"
	elif reloading:
		note = "reloading"
		col = UiTheme.WARN
	elif loaded <= 0:
		col = UiTheme.WARN
		note = "empty · R reload"
	elif loaded <= 2:
		col = UiTheme.WARN
	_ammo_count.add_theme_color_override("font_color", col)
	_ammo_icon.color = col
	_ammo_note.text = note
	_ammo_note.add_theme_color_override("font_color", col if col != UiTheme.TEXT else UiTheme.TEXT_DIM)
	_reload_bar.visible = reloading
	_reload_bar.value = float(w.get("reload_progress", 0.0))


static func _spare_name(ammo_id: String, n: int) -> String:
	var word: String = {"ammo": "round", "shells": "shell"}.get(ammo_id, "round")
	return word if n == 1 else word + "s"


## Warning words derived from the stats (or GameState.warnings() when S adds
## it): [[text, kind], ...] with kind "warn" | "bad".
static func warnings_for(s: GameState) -> Array:
	var out := []
	if s.has_method("warnings"):
		var w = s.call("warnings")
		if typeof(w) == TYPE_ARRAY:
			for e in w:
				if typeof(e) == TYPE_DICTIONARY:
					out.append([str(e.get("text", "")), str(e.get("kind", "warn"))])
				elif typeof(e) == TYPE_ARRAY and e.size() >= 2:
					out.append([str(e[0]), str(e[1])])
				else:
					var t := str(e)
					out.append([t, "bad" if t in ["Dehydrated", "Starving", "Badly hurt", "Spent"] else "warn"])
			if s.invasion_due_soon():
				out.append(["Something is coming tonight.", "warn"])
			return out
	var lvl := SurvivalTuning.WARN_LEVEL
	if s.health <= lvl:
		out.append(["Badly hurt", "bad"])
	if s.hunger <= 0.0:
		out.append(["Starving", "bad"])
	elif s.hunger <= lvl:
		out.append(["Hungry", "warn"])
	if s.hydration <= 0.0:
		out.append(["Dehydrated", "bad"])
	elif s.hydration <= lvl:
		out.append(["Thirsty", "warn"])
	if s.energy <= 0.0:
		out.append(["Spent", "bad"])
	elif s.energy <= lvl:
		out.append(["Exhausted", "warn"])
	if s.invasion_due_soon():
		out.append(["Something is coming tonight.", "warn"])
	return out


static func active_cheats(s: GameState) -> Array:
	var out := []
	for k in s.cheats:
		if s.cheats[k]:
			out.append(CHEAT_NAMES.get(k, str(k).capitalize()))
	return out


static func period_name(minute: float) -> String:
	var h := minute / 60.0
	if h >= 21.0 or h < 5.0:
		return "Night"
	if h < 7.0:
		return "Dawn"
	if h < 12.0:
		return "Morning"
	if h < 17.0:
		return "Afternoon"
	if h < 19.5:
		return "Evening"
	return "Dusk"


func _set_warnings(warns: Array) -> void:
	for c in _warn_box.get_children():
		_warn_box.remove_child(c)
		c.queue_free()
	_warn_box.visible = not warns.is_empty()
	for w in warns:
		var col: Color = UiTheme.BAD if w[1] == "bad" else UiTheme.WARN
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := UiTheme.make_icon("warn", 13, col)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		var l := UiTheme.make_hud_label(w[0], UiTheme.FONT_SMALL + 1, col)
		l.name = "Text"
		row.add_child(l)
		_warn_box.add_child(row)


func _life_for(text: String) -> float:
	return TOAST_LIFE + text.length() / 40.0


func _tick_toasts(delta: float) -> void:
	if _toasts == null:
		return
	for c in _toasts.get_children():
		var life: float = c.get_meta("life", 0.0) - delta
		c.set_meta("life", life)
		if life <= 0.0 and not c.get_meta("dying", false):
			c.set_meta("dying", true)
			var tw := c.create_tween()
			tw.tween_property(c, "modulate:a", 0.0, 0.4)
			tw.tween_callback(c.queue_free)


# --- construction -------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.theme()
	add_child(_root)

	# damage vignette
	_flash = TextureRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flash.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.02, 0.02, 0.0))
	g.set_color(1, Color(0.6, 0.03, 0.02, 0.85))
	g.add_point(0.55, Color(0.55, 0.02, 0.02, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 0.5)
	gt.width = 256
	gt.height = 256
	_flash.texture = gt
	_flash.modulate.a = 0.0
	_root.add_child(_flash)

	# top left: clock and needs
	_status_card = UiTheme.make_card()
	_status_card.name = "Status"
	_status_card.position = Vector2(20, 18)
	_status_card.custom_minimum_size.x = 236
	_root.add_child(_status_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 9)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var glyph := Control.new()
	glyph.custom_minimum_size = Vector2(22, 22)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(glyph)
	_sun = UiTheme.make_icon("sun", 22, Color(1.0, 0.88, 0.62))
	_sun.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.add_child(_sun)
	_moon = UiTheme.make_icon("moon", 22, Color(0.8, 0.85, 0.98))
	_moon.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.add_child(_moon)
	var clock_col := VBoxContainer.new()
	clock_col.add_theme_constant_override("separation", -3)
	clock_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(clock_col)
	_clock = UiTheme.make_hud_label("", 20)
	_clock.name = "Clock"
	clock_col.add_child(_clock)
	_period = UiTheme.make_hud_label("", 12, UiTheme.TEXT_DIM)
	_period.add_theme_font_override("font", UiTheme.tracked_font(2))
	_period.uppercase = true
	clock_col.add_child(_period)
	col.add_child(UiTheme.make_spacer(3))
	for k in [["health", "health", "Health"], ["food", "hunger", "Food"], ["water", "hydration", "Water"], ["energy", "energy", "Energy"]]:
		var bar := UiTheme.make_stat_bar(k[0], k[2])
		bar.name = "Bar_" + k[1]
		bar.custom_minimum_size = Vector2(212, 17)
		col.add_child(bar)
		_bars[k[1]] = bar
	_warn_box = VBoxContainer.new()
	_warn_box.add_theme_constant_override("separation", 1)
	_warn_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warn_box.visible = false
	col.add_child(_warn_box)
	_materials = UiTheme.make_hud_label("", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	_materials.name = "Materials"
	col.add_child(_materials)

	# top centre: banner + toasts
	var top := VBoxContainer.new()
	top.name = "TopCentre"
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -330
	top.offset_right = 330
	top.offset_top = 20
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top)
	_banner = PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.1, 0.025, 0.02, 0.78)
	bsb.border_color = Color(UiTheme.BAD, 0.7)
	bsb.border_width_top = 1
	bsb.border_width_bottom = 1
	bsb.content_margin_left = 28
	bsb.content_margin_right = 28
	bsb.content_margin_top = 8
	bsb.content_margin_bottom = 8
	_banner.add_theme_stylebox_override("panel", bsb)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_banner.visible = false
	top.add_child(_banner)
	_banner_label = UiTheme.make_hud_label("", 17, Color(1.0, 0.86, 0.8))
	_banner_label.add_theme_font_override("font", UiTheme.tracked_font(4))
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_label)
	_alert = PanelContainer.new()
	_alert.name = "Alert"
	var asb := StyleBoxFlat.new()
	asb.bg_color = Color(0.16, 0.07, 0.01, 0.85)
	asb.border_color = Color(UiTheme.ACCENT, 0.95)
	asb.set_border_width_all(2)
	asb.set_corner_radius_all(3)
	asb.content_margin_left = 22
	asb.content_margin_right = 22
	asb.content_margin_top = 6
	asb.content_margin_bottom = 7
	_alert.add_theme_stylebox_override("panel", asb)
	_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_alert.visible = false
	top.add_child(_alert)
	var arow0 := HBoxContainer.new()
	arow0.add_theme_constant_override("separation", 9)
	arow0.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert.add_child(arow0)
	var aicon := UiTheme.make_icon("warn", 16, UiTheme.ACCENT)
	aicon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arow0.add_child(aicon)
	_alert_label = UiTheme.make_hud_label("", 16, Color(1.0, 0.82, 0.55))
	_alert_label.add_theme_font_override("font", UiTheme.tracked_font(3))
	arow0.add_child(_alert_label)
	_toasts = VBoxContainer.new()
	_toasts.name = "Toasts"
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_toasts)

	# top right: cheats badge
	_badge = PanelContainer.new()
	_badge.name = "Cheats"
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.16, 0.08, 0.02, 0.8)
	csb.border_color = Color(UiTheme.ACCENT, 0.85)
	csb.set_border_width_all(1)
	csb.set_corner_radius_all(3)
	csb.content_margin_left = 10
	csb.content_margin_right = 12
	csb.content_margin_top = 5
	csb.content_margin_bottom = 6
	_badge.add_theme_stylebox_override("panel", csb)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_badge.offset_right = -20
	_badge.offset_left = -20
	_badge.offset_top = 18
	_badge.visible = false
	_root.add_child(_badge)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 0)
	bcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_child(bcol)
	var bhead := HBoxContainer.new()
	bhead.add_theme_constant_override("separation", 6)
	bhead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bcol.add_child(bhead)
	var star := UiTheme.make_icon("cheat", 12, UiTheme.ACCENT)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bhead.add_child(star)
	var btitle := UiTheme.make_hud_label("CHEATS ACTIVE", 12, UiTheme.ACCENT)
	btitle.add_theme_font_override("font", UiTheme.tracked_font(2))
	bhead.add_child(btitle)
	_badge_list = UiTheme.make_hud_label("", UiTheme.FONT_SMALL, UiTheme.TEXT)
	bcol.add_child(_badge_list)

	# bottom right: ammo
	_ammo_card = UiTheme.make_card()
	_ammo_card.name = "Ammo"
	_ammo_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ammo_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ammo_card.offset_left = -22
	_ammo_card.offset_right = -22
	_ammo_card.offset_top = -20
	_ammo_card.offset_bottom = -20
	_root.add_child(_ammo_card)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 9)
	arow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_card.add_child(arow)
	_ammo_icon = UiTheme.make_icon("ammo", 22)
	_ammo_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arow.add_child(_ammo_icon)
	var wcol := VBoxContainer.new()
	wcol.add_theme_constant_override("separation", 0)
	wcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arow.add_child(wcol)
	var whead := HBoxContainer.new()
	whead.add_theme_constant_override("separation", 12)
	whead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wcol.add_child(whead)
	_weapon_name = UiTheme.make_hud_label("", 12, UiTheme.TEXT)
	_weapon_name.name = "WeaponName"
	_weapon_name.add_theme_font_override("font", UiTheme.tracked_font(2))
	_weapon_name.uppercase = true
	whead.add_child(_weapon_name)
	_weapon_other = UiTheme.make_hud_label("", 11, UiTheme.TEXT_FAINT)
	_weapon_other.name = "WeaponOther"
	_weapon_other.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_other.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	whead.add_child(_weapon_other)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 6)
	nrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wcol.add_child(nrow)
	_ammo_count = UiTheme.make_hud_label("", 26)
	_ammo_count.name = "AmmoCount"
	nrow.add_child(_ammo_count)
	_ammo_cap = UiTheme.make_hud_label("", 15, UiTheme.TEXT_DIM)
	_ammo_cap.name = "AmmoCap"
	_ammo_cap.size_flags_vertical = Control.SIZE_SHRINK_END
	_ammo_cap.custom_minimum_size.y = 28
	_ammo_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nrow.add_child(_ammo_cap)
	_ammo_note = UiTheme.make_hud_label("", 12, UiTheme.TEXT_DIM)
	_ammo_note.add_theme_font_override("font", UiTheme.tracked_font(2))
	_ammo_note.uppercase = true
	_ammo_note.size_flags_vertical = Control.SIZE_SHRINK_END
	_ammo_note.custom_minimum_size = Vector2(150, 28)
	_ammo_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nrow.add_child(_ammo_note)
	_reload_bar = ProgressBar.new()
	_reload_bar.name = "ReloadBar"
	_reload_bar.show_percentage = false
	_reload_bar.min_value = 0.0
	_reload_bar.max_value = 1.0
	_reload_bar.custom_minimum_size = Vector2(0, 4)
	_reload_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rbg := StyleBoxFlat.new()
	rbg.bg_color = Color(1, 1, 1, 0.1)
	var rfg := StyleBoxFlat.new()
	rfg.bg_color = UiTheme.WARN
	_reload_bar.add_theme_stylebox_override("background", rbg)
	_reload_bar.add_theme_stylebox_override("fill", rfg)
	_reload_bar.visible = false
	wcol.add_child(_reload_bar)

	# bottom centre: interaction prompt
	var pc := CenterContainer.new()
	pc.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	pc.offset_top = -168
	pc.offset_bottom = -120
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(pc)
	_prompt_card = UiTheme.make_card()
	_prompt_card.name = "Prompt"
	pc.add_child(_prompt_card)
	_prompt_holder = HBoxContainer.new()
	_prompt_holder.add_theme_constant_override("separation", 9)
	_prompt_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_card.add_child(_prompt_holder)

	# bottom left: help hint, fps
	_bottom_left = VBoxContainer.new()
	_bottom_left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_bottom_left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom_left.offset_left = 22
	_bottom_left.offset_bottom = -20
	_bottom_left.offset_top = -20
	_bottom_left.add_theme_constant_override("separation", 6)
	_bottom_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bottom_left)
	_help_card = UiTheme.make_card()
	_help_card.name = "Help"
	_help_card.visible = false
	_bottom_left.add_child(_help_card)
	var hgrid := GridContainer.new()
	hgrid.columns = 2
	hgrid.add_theme_constant_override("h_separation", 12)
	hgrid.add_theme_constant_override("v_separation", 5)
	hgrid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_card.add_child(hgrid)
	for h in HELP:
		var keys := UiTheme.make_key_hint(h[0], "")
		hgrid.add_child(keys)
		hgrid.add_child(UiTheme.make_hud_label(h[1], UiTheme.FONT_SMALL + 1, UiTheme.TEXT))
	var hint_card := UiTheme.make_card()
	var hsb := UiTheme.card_style()
	hsb.content_margin_left = 7
	hsb.content_margin_right = 9
	hsb.content_margin_top = 4
	hsb.content_margin_bottom = 4
	hint_card.add_theme_stylebox_override("panel", hsb)
	hint_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hint_card.add_child(UiTheme.make_key_hint("H", "Controls", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM))
	_help_hint = hint_card
	_bottom_left.add_child(_help_hint)
	_fps = UiTheme.make_hud_label("", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	_fps.name = "Fps"
	_fps.visible = show_fps
	_bottom_left.add_child(_fps)
