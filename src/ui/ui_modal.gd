class_name UiModal
extends CanvasLayer
## Shared shell for every modal panel (pause, settings, inventory, sleep,
## confirm, death; E's expedition screens may extend it too). Owner: U.
##
## Gives each panel the same scrim, centred panel, small-caps title, fade and
## slide, keyboard focus on the first enabled button, open/close sounds and
## Esc handling. It runs while the tree is paused (process_mode ALWAYS).
##
##   class_name MyScreen extends UiModal
##   func open() -> void:
##       var box := _begin("Into the fog", 520)   # fresh content box
##       box.add_child(UiTheme.make_button("Go"))
##       _show()                                  # fade in + focus
##   func _on_cancel() -> void:                    # Esc / ui_cancel
##       close()

var is_open := false
var dim_background := true
var panel_width := 420.0
var fade_in_time := UiTheme.FADE_IN

var _root: Control
var _scrim: ColorRect
var _center: Control
var _panel: PanelContainer
var _box: VBoxContainer
var _tween: Tween


func _init() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	if is_open and _panel != null:
		_focus.call_deferred()


## Builds a fresh panel with `title` and returns its content box.
func _begin(title: String, width := 0.0) -> VBoxContainer:
	_clear()
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.theme()
	add_child(_root)
	if dim_background:
		_scrim = UiTheme.make_scrim()
		_root.add_child(_scrim)
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_center)
	_panel = UiTheme.make_panel()
	_panel.name = "Panel"
	_panel.custom_minimum_size.x = width if width > 0.0 else panel_width
	_center.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", UiTheme.GAP)
	_panel.add_child(_box)
	if title != "":
		var t := UiTheme.make_title(title)
		t.name = "Title"
		_box.add_child(t)
		_box.add_child(UiTheme.make_spacer(2))
	return _box


## Shows the panel built by _begin with the standard fade; focuses `focus`
## (or the first enabled button).
func _show(focus: Control = null) -> void:
	var was_open := is_open
	visible = true
	is_open = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		_root.modulate.a = 1.0   # opened before add_child: no fade; focus in _ready
		return
	if not was_open:
		Sfx.ui("ui/open")
		_root.modulate.a = 0.0
		_center.position.y = 10.0
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(_root, "modulate:a", 1.0, fade_in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_center, "position:y", 0.0, fade_in_time + 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_root.modulate.a = 1.0
	_focus(focus)


func _focus(focus: Control = null) -> void:
	var target := focus if focus != null else UiTheme.first_focusable(_panel)
	if target != null:
		UiTheme.focus_quietly(target)


## Closes with the standard fade. Safe to call when already closed.
func close() -> void:
	if not is_open:
		return
	is_open = false
	Sfx.ui("ui/close")
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _root == null or not is_inside_tree():
		visible = false
		return
	var vp := get_viewport()
	var owner_focus := vp.gui_get_focus_owner() if vp != null else null
	if owner_focus != null and _root.is_ancestor_of(owner_focus):
		owner_focus.release_focus()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 0.0, UiTheme.FADE_OUT)
	_tween.tween_callback(func():
		if not is_open:
			visible = false)


## Esc / ui_cancel while open. Override for other behaviour.
func _on_cancel() -> void:
	close()


func _input(event: InputEvent) -> void:
	if not is_open or not visible:
		return
	if is_cancel_event(event):
		get_viewport().set_input_as_handled()
		_on_cancel()


static func is_cancel_event(event: InputEvent) -> bool:
	if event.is_echo():
		return false
	return event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")


func _clear() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _root != null and is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_root = null
	_scrim = null
	_center = null
	_panel = null
	_box = null


## A button for a vertical menu: text on the left, optional caption on the right.
func _menu_button(text: String, caption := "") -> Button:
	var b := UiTheme.make_button(text, caption)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


## A horizontal row of equal-width buttons (e.g. confirm / cancel).
func _button_row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.GAP)
	for b in buttons:
		(b as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	return row


## The standard foot: a dim key hint on the left, buttons on the right.
func _footer(hint_keys: String, hint_text: String, buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.GAP)
	if hint_keys != "":
		var h := UiTheme.make_key_hint(hint_keys, hint_text)
		h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(h)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)
	for b in buttons:
		(b as Control).custom_minimum_size.x = maxf((b as Control).custom_minimum_size.x, 120.0)
		row.add_child(b)
	return row
