class_name PoiDoor
extends WorldObject
## Experiment 007 (P): a door at a POI. As any door (open, close, enemies bash
## it, bullets damage it), but a locked one (a stockroom, the library archive)
## needs a crowbar: E forces it open through the POI helper (time, noise),
## and it stays forced (PoiState record "forced").

var door_id := ""
var locked := false


func interact_prompt() -> String:
	if kind == "door" and locked:
		var h: Variant = world.get("helper") if world != null else null
		if h is Object and is_instance_valid(h) and h.has_method("door_prompt"):
			return str(h.door_prompt(self))
		return "[E] Force the door (crowbar)"
	return super()


## Exp 008 (L): true while the POI helper forces this door (the interaction finder).
func interact_busy() -> bool:
	var h: Variant = world.get("helper") if world != null else null
	return h is Object and is_instance_valid(h) and h.has_method("busy_with") and bool(h.busy_with(self))


func interact(game: Node) -> void:
	if kind == "door" and locked:
		var h: Variant = world.get("helper") if world != null else null
		if not (h is Object and is_instance_valid(h)) and game != null:
			h = game.get("poi")
		if h is Object and is_instance_valid(h) and h.has_method("force_door"):
			h.force_door(self)
		return
	super(game)
