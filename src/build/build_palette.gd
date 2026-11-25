class_name BuildPalette
extends CanvasLayer
## Build mode's menu (Exp 006, U): a category menu at the bottom centre, built
## from data (BuildCatalog.CATEGORIES + BuildPieces.LIST), so a new piece
## only needs a LIST entry with "cat" and "icon".
##
##   BUILD  [Level +1 · First upper floor]           [wood] 12 [stone] 4 ...
##   [1 Walls] [2 Floors] ... [8 Tools]              [F Repair] [X Demolish] [G Move]
##   [tile] [tile] [tile] ...      (the category's pieces: icon, name, cost)
##   [icon] NAME  cost  · missing · lock reason                 Recent: [] [] []
##          ● status (green when the preview is valid, red with the reason)
##   piece hint  [R] Rotate  [RMB] Cancel  [1-8] Category  [Q] Previous ...
##
## A tile shows its piece's icon, name and cost as material icons with
## numbers; unaffordable pieces are dimmed with the missing numbers in red,
## gated ones (SPEC-006 §2) carry a lock and say why. Costs count what
## building can draw on (BuildCatalog.available: B's house supply, else the
## inventory). The header names the storey being built on (PgUp / PgDn).
## Clicking a tab picks its last-used piece; clicking a tile picks it.

signal slot_pressed(slot: int)          ## kept from Experiment 004 (a category by index; steps on repeat)
signal variant_pressed(index: int)      ## a piece tile or a Recent button (BuildPieces.LIST index)
signal category_pressed(cat: int)       ## Exp 006: a category tab (no stepping)

const COLUMNS := 8
const TILE := Vector2(150, 48)
const KEY_HINTS := [["R", "Rotate"], ["RMB", "Cancel"], ["1-8", "Category (again: next)"], ["Q", "Previous"],
	["PgUp / PgDn", "Level"], ["Esc", "Leave"]]

var build: Node                         ## BuildMode (duck-typed: piece, state, plane_y, recent, last_eval)

var _level: Label
var _mat_labels := {}                   # item -> Label
var _unlimited: Label
var _tabs: Array[Button] = []
var _quick := {}                        # piece id -> Button
var _grid: GridContainer
var _tiles: Array[BuildTile] = []
var _tile_ids: Array[int] = []
var _recent_box: HBoxContainer
var _recent_btns: Array[Button] = []
var _sel_icon: UiIcon
var _title: Label
var _cost: Label
var _missing: Label
var _lock_icon: UiIcon
var _lock: Label
var _status_icon: UiIcon
var _status: Label
var _hint: Label
var _selected := 0
var _shown := -1                        # the piece the detail line was last filled for (show_state)


func _ready() -> void:
	layer = 6
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.theme()
	add_child(root)
	var panel := UiTheme.make_panel()
	panel.name = "BuildMenu"
	var sb := UiTheme.panel_style()
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -12
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	panel.add_child(col)
	col.add_child(_build_header())
	col.add_child(_build_tabs())
	_grid = GridContainer.new()
	_grid.name = "Pieces"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	col.add_child(_grid)
	var most := 0
	for c in BuildCatalog.count():
		most = maxi(most, BuildPieces.variants(c).size())
	for k in most:
		var t := BuildTile.new()
		t.custom_minimum_size = TILE
		t.pressed.connect(func() -> void:
			if k < _tile_ids.size():
				variant_pressed.emit(_tile_ids[k]))
		_grid.add_child(t)
		_tiles.append(t)
	col.add_child(_build_detail())
	col.add_child(_build_hints())
	if build != null and build.has_signal("changed"):
		build.changed.connect(refresh)
	refresh()


func _build_header() -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UiTheme.make_icon("construction", 24, UiTheme.ACCENT))
	var t := UiTheme.make_title("Build")
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	var lv := UiTheme.make_icon_label("levels", "", UiTheme.FONT_LARGE, UiTheme.FROST)
	lv.name = "Level"
	_level = lv.get_node("Text")
	head.add_child(lv)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	for item in BuildCatalog.MATERIALS:
		var m := UiTheme.make_icon_label(item, "0", UiTheme.FONT_BODY, UiTheme.TEXT)
		m.tooltip_text = Items.name_of(item)
		m.mouse_filter = Control.MOUSE_FILTER_PASS
		_mat_labels[item] = m.get_node("Text")
		head.add_child(m)
	_unlimited = UiTheme.make_label("unlimited", UiTheme.FONT_SMALL, UiTheme.ACCENT)
	_unlimited.visible = false
	head.add_child(_unlimited)
	return head


