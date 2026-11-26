class_name PoiLeaveDialog
extends UiModal
## Experiment 009 (X): the small choice when Eli leaves a place (the POI
## helper, game_poi.gd, opens it and acts on `chosen`).
##   ask_leave()  "[E] Leave location" at the parked car or the departure
##                marker: Go home / Travel on (map) / Stay
##   ask_dark()   walking into an apartment's dark hallway end: "Leave this
##                location?" Leave / Stay (Leave then asks where to)
## chosen(what): "home", "map", "leave" or "stay". Esc answers Stay. The
## world is paused while it is open (the helper sets the game's modal).

signal chosen(what: String)

var mode := ""                     ## "leave" | "dark" while open


func _init() -> void:
	super()
	layer = 84


func ask_leave(place: String, can_map: bool, by_car: bool) -> void:
	mode = "leave"
	var box := _begin("Leave location", 470)
	var carry := "The car and its boot come with you." if by_car else "What you carry comes with you."
	box.add_child(UiTheme.make_caption("%s. %s" % [place, carry] if place != "" else carry, 430, UiTheme.TEXT))
	box.add_child(UiTheme.make_spacer(4))
	var home := _menu_button("Go home", "by car" if by_car else "on foot")
	home.name = "GoHome"
	home.pressed.connect(choose.bind("home"))
	box.add_child(home)
	var on := _menu_button("Travel on (map)", "" if can_map else "no map here")
	on.name = "TravelOn"
	on.disabled = not can_map
	on.pressed.connect(choose.bind("map"))
	box.add_child(on)
	var stay := _menu_button("Stay")
	stay.name = "Stay"
	stay.pressed.connect(choose.bind("stay"))
	box.add_child(stay)
	box.add_child(UiTheme.make_spacer(2))
	box.add_child(UiTheme.make_key_hint("Esc", "Stay"))
	_show(home)


func ask_dark() -> void:
	mode = "dark"
	var box := _begin("Leave this location?", 470)
	box.add_child(UiTheme.make_caption("The hallway runs on into the dark, down to the stairwell and out.", 430, UiTheme.TEXT))
	box.add_child(UiTheme.make_spacer(6))
	var stay := UiTheme.make_button("Stay")
	stay.name = "Stay"
	stay.pressed.connect(choose.bind("stay"))
	var go := UiTheme.make_button("Leave")
	go.name = "Leave"
	go.pressed.connect(choose.bind("leave"))
	box.add_child(_button_row([stay, go]))
	_show(stay)


## Answers (the buttons call this; tests may too).
func choose(what: String) -> void:
	if not is_open:
		return
	mode = ""
	close()
	chosen.emit(what)


## The button for `what` ("home", "map", "stay", "leave") while open, else null.
func button(what: String) -> Button:
	if _root == null or not is_open:
		return null
	var n: String = {"home": "GoHome", "map": "TravelOn", "stay": "Stay", "leave": "Leave"}.get(what, "")
	return _root.find_child(n, true, false) as Button if n != "" else null


func _on_cancel() -> void:
	choose("stay")
