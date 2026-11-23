extends "res://tests/test_case.gd"
## Main menu: Continue follows SaveGame.info(), New Game confirms before
## overwriting, the hand-off through GameLaunch, the one-shot notice, and the
## Visual Experiments screen.

const U := preload("res://tests/ui/ui_test_util.gd")
const MENU := "res://src/menu/main_menu.tscn"
const SAVE_PATH := "user://test_ui_menu_save.dat"


func _menu(changes: Array) -> Control:
	var m: Control = (load(MENU) as PackedScene).instantiate()
	m.transition_time = 0.0
	m.scene_changer = func(path: String): changes.append(path)
	add(m)
	return m


func _clear_save() -> void:
	SaveGame.path_override = SAVE_PATH
	SaveGame.delete_save()
	for ext in [".bak", ".tmp"]:
		if FileAccess.file_exists(SAVE_PATH + ext):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH + ext))


func _restore() -> void:
	_clear_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.notice = ""


func _write_valid_save() -> Dictionary:
	var s := GameState.new_run(11)
	s.cheats["invulnerable"] = true             # 86 h without water would kill the run
	s.advance(3 * 1440.0 + 14 * 60.0 + 15.0)   # Day 4, 21:15
	var err := SaveGame.write({"summary": {"day": s.day(), "clock": s.clock_text(), "total_minutes": s.total_minutes},
		"state": s.to_dict(), "world": {}, "game": {}})
	check_eq(err, OK, "fixture save written")
	return SaveGame.info()


func test_continue_disabled_without_save_and_enabled_with_one() -> void:
	_clear_save()
	var changes := []
	var m := _menu(changes)
	await frames(2)
	var cont: Button = m.button("Continue")
	check(cont.disabled, "Continue disabled without a save")
	check_eq(UiTheme.caption_of(cont), "No saved game", "short visible reason")
	m.continue_game()
	check(changes.is_empty(), "disabled Continue does nothing")
	var info := _write_valid_save()
	check(info.get("valid", false), "SaveGame accepts the UI test fixture (%s)" % info.get("error", ""))
	m.refresh_save_info()
	check(not cont.disabled, "Continue enabled with a valid save")
	check_eq(UiTheme.caption_of(cont), "Day 4 · 21:15", "summary shown")
	cont.pressed.emit()
	check_eq(GameLaunch.mode, "continue", "mode continue")
	check_eq(changes, [GameLaunch.GAME_SCENE], "changes to the game scene")
	_restore()


func test_invalid_save_shows_error_and_stays_disabled() -> void:
	_clear_save()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string("not a save")
	f.close()
	var m := _menu([])
	await frames(2)
	check(m.button("Continue").disabled, "invalid save: Continue disabled")
	check(U.all_label_text(m).contains(str(SaveGame.info().get("error", "@@"))), "error text visible")
	_restore()


func test_new_game_confirms_when_a_save_exists() -> void:
	_clear_save()
	var changes := []
	var m := _menu(changes)
	await frames(2)
	# no save: straight in
	m.button("NewGame").pressed.emit()
	await frames(1)
	check_eq(changes, [GameLaunch.GAME_SCENE], "no save: no confirmation")
	check_eq(GameLaunch.mode, "new", "mode new")
	m.queue_free()
	await frames(2)
	_write_valid_save()
	changes.clear()
	GameLaunch.mode = "continue"
	var m2 := _menu(changes)
	await frames(2)
	m2.button("NewGame").pressed.emit()
	await frames(1)
	var dlg: ConfirmDialog = m2.confirm_dialog()
	check(dlg.is_open, "asks before overwriting")
	check(U.all_label_text(dlg).contains("overwrite your current survival run"), "says why")
	U.find_button(dlg, "Cancel").pressed.emit()
	await frames(1)
	check(changes.is_empty() and GameLaunch.mode == "continue", "cancel keeps everything")
	m2.button("NewGame").pressed.emit()
	await frames(1)
	U.find_button(dlg, "Start a new run").pressed.emit()
	await frames(1)
	check_eq(changes, [GameLaunch.GAME_SCENE], "confirmed: game scene")
	check_eq(GameLaunch.mode, "new", "mode new")
	_restore()


func test_notice_shown_once_and_cleared() -> void:
	_clear_save()
	GameLaunch.notice = "The save could not be loaded: damaged."
	var m := _menu([])
	await frames(2)
	check_eq(GameLaunch.notice, "", "notice cleared")
	check(m.confirm_dialog().is_open, "notice shown")
	check(U.all_label_text(m.confirm_dialog()).contains("damaged"), "notice text")
	_restore()


func test_settings_and_experiments_buttons() -> void:
	_clear_save()
	var changes := []
	var m := _menu(changes)
	await frames(2)
	m.button("Settings").pressed.emit()
	await frames(1)
	check(m.settings_panel().is_open, "settings open from the menu")
	U.key(tree, KEY_ESCAPE)
	await frames(1)
	check(not m.settings_panel().is_open, "Esc closes settings")
	m.button("Experiments").pressed.emit()
	check_eq(changes, [GameLaunch.EXPERIMENTS_SCENE], "Visual Experiments")
	GameSettings.reset()
	_restore()


func test_visual_experiments_screen_keeps_demos_and_goes_back() -> void:
	var l: Control = (load(GameLaunch.EXPERIMENTS_SCENE) as PackedScene).instantiate()
	add(l)
	await frames(2)
	check_eq(l.VERSIONS.size(), 3, "three demos")
	var text := U.all_label_text(l)
	check(text.contains("VISUAL EXPERIMENTS · EXPERIMENT 001"), "retitled")
	check(U.find_button(l, "Back") != null, "Back button")
	var enabled := 0
	for b in l._buttons:
		enabled += 0 if b.disabled else 1
	check_eq(enabled, 3, "three demo buttons available")