func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for c in BuildCatalog.count():
		var cd: Dictionary = BuildCatalog.CATEGORIES[c]
		var b := UiTheme.make_tab("%s %s" % [cd["key"], cd["short"]], str(cd["icon"]))
		b.name = "Tab%s" % cd["key"]
		b.tooltip_text = "%s (key %s)" % [cd["name"], cd["key"]]
		b.pressed.connect(func() -> void: category_pressed.emit(c))
		row.add_child(b)
		_tabs.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	for q in BuildCatalog.QUICK:
		var i := BuildPieces.index_of(str(q["id"]))
		if i < 0:
			continue
		var b := UiTheme.make_tab("%s %s" % [q["key"], q["name"]], BuildCatalog.icon_of(i))
		b.name = "Quick" + str(q["name"])
		b.tooltip_text = "%s (key %s)" % [BuildPieces.LIST[i]["name"], q["key"]]
		b.pressed.connect(func() -> void: variant_pressed.emit(i))
		row.add_child(b)
		_quick[str(q["id"])] = b
	return row


func _build_detail() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_sel_icon = UiTheme.make_icon("dot", 36, UiTheme.ACCENT)
	_sel_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_sel_icon)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	texts.add_child(line)
	_title = UiTheme.make_label("", UiTheme.FONT_LARGE, UiTheme.ACCENT)
	line.add_child(_title)
	_cost = UiTheme.make_label("", UiTheme.FONT_BODY, UiTheme.TEXT)
	line.add_child(_cost)
	_missing = UiTheme.make_label("", UiTheme.FONT_BODY, UiTheme.BAD)
	line.add_child(_missing)
	_lock_icon = UiTheme.make_icon("lock", 12, UiTheme.BAD)
	_lock_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(_lock_icon)
	_lock = UiTheme.make_label("", UiTheme.FONT_BODY, UiTheme.BAD)
	_lock.name = "Lock"
	line.add_child(_lock)
	var st := HBoxContainer.new()
	st.add_theme_constant_override("separation", 6)
	texts.add_child(st)
	_status_icon = UiTheme.make_icon("dot", 12, UiTheme.GOOD)
	_status_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st.add_child(_status_icon)
	_status = UiTheme.make_label("", UiTheme.FONT_BODY, UiTheme.GOOD)
	_status.name = "Status"
	st.add_child(_status)
	_recent_box = HBoxContainer.new()
	_recent_box.add_theme_constant_override("separation", 4)
	_recent_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_recent_box)
	var rl := UiTheme.make_icon_label("recent", "Recent", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM, 12.0)
	_recent_box.add_child(rl)
	for k in BuildCatalog.RECENT_MAX:
		var b := Button.new()
		b.theme = UiTheme.theme()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(36, 36)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for s in ["normal", "hover", "pressed", "hover_pressed"]:
			var bs := UiTheme.button_style(s)
			bs.set_content_margin_all(5)
			b.add_theme_stylebox_override(s, bs)
		b.pressed.connect(func() -> void:
			var ids: Array = build.get("recent") if build != null else []
			if k < ids.size():
				variant_pressed.emit(BuildPieces.index_of(str(ids[k]))))
		UiTheme.wire_sounds(b)
		_recent_box.add_child(b)
		_recent_btns.append(b)
	return row


