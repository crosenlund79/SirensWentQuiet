extends Control
## Main menu (SPEC §2). Owner: U. Foundation stub: plain buttons.

func _ready() -> void:
	GameSettings.apply()
	var bg := ColorRect.new()
	bg.color = UiTheme.BG_SOLID
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.position = Vector2(120, 260)
	add_child(box)
	box.add_child(UiTheme.make_title("Sirens Went Quiet", 40))
	var info := SaveGame.info()
	var items := [["New Game", _new_game], ["Continue", _continue], ["Visual Experiments", _experiments], ["Quit", func(): get_tree().quit()]]
	for it in items:
		var b := UiTheme.make_button(it[0])
		b.pressed.connect(it[1])
		box.add_child(b)
		if it[0] == "Continue":
			b.disabled = not info["valid"]


func _new_game() -> void:
	GameLaunch.mode = "new"
	get_tree().change_scene_to_file(GameLaunch.GAME_SCENE)


func _continue() -> void:
	GameLaunch.mode = "continue"
	get_tree().change_scene_to_file(GameLaunch.GAME_SCENE)


func _experiments() -> void:
	get_tree().change_scene_to_file(GameLaunch.EXPERIMENTS_SCENE)
