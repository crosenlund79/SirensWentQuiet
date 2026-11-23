class_name DeathScreen
extends CanvasLayer
## Run over: days survived (SPEC §7.8). Owner: U. Foundation stub.

signal main_menu_requested

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


func open(days: int, cause: String) -> void:
	_begin("You didn't make it")
	_box.add_child(UiTheme.make_label("Days survived: %d (%s)" % [days, cause]))
	_button("Main Menu", func(): main_menu_requested.emit())
