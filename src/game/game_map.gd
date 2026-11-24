extends Node
## The region map in the game (Experiment 003): M's RegionMapScreen, created
## once and kept (prewarmed while the game loads), and a map interactable on
## the dining table ("[E] Study the region map"). Opening it is a modal like
## the inventory: the world pauses (clock, enemies, the player), so movement,
## firing and building are blocked, and the game's own 3D view stops
## rendering while the map covers the screen. The map handles its own keys
## (WASD pan, wheel zoom, Tab, 1-4, Enter) and closes on Esc or M; the game
## restores its state on `closed`. Planning shows a toast "Planned: <place>
## (<purpose>)" and autosaves. Docs: docs/experiment-003/game.md.

const TABLE_POS := Vector3(7.8, 0.0, 5.65)     ## the dining table (HousePlan.FURNITURE)
const TABLE_TOP := 0.76

var game: Node                         ## SurvivalGame
var screen: RegionMapScreen
var table: MapTable
var last_plan := ""                    ## "id|purpose" (tests, playtest)


func setup(g: Node) -> void:
	game = g
	RegionMapScreen.prewarm()          # builds and caches the region (about a second, once per session)
	screen = RegionMapScreen.new()
	screen.name = "RegionMap"
	game.ui.add_child(screen)
	screen.destination_selected.connect(_on_planned)
	screen.closed.connect(_on_closed)
	table = MapTable.new()
	table.name = "MapTable"
	game.add_child(table)
	table.global_position = TABLE_POS


func is_open() -> bool:
	return screen != null and screen.is_open


## Opens the map (the caller checked that no other modal is open).
func open() -> void:
	screen.open(game.state)
	_set_world_render(false)


func close() -> void:
	if is_open():
		screen.close()             # emits closed -> _on_closed


## The interactables this helper adds to the world's (merged by the game).
func interactables() -> Array:
	return [table] if table != null and is_instance_valid(table) else []


func _on_closed() -> void:
	_set_world_render(true)
	if game.has_method("_on_map_closed"):
		game._on_map_closed()


func _on_planned(id: String, purpose: String) -> void:
	last_plan = id + "|" + purpose
	game.toast("Planned: %s (%s)" % [RegionLocations.name_of(id), purpose_text(purpose)], "good")
	game._autosave("plan")


## "targeted:stone" -> "Targeted collection: stone".
static func purpose_text(purpose: String) -> String:
	var p := ExpeditionData.parse_purpose(purpose)
	var a := ExpeditionData.approach_def(str(p.get("approach", "general")))
	var t := str(a.get("name", str(p.get("approach", "general")).capitalize()))
	var item := str(p.get("target", ""))
	return t + (": " + Items.name_of(item).to_lower() if item != "" else "")


## The map draws its own world: the game's 3D view need not render under it.
func _set_world_render(on: bool) -> void:
	if game.is_inside_tree():
		game.get_viewport().disable_3d = not on


## A folded paper map on the dining table: "[E] Study the region map".
class MapTable extends Node3D:
	func _ready() -> void:
		var paper := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.78, 0.008, 0.54)
		paper.mesh = box
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.78, 0.72, 0.58)
		m.roughness = 0.95
		paper.material_override = m
		paper.position = Vector3(0.0, 0.76, 0.0)
		paper.rotation.y = 0.12
		add_child(paper)
		# a few inked marks: a river, two roads, the house circled in red
		for mark in [[Vector3(0.5, 0.002, 0.03), Vector3(0.02, 0, -0.06), Color(0.32, 0.45, 0.55)],
				[Vector3(0.03, 0.002, 0.42), Vector3(-0.14, 0, 0.0), Color(0.35, 0.3, 0.26)],
				[Vector3(0.6, 0.002, 0.025), Vector3(0.0, 0, 0.12), Color(0.35, 0.3, 0.26)],
				[Vector3(0.07, 0.003, 0.07), Vector3(-0.2, 0, 0.14), Color(0.72, 0.18, 0.12)]]:
			var mi := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = mark[0]
			mi.mesh = b
			var mm := StandardMaterial3D.new()
			mm.albedo_color = mark[2]
			mi.material_override = mm
			paper.add_child(mi)
			mi.position = mark[1] + Vector3(0, 0.005, 0)

	func interact_prompt() -> String:
		return "[E] Study the region map"

	func interact(g: Node) -> void:
		if g.has_method("open_map"):
			g.open_map()
