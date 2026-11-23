class_name ExpeditionScreen
extends CanvasLayer
## Destination choice, events and the return report (SPEC §7.7). Owner: E.
## Foundation stub: one fixed expedition.

signal finished(result: Dictionary)
signal cancelled

var _panel: PanelContainer


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open(state: GameState) -> void:
	visible = true
	if _panel != null:
		_panel.queue_free()
	_panel = UiTheme.make_panel()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	box.add_child(UiTheme.make_title("Into the fog"))
	var go := UiTheme.make_button("Nearby Homes (stub): 2 h")
	go.pressed.connect(func():
		visible = false
		finished.emit({"id": "stub_%d" % Time.get_ticks_usec(), "destination": "homes", "name": "Nearby Homes",
			"minutes": 120, "gained": {"water": 1, "canned_food": 1}, "consumed": {}, "lost": {}, "left_behind": {},
			"damage": 0.0, "events": [], "summary": "A quiet search."}))
	box.add_child(go)
	var back := UiTheme.make_button("Turn back")
	back.pressed.connect(func():
		visible = false
		cancelled.emit())
	box.add_child(back)
