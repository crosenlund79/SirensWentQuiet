class_name InventoryPanel
extends CanvasLayer
## Supplies and consumables (SPEC §7.8). Owner: U. Foundation stub.

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


func open(state: GameState) -> void:
	_begin("Supplies")
	for id in state.inventory.counts:
		var b := _button("%s x%d" % [Items.name_of(id), state.inventory.count(id)], func(): state.use_item(id))
		b.disabled = not Items.is_consumable(id)
	_button("Close", func():
		close()
		closed.emit())
