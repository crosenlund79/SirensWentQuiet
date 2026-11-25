extends Node3D
## Exp 007 (O): the [E] target of one observation hole (the SPEC §7.3 duck
## type the game's InteractionFinder uses). The holes helper keeps one per open
## hole in its world's `hole_spots`, which HouseWorld.interactables() lists.

const REACH_ALONG := 0.7               ## m along the wall from the hole where the prompt shows
const REACH_ACROSS := 1.3              ## m from the wall line

var helper: Node                       ## src/holes/game_holes.gd
var world: HouseWorld
var rec: Dictionary


func interact_prompt() -> String:
	if helper == null or helper.busy():
		return ""
	var o := HoleRules.object_of(world, rec)
	if o != null and o.kind == "door" and o.open:
		return ""
	return "[E] Look through the hole · [F] Cover it"


## Only from in front of the hole (either side), not from along the wall.
func interact_reach(p: Vector2) -> bool:
	var c := HoleRules.plan_point(world, rec)
	var n := HoleRules.normal(world, rec)
	var d := p - c
	return absf(d.dot(n)) <= REACH_ACROSS and absf(d.dot(Vector2(n.y, n.x))) <= REACH_ALONG


func interact(_game: Node) -> void:
	if helper != null:
		helper.start_peek(world, rec)
