extends Node3D
## The bed as an interactable (SPEC §7.3 duck type). Owner: V.

func interact_prompt() -> String:
	return "[E] Sleep"


func interact(game: Node) -> void:
	if game.has_method("open_sleep"):
		game.open_sleep()
