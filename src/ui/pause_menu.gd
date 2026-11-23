class_name PauseMenu
extends CanvasLayer
## Pause menu: Resume, Save, Settings, Main Menu (SPEC §7.8). Owner: U. Foundation stub.

signal resume_requested
signal save_requested
signal settings_requested
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


func open(save_block_reason: String) -> void:
	_begin("Paused")
	_button("Resume", func(): resume_requested.emit())
	var s := _button("Save", func(): save_requested.emit())
	s.disabled = save_block_reason != ""
	s.tooltip_text = save_block_reason
	_button("Settings", func(): settings_requested.emit())
	_button("Main Menu", func(): main_menu_requested.emit())
