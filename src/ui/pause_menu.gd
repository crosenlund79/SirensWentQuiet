class_name PauseMenu
extends UiModal
## Pause menu: Resume, Save, Settings, Main Menu (SPEC §7.8). Owner: U.
##
## Signal sequence (the game root wires these; the tree is paused while open):
## - Resume button or Esc: the menu closes itself, then emits resume_requested.
## - Save: emits save_requested. The game saves synchronously and may call
##   report_save(error) ("" = success); the menu shows "Game saved." or the error.
## - Settings: emits settings_requested. If nothing is connected to it, the
##   menu opens its own SettingsPanel and comes back when it closes.
## - Main Menu: shows a confirmation page ("progress since your last save
##   will be lost"):
##     "Save and quit" (only when saving is allowed): save_requested, then, unless
##       report_save() reported an error during it, main_menu_requested;
##     "Quit without saving": main_menu_requested;
##     "Back" or Esc: back to the main page.
## The menu does not close itself on main_menu_requested (the scene changes).

signal resume_requested
signal save_requested
signal settings_requested
signal main_menu_requested

var page := ""              ## "main" | "confirm" (tests)
var save_block_reason := ""
var subtitle := ""          ## a line under the title, e.g. "Hard difficulty · Day 3"
var _status: Label
var _settings: SettingsPanel
var _save_error := ""
var _save_reported := false


func _init() -> void:
	super()
	layer = 70


func open(reason: String, sub := "") -> void:
	save_block_reason = reason
	subtitle = sub
	_main_page()
	_show()


## The game reports the result of a save_requested ("" = saved).
func report_save(error := "") -> void:
	_save_error = error
	_save_reported = true
	if error != "":
		_set_status(error, UiTheme.BAD)
	else:
		_set_status("Game saved.", UiTheme.GOOD)


func _main_page(focus_name := "") -> void:
	page = "main"
	var box := _begin("Paused", 380)
	if subtitle != "":
		var sub := UiTheme.make_caption(subtitle, 344, UiTheme.TEXT_DIM)
		sub.name = "Subtitle"
		box.add_child(sub)
	var resume := _menu_button("Resume")
	resume.name = "Resume"
	resume.pressed.connect(_resume)
	box.add_child(resume)
	var save := _menu_button("Save")
	save.name = "Save"
	save.disabled = save_block_reason != ""
	if save.disabled:
		UiTheme.set_caption(save, save_block_reason)
		save.tooltip_text = save_block_reason
	save.pressed.connect(_save)
	box.add_child(save)
	var settings := _menu_button("Settings")
	settings.name = "Settings"
	settings.pressed.connect(_open_settings)
	box.add_child(settings)
	var menu := _menu_button("Main Menu")
	menu.name = "MainMenu"
	menu.pressed.connect(_confirm_page)
	box.add_child(menu)
	_status = UiTheme.make_caption("", 344)
	_status.name = "Status"
	_status.visible = false
	box.add_child(_status)
	box.add_child(UiTheme.make_spacer(2))
	box.add_child(_footer("Esc", "Resume", []))
	if is_open:
		_root.modulate.a = 1.0
		_focus(box.get_node_or_null(focus_name) as Control if focus_name != "" else null)


func _confirm_page() -> void:
	page = "confirm"
	var box := _begin("Leave this run?", 440)
	box.add_child(UiTheme.make_caption("Progress since your last save will be lost.", 404, UiTheme.TEXT))
	if save_block_reason != "":
		box.add_child(UiTheme.make_caption("You can't save right now.", 404, UiTheme.WARN))
		box.add_child(UiTheme.make_caption(save_block_reason, 404, UiTheme.TEXT_DIM))
	box.add_child(UiTheme.make_spacer(4))
	var first: Control = null
	if save_block_reason == "":
		var sq := _menu_button("Save and quit")
		sq.name = "SaveAndQuit"
		sq.pressed.connect(_save_and_quit)
		box.add_child(sq)
		first = sq
	var quit := _menu_button("Quit without saving")
	quit.name = "QuitWithoutSaving"
	quit.pressed.connect(func(): main_menu_requested.emit())
	box.add_child(quit)
	var back := _menu_button("Back")
	back.name = "Back"
	back.pressed.connect(_main_page.bind("MainMenu"))
	box.add_child(back)
	_status = UiTheme.make_caption("", 404)
	_status.name = "Status"
	_status.visible = false
	box.add_child(_status)
	if first == null:
		first = back
	_root.modulate.a = 1.0
	_focus(first)


func _resume() -> void:
	if not is_open:
		return
	close()
	resume_requested.emit()


func _save() -> void:
	_save_error = ""
	_save_reported = false
	save_requested.emit()
	if not _save_reported:
		_set_status("Game saved.", UiTheme.GOOD)


func _save_and_quit() -> void:
	_save_error = ""
	_save_reported = false
	save_requested.emit()
	if _save_error != "":
		_set_status("Couldn't save: %s" % _save_error, UiTheme.BAD)
		return
	main_menu_requested.emit()


func _open_settings() -> void:
	var handled := not settings_requested.get_connections().is_empty()
	settings_requested.emit()
	if handled:
		return
	if _settings == null:
		_settings = SettingsPanel.new()
		_settings.name = "Settings"
		add_child(_settings)
		_settings.closed.connect(_on_settings_closed)
	_root.visible = false
	_settings.open()


func _on_settings_closed() -> void:
	if not is_open:
		return
	_root.visible = true
	_focus(_panel.find_child("Settings", true, false) as Control)


func _set_status(text: String, color: Color) -> void:
	if _status == null or not is_instance_valid(_status):
		return
	_status.text = text
	_status.add_theme_color_override("font_color", color)
	_status.visible = text != ""


func close() -> void:
	if _settings != null and _settings.is_open:
		_settings.close()
	super.close()


func _on_cancel() -> void:
	if page == "confirm":
		_main_page("MainMenu")
	else:
		_resume()


## The embedded settings panel (null until first opened).
func settings_panel() -> SettingsPanel:
	return _settings
