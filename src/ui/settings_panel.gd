class_name SettingsPanel
extends UiModal
## Volumes, window mode and the controls reference (SPEC §7.8). Owner: U.
## Used by the main menu and the pause menu. Changes apply live through
## GameSettings and are saved when the panel closes (Back, Esc).

signal closed

const VOLUMES := [["master", "Master"], ["sfx", "Sound effects"], ["ambient", "Ambient"], ["music", "Music"]]
## Every in-game action (SPEC §3) plus the raw build keys and the dev menu.
const CONTROLS := [
	["W A S D / Arrows", "Move"],
	["Mouse", "Aim"],
	["LMB", "Shoot"],
	["R", "Reload"],
	["Q / 1 / 2", "Next weapon / primary / secondary"],
	["Wheel", "Zoom"],
	["Z / C", "Turn the view 90° left / right"],
	["V", "Roofs: hide / automatic"],
	["E", "Interact"],
	["I / Tab", "Inventory and equipment"],
	["M", "Region map"],
	["B", "Build mode"],
	["1-9, 0", "Build: pieces 1-6 (again: material), 7 repair, 8 plating, 9 demolish, 0 foundation"],
	["R", "Rotate piece (build)"],
	["RMB", "Cancel / step back (build)"],
	["Esc", "Pause / close panel"],
	["H / F1", "Controls card"],
	["F3", "Frame rate"],
	["F10", "Developer menu"],
]

var _sliders := {}
var _value_labels := {}
var _fullscreen: UiToggle


func _init() -> void:
	super()
	layer = 72


func open() -> void:
	GameSettings.get_value("master")   # loads once
	_sliders.clear()
	_value_labels.clear()
	var box := _begin("Settings", 900)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	box.add_child(cols)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", UiTheme.GAP)
	left.custom_minimum_size.x = 400
	cols.add_child(left)
	left.add_child(UiTheme.make_section("Sound"))
	for v in VOLUMES:
		left.add_child(_volume_row(v[0], v[1]))
	left.add_child(UiTheme.make_spacer(8))
	left.add_child(UiTheme.make_section("Display"))
	_fullscreen = UiTheme.make_toggle("Fullscreen", bool(GameSettings.get_value("fullscreen")))
	_fullscreen.name = "Fullscreen"
	_fullscreen.toggled.connect(func(on: bool): GameSettings.set_value("fullscreen", on))
	left.add_child(_fullscreen)
	left.add_child(UiTheme.make_caption("Settings are saved when you leave this screen.", 400, UiTheme.TEXT_FAINT))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 7)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(UiTheme.make_section("Controls"))
	for c in CONTROLS:
		right.add_child(_control_row(c[0], c[1]))

	box.add_child(UiTheme.make_spacer(4))
	var back := UiTheme.make_button("Back")
	back.name = "Back"
	back.pressed.connect(_back)
	box.add_child(_footer("Esc", "Back", [back]))
	_show(_sliders["master"])


func _volume_row(key: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := UiTheme.make_label(text, UiTheme.FONT_BODY - 1)
	l.custom_minimum_size.x = 130
	row.add_child(l)
	var s := UiTheme.make_slider(0.0, 1.0, 0.05)
	s.name = "Slider_" + key
	s.value = float(GameSettings.get_value(key))
	row.add_child(s)
	var pct := UiTheme.make_label("", UiTheme.FONT_SMALL + 1, UiTheme.TEXT_DIM)
	pct.custom_minimum_size.x = 44
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)
	_sliders[key] = s
	_value_labels[key] = pct
	_show_pct(key, s.value)
	s.value_changed.connect(func(v: float):
		GameSettings.set_value(key, v)
		_show_pct(key, v))
	s.drag_ended.connect(func(_changed: bool): UiTheme.ui_sound("ui/click"))
	return row


func _show_pct(key: String, v: float) -> void:
	(_value_labels[key] as Label).text = "%d%%" % int(round(v * 100.0))


func _control_row(keys: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UiTheme.make_label(text, UiTheme.FONT_SMALL + 1, UiTheme.TEXT)
	l.custom_minimum_size.x = 210
	row.add_child(l)
	var chips := UiTheme.make_key_hint(keys, "")
	row.add_child(chips)
	return row


## Test/automation access to one volume slider.
func slider(key: String) -> HSlider:
	return _sliders.get(key)


func fullscreen_toggle() -> UiToggle:
	return _fullscreen


func _back() -> void:
	if not is_open:
		return
	GameSettings.save_settings()
	close()
	closed.emit()


func _on_cancel() -> void:
	_back()
