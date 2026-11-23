extends "res://tests/test_case.gd"
## UI panels: open/close, keyboard, and the signals the game root relies on.

const U := preload("res://tests/ui/ui_test_util.gd")
const SETTINGS_PATH := "user://test_ui_settings.cfg"


class SleeplessState extends GameState:
	func can_sleep() -> String:
		return "Not with them at the door."


func _cleanup_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	GameSettings.path_override = ""
	GameSettings.reset()


func test_theme_helpers_build_consistent_controls() -> void:
	var t := UiTheme.theme()
	check(t.has_stylebox("hover", "Button") and t.has_stylebox("panel", "PanelContainer"), "theme styles buttons and panels")
	check(UiTheme.theme() == t, "theme is shared")
	var b := UiTheme.make_button("Go", "2 h")
	check_eq(UiTheme.caption_of(b), "2 h", "button caption")
	UiTheme.set_caption(b, "")
	check_eq(UiTheme.caption_of(b), "", "caption cleared")
	check_eq(UiTheme.make_title("Into the fog").text, "INTO THE FOG", "titles are upper case")
	check(UiTheme.make_section("Supplies") is HBoxContainer, "section header")
	check(UiTheme.make_key_hint("I / Tab", "Inventory").get_child_count() >= 4, "two key chips, a slash and a label")
	check_eq(UiTheme.day_time_text(3, "21:40"), "Day 3 · 21:40", "day/time format")
	check_eq(UiTheme.save_summary_text({"day": 4, "clock": "21:15"}), "Day 4 · 21:15", "summary from day + clock")
	check_eq(UiTheme.save_summary_text({"total_minutes": 1440.0 + 450.0}), "Day 2 · 07:30", "summary from total_minutes")
	check_eq(UiTheme.duration_text(150), "2 h 30", "duration")
	var bar := UiTheme.make_stat_bar("food")
	bar.set_value(10)
	check_eq(bar.level(), "warn", "food at 10 warns")
	bar.set_value(0)
	check_eq(bar.level(), "critical", "food at 0 is critical")
	var hb := UiTheme.make_stat_bar("health")
	hb.set_value(15)
	check_eq(hb.level(), "critical", "health at 15 is critical")
	for n in [b, bar, hb]:
		n.free()


func test_confirm_dialog_answers_and_esc_means_no() -> void:
	var d: ConfirmDialog = add(ConfirmDialog.new())
	var log := []
	U.record(d.answered, "answered", log)
	d.ask("Overwrite?", "Start over", "Cancel")
	await frames(2)
	check(d.is_open and d.visible, "opens")
	U.find_button(d, "Start over").pressed.emit()
	check_eq(log, [["answered", true]], "yes")
	check(not d.is_open, "closes on answer")
	d.ask("Again?")
	await frames(2)
	U.key(tree, KEY_ESCAPE)
	await frames(2)
	check_eq(log, [["answered", true], ["answered", false]], "Esc answers no")
	d.inform("The save could not be loaded.")
	await frames(1)
	U.find_button(d, "OK").pressed.emit()
	check_eq(log.back(), ["answered", true], "inform answers true")