func _build_hints() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 14)
	row.add_theme_constant_override("v_separation", 4)
	_hint = UiTheme.make_label("", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	_hint.name = "Hint"
	row.add_child(_hint)
	for h in KEY_HINTS:
		row.add_child(UiTheme.make_key_hint(h[0], h[1], UiTheme.FONT_SMALL, UiTheme.TEXT_FAINT))
	return row


## `selected` is the BuildPieces.LIST index of the selected piece. Called by
## BuildMode after each evaluation (materials: the Exp 004 text, unused now).
func show_state(selected: int, title: String, cost: String, _materials: String, status: String, ok: bool, hint: String) -> void:
	if _title == null:
		return
	_selected = selected
	_shown = selected
	refresh()
	_title.text = title.to_upper()
	_cost.text = cost
	_status.text = status
	_status.add_theme_color_override("font_color", UiTheme.GOOD if ok else UiTheme.BAD)
	_status_icon.kind = "dot" if ok else "warn"
	_status_icon.color = UiTheme.GOOD if ok else UiTheme.BAD
	_hint.text = hint


## Redraws the tabs, the tiles, the header and the Recent row from build mode.
func refresh() -> void:
	if _title == null:
		return
	if build != null:
		_selected = int(build.get("piece"))
	var cat := BuildPieces.slot_of(_selected)
	for c in _tabs.size():
		_tabs[c].set_pressed_no_signal(c == cat)
	var sel_id: String = BuildPieces.LIST[_selected]["id"] if _selected >= 0 and _selected < BuildPieces.LIST.size() else ""
	for id in _quick:
		(_quick[id] as Button).set_pressed_no_signal(id == sel_id)
	# tiles
	var v := BuildPieces.variants(cat)
	_tile_ids.clear()
	var state: Object = build.get("state") if build != null else null
	for k in _tiles.size():
		var t := _tiles[k]
		t.visible = k < v.size()
		if k >= v.size():
			continue
		var i: int = v[k]
		_tile_ids.append(i)
		var p: Dictionary = BuildPieces.LIST[i]
		var lock := BuildCatalog.lock_reason(state, p)
		var miss := BuildCatalog.missing(build, p["cost"]) if p["tool"] == "place" or p["tool"] == "upgrade" else {}
		t.set_piece(i, BuildCatalog.icon_of(i), str(p["name"]), p["cost"], _tile_note(p), miss, lock)
		t.set_pressed_no_signal(i == _selected)
		var tip := "%s\n%s" % [p["name"], BuildPieces.cost_text(p["cost"]) if not p["cost"].is_empty() else _tile_note(p)]
		if not miss.is_empty():
			tip += "\nMissing: " + BuildPieces.cost_text(miss)
		if lock != "":
			tip += "\n" + lock
		t.tooltip_text = tip + "\n" + str(p.get("hint", ""))
	# header
	if build != null:
		var storey := Levels.storey_at(float(build.get("plane_y")))
		_level.text = "Building on " + Levels.label(storey)
	for item in _mat_labels:
		(_mat_labels[item] as Label).text = str(BuildCatalog.available(build, item))
	_unlimited.visible = state is GameState and (state as GameState).cheats.get("unlimited", false)
	# selected piece: icon, what is missing, the lock
	if _selected >= 0 and _selected < BuildPieces.LIST.size():
		var p: Dictionary = BuildPieces.LIST[_selected]
		_sel_icon.kind = BuildCatalog.icon_of(_selected)
		var lock := BuildCatalog.lock_reason(state, p)
		_lock.text = lock
		_lock.visible = lock != ""
		_lock_icon.visible = lock != ""
		var cost: Dictionary = p["cost"]
		var ev: Dictionary = build.get("last_eval") if build != null else {}
		if not ev.is_empty() and str(ev.get("piece", "")) == str(p["id"]):
			cost = ev.get("gross_cost", ev.get("cost", cost))
		var miss := BuildCatalog.missing(build, cost) if p["tool"] in ["place", "upgrade", "repair"] else {}
		_missing.text = ("Missing " + BuildPieces.cost_text(miss)) if not miss.is_empty() else ""
		_missing.visible = not miss.is_empty()
		if _shown != _selected:            # picked, not evaluated yet: the plain facts
			_shown = _selected
			_title.text = str(p["name"]).to_upper()
			_cost.text = BuildPieces.cost_text(cost) if not cost.is_empty() else _tile_note(p)
			_status.text = ""
			_hint.text = str(p.get("hint", ""))
	# recent
	var ids: Array = build.get("recent") if build != null else []
	for k in _recent_btns.size():
		var b := _recent_btns[k]
		var i := BuildPieces.index_of(str(ids[k])) if k < ids.size() else -1
		b.visible = i >= 0
		if i >= 0:
			b.icon = UiIcons.texture(BuildCatalog.icon_of(i), 24)
			b.tooltip_text = str(BuildPieces.LIST[i]["name"])
			b.set_pressed_no_signal(i == _selected)
	_recent_box.visible = ids.size() > 1


## What a tile says instead of a cost (tools and free pieces).
static func _tile_note(p: Dictionary) -> String:
	match str(p["tool"]):
		"repair":
			return "uses the material"
		"demolish":
			return "gives back"
		"move":
			return "free"
		"dig":
			return "shovel, +1 stone"
	return "free"


func status_text() -> String:
	return _status.text if _status != null else ""


## Labels of the category tabs in menu order (tests, captures).
func slot_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for b in _tabs:
		out.append(b.text)
	return out


## Test access: the LIST indices the tiles show, in order.
func tile_ids() -> Array[int]:
	return _tile_ids.duplicate()


## Test access: the tile of LIST index `i` (null when not shown).
func tile_of(i: int) -> BuildTile:
	var k := _tile_ids.find(i)
	return _tiles[k] if k >= 0 else null


## Test access: the header's level text ("Building on Level +1 · ...").
func level_text() -> String:
	return _level.text if _level != null else ""


## One piece in the grid: a toggle button drawn as icon + name + cost.
class BuildTile extends Button:
	var index := -1
	var icon_kind := "dot"
	var title := ""
	var cost := {}
	var note := ""
	var missing := {}
	var locked := ""

	func _init() -> void:
		theme = UiTheme.theme()
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		clip_contents = true
		for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var sb := UiTheme.button_style(s)
			sb.set_content_margin_all(4)
			if s == "pressed" or s == "hover_pressed":
				sb.border_width_bottom = 3
			add_theme_stylebox_override(s, sb)
		UiTheme.wire_sounds(self)

	func set_piece(i: int, kind: String, name_text: String, c: Dictionary, note_text: String, miss: Dictionary, lock: String) -> void:
		if i == index and kind == icon_kind and name_text == title and c == cost and miss == missing and lock == locked:
			return
		index = i
		icon_kind = kind
		title = name_text
		cost = c
		note = note_text
		missing = miss
		locked = lock
		queue_redraw()

	## True when the piece can't be afforded or is gated (drawn dimmed).
	func dimmed() -> bool:
		return not missing.is_empty() or locked != ""

	func _draw() -> void:
		var font := UiTheme.font("regular")
		var a := 0.42 if dimmed() else 1.0
		var ic := UiTheme.ACCENT if button_pressed else UiTheme.TEXT
		UiIcons.paint(self, icon_kind, Rect2(Vector2(9, 13), Vector2(24, 24)), Color(0, 0, 0, 0.5 * a))
		UiIcons.paint(self, icon_kind, Rect2(Vector2(8, 12), Vector2(24, 24)), Color(ic, a))
		var x := 40.0
		var w := size.x - x - 6.0
		draw_string(font, Vector2(x, 20), _fit(font, title, w), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(UiTheme.TEXT, a))
		var y := 38.0
		if cost.is_empty():
			draw_string(font, Vector2(x, y), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(UiTheme.TEXT_FAINT, maxf(a, 0.7)))
		else:
			for k in BuildPieces.COST_ORDER:
				if not cost.has(k) or int(cost[k]) <= 0:
					continue
				var short := missing.has(k)
				UiIcons.paint(self, k, Rect2(Vector2(x, y - 11), Vector2(12, 12)), Color(UiTheme.BAD if short else UiTheme.TEXT_DIM, maxf(a, 0.75)))
				x += 14.0
				var t := str(cost[k])
				draw_string(font, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.BAD if short else Color(UiTheme.TEXT_DIM, maxf(a, 0.75)))
				x += font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 7.0
		if locked != "":
			draw_rect(Rect2(Vector2(size.x - 19, 4), Vector2(16, 16)), Color(0, 0, 0, 0.55))
			UiIcons.paint(self, "lock", Rect2(Vector2(size.x - 17, 6), Vector2(12, 12)), UiTheme.BAD)

	static func _fit(font: Font, text: String, w: float) -> String:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x <= w:
			return text
		var t := text
		while t.length() > 1 and font.get_string_size(t + ".", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x > w:
			t = t.substr(0, t.length() - 1)
		return t.strip_edges() + "."
