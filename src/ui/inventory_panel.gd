class_name InventoryPanel
extends UiModal
## Supplies and consumables (SPEC §7.8). Owner: U.
## Food, Water, Medical, Ammo, Materials (count / cap) and Tools, with
## descriptions. Use eats, drinks or bandages through GameState.use_item and
## plays player/eat, player/drink or player/bandage. Closes with I, Tab or Esc
## (emits closed).

signal closed

const GROUPS := [["food", "Food"], ["water", "Water"], ["medical", "Medical"], ["ammo", "Ammo"], ["material", "Materials"], ["tool", "Tools"]]
const USE_SOUNDS := {"food": "player/eat", "water": "player/drink", "medical": "player/bandage"}

var state: GameState
var _rows := {}           # id -> {"row", "count", "use"}
var _bars := {}
var _feedback: Label
var _crates: Label


func _init() -> void:
	super()
	layer = 70


func open(s: GameState) -> void:
	_disconnect_state()
	state = s
	_rows.clear()
	_bars.clear()
	var box := _begin("Supplies", 740)
	# current needs, so the effect of eating is visible
	var needs := GridContainer.new()
	needs.columns = 4
	needs.add_theme_constant_override("h_separation", 18)
	for k in [["health", "health"], ["food", "hunger"], ["water", "hydration"], ["energy", "energy"]]:
		var bar := UiTheme.make_stat_bar(k[0])
		bar.custom_minimum_size.x = 158
		needs.add_child(bar)
		_bars[k[1]] = bar
	box.add_child(needs)
	box.add_child(UiTheme.make_spacer(2))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 500)
	scroll.follow_focus = true
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for g in GROUPS:
		list.add_child(UiTheme.make_section(g[1]))
		for id in Items.ids(g[0]):
			list.add_child(_item_row(id))
		if g[0] == "material":
			_crates = UiTheme.make_caption("", 0, UiTheme.TEXT_FAINT)
			list.add_child(_crates)
		list.add_child(UiTheme.make_spacer(4))

	_feedback = UiTheme.make_label("", UiTheme.FONT_BODY - 1, UiTheme.GOOD)
	_feedback.name = "Feedback"
	_feedback.custom_minimum_size.y = 22
	box.add_child(_feedback)
	var close_b := UiTheme.make_button("Close")
	close_b.name = "Close"
	close_b.pressed.connect(_close_and_emit)
	box.add_child(_footer("I / Tab / Esc", "Close", [close_b]))
	_refresh()
	if state != null and not state.changed.is_connected(_refresh):
		state.changed.connect(_refresh)
	var first := _first_use_button()
	_show(first if first != null else close_b)


func _item_row(id: String) -> Control:
	var d: Dictionary = Items.DEFS[id]
	var row := HBoxContainer.new()
	row.name = "Row_" + id
	row.add_theme_constant_override("separation", 14)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	texts.add_child(UiTheme.make_label(d.get("name", id), UiTheme.FONT_BODY))
	var desc: String = d.get("desc", "")
	var fx := _effect_text(d)
	if fx != "":
		desc += "  ·  " + fx
	texts.add_child(UiTheme.make_caption(desc, 0, UiTheme.TEXT_DIM))
	var count := UiTheme.make_label("", UiTheme.FONT_LARGE)
	count.name = "Count"
	count.custom_minimum_size.x = 96
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(count)
	var use: Button = null
	if Items.is_consumable(id):
		use = UiTheme.make_button("Use")
		use.name = "Use"
		use.custom_minimum_size.x = 86
		use.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		use.pressed.connect(use_item.bind(id))
		row.add_child(use)
	else:
		var gap := Control.new()
		gap.custom_minimum_size.x = 86
		row.add_child(gap)
	_rows[id] = {"row": row, "count": count, "use": use}
	return row


static func _effect_text(d: Dictionary) -> String:
	var parts := []
	if d.has("hunger"):
		parts.append("food +%d" % int(d["hunger"]))
	if d.has("hydration"):
		parts.append("water +%d" % int(d["hydration"]))
	if d.has("health"):
		parts.append("health +%d" % int(d["health"]))
	return ", ".join(parts)


## Uses one unit of `id` (the Use button). Returns the feedback text.
func use_item(id: String) -> String:
	if state == null:
		return ""
	var text := state.use_item(id)
	if text == "":
		_say("You can't use that right now.", UiTheme.WARN)
		Sfx.ui("ui/error")
	else:
		_say(text, UiTheme.GOOD)
		Sfx.play(USE_SOUNDS.get(Items.category(id), "ui/click"))
	_refresh()
	return text


func _say(text: String, color: Color) -> void:
	if _feedback != null:
		_feedback.text = text
		_feedback.add_theme_color_override("font_color", color)


func _refresh() -> void:
	if state == null or _rows.is_empty():
		return
	var inv := state.inventory
	for id in _rows:
		var r: Dictionary = _rows[id]
		var n := inv.count(id)
		var cap := inv.cap(id)
		var count: Label = r["count"]
		if Items.category(id) == "tool":
			count.text = "Owned" if n > 0 else "—"
		elif cap > 0:
			count.text = "%d / %d" % [n, cap]
		else:
			count.text = str(n)
		var full := cap > 0 and n >= cap
		count.add_theme_color_override("font_color", UiTheme.WARN if full else (UiTheme.TEXT if n > 0 else UiTheme.TEXT_FAINT))
		(r["row"] as Control).modulate.a = 1.0 if n > 0 else 0.55
		if r["use"] != null:
			(r["use"] as Button).disabled = n <= 0
	if _crates != null:
		_crates.text = "Storage crates raise these caps (you have %d)." % inv.storage_crates
	if _bars.has("health"):
		for k in _bars:
			(_bars[k] as UiStatBar).set_value(float(state.get(k)), not is_open)


func _first_use_button() -> Button:
	for id in _rows:
		var b = _rows[id]["use"]
		if b != null and not (b as Button).disabled:
			return b
	return null


func _close_and_emit() -> void:
	if not is_open:
		return
	close()
	closed.emit()


func close() -> void:
	_disconnect_state()
	super.close()


func _disconnect_state() -> void:
	if state != null and state.changed.is_connected(_refresh):
		state.changed.disconnect(_refresh)


func _on_cancel() -> void:
	_close_and_emit()


func _input(event: InputEvent) -> void:
	if is_open and visible and not event.is_echo() and event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		_close_and_emit()
		return
	super._input(event)


## Test access: the Use button of an item (null for tools and materials).
func use_button(id: String) -> Button:
	return _rows.get(id, {}).get("use")


func count_text(id: String) -> String:
	return (_rows[id]["count"] as Label).text if _rows.has(id) else ""
