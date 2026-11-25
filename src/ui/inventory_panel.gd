class_name InventoryPanel
extends UiModal
## Supplies and equipment (SPEC §7.8, SPEC-003 §7). Owner: U, then I.
## Two tabs:
##   Supplies:  Food, Water, Medical | Ammo, Materials (count / cap; wood,
##              nails, scrap, stone, iron) with descriptions. Use eats, drinks
##              or bandages through GameState.use_item and plays player/eat,
##              player/drink or player/bandage.
##   Equipment: the six slots (Equipment.SLOTS) with what is in them and its
##              effect, and the gear owned (weapons, protective, utility,
##              tools) with Equip / Unequip through GameState.equip / unequip
##              (a refusal's reason is shown). Weapons show their magazine.
## Closes with I, Tab or Esc (emits closed).

signal closed

const GROUPS := [["food", "Food"], ["water", "Water"], ["medical", "Medical"], ["ammo", "Ammo"], ["material", "Materials"], ["book", "Books"]]   # Exp 006 (R): Books
const GEAR_GROUPS := [["weapon", "Weapons"], ["protective", "Protective"], ["utility", "Utility"], ["tool", "Tools"]]
const USE_SOUNDS := {"food": "player/eat", "water": "player/drink", "medical": "player/bandage"}
const TABS := [["supplies", "Supplies"], ["equipment", "Equipment"], ["home", "Home"], ["skills", "Skills"]]   # Exp 005 (C): Home; Exp 006 (R): Skills
## What each piece of gear does when equipped (Equipment and the expedition rules).
const EFFECTS := {
	"handgun": "9 mm · magazine 12 · quick",
	"shotgun": "Shells · magazine 5 · 6 pellets, short range",
	"vest": "Blows and blasts hurt 35 % less",
	"backpack": "Carry half as much again from expeditions",
	"flashlight": "Dark places: more options, less risk",
	"crowbar": "Stockrooms and locked doors on expeditions",
	"hammer": "Needed to build (owning it is enough)",
}
## Exp 006 (U): pixel icons of the tabs (section icons come from UiTheme.SECTION_ICONS).
const TAB_ICONS := {"supplies": "inventory", "equipment": "pistol", "home": "mood", "skills": "skills"}

var state: GameState
var tab := "supplies"
var _rows := {}           # id -> {"row", "count", "use", "fx", "gear"}
var _slots := {}          # slot -> {"item", "fx", "button"}
var _tabs := {}           # tab -> Button
var _bars := {}
var _feedback: Label
var _crates: Label
var home_source: Object   # Exp 005 (C): the game's comfort helper (report()); the Home tab shows only with one


func _init() -> void:
	super()
	layer = 70


## Opens on `which` ("supplies" | "equipment"), or the tab last shown.
func open(s: GameState, which := "") -> void:
	_disconnect_state()
	state = s
	if which in ["supplies", "equipment", "home", "skills"]:      # Exp 006 (R): skills
		tab = which
	if tab == "home" and home_source == null:
		tab = "supplies"
	var focus := _build_tab()
	_refresh()
	if state != null and not state.changed.is_connected(_refresh):
		state.changed.connect(_refresh)
	_show(focus)


func show_tab(which: String) -> void:
	if not which in ["supplies", "equipment", "home", "skills"] or not is_open or (which == "home" and home_source == null):
		return
	tab = which
	var focus := _build_tab()
	_refresh()
	_root.modulate.a = 1.0
	_focus(focus)


