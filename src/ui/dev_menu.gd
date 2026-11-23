class_name DevMenu
extends CanvasLayer
## Developer / cheat menu on F10 (SPEC §7.8). Owner: U. Foundation stub.

var state: GameState
var game: Node
var _panel: PanelContainer


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func setup(s: GameState, g: Node) -> void:
	state = s
	game = g


func toggle() -> void:
	visible = not visible
	if not visible:
		return
	if _panel != null:
		_panel.queue_free()
	_panel = UiTheme.make_panel()
	_panel.position = Vector2(20, 80)
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	box.add_child(UiTheme.make_title("Developer"))
	for pair in [["Invulnerable", func(): state.cheats["invulnerable"] = not state.cheats["invulnerable"]],
			["Unlimited resources", func(): state.cheats["unlimited"] = not state.cheats["unlimited"]],
			["+5 ammo", func(): state.inventory.add("ammo", 5)],
			["+1 hour", func(): game.dev_advance(60.0)],
			["Trigger invasion", func(): game.dev_trigger_invasion()],
			["Spawn 2 psychos", func(): game.dev_spawn(2)],
			["Repair house", func(): game.dev_repair_house()]]:
		var b := UiTheme.make_button(pair[0])
		b.pressed.connect(pair[1])
		box.add_child(b)
