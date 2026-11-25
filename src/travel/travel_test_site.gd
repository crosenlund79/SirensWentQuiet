class_name TravelTestSite
extends HouseWorld
## Exp 007 (T): the stand-in POI until agent P's src/poi is merged (tests, and
## a build without it). A HouseWorld (so the shared gameplay runs unchanged):
## a copy of the pristine lot, labelled with the place's name, with the entry
## in the front yard and one exit at the lot's southern fog edge,
## "[E] Leave for home". Its helper keeps a car cargo box as a plain
## Dictionary (tests fill it; take_cargo() empties it on the way home).

const ENTRY := Vector2(9.0, 11.4)
const EXIT := Vector2(9.0, 12.1)

var poi_id := ""


static func build_world(id: String, game: Node) -> HouseWorld:
	var w := TravelTestSite.new()
	w.poi_id = id
	w.name = "World"
	w.setup(game.lighting)
	game.add_child(w)
	w.build_new()
	return w


static func make_helper(game: Node) -> Node:
	var h := Helper.new()
	h.name = "Poi"
	h.game = game
	game.add_child(h)
	h.setup()
	game.set("poi", h)
	return h


func entry_point() -> Vector2:
	return ENTRY


func exit_points() -> Array:
	return [EXIT]


## The test site's helper: the exit and a cargo box.
class Helper extends Node:
	var game: Node
	var exit: ExitSpot
	var cargo := {}                ## the car's boot here: {item: n}

	func setup() -> void:
		exit = ExitSpot.new()
		exit.name = "Exit"
		game.add_child(exit)
		exit.global_position = Vector3(TravelTestSite.EXIT.x, 0.0, TravelTestSite.EXIT.y)

	func interactables() -> Array:
		return [exit] if exit != null and is_instance_valid(exit) else []

	## Empties the cargo box: what goes home in the car.
	func take_cargo() -> Dictionary:
		var c := cargo.duplicate()
		cargo.clear()
		return c

	func save_state() -> Dictionary:
		return {"cargo": cargo.duplicate()}

	func load_state(d: Dictionary) -> void:
		var c = d.get("cargo", {})
		cargo = (c as Dictionary).duplicate() if typeof(c) == TYPE_DICTIONARY else {}


class ExitSpot extends Node3D:
	func interact_prompt() -> String:
		return "[E] Leave for home"

	func interact(g: Node) -> void:
		if g.has_method("leave_site"):
			g.leave_site()
