extends "res://tests/test_case.gd"
## Experiment 005 (A): one smoke test in the real game scene. The audio helper
## is wired, the ambience knows the player woke indoors and then stepped out,
## the steps follow the walk on the snow, Eli welcomes a new game, and the F10
## Audio section is there.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_audio_game.dat"


func cleanup() -> void:
	tree.paused = false
	Voice.stop()
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()


func test_game_audio_smoke() -> void:
	SaveGame.path_override = SAVE
	GameLaunch.mode = "new"
	GameLaunch.seed = 5
	Voice.stop()
	var said := Voice.lines_said
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	var audio: Node = g.get("audio")
	if not check(audio != null, "the game has its audio helper"):
		return
	check_eq(audio.voice_line, "voice/eli_new_game", "Eli's welcome is scheduled")
	await frames(20)
	check_eq(g.ambience.place, "inside", "the player wakes indoors")
	g._place_player(Vector3(8.0, 0.0, 11.5), 0.0)   # the front yard, clear to the east
	Input.action_press("move_right")
	await frames(50)
	Input.action_release("move_right")
	await frames(5)
	check(audio.steps_played >= 2, "steps while walking (%d)" % audio.steps_played)
	check_eq(audio.last_surface, "snow", "on the snow outside")
	check_eq(g.ambience.place, "outside", "the ambience follows the player out")
	var n: int = audio.steps_played
	await frames(30)
	check_eq(audio.steps_played, n, "no steps when standing")
	await seconds(1.3)
	check(Voice.lines_said > said and Voice.last_line == "voice/eli_new_game", "Eli said his welcome")
	g.ui.dev_menu.set_open(true)
	await frames(2)
	check(g.ui.dev_menu.button("Play sound") != null, "F10 has the Audio section")
	g.ui.dev_menu.audio_call("dev_toggle_layer", ["details"])
	check(not g.ambience.layers["details"], "F10 toggles a layer")
	check(str(audio.dev_status()).contains("Place: outside"), "F10 status text")
