class_name BuildPalette
extends CanvasLayer
## Build mode's compact bottom bar (UiTheme style): one button per building
## class (BuildPieces.SLOTS: keys 1-9 and 0; pieces first, then the tools),
## a row with the selected class's material variants (only when it has more
## than one), the selected piece with its cost, owned materials, a status
## line (green when the preview is valid, red with the reason when not) and
## a hint.

signal slot_pressed(slot: int)          ## a class button (BuildPieces slot)
signal variant_pressed(index: int)      ## a variant button (BuildPieces.LIST index)

var _slots := {}                        # slot -> Button
var _variant_row: HBoxContainer
var _variant_label: Label
var _variants: Array[Button] = []
var _variant_ids: Array[int] = []
var _title: Label
var _cost: Label
var _materials: Label
var _status: Label
var _hint: Label


func _ready() -> void:
	layer = 6
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.theme()
	add_child(root)
	var panel := UiTheme.make_panel()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -14
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	_title = _label("", 17, UiTheme.ACCENT)
	head.add_child(_title)
	_cost = _label("", 15, UiTheme.TEXT)
	head.add_child(_cost)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_materials = _label("", 15, UiTheme.TEXT_DIM)
	head.add_child(_materials)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	col.add_child(row)
	for slot in BuildPieces.SLOT_ORDER:
		if slot == 6:
			row.add_child(VSeparator.new())
		var sd: Dictionary = BuildPieces.SLOTS[slot]
		var b := UiTheme.make_button("%s  %s" % [sd["key"], sd["name"]])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func() -> void: slot_pressed.emit(slot))
		row.add_child(b)
		_slots[slot] = b
	_variant_row = HBoxContainer.new()
	_variant_row.add_theme_constant_override("separation", 5)
	col.add_child(_variant_row)
	_variant_label = _label("", 13, UiTheme.TEXT_DIM)
	_variant_row.add_child(_variant_label)
	for k in 3:
		var vb := UiTheme.make_button("")
		vb.toggle_mode = true
		vb.focus_mode = Control.FOCUS_NONE
		vb.add_theme_font_size_override("font_size", 13)
		vb.pressed.connect(func() -> void:
			if k < _variant_ids.size():
				variant_pressed.emit(_variant_ids[k]))
		_variant_row.add_child(vb)
		_variants.append(vb)
	_status = _label("", 15, UiTheme.GOOD)
	col.add_child(_status)
	_hint = _label("", 13, UiTheme.TEXT_DIM)
	col.add_child(_hint)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## `selected` is the BuildPieces.LIST index of the selected piece.
func show_state(selected: int, title: String, cost: String, materials: String, status: String, ok: bool, hint: String) -> void:
	if _title == null:
		return
	var slot := BuildPieces.slot_of(selected)
	for s in _slots:
		(_slots[s] as Button).set_pressed_no_signal(s == slot)
	var v := BuildPieces.variants(slot)
	_variant_row.visible = v.size() > 1
	_variant_ids.clear()
	for k in _variants.size():
		var b := _variants[k]
		b.visible = k < v.size()
		if k < v.size():
			var p: Dictionary = BuildPieces.LIST[v[k]]
			_variant_ids.append(v[k])
			b.text = "%s · %s" % [p["short"], BuildPieces.cost_text(p["cost"])]
			b.set_pressed_no_signal(v[k] == selected)
	_variant_label.text = ("Material (%s again):" % BuildPieces.SLOTS[slot]["key"]) if slot >= 0 else ""
	_title.text = title.to_upper()
	_cost.text = cost
	_materials.text = materials
	_status.text = status
	_status.add_theme_color_override("font_color", UiTheme.GOOD if ok else UiTheme.BAD)
	_hint.text = hint + "   ·   R rotate   ·   1-9, 0 select   ·   Esc leave"


func status_text() -> String:
	return _status.text if _status != null else ""


## Labels of the class buttons in palette order (tests, captures).
func slot_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for s in BuildPieces.SLOT_ORDER:
		out.append((_slots[s] as Button).text)
	return out