func _build_tab() -> Control:
	_rows.clear()
	_slots.clear()
	_tabs.clear()
	_bars.clear()
	_crates = null
	var box := _begin("", 1040)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)
	for t in TABS:
		if t[0] == "home" and home_source == null:
			continue
		var b := UiTheme.make_icon_button(t[1], TAB_ICONS.get(t[0], "dot"))   # Exp 006 (U)
		b.name = "Tab_" + t[0]
		b.toggle_mode = true
		b.custom_minimum_size.x = 150
		b.set_pressed_no_signal(t[0] == tab)
		b.pressed.connect(show_tab.bind(t[0]))
		head.add_child(b)
		_tabs[t[0]] = b
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	if state != null:
		var dl := UiTheme.make_label("%s difficulty" % Difficulty.name_of(state.difficulty), UiTheme.FONT_SMALL, UiTheme.TEXT_FAINT)
		dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(dl)
	# current needs, so the effect of eating is visible
	var needs := GridContainer.new()
	needs.columns = 4
	needs.add_theme_constant_override("h_separation", 34)
	for k in [["health", "health"], ["food", "hunger"], ["water", "hydration"], ["energy", "energy"]]:
		var bar := UiTheme.make_stat_bar(k[0])
		bar.custom_minimum_size.x = 226
		needs.add_child(bar)
		_bars[k[1]] = bar
	box.add_child(needs)
	box.add_child(UiTheme.make_spacer(2))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 34)
	box.add_child(cols)
	var lists := {}
	for side in ["left", "right"]:
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 7)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.custom_minimum_size.x = 485
		cols.add_child(list)
		lists[side] = list
	if tab == "supplies":
		_build_supplies(lists)
	elif tab == "home":
		HomePanelView.build(lists, home_source)     # Exp 005 (C)
	elif tab == "skills":
		ResearchPanelView.build(lists, state, self)     # Exp 006 (R): the research tree and the books
	else:
		_build_equipment(lists)
	box.add_child(UiTheme.make_spacer(2))
	_feedback = UiTheme.make_label("", UiTheme.FONT_BODY - 1, UiTheme.GOOD)
	_feedback.name = "Feedback"
	_feedback.custom_minimum_size.y = 22
	box.add_child(_feedback)
	var close_b := UiTheme.make_button("Close")
	close_b.name = "Close"
	close_b.pressed.connect(_close_and_emit)
	var foot := _footer("I / Tab / Esc", "Close", [close_b])
	var bar_hint := UiTheme.make_key_hint("1-8", "Choose the bar slot \"Bar\" fills")
	bar_hint.name = "BarHint"
	bar_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(bar_hint)
	foot.move_child(bar_hint, 1)
	box.add_child(foot)
	var first := _first_action_button() if tab == "supplies" else _tabs.get(tab) as Button
	return first if first != null else close_b


func _build_supplies(lists: Dictionary) -> void:
	for g in GROUPS:
		var list: VBoxContainer = lists["right" if g[0] in ["ammo", "material"] else "left"]
		if list.get_child_count() > 0:
			list.add_child(UiTheme.make_spacer(4))
		list.add_child(UiTheme.make_section(g[1]))
		if g[0] == "book":      # Exp 006 (R): only the books you carry, each with Read
			var any := false
			for id in Items.ids("book"):
				if state != null and state.inventory.count(id) > 0:
					list.add_child(_item_row(id))
					any = true
			if not any:
				list.add_child(UiTheme.make_caption("Skill books you find show here. K: the Skills tab.", 470, UiTheme.TEXT_FAINT))
			continue
		for id in Items.ids(g[0]):
			list.add_child(_item_row(id))
		if g[0] == "material":
			_crates = UiTheme.make_caption("", 0, UiTheme.TEXT_FAINT)
			list.add_child(_crates)


func _build_equipment(lists: Dictionary) -> void:
	var left: VBoxContainer = lists["left"]
	left.add_child(UiTheme.make_section("Equipped"))
	for slot in Equipment.SLOTS:
		left.add_child(_slot_row(slot))
	left.add_child(UiTheme.make_spacer(4))
	left.add_child(UiTheme.make_caption("New gear goes into a free slot by itself. Equipped gear counts on expeditions and in fights; the hammer only needs to be owned.", 470, UiTheme.TEXT_FAINT))
	var right: VBoxContainer = lists["right"]
	for g in GEAR_GROUPS:
		if right.get_child_count() > 0:
			right.add_child(UiTheme.make_spacer(2))
		right.add_child(UiTheme.make_section(g[1]))
		for id in Items.ids(g[0]):
			right.add_child(_item_row(id, true))