func test_pause_menu_signals_and_save_block() -> void:
	var p: PauseMenu = add(PauseMenu.new())
	var log := []
	for s in [[p.resume_requested, "resume"], [p.save_requested, "save"], [p.main_menu_requested, "menu"]]:
		U.record(s[0], s[1], log)
	p.open("Not while enemies are near")
	await frames(2)
	check(p.is_open and p.visible and p.process_mode == Node.PROCESS_MODE_ALWAYS, "open, runs while paused")
	var save := U.find_button(p, "Save") as Button
	check(save.disabled, "Save disabled with a reason")
	check_eq(UiTheme.caption_of(save), "Not while enemies are near", "reason visible on the button")
	# Main Menu -> confirm page; saving blocked: only quit without saving / back
	U.find_button(p, "Main Menu").pressed.emit()
	check_eq(p.page, "confirm", "confirm page")
	check(U.find_button(p, "Save and quit") == null, "no Save and quit while saving is blocked")
	U.key(tree, KEY_ESCAPE)
	await frames(1)
	check_eq(p.page, "main", "Esc on the confirm page goes back")
	check(p.is_open, "still open")
	# allowed: Save and quit emits save then menu
	p.open("")
	await frames(1)
	check(not (U.find_button(p, "Save") as Button).disabled, "Save enabled")
	U.find_button(p, "Save").pressed.emit()
	check_eq(log, ["save"], "save_requested")
	check(U.all_label_text(p).contains("Game saved."), "saved feedback")
	log.clear()
	U.find_button(p, "Main Menu").pressed.emit()
	U.find_button(p, "Save and quit").pressed.emit()
	check_eq(log, ["save", "menu"], "Save and quit: save_requested, then main_menu_requested")
	# a reported save error stops the quit
	log.clear()
	var once := func(): p.report_save("Disk full")
	p.save_requested.connect(once)
	U.find_button(p, "Save and quit").pressed.emit()
	p.save_requested.disconnect(once)
	check_eq(log, ["save"], "no main_menu_requested after a failed save")
	check(U.all_label_text(p).contains("Disk full"), "error shown")
	log.clear()
	U.find_button(p, "Quit without saving").pressed.emit()
	check_eq(log, ["menu"], "quit without saving")
	# Esc on the main page resumes
	p.open("")
	await frames(1)
	log.clear()
	U.key(tree, KEY_ESCAPE)
	await frames(1)
	check_eq(log, ["resume"], "Esc resumes")
	check(not p.is_open, "closed on resume")


func test_pause_menu_opens_its_own_settings() -> void:
	GameSettings.path_override = SETTINGS_PATH
	GameSettings.reset()
	var p: PauseMenu = add(PauseMenu.new())
	p.open("")
	await frames(1)
	U.find_button(p, "Settings").pressed.emit()
	await frames(1)
	check(p.settings_panel() != null and p.settings_panel().is_open, "settings opened by the pause menu")
	U.key(tree, KEY_ESCAPE)
	await frames(1)
	check(not p.settings_panel().is_open, "Esc closes settings first")
	check(p.is_open and p.page == "main", "back on the pause menu")
	p.close()
	_cleanup_settings()


func test_settings_apply_live_and_persist() -> void:
	_cleanup_settings()
	GameSettings.path_override = SETTINGS_PATH
	var s: SettingsPanel = add(SettingsPanel.new())
	var log := []
	U.record(s.closed, "closed", log)
	s.open()
	await frames(2)
	check(s.is_open, "opens")
	s.slider("music").value = 0.25
	s.slider("master").value = 0.5
	s.fullscreen_toggle().button_pressed = true
	var bus := AudioServer.get_bus_index("Music")
	if bus >= 0:
		check(absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.25)) < 0.01, "music bus follows the slider live")
	check(U.all_label_text(s).contains("Developer menu"), "controls reference lists the dev menu")
	check(U.all_label_text(s).contains("Rotate piece"), "controls reference lists build keys")
	U.find_button(s, "Back").pressed.emit()
	check_eq(log, ["closed"], "closed emitted")
	check(FileAccess.file_exists(SETTINGS_PATH), "saved on close")
	GameSettings.reset()
	GameSettings.load_settings()
	check(absf(float(GameSettings.values["music"]) - 0.25) < 0.001, "music persisted")
	check(absf(float(GameSettings.values["master"]) - 0.5) < 0.001, "master persisted")
	check_eq(GameSettings.values["fullscreen"], true, "fullscreen persisted")
	GameSettings.apply()   # headless: must not touch the window or crash
	_cleanup_settings()


