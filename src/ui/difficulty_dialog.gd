class_name DifficultyDialog
extends UiModal
## New Game's difficulty choice (SPEC-003 §7): Easy, Normal, Hard, each with
## its one-line description (Difficulty.desc_of). The main menu asks, then
## hands the answer to the game through GameLaunch.difficulty.
##   dialog.ask("normal")
##   var level: String = await dialog.answered     # "" = cancelled (Esc, Back)
## Keyboard: arrows move, Enter chooses (focus starts on `current`), Esc backs out.

signal answered(level: String)

var choice := ""


func _init() -> void:
	super()
	layer = 84


func ask(current := Difficulty.DEFAULT) -> void:
	choice = ""
	var box := _begin("Difficulty", 520)
	box.add_child(UiTheme.make_caption("How hard should the first days be? It stays with this run.", 484, UiTheme.TEXT_DIM))
	box.add_child(UiTheme.make_spacer(2))
	var focus: Button = null
	for level in Difficulty.LEVELS:
		var b := _menu_button(Difficulty.name_of(level), _schedule(level))
		b.name = "Difficulty_" + level
		b.custom_minimum_size = Vector2(484, 46)
		b.pressed.connect(_answer.bind(level))
		box.add_child(b)
		var desc := UiTheme.make_caption(Difficulty.desc_of(level), 470, UiTheme.TEXT_DIM)
		desc.name = "Desc_" + level
		box.add_child(desc)
		if level == Difficulty.valid(current):
			focus = b
	box.add_child(UiTheme.make_spacer(2))
	var back := UiTheme.make_button("Back")
	back.name = "Back"
	back.pressed.connect(_answer.bind(""))
	box.add_child(_footer("Enter", "Start", [back]))
	_show(focus)


## The button's caption: when the invasions come.
static func _schedule(level: String) -> String:
	var first := int(Difficulty.get_value(level, "first_invasion_day"))
	var every := int(Difficulty.get_value(level, "invasion_interval_days"))
	return "Invasions from Day %d, every %d days" % [first, every]


func _answer(level: String) -> void:
	if not is_open:
		return
	choice = level
	close()
	answered.emit(level)


func _on_cancel() -> void:
	_answer("")
