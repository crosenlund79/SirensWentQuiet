class_name ConfirmDialog
extends UiModal
## Yes/no question (SPEC §7.8). Owner: U.
##   dialog.ask("This will overwrite your current survival run.", "Start over", "Cancel")
##   var yes: bool = await dialog.answered
## Esc answers no. Keyboard focus starts on the safe ("no") choice.
## inform() is a one-button notice that answers true.

signal answered(yes: bool)


func _init() -> void:
	super()
	layer = 85


func ask(text: String, yes_text := "Yes", no_text := "Cancel", title := "") -> void:
	var box := _begin(title if title != "" else "Are you sure?", 460)
	box.add_child(UiTheme.make_caption(text, 424, UiTheme.TEXT))
	box.add_child(UiTheme.make_spacer(6))
	var no := UiTheme.make_button(no_text)
	no.name = "No"
	no.pressed.connect(_answer.bind(false))
	var yes := UiTheme.make_button(yes_text)
	yes.name = "Yes"
	yes.pressed.connect(_answer.bind(true))
	box.add_child(_button_row([no, yes]))
	_show(no)


## A notice with a single button (answers true).
func inform(text: String, ok_text := "OK", title := "Notice") -> void:
	var box := _begin(title, 460)
	box.add_child(UiTheme.make_caption(text, 424, UiTheme.TEXT))
	box.add_child(UiTheme.make_spacer(6))
	var ok := UiTheme.make_button(ok_text)
	ok.name = "Yes"
	ok.pressed.connect(_answer.bind(true))
	box.add_child(_button_row([ok]))
	_show(ok)


func _answer(yes: bool) -> void:
	if not is_open:
		return
	close()
	answered.emit(yes)


func _on_cancel() -> void:
	_answer(false)
