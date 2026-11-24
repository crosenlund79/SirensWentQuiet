extends "res://tests/test_case.gd"
## Experiment 004 (agent D) smoke test in the real game scene: the fuse box
## and furniture are there, the F10 "House (Exp. 004)" tools reach them, and
## closing the front door from the doorway steps the player inside.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_house_exp004_game.dat"


func _boot() -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = "new"
	GameLaunch.seed = 4004
	GameLaunch.difficulty = "normal"
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.death_delay = 0.05
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	return g


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()


func test_house_tools_fuse_box_and_door_in_the_game() -> void:
	var g: Node = await _boot()
	var w: HouseWorld = g.debug_world()
	check(w.fuse_box() != null and w.interactables().has(w.fuse_box()), "the fuse box is an interactable")
	check(w.furniture != null and w.furniture_ok("fridge") and w.furniture_ok("sink_counter"), "the kitchen furniture stands")
	var m: DevMenu = g.debug_ui().dev_menu
	m.toggle()
	await frames(2)
	check(m.button("Destroy furniture") != null, "the House (Exp. 004) section is there")
	var n0 := w.furniture.count(HouseFurniture.INTACT)
	m.button("Destroy furniture").pressed.emit()
	check_eq(w.furniture.count(HouseFurniture.INTACT), n0 - 1, "one piece destroyed")
	m.button("Toggle fuse box").pressed.emit()
	check(not w.fuse_box().mains_on, "the main power is off")
	m.button("Damage all doors").pressed.emit()
	var damaged := 0
	for o in w.objects:
		if o.kind == "door" and o.hp < o.max_hp:
			damaged += 1
	check_eq(damaged, 2, "both doors damaged")
	m.button("Destroy fuse box").pressed.emit()
	check(w.fuse_box() == null, "the fuse box is gone")
	m.button("Repair everything").pressed.emit()
	check_eq(w.furniture.count(HouseFurniture.INTACT), w.furniture.pieces.size(), "repair restores the furniture")
	check(w.fuse_box() != null, "and the fuse box")
	m.toggle()
	# the front door, closed from the doorway
	var front: WorldObject = w.object_at(Vector2(4.5, 9.0))
	w.set_door_open(front, true)
	g.debug_teleport_player(Vector2(4.5, 8.95))
	await physics_frames(3)
	front.interact(g)
	await physics_frames(2)
	check(not front.open, "the door closes")
	check(g.player.global_position.z < 8.6, "the player stepped inside (%s)" % str(g.player.global_position))