func _slot_row(slot: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Slot_" + slot
	row.add_theme_constant_override("separation", 12)
	var key := UiTheme.make_label(Equipment.SLOT_NAMES[slot], UiTheme.FONT_SMALL + 1, UiTheme.TEXT_DIM)
	key.custom_minimum_size.x = 128
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(key)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	var item := UiTheme.make_label("", UiTheme.FONT_BODY)
	item.name = "Item"
	texts.add_child(item)
	var fx := UiTheme.make_caption("", 250, UiTheme.TEXT_DIM)
	fx.name = "Effect"
	texts.add_child(fx)
	var b := UiTheme.make_button("Unequip")
	b.name = "Unequip"
	b.custom_minimum_size.x = 96
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(unequip_slot.bind(slot))
	row.add_child(b)
	_slots[slot] = {"item": item, "fx": fx, "button": b}
	return row


func _item_row(id: String, gear := false) -> Control:
	var d: Dictionary = Items.DEFS[id]
	var row := HBoxContainer.new()
	row.name = "Row_" + id
	row.add_theme_constant_override("separation", 14)
	var icon := UiTheme.make_icon(UiIcons.for_item(id), 24, UiTheme.TEXT)    # Exp 006 (U)
	icon.name = "Icon"
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	texts.add_child(name_row)
	name_row.add_child(UiTheme.make_label(d.get("name", id), UiTheme.FONT_BODY))
	var fl := UiTheme.make_label(_effect_text(d) if not gear else "", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	fl.name = "Fx"
	fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(fl)
	texts.add_child(UiTheme.make_caption(EFFECTS.get(id, d.get("desc", "")) if gear else d.get("desc", ""), 300, UiTheme.TEXT_DIM))
	var count := UiTheme.make_label("", UiTheme.FONT_LARGE if not gear else UiTheme.FONT_SMALL + 1)
	count.name = "Count"
	count.custom_minimum_size.x = 70 if not gear else 120
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(count)
	if Hotbar.can_hold(id):
		var bb := UiTheme.make_button("Bar")
		bb.name = "Bar"
		bb.tooltip_text = "Put on the quick-access bar, in the selected slot (1-8 choose it)"
		bb.custom_minimum_size.x = 52
		bb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bb.pressed.connect(put_on_bar.bind(id))
		row.add_child(bb)
	var use: Button = null
	if gear:
		use = UiTheme.make_button("Equip")
		use.name = "Equip"
		use.custom_minimum_size.x = 96
		use.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		use.pressed.connect(toggle_equip.bind(id))
		row.add_child(use)
	elif Research.is_book(id):      # Exp 006 (R)
		use = UiTheme.make_button("Read")
		use.name = "Read"
		use.custom_minimum_size.x = 80
		use.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		use.tooltip_text = "Study it: learns %s and uses the book up" % Research.name_of(Research.book_skill(id)).to_lower()
		use.pressed.connect(read_book.bind(id))
		row.add_child(use)
	elif Items.is_consumable(id):
		use = UiTheme.make_button("Use")
		use.name = "Use"
		use.custom_minimum_size.x = 80
		use.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		use.pressed.connect(use_item.bind(id))
		row.add_child(use)
	else:
		var gap := Control.new()
		gap.custom_minimum_size.x = 80
		row.add_child(gap)
	_rows[id] = {"row": row, "count": count, "use": use, "fx": fl, "gear": gear}
	return row


static func _effect_text(d: Dictionary) -> String:
	var parts := []
	if d.has("hunger"):
		parts.append("food +%d" % int(d["hunger"]))
	if d.has("hydration"):
		parts.append("water +%d" % int(d["hydration"]))
	if d.has("health"):
		parts.append("health +%d" % int(d["health"]))
	return " · ".join(parts)


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


## Equips `id` (into the slot it fits), or unequips it when it is equipped.
## Returns "" or the reason it couldn't.
func toggle_equip(id: String) -> String:
	if state == null:
		return ""
	if state.has_equipped(id):
		return unequip_slot(state.slot_of(id))
	var why := state.equip(id)
	if why != "":
		_say(why, UiTheme.WARN)
		Sfx.ui("ui/error")
	else:
		_say("%s: %s." % [Items.name_of(id), str(Equipment.SLOT_NAMES[state.slot_of(id)]).to_lower()], UiTheme.GOOD)
		Sfx.ui("ui/click")
	_refresh()
	return why


## Exp 006 (R): reads a skill book (Read on the Skills and Supplies tabs): the skill
## is learned and the book used up (Research.read_book). Returns the feedback.
func read_book(id: String) -> String:
	if state == null:
		return ""
	var r := Research.read_book(state, id)
	if is_open and tab in ["skills", "supplies"] and r["ok"]:
		show_tab(tab)
	_say(str(r["text"]), UiTheme.GOOD if r["ok"] else UiTheme.WARN)
	Sfx.ui("ui/click" if r["ok"] else "ui/error")
	return str(r["text"])


## Experiment 004 (E): puts `id` in the quick-access bar's selected slot
## (Hotbar.assign; the item there swaps places). Returns "" or the reason.
func put_on_bar(id: String) -> String:
	if state == null:
		return ""
	var i := int(state.hotbar.get("selected", 0))
	var why := Hotbar.assign(state.hotbar, i, id)
	if why != "":
		_say(why, UiTheme.WARN)
		Sfx.ui("ui/error")
		return why
	state.hotbar["holstered"] = false
	_say("%s on the bar, slot %d." % [Items.name_of(id), i + 1], UiTheme.GOOD)
	Sfx.ui("ui/click")
	state.changed.emit()
	return ""


## Experiment 004 (E): 1-8 choose the bar slot that "Bar" fills.
func select_bar_slot(i: int) -> void:
	if state == null or i < 0 or i >= Hotbar.SIZE:
		return
	state.hotbar["selected"] = i
	var id := Hotbar.at(state.hotbar, i)
	_say("Bar slot %d selected%s." % [i + 1, (": " + Items.name_of(id)) if id != "" else " (empty)"], UiTheme.TEXT_DIM)
	state.changed.emit()


func unequip_slot(slot: String) -> String:
	if state == null:
		return ""
	var id := state.equipped(slot)
	if not state.unequip(slot):
		return "Nothing to take off."
	_say("%s unequipped." % Items.name_of(id), UiTheme.TEXT_DIM)
	Sfx.ui("ui/click")
	_refresh()
	return ""


func _say(text: String, color: Color) -> void:
	if _feedback != null:
		_feedback.text = text
		_feedback.add_theme_color_override("font_color", color)


## The count column's text for `id` (also for rows of the other tab).
func _count_for(id: String) -> String:
	var inv := state.inventory
	var n := inv.count(id)
	if Items.is_unique(id):
		if n <= 0:
			return "—"
		return str(Equipment.SLOT_NAMES[state.slot_of(id)]) if state.has_equipped(id) else "Owned"
	var cap := inv.cap(id)
	return "%d / %d" % [n, cap] if cap > 0 else str(n)


func _refresh() -> void:
	if state == null or (_rows.is_empty() and _slots.is_empty() and _bars.is_empty()):   # Exp 005 (C): the Home tab has only bars
		return
	var inv := state.inventory
	for id in _rows:
		var r: Dictionary = _rows[id]
		var n := inv.count(id)
		var cap := inv.cap(id)
		var count: Label = r["count"]
		count.text = _count_for(id)
		var full := cap > 0 and n >= cap and not Items.is_unique(id)
		var equipped := state.has_equipped(id)
		count.add_theme_color_override("font_color", UiTheme.WARN if full else (UiTheme.ACCENT if equipped else (UiTheme.TEXT if n > 0 else UiTheme.TEXT_FAINT)))
		(r["row"] as Control).modulate.a = 1.0 if n > 0 else 0.55
		if r["gear"]:
			if WeaponDefs.has(id):
				(r["fx"] as Label).text = ("%d / %d loaded · %d spare" % [state.magazine(id), WeaponDefs.capacity(id), state.reserve(id)]) if n > 0 else ""
			if r["use"] != null:
				(r["use"] as Button).text = "Unequip" if equipped else "Equip"
				(r["use"] as Button).disabled = n <= 0
		elif r["use"] != null:
			(r["use"] as Button).disabled = n <= 0
	for slot in _slots:
		var sr: Dictionary = _slots[slot]
		var id := state.equipped(slot)
		(sr["item"] as Label).text = Items.name_of(id) if id != "" else "Empty"
		(sr["item"] as Label).add_theme_color_override("font_color", UiTheme.TEXT if id != "" else UiTheme.TEXT_FAINT)
		var fx: String = EFFECTS.get(id, "") if id != "" else ""
		if id != "" and slot == state.active_weapon_slot and WeaponDefs.has(id):
			fx = "In hand · " + fx
		(sr["fx"] as Label).text = fx
		(sr["button"] as Button).visible = id != ""
	if _crates != null:
		_crates.text = "Storage crates raise these caps (you have %d)." % inv.storage_crates
	for t in _tabs:
		(_tabs[t] as Button).set_pressed_no_signal(t == tab)
	if _bars.has("health"):
		for k in _bars:
			(_bars[k] as UiStatBar).set_value(float(state.get(k)), not is_open)


func _first_action_button() -> Button:
	for id in _rows:
		var b = _rows[id]["use"]
		if b != null and state != null and state.inventory.count(id) > 0:
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
	if is_open and visible and event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).physical_keycode
		if k == KEY_K:      # Exp 006 (R): K opened the Skills tab and closes the panel again
			get_viewport().set_input_as_handled()
			_close_and_emit()
			return
		if k >= KEY_1 and k <= KEY_8:
			get_viewport().set_input_as_handled()
			select_bar_slot(k - KEY_1)
			return
	super._input(event)


## Test access: the Use (supplies) or Equip / Unequip (gear) button of an item
## on the tab shown (null for materials and for rows of the other tab).
func use_button(id: String) -> Button:
	return _rows.get(id, {}).get("use")


func count_text(id: String) -> String:
	if _rows.has(id):
		return (_rows[id]["count"] as Label).text
	return _count_for(id) if state != null and Items.has(id) else ""


## Test access: the text shown for an equipment slot (equipment tab).
func slot_text(slot: String) -> String:
	return (_slots[slot]["item"] as Label).text if _slots.has(slot) else ""
