class_name BuildPalette
extends CanvasLayer
## Build mode's compact bottom bar (UiTheme style): numbered piece and tool
## slots, the selected piece with its cost, owned materials, a status line
## (green when the preview is valid, red with the reason when not) and a hint.

signal slot_pressed(index: int)

var _slots: Array[Button] = []
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
	for i in BuildPieces.LIST.size():
		if i == 6:
			var sep := VSeparator.new()
			row.add_child(sep)
		var p: Dictionary = BuildPieces.LIST[i]
		var b := UiTheme.make_button("%d  %s" % [i + 1, p["short"]])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(98, 0)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func() -> void: slot_pressed.emit(i))
		row.add_child(b)
		_slots.append(b)
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


func show_state(selected: int, title: String, cost: String, materials: String, status: String, ok: bool, hint: String) -> void:
	if _title == null:
		return
	for i in _slots.size():
		_slots[i].set_pressed_no_signal(i == selected)
	_title.text = title.to_upper()
	_cost.text = cost
	_materials.text = materials
	_status.text = status
	_status.add_theme_color_override("font_color", UiTheme.GOOD if ok else UiTheme.BAD)
	_hint.text = hint + "   ·   R rotate   ·   1-9 select   ·   Esc leave"


func status_text() -> String:
	return _status.text if _status != null else ""
