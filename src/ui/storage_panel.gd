class_name StoragePanel
extends UiModal
## Experiment 005 (F): one storage container (a cupboard, the fridge, a
## wardrobe, a chest, a loot pile...). Two lists side by side:
##   You carry   the household pool's items this container takes, with
##               "Put 1" / "Put all"
##   In it       what it holds, with "Take 1" / "Take all" and, for food,
##               drink and medicine, "Eat" / "Drink" / "Apply" straight from it
## A line under the title says what it is for and how full it is; the rule
## line says that stored items are kept aside. "Take everything" empties it
## as far as the pool's caps allow. Closes with E, Esc or Close (emits
## closed). Transfers go through FurnitureStorage (nothing is duplicated or
## lost). The panel works on the live contents dictionary it is given.

signal closed

const WIDTH := 980

var state: GameState
var type := ""                 ## FurnitureStorage type ("fridge", "loot_pile", ...)
var title_text := ""
var items: Dictionary = {}     ## the live contents
var last_text := ""
var _feedback: Label


func _init() -> void:
	super()
	layer = 72


## Opens on `contents` (the live dictionary) of a container of `storage_type`.
func open(s: GameState, storage_type: String, contents: Dictionary, title := "") -> void:
	_disconnect_state()
	state = s
	type = storage_type
	items = contents
	title_text = title if title != "" else FurnitureStorage.name_of(storage_type)
	last_text = ""
	if state != null and not state.changed.is_connected(_render):
		state.changed.connect(_render)
	_render()
	_show()


func _render() -> void:
	if state == null:
		return
	var had_focus := is_open
	var box := _begin(title_text, WIDTH)
	var cap := FurnitureStorage.capacity(type)
	var sub := "Holds %s" % FurnitureStorage.purpose(type) if type != "loot_pile" else "What was inside, dropped where it broke"
	sub += "  ·  %s" % (("%d / %d" % [FurnitureStorage.total(items), cap]) if cap > 0 else "%d items" % FurnitureStorage.total(items))
	var subl := UiTheme.make_label(sub, UiTheme.FONT_BODY, UiTheme.TEXT_DIM)
	subl.name = "Fill"
	box.add_child(subl)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	box.add_child(cols)
	var left := _column(cols, "You carry")
	var right := _column(cols, "In the %s" % FurnitureStorage.name_of(type).to_lower() if type != "loot_pile" else "In the pile")
	var any_left := false
	for id in Items.DEFS:
		if state.inventory.count(id) > 0 and FurnitureStorage.accepts(type, id) and type != "loot_pile":
			left.add_child(_row(id, state.inventory.count(id), true))
			any_left = true
	if not any_left:
		left.add_child(UiTheme.make_caption("Nothing that goes in here." if type != "loot_pile" else "You can only take from a pile.", 420, UiTheme.TEXT_FAINT))
	var any_right := false
	for id in Items.DEFS:
		if int(items.get(id, 0)) > 0:
			right.add_child(_row(id, int(items[id]), false))
			any_right = true
	if not any_right:
		right.add_child(UiTheme.make_caption("Empty.", 420, UiTheme.TEXT_FAINT))
	box.add_child(UiTheme.make_spacer(2))
	box.add_child(UiTheme.make_caption(FurnitureStorage.RULE_TEXT, WIDTH - 60, UiTheme.TEXT_FAINT))
	_feedback = UiTheme.make_label(last_text, UiTheme.FONT_BODY - 1, UiTheme.GOOD)
	_feedback.name = "Feedback"
	_feedback.custom_minimum_size.y = 22
	box.add_child(_feedback)
	var all_b := UiTheme.make_button("Take everything")
	all_b.name = "TakeAll"
	all_b.disabled = items.is_empty()
	all_b.pressed.connect(take_everything)
	var close_b := UiTheme.make_button("Close")
	close_b.name = "Close"
	close_b.pressed.connect(_close_and_emit)
	box.add_child(_footer("E / Esc", "Close", [all_b, close_b]))
	if had_focus:
		_root.modulate.a = 1.0
		_focus()


