extends "res://tests/test_case.gd"
## Experiment 005 (F): placed lamps follow the house's power in the game
## (the fuse box's mains, as the electric fixtures), and their own switch.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_storage_lamps_exp005.save"


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()


func test_placed_lamp_follows_the_mains() -> void:
	SaveGame.path_override = SAVE
	GameLaunch.mode = "new"
	GameLaunch.seed = 4242
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	var w: HouseWorld = g.debug_world()
	var lamp := w.place_object("floor_lamp", Vector2(-2.0, 4.0), 0, true)
	await frames(2)
	check(lamp.is_lit(), "a placed floor lamp shines while the mains are on")
	check(g.storage.lit_lamps().has(lamp), "listed as lit")
	w.toggle_mains(w.fuse_box())
	await frames(2)
	check(not lamp.is_lit(), "dark with the mains off")
	w.toggle_mains(w.fuse_box())
	await frames(2)
	check(lamp.is_lit(), "lit again")
	g.debug_teleport_player(Vector2(-2.0, 4.8))
	await frames(2)
	check_eq(g.debug_prompt(), "[E] Turn the lamp off", "its own switch")
	g.debug_interact()
	await frames(1)
	check(not lamp.is_lit() and not lamp.lamp_on, "switched off")
