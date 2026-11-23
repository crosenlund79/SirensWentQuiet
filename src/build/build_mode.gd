class_name BuildMode
extends Node3D
## Construction mode (SPEC §7.4). Owner: V. Foundation stub: toggles only.

signal message(text: String, ok: bool)
signal changed

var active := false
var world: HouseWorld
var state: GameState
var camera: Camera3D
var player: Node3D


func setup(w: HouseWorld, s: GameState, cam: Camera3D, p: Node3D) -> void:
	world = w
	state = s
	camera = cam
	player = p


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if on and state != null and state.inventory.count("hammer") <= 0 and not state.cheats.get("unlimited", false):
		active = false
		message.emit("You need a hammer to build.", false)
		return
	message.emit("Build mode (not implemented yet)" if on else "", true)
	changed.emit()


func handles_input() -> bool:
	return active