func _column(parent: Control, heading: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size.x = 450
	parent.add_child(col)
	col.add_child(UiTheme.make_section(heading))
	return col


func _row(id: String, n: int, carried: bool) -> Control:
	var row := HBoxContainer.new()
	row.name = ("Carry_" if carried else "Stored_") + id
	row.add_theme_constant_override("separation", 8)
	var name_l := UiTheme.make_label(Items.name_of(id), UiTheme.FONT_BODY)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)
	var count := UiTheme.make_label(str(n), UiTheme.FONT_BODY)
	count.name = "Count"
	count.custom_minimum_size.x = 44
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(count)
	if carried:
		var space := FurnitureStorage.space_left(type, items)
		row.add_child(_small("Put 1", put.bind(id, 1), space <= 0))
		row.add_child(_small("Put all", put.bind(id, n), space <= 0))
	else:
		if Items.is_consumable(id):
			row.add_child(_small(Items.verb(id), use.bind(id), false))
		var room := state.inventory.space_for(id)
		row.add_child(_small("Take 1", take.bind(id, 1), room <= 0))
		row.add_child(_small("Take all", take.bind(id, n), room <= 0))
	return row


func _small(text: String, cb: Callable, off: bool) -> Button:
	var b := UiTheme.make_button(text)
	b.name = text.replace(" ", "")
	b.custom_minimum_size.x = 76
	b.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL + 1)
	b.disabled = off
	b.pressed.connect(cb)
	return b


# --- actions (buttons; tests call them directly) ----------------------------------------

## Puts up to n of `id` into the container. Returns how many went in.
func put(id: String, n: int) -> int:
	var k := FurnitureStorage.store(state, items, type, id, n)
	if k > 0:
		_say("Put away %d %s." % [k, Items.name_of(id).to_lower()], true)
		Sfx.ui("ui/click")
	else:
		_say("No room in here." if FurnitureStorage.space_left(type, items) <= 0 else "That doesn't go in here.", false)
	_render()
	return k


## Takes up to n of `id` out into the household pool. Returns how many came out.
func take(id: String, n: int) -> int:
	var k := FurnitureStorage.take(state, items, id, n)
	if k > 0:
		_say("Took %d %s." % [k, Items.name_of(id).to_lower()], true)
		Sfx.ui("ui/click")
	else:
		_say("No room for more %s: material caps (storage crates raise them)." % Items.name_of(id).to_lower(), false)
	_render()
	return k


func take_everything() -> Dictionary:
	var got := FurnitureStorage.take_all(state, items)
	if got.is_empty():
		_say("Nothing taken: no room for it." if not items.is_empty() else "It's empty.", false)
	else:
		_say("Took %s." % FurnitureStorage.contents_text(got) + (" Some didn't fit." if not items.is_empty() else ""), true)
		Sfx.ui("ui/click")
	_render()
	return got


## Eats, drinks or applies one `id` from the container.
func use(id: String) -> String:
	var r := FurnitureStorage.use_from(state, items, id)
	_say(str(r["text"]), r["ok"])
	if r["ok"]:
		Sfx.play({"food": "player/eat", "water": "player/drink", "medical": "player/bandage"}.get(Items.category(id), "player/eat"))
	_render()
	return str(r["text"]) if r["ok"] else ""


func _say(text: String, good: bool) -> void:
	last_text = text
	if _feedback != null:
		_feedback.text = text
		_feedback.add_theme_color_override("font_color", UiTheme.GOOD if good else UiTheme.WARN)


# --- closing ---------------------------------------------------------------------------

func _close_and_emit() -> void:
	if not is_open:
		return
	close()
	closed.emit()


func close() -> void:
	_disconnect_state()
	super.close()


func _disconnect_state() -> void:
	if state != null and state.changed.is_connected(_render):
		state.changed.disconnect(_render)


func _on_cancel() -> void:
	_close_and_emit()


func _input(event: InputEvent) -> void:
	if is_open and visible and not event.is_echo() and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close_and_emit()
		return
	super._input(event)
