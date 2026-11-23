extends Node
## Forwards unhandled input to the game root, also while the tree is paused
## (panels open), so Esc / I / F10 keep working. Clicks the GUI consumed never
## arrive here, so pressing a button never fires the gun.

var game: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if game != null and game.has_method("_on_input"):
		game._on_input(event)
