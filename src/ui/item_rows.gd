class_name ItemRows
extends RefCounted
## Exp 012 (L, §26-27): compact item rows and fixed-size, internally
## scrolling lists for the item windows (looting, storage, the boot,
## corpses, the inventory). A row is one line: icon, name, quantity, a short
## status tag (what matters at a glance: "food +30", "wt 1.5", "equipped",
## "none left") and its action buttons. The description is never in the row:
## it is the row's hover tooltip (a popup: it never resizes the window), and
## the window's details line shows it for the row under the mouse or holding
## keyboard / controller focus (details_line + track).
##
##   var lst := ItemRows.scroll_list("Loot")          # fills the space it gets
##   lst.list.add_child(ItemRows.row(id, n, {"status": "wt 2", "actions": [["Take 1", cb, false, "Take1"]]}))
##   var det := ItemRows.details_line(900)
##   ItemRows.track(row, id, det)                     # hover / focus -> details

const ROW_H := 34.0
const ICON := 22.0
const QTY_W := 48.0
const STATUS_W := 84.0
const BUTTON_W := 72.0
const DETAILS_H := 46.0
const DETAILS_IDLE := "Point at an item, or select it with the keyboard, for details."


## One item row. opts: "name" (text instead of the item's name), "qty"
## (text instead of n), "status" (a short tag), "status_color", "dim" (the
## row faded: nothing left), "actions": [[text, Callable, disabled, node
## name]], "prefix" (the row's node name prefix, default "Row_").
static func row(id: String, n: int, opts := {}) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.name = str(opts.get("prefix", "Row_")) + id
	r.add_theme_constant_override("separation", 8)
	r.custom_minimum_size.y = ROW_H
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.tooltip_text = description(id)
	var icon := UiTheme.make_icon(UiIcons.for_item(id), ICON, UiTheme.TEXT)
	icon.name = "Icon"
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	r.add_child(icon)
	var name_l := UiTheme.make_label(str(opts.get("name", Items.name_of(id))), UiTheme.FONT_BODY)
	name_l.name = "Name"
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.mouse_filter = Control.MOUSE_FILTER_PASS
	name_l.tooltip_text = r.tooltip_text
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(name_l)
	var qty := UiTheme.make_label(str(opts.get("qty", str(n))), UiTheme.FONT_BODY)
	qty.name = "Count"
	qty.custom_minimum_size.x = QTY_W
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty.clip_text = true
	qty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(qty)
	var st := UiTheme.make_label(str(opts.get("status", "")), UiTheme.FONT_SMALL, opts.get("status_color", UiTheme.TEXT_FAINT))
	st.name = str(opts.get("status_name", "Status"))
	st.custom_minimum_size.x = STATUS_W
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	st.clip_text = true
	st.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(st)
	for a in opts.get("actions", []):
		r.add_child(button(str(a[0]), a[1], bool(a[2]) if a.size() > 2 else false, str(a[3]) if a.size() > 3 else str(a[0]).replace(" ", "")))
	if bool(opts.get("dim", false)):
		r.modulate.a = 0.5
	return r


## A compact action button of a row.
static func button(text: String, cb: Callable, off := false, node_name := "") -> Button:
	var b := UiTheme.make_button(text)
	b.name = node_name if node_name != "" else text.replace(" ", "")
	b.custom_minimum_size = Vector2(BUTTON_W, ROW_H - 4.0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.FONT_SMALL))
	b.disabled = off
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## A fixed-width blank where a row has no button (keeps the columns lined up).
static func gap(node_name := "NoVerb") -> Control:
	var c := Control.new()
	c.name = node_name
	c.custom_minimum_size = Vector2(BUTTON_W, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## The item's description for its tooltip and the details line: its text,
## plus what using it does.
static func description(id: String) -> String:
	if not Items.has(id):
		return ""
	var d: Dictionary = Items.DEFS[id]
	var t := str(d.get("desc", ""))
	var fx := effect_text(id)
	if fx != "":
		t += "  (" + fx + ")"
	return Items.name_of(id) + ": " + t if t != "" else Items.name_of(id)


## "food +30 · water +4" for consumables, "" otherwise.
static func effect_text(id: String) -> String:
	if not Items.has(id):
		return ""
	var d: Dictionary = Items.DEFS[id]
	var parts := []
	if d.has("hunger"):
		parts.append("food +%d" % int(d["hunger"]))
	if d.has("hydration"):
		parts.append("water +%d" % int(d["hydration"]))
	if d.has("health"):
		parts.append("health +%d" % int(d["health"]))
	return " · ".join(parts)


## A column of rows that scrolls inside the space it gets (it expands to
## fill its parent's height; its own minimum stays small, so the window
## never grows with the list and never shrinks when it is empty).
## Returns {"box": VBoxContainer (heading + scroll), "scroll": ScrollContainer, "list": VBoxContainer}.
static func scroll_list(heading: String, icon := "", min_w := 420.0) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.x = min_w
	if heading != "":
		box.add_child(UiTheme.make_section(heading, icon))
	var sc := ScrollContainer.new()
	sc.name = "Scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size.y = 96
	sc.follow_focus = true
	box.add_child(sc)
	var list := VBoxContainer.new()
	list.name = "List"
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	return {"box": box, "scroll": sc, "list": list}


## The details line: a fixed-height, two-line label under the lists.
static func details_line(width: float) -> Label:
	var l := UiTheme.make_label(DETAILS_IDLE, UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	l.name = "Details"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, DETAILS_H)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.max_lines_visible = 2
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return l


## Wires a row so hovering it, or focusing any of its buttons, shows the
## item's description in `details` (the keyboard / controller equivalent of
## the tooltip).
static func track(r: Control, id: String, details: Label) -> void:
	if details == null:
		return
	var show := func():
		if is_instance_valid(details):
			details.text = description(id)
			details.add_theme_color_override("font_color", UiTheme.TEXT)
	r.mouse_entered.connect(show)
	for c in r.get_children():
		if c is BaseButton:
			(c as BaseButton).focus_entered.connect(show)
			(c as BaseButton).mouse_entered.connect(show)
		elif c is Control:
			(c as Control).mouse_entered.connect(show)


## Keeps a scroll position across a rebuild: sets it once the new list has
## been laid out (the scroll bar's range changes), and at once if it already fits.
static func restore_scroll(sc: ScrollContainer, v: int) -> void:
	if sc == null or v <= 0:
		return
	var bar := sc.get_v_scroll_bar()
	var apply := func():
		if is_instance_valid(sc):
			sc.scroll_vertical = v
	bar.changed.connect(apply, CONNECT_ONE_SHOT)
	sc.scroll_vertical = v
