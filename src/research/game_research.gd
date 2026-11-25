extends Node
## Exp 006 (R): research in the game (the game_*.gd helper pattern; created
## in SurvivalGame._assemble). Rules live in Research (research.gd) on
## GameState.skills; the panel is the inventory's "Skills" tab
## (ResearchPanelView). This node:
##   K            opens the inventory on the Skills tab (outside panels)
##   new books    a toast says where to read one when it arrives
##   older saves  a toast names the skills granted from the loaded house
##   F10          dev_* functions for the developer menu's Research section

const KEY := KEY_K

var game: Node                         ## SurvivalGame
var _books := {}                       ## book id -> count at the last look


func setup(g: Node) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS
	var s: GameState = game.state
	if not s.changed.is_connected(_on_state_changed):
		s.changed.connect(_on_state_changed)
	_books = _count_books()
	var inferred: Array = (game.get("_loaded") as Dictionary).get("skills_inferred", []) if typeof(game.get("_loaded")) == TYPE_DICTIONARY else []
	if not inferred.is_empty():
		call_deferred("_toast", "Your earlier work counts: you know %s." % ", ".join(inferred.map(func(id): return Research.name_of(id).to_lower())), "info")


## True when the event was K (the game marks it handled).
func handle_input(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	if (event as InputEventKey).physical_keycode != KEY and (event as InputEventKey).keycode != KEY:
		return false
	open_panel()
	return true


## Opens the inventory on the Skills tab.
func open_panel() -> void:
	if game == null or not game.has_method("_open_inventory"):
		return
	if str(game.get("_modal")) != "":
		return
	game.call("_open_inventory")
	var inv: Node = game.ui.inventory
	if inv.has_method("show_tab"):
		inv.show_tab("skills")


func _count_books() -> Dictionary:
	var out := {}
	var s: GameState = game.state
	for b in Research.books():
		out[b] = s.inventory.count(b)
	return out


func _on_state_changed() -> void:
	var now := _count_books()
	for b in now:
		if int(now[b]) > int(_books.get(b, 0)):
			_toast("New book: '%s'. Read it in the inventory's Skills tab (K)." % Items.name_of(b), "good")
	_books = now


func _toast(text: String, kind := "info") -> void:
	if game != null and game.has_method("toast"):
		game.toast(text, kind)


# --- F10 (DevMenu "Research") -------------------------------------------------------------

func dev_give_book(id: String) -> String:
	if not Research.is_book(id):
		return "No such book."
	var n: int = game.state.inventory.add(id, 1)
	return "Added '%s'." % Items.name_of(id) if n > 0 else "You already carry '%s'." % Items.name_of(id)


func dev_give_all_books() -> String:
	var got := []
	for b in Research.books():
		if game.state.inventory.add(b, 1) > 0:
			got.append(Items.name_of(b))
	return ("Added " + ", ".join(got) + ".") if not got.is_empty() else "You already carry every book."


func dev_learn_all() -> String:
	Research.learn_all(game.state)
	return "Every skill learned."


func dev_forget_all() -> String:
	Research.forget_all(game.state)
	return "Every skill forgotten (built structures stay)."


func dev_skills_text() -> String:
	var k := Research.known(game.state)
	return "Skills: " + (", ".join(k.map(func(id): return Research.name_of(id))) if not k.is_empty() else "none")
