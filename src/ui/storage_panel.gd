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
signal taken(id: String, n: int)          ## Exp 012 (L): anything moved out into the pool (corpses, tests)

const WIDTH := 1120
## Exp 012 (L, §26): every item window has this fixed size; the lists scroll
## inside it, it never shrinks for an empty container and never moves as
## items are taken (the panel is rebuilt in place, scroll and focus kept).
const HEIGHT := 640

var state: GameState
var type := ""                 ## FurnitureStorage type ("fridge", "loot_pile", ...)
var title_text := ""
var items: Dictionary = {}     ## the live contents
var last_text := ""
var _feedback: Label
var _details: Label            ## Exp 012 (L, §27): the selected / hovered item's description
var _lists := []               ## Exp 012 (L): the ScrollContainers of this build (scroll kept across rebuilds)
var _opened_ids := []          ## Exp 012 (L): ids the container held when opened (their rows stay, dimmed, once taken)


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
	_opened_ids = []
	for id in Items.DEFS:
		if int(items.get(id, 0)) > 0:
			_opened_ids.append(id)
	_lists = []
	if state != null and not state.changed.is_connected(_render):
		state.changed.connect(_render)
	_render()
	_show()


# --- the layout (Exp 012 (L): one fixed-size frame for every item window) ----------------------------

## The line under the title.
func _sub_text() -> String:
	var cap := FurnitureStorage.capacity(type)
	var sub := "Holds %s" % FurnitureStorage.purpose(type) if type != "loot_pile" else "What was inside, dropped where it broke"
	return sub + "  ·  %s" % (("%d / %d" % [FurnitureStorage.total(items), cap]) if cap > 0 else "%d items" % FurnitureStorage.total(items))


func _sub_color() -> Color:
	return UiTheme.TEXT_DIM


func _left_heading() -> String:
	return "You carry"


func _right_heading() -> String:
	return "In the %s" % FurnitureStorage.name_of(type).to_lower() if type != "loot_pile" else "In the pile"


## Fills the left list; returns false when it stays empty.
func _fill_left(list: VBoxContainer) -> bool:
	var any := false
	for id in Items.DEFS:
		if state.inventory.count(id) > 0 and FurnitureStorage.accepts(type, id) and type != "loot_pile":
			list.add_child(_row(id, state.inventory.count(id), true))
			any = true
	return any


func _left_empty_text() -> String:
	return "Nothing that goes in here." if type != "loot_pile" else "You can only take from a pile."


## Fills the right list (the container): what it holds, and the rows of what
## it held when opened and is now gone, dimmed, so nothing jumps.
func _fill_right(list: VBoxContainer) -> bool:
	var any := false
	for id in Items.DEFS:
		var n := int(items.get(id, 0))
		if n > 0:
			list.add_child(_row(id, n, false))
			any = true
		elif id in _opened_ids:
			list.add_child(_gone_row(id))
	return any


func _right_empty_text() -> String:
	return "Empty."


func _rule_text() -> String:
	return FurnitureStorage.RULE_TEXT


func _buttons() -> Array:
	var all_b := UiTheme.make_button("Take everything")
	all_b.name = "TakeAll"
	all_b.disabled = items.is_empty()
	all_b.pressed.connect(take_everything)
	var close_b := UiTheme.make_button("Close")
	close_b.name = "Close"
	close_b.pressed.connect(_close_and_emit)
	return [all_b, close_b]


func _render() -> void:
	if state == null:
		return
	var had_focus := is_open
	var keep_scroll := []
	for sc in _lists:
		keep_scroll.append((sc as ScrollContainer).scroll_vertical if is_instance_valid(sc) else 0)
	var keep_focus := _focus_key()
	_lists = []
	var box := _begin(title_text, WIDTH)
	_panel.custom_minimum_size = Vector2(WIDTH, HEIGHT)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var subl := UiTheme.make_label(_sub_text(), UiTheme.FONT_BODY, _sub_color())
	subl.name = "Fill"
	subl.clip_text = true
	subl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subl.custom_minimum_size.x = 1
	box.add_child(subl)
	var cols := HBoxContainer.new()
	cols.name = "Columns"
	cols.add_theme_constant_override("separation", 30)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cols)
	_details = ItemRows.details_line(WIDTH - 60)
	var left := _column(cols, _left_heading())
	var right := _column(cols, _right_heading())
	if not _fill_left(left):
		left.add_child(UiTheme.make_caption(_left_empty_text(), 420, UiTheme.TEXT_FAINT))
	if not _fill_right(right):
		if right.get_child_count() == 0:
			right.add_child(UiTheme.make_caption(_right_empty_text(), 420, UiTheme.TEXT_FAINT))
	box.add_child(_details)
	var rule := UiTheme.make_caption(_rule_text(), WIDTH - 60, UiTheme.TEXT_FAINT)
	rule.name = "Rule"
	rule.max_lines_visible = 2
	box.add_child(rule)
	_feedback = UiTheme.make_label(last_text, UiTheme.FONT_BODY - 1, UiTheme.GOOD)
	_feedback.name = "Feedback"
	_feedback.custom_minimum_size = Vector2(1, 22)
	_feedback.clip_text = true
	_feedback.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_feedback)
	box.add_child(_footer("E / Esc", "Close", _buttons()))
	for k in mini(keep_scroll.size(), _lists.size()):
		ItemRows.restore_scroll(_lists[k], int(keep_scroll[k]))
	if had_focus:
		_root.modulate.a = 1.0
		var f := _find_focus(keep_focus)
		_focus(f)


