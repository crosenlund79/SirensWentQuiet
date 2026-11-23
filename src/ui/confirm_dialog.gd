class_name ConfirmDialog
extends CanvasLayer
## Yes/no question (SPEC §7.8). Owner: U. Foundation stub.

signal answered(yes: bool)

var is_open := false
var _panel: PanelContainer
var _box: VBoxContainer


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _begin(title: String) -> void:
	if _panel != null:
		_panel.queue_free()
	_panel = UiTheme.make_panel()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_panel)
	_box = VBoxContainer.new()
	_panel.add_child(_box)
	_box.add_child(UiTheme.make_title(title))
	visible = true
	is_open = true


func _button(text: String, cb: Callable) -> Button:
	var b := UiTheme.make_button(text)
	b.pressed.connect(cb)
	_box.add_child(b)
	return b


func close() -> void:
	visible = false
	is_open = false


func ask(text: String, yes_text := "Yes", no_text := "Cancel") -> void:
	_begin("Are you sure?")
	_box.add_child(UiTheme.make_label(text))
	_button(yes_text, func():
		close()
		answered.emit(true))
	_button(no_text, func():
		close()
		answered.emit(false))
