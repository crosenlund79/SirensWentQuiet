class_name DeathScreen
extends UiModal
## Run over (SPEC §7.8). Owner: U. A slow fade to near-black, the days
## survived, the cause, one quiet line, and Main Menu (emits
## main_menu_requested). The button arms after a moment so a held click or
## key doesn't skip the screen.

signal main_menu_requested

const ARM_DELAY := 1.2
const MOODS := [
	"The fog keeps what it takes.",
	"The house will stand a while longer without you.",
	"Out past the fog, the siren mast stays silent.",
	"Nobody heard. There was nobody left to.",
]

var days := 0
var cause := ""
var _button: Button


func _init() -> void:
	super()
	layer = 76
	fade_in_time = 1.4


func open(d: int, c: String) -> void:
	days = maxi(d, 0)
	cause = c
	_clear()
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.theme()
	add_child(_root)
	_scrim = UiTheme.make_scrim(Color(0.02, 0.012, 0.012, 0.9))
	_root.add_child(_scrim)
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_center)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_center.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	_box.custom_minimum_size.x = 620
	_panel.add_child(_box)

	var title := UiTheme.make_label("YOU DIDN'T MAKE IT", 40)
	title.name = "Title"
	title.add_theme_font_override("font", UiTheme.tracked_font(8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
	var rule := ColorRect.new()
	rule.color = UiTheme.ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(rule)
	_box.add_child(UiTheme.make_spacer(10))
	var n := UiTheme.make_label(str(days), 64, UiTheme.ACCENT)
	n.name = "Days"
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(n)
	var unit := UiTheme.make_label("DAY SURVIVED" if days == 1 else "DAYS SURVIVED", 13, UiTheme.TEXT_DIM)
	unit.add_theme_font_override("font", UiTheme.tracked_font(3))
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(unit)
	_box.add_child(UiTheme.make_spacer(10))
	var why := UiTheme.make_label(cause_text(c), UiTheme.FONT_LARGE)
	why.name = "Cause"
	why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(why)
	var mood := UiTheme.make_label(MOODS[days % MOODS.size()], UiTheme.FONT_BODY - 1, UiTheme.TEXT_FAINT)
	mood.name = "Mood"
	mood.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(mood)
	_box.add_child(UiTheme.make_spacer(22))
	_button = UiTheme.make_button("Main Menu")
	_button.name = "MainMenu"
	_button.custom_minimum_size.x = 240
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.disabled = true
	_button.pressed.connect(func(): main_menu_requested.emit())
	_box.add_child(_button)
	_show(null)
	if is_inside_tree():
		get_tree().create_timer(ARM_DELAY, true, false, true).timeout.connect(_arm)
	else:
		_arm()


func _arm() -> void:
	if _button != null and is_instance_valid(_button):
		_button.disabled = false
		_focus(_button)


## "Killed by a psycho", "Starvation", ... from the game's cause string.
static func cause_text(c: String) -> String:
	var l := c.to_lower()
	if l == "":
		return "You died."
	if "psycho" in l or "enemy" in l or "attack" in l or "bite" in l:
		return "Killed by a psycho."
	if "starv" in l or "hunger" in l:
		return "Starved."
	if "dehydrat" in l or "thirst" in l:
		return "Died of thirst."
	if "expedition" in l or "fog" in l:
		return "Lost out in the fog."
	return c.substr(0, 1).to_upper() + c.substr(1) + ("" if c.ends_with(".") else ".")


func _on_cancel() -> void:
	pass   # Esc does nothing here; the only way on is Main Menu


## Test access.
func menu_button() -> Button:
	return _button
