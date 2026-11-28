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
var _quality := {}                 ## Exp 012: preset -> its button
var _fps_toggle: UiToggle


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
	_build_graphics(left)           # Exp 012 (C)
	_build_character(left)          # Exp 010
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


## Exp 012 (C, §32-33): the graphics preset (applies live, see
## GraphicsQuality) and the frame-rate overlay.
func _build_graphics(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "Quality"
	row.add_theme_constant_override("separation", 6)
	var l := UiTheme.make_label("Graphics", UiTheme.FONT_BODY - 1)
	l.custom_minimum_size.x = 130
	row.add_child(l)
	_quality.clear()
	for q in GraphicsQuality.PRESETS:
		var b := UiTheme.make_tab(str(GraphicsQuality.NAMES[q]))
		b.name = "Quality_" + q
		b.custom_minimum_size.x = 62
		b.pressed.connect(func():
			GraphicsQuality.set_preset(q)
			_show_quality())
		row.add_child(b)
		_quality[q] = b
	box.add_child(row)
	_show_quality()
	_fps_toggle = UiTheme.make_toggle("Show frame rate", GraphicsQuality.show_fps())
	_fps_toggle.name = "ShowFps"
	_fps_toggle.toggled.connect(func(on: bool): GraphicsQuality.set_show_fps(on))
	box.add_child(_fps_toggle)


func _show_quality() -> void:
	for q in _quality:
		(_quality[q] as Button).set_pressed_no_signal(q == GraphicsQuality.preset())


## Test/automation access: the preset buttons and the frame-rate toggle.
func quality_button(q: String) -> Button:
	return _quality.get(q)


func fps_toggle() -> UiToggle:
	return _fps_toggle


## Exp 010: the experimental character (Eli) or the original figure, and
## Eli's look. Applies live (the player swaps its rig); not in the save game.
func _build_character(box: VBoxContainer) -> void:
	box.add_child(UiTheme.make_spacer(8))
	box.add_child(UiTheme.make_section("Character"))
	var eli := UiTheme.make_toggle("Experimental Eli", str(GameSettings.get_value("character")) != "original")
	eli.name = "ExperimentalEli"
	box.add_child(eli)
	var look := UiTheme.make_button("")
	look.name = "EliLook"
	var show := func():
		look.text = "Look: " + EliSculpt.variant_name(int(GameSettings.get_value("eli_variant")))
		look.disabled = str(GameSettings.get_value("character")) == "original"
	show.call()
	eli.toggled.connect(func(on: bool):
		GameSettings.set_value("character", "eli" if on else "original")
		show.call())
	look.pressed.connect(func():
		GameSettings.set_value("eli_variant", (int(GameSettings.get_value("eli_variant")) + 1) % EliSculpt.variant_count())
		show.call())
	box.add_child(look)


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