## A column: its heading over a list that scrolls within the window.
func _column(parent: Control, heading: String) -> VBoxContainer:
	var l := ItemRows.scroll_list(heading, "inventory" if heading == "You carry" else "storage", 500)    # Exp 006 (U) icons
	parent.add_child(l["box"])
	_lists.append(l["scroll"])
	return l["list"]


## The options of an item row (Exp 012: one line; subclasses add their own).
func _row_opts(id: String, n: int, carried: bool) -> Dictionary:
	var acts := []
	var status := ""
	if carried:
		var space := FurnitureStorage.space_left(type, items)
		acts.append(["Put 1", put.bind(id, 1), space <= 0, "Put1"])
		acts.append(["Put all", put.bind(id, n), space <= 0, "Putall"])
		var cap := state.inventory.cap(id)
		status = "of %d" % cap if cap > 0 else ""
	else:
		var room := state.inventory.space_for(id)
		acts.append([Items.verb(id), use.bind(id), false, Items.verb(id)] if Items.is_consumable(id) else ["", Callable(), true, "NoVerb"])
		acts.append(["Take 1", take.bind(id, 1), room <= 0, "Take1"])
		acts.append(["Take all", take.bind(id, n), room <= 0, "Takeall"])
		status = ItemRows.effect_text(id) if room > 0 else "no room"
	return {"prefix": "Carry_" if carried else "Stored_", "status": status, "actions": acts,
		"status_color": UiTheme.WARN if status == "no room" else UiTheme.TEXT_FAINT}


func _row(id: String, n: int, carried: bool) -> Control:
	var opts := _row_opts(id, n, carried)
	var acts: Array = opts["actions"]
	opts["actions"] = []
	var r := ItemRows.row(id, n, opts)
	for a in acts:
		if not (a[1] as Callable).is_valid():
			r.add_child(ItemRows.gap(str(a[3])))          # keeps the buttons lined up
		else:
			r.add_child(ItemRows.button(str(a[0]), a[1], bool(a[2]), str(a[3])))
	ItemRows.track(r, id, _details)
	return r


## A row for something that was here and is all taken (stays, dimmed, so the
## rows below don't jump).
func _gone_row(id: String) -> Control:
	var r := ItemRows.row(id, 0, {"prefix": "Gone_", "qty": "0", "status": "taken", "dim": true})
	ItemRows.track(r, id, _details)
	return r


func _small(text: String, cb: Callable, off: bool) -> Button:
	return ItemRows.button(text, cb, off)


## "row name/button name" of the focused button, to focus it again after a rebuild.
func _focus_key() -> String:
	if _root == null or not is_inside_tree():
		return ""
	var f := get_viewport().gui_get_focus_owner()
	if f == null or not _root.is_ancestor_of(f):
		return ""
	return "%s/%s" % [f.get_parent().name, f.name]


func _find_focus(key: String) -> Control:
	if key == "" or _root == null:
		return null
	var parts := key.split("/")
	var row := _root.find_child(parts[0], true, false)
	if row == null:
		return null
	var b := row.get_node_or_null(NodePath(parts[1])) as Control
	if b is BaseButton and not (b as BaseButton).disabled:
		return b
	return null


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
		taken.emit(id, k)
		_say("Took %d %s." % [k, Items.name_of(id).to_lower()], true)
		Sfx.ui("ui/click")
	else:
		_say("No room for more %s: material caps (storage crates raise them)." % Items.name_of(id).to_lower(), false)
	_render()
	return k


func take_everything() -> Dictionary:
	var got := FurnitureStorage.take_all(state, items)
	for id in got:
		taken.emit(id, int(got[id]))
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
