class_name PoiSpot
extends Node3D
## Experiment 007 (P): one thing to use at a POI (the SPEC §7.3 interactable
## duck type: interact_prompt / interact / interact_reach). It stands where
## the player stands to use it. Kinds:
##   container  searchable furniture (data: the layout's container entry)
##   pickup     a loose item lying around (data: the layout's pickup entry)
##   wood       a fallen tree to chop (data: the layout's wood entry)
##   exit       "[E] Leave for home"
##   cargo      the car's boot (only when Eli came by car)
## The game's POI helper (game.poi, game_poi.gd) owns the rules; a spot only
## asks it (world.helper) for its prompt and hands it the interaction.

var kind := "container"
var id := ""
var data := {}
var world: Node                 ## the PoiWorld
var front := Vector2.ZERO       ## containers: the way the piece faces (use it from that side)
var visual: Node3D              ## pickups: the item's mesh (hidden when taken)


func setup(k: String, spot_id: String, at: Vector2, d: Dictionary, w: Node) -> void:
	kind = k
	id = spot_id
	data = d
	world = w
	name = "Spot_%s_%s" % [k, spot_id]
	position = Vector3(at.x, 0, at.y)
	if k == "container":
		front = PoiLayouts.FRONT.get(str(d.get("facing", "S")), Vector2(0, 1))


func plan_pos() -> Vector2:
	return Vector2(position.x, position.z)


func label() -> String:
	return str(data.get("label", kind))


func _helper() -> Object:
	var h: Variant = world.get("helper") if world != null else null
	return h if h is Object and is_instance_valid(h) else null


func interact_prompt() -> String:
	var h := _helper()
	if h != null and h.has_method("prompt_for"):
		return str(h.prompt_for(self))
	match kind:
		"exit":
			return "[E] Leave for home"
		"cargo":
			return "[E] Car (cargo)"
		"pickup":
			return "[E] Pick up %s" % Items.name_of(str(data.get("item", ""))).to_lower()
		"wood":
			return "[E] Chop wood"
	return "[E] Search the %s" % label()


func interact(game: Node) -> void:
	var h := _helper()
	if h == null and game != null:
		var p: Variant = game.get("poi")
		h = p if p is Object and is_instance_valid(p) else null
	if h != null and h.has_method("interact_spot"):
		h.interact_spot(self)


## Containers are used from their front (not through the wall behind them).
func interact_reach(p: Vector2) -> bool:
	if kind != "container":
		return true
	return (p - plan_pos()).dot(front) > -0.45