func test_inventory_use_consumes_one_and_closes_on_keys() -> void:
	var state := GameState.new_run(3)
	state.hunger = 40.0
	var inv: InventoryPanel = add(InventoryPanel.new())
	var log := []
	U.record(inv.closed, "closed", log)
	inv.open(state)
	await frames(2)
	check(inv.is_open, "opens")
	check_eq(inv.count_text("wood"), "6 / 40", "materials show count / cap")
	check_eq(inv.count_text("hammer"), "Owned", "tools show ownership")
	check(inv.use_button("wood") == null, "materials have no Use button")
	var before := state.inventory.count("canned_food")
	inv.use_button("canned_food").pressed.emit()
	check_eq(state.inventory.count("canned_food"), before - 1, "Use consumes exactly one")
	check(state.hunger > 40.0, "and feeds")
	check(U.all_label_text(inv).contains("Canned food"), "feedback text shown")
	check_eq(inv.count_text("canned_food"), str(before - 1), "count refreshed")
	state.inventory.remove("snacks", state.inventory.count("snacks"))
	await frames(1)
	check((inv.use_button("snacks") as Button).disabled, "Use disabled at zero")
	for k in [KEY_I, KEY_TAB, KEY_ESCAPE]:
		inv.open(state)
		await frames(1)
		U.key(tree, k)
		await frames(1)
		check(not inv.is_open, "closes with %s" % OS.get_keycode_string(k))
	check_eq(log, ["closed", "closed", "closed"], "closed emitted each time")


func test_sleep_dialog_choices_and_block_reason() -> void:
	var state := GameState.new_run(5)
	var d: SleepDialog = add(SleepDialog.new())
	var log := []
	U.record(d.sleep_chosen, "sleep", log)
	U.record(d.closed, "closed", log)
	d.open(state)
	await frames(1)
	check(UiTheme.caption_of(U.find_button(d, "Sleep until morning")).contains("06:00"), "shows the wake time")
	U.find_button(d, "Sleep until morning").pressed.emit()
	check_eq(log, [["sleep", -1.0]], "until morning emits -1")
	d.open(state)
	U.find_button(d, "Rest 2 hours").pressed.emit()
	check_eq(log.back(), ["sleep", 120.0], "rest emits 120")
	d.open(state)
	await frames(1)
	U.key(tree, KEY_ESCAPE)
	await frames(1)
	check_eq(log.back(), "closed", "Esc cancels")
	# invasion warning
	state.total_minutes = 2 * 1440.0 + 13 * 60.0   # Day 3, 13:00
	d.open(state)
	check(U.all_label_text(d).contains("Something is coming"), "warns before an invasion")
	d.close()
	# can_sleep() reason disables sleeping
	var blocked := SleeplessState.new()
	d.open(blocked)
	await frames(1)
	check((U.find_button(d, "Sleep until morning") as Button).disabled and (U.find_button(d, "Rest 2 hours") as Button).disabled, "sleep buttons disabled")
	check(U.all_label_text(d).contains("Not with them at the door."), "reason shown")


func test_death_screen_shows_days_and_returns_to_menu() -> void:
	var d: DeathScreen = add(DeathScreen.new())
	var log := []
	U.record(d.main_menu_requested, "menu", log)
	d.open(4, "psycho")
	await frames(1)
	var text := U.all_label_text(d)
	check(text.contains("YOU DIDN'T MAKE IT") and text.contains("4") and text.contains("DAYS SURVIVED"), "title and days")
	check(text.contains("Killed by a psycho."), "cause")
	check(d.menu_button().disabled, "button armed after a moment")
	await seconds(DeathScreen.ARM_DELAY + 0.2)
	check(not d.menu_button().disabled, "armed")
	d.menu_button().pressed.emit()
	check_eq(log, ["menu"], "main_menu_requested")
	check_eq(DeathScreen.cause_text("starvation"), "Starved.", "starvation wording")


func test_intro_plays_through_or_skips_and_emits_done_once() -> void:
	var a: IntroOverlay = add(IntroOverlay.new())
	var log := []
	U.record(a.done, "done", log)
	a.play()
	await frames(2)
	check(a.visible and a.is_playing, "playing")
	check(IntroOverlay.duration() >= 8.0 and IntroOverlay.duration() <= 10.5, "about 8-10 s (%.1f)" % IntroOverlay.duration())
	await seconds(IntroOverlay.duration() + 0.5)
	check_eq(log, ["done"], "done after the full run")
	check(not a.visible, "hidden")
	var b: IntroOverlay = add(IntroOverlay.new())
	var log2 := []
	U.record(b.done, "done", log2)
	b.play()
	await frames(2)
	U.key(tree, KEY_SPACE)
	await seconds(IntroOverlay.SKIP_FADE + 0.3)
	U.key(tree, KEY_SPACE)
	await frames(2)
	check_eq(log2, ["done"], "any key skips; done exactly once")
