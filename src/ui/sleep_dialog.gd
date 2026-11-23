class_name SleepDialog
extends CanvasLayer
## Sleep options at the bed (SPEC §7.8). sleep_chosen(-1) = until morning. Owner: U. Foundation stub.

signal sleep_chosen(minutes: float)
signal closed

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


func open(_state: GameState) -> void:
	_begin("Sleep")
	_button("Until morning", func():
		close()
		sleep_chosen.emit(-1.0))
	_button("Two hours", func():
		close()
		sleep_chosen.emit(120.0))
	_button("Not now", func():
		close()
		closed.emit())
