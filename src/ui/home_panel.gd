class_name HomePanelView
extends RefCounted
## Experiment 005 (C): the Home tab of the inventory panel (I / Tab, "Home").
## Left: the room you're in (its label, comfort and the factors behind it,
## and hints). Right: Eli's mood and its causes, what it does, and the house
## overview by storey and room. Built from game_comfort.gd's report(); the
## inventory panel rebuilds it whenever the tab opens.

const MAX_FACTORS := 12
const MAX_CAUSES := 8


## Fills the inventory panel's two columns from `source.report()`.
static func build(lists: Dictionary, source: Object) -> void:
	var left: VBoxContainer = lists["left"]
	var right: VBoxContainer = lists["right"]
	if source == null or not source.has_method("report"):
		left.add_child(UiTheme.make_caption("No home to show.", 470))
		return
	var rep: Dictionary = source.call("report")
	_build_room(left, rep)
	_build_mood(right, rep)
	_build_house(right, rep)


static func _build_room(box: VBoxContainer, rep: Dictionary) -> void:
	box.add_child(UiTheme.make_section("This room"))
	var here: Dictionary = rep.get("here", {})
	if here.is_empty():
		var t := UiTheme.make_label("Outdoors", UiTheme.FONT_LARGE)
		t.name = "RoomTitle"
		box.add_child(t)
		box.add_child(UiTheme.make_caption("You're not inside a room. Rooms are the spaces your walls, doors and windows close off.", 470))
		return
	var title := UiTheme.make_label("%s · %s" % [here["label"], here.get("storey_name", "")], UiTheme.FONT_LARGE)
	title.name = "RoomTitle"
	box.add_child(title)
	var lvl := UiTheme.make_label("%s (%.0f)" % [here["level_name"], float(here["comfort"])], UiTheme.FONT_BODY, level_color(int(here["level"])))
	lvl.name = "RoomComfort"
	box.add_child(lvl)
	var rows := VBoxContainer.new()
	rows.name = "Factors"
	rows.add_theme_constant_override("separation", 2)
	box.add_child(rows)
	var factors: Array = here.get("factors", []).duplicate()
	factors.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	for f in factors.slice(0, MAX_FACTORS):
		rows.add_child(_delta_row(str(f[0]), float(f[1])))
	for h in here.get("hints", []):
		box.add_child(UiTheme.make_caption("Tip: " + str(h), 470, UiTheme.ACCENT))


static func _build_mood(box: VBoxContainer, rep: Dictionary) -> void:
	box.add_child(UiTheme.make_section("Eli's mood"))
	var m := float(rep.get("mood", Mood.START))
	var t := float(rep.get("target", m))
	var arrow := "steady" if absf(t - m) < 2.0 else ("rising toward %.0f" % t if t > m else "sinking toward %.0f" % t)
	var head := UiTheme.make_label("%s (%.0f), %s" % [rep.get("mood_name", Mood.name_of(m)), m, arrow], UiTheme.FONT_BODY, level_color(Mood.band(m)))
	head.name = "MoodTitle"
	box.add_child(head)
	var rows := VBoxContainer.new()
	rows.name = "Causes"
	rows.add_theme_constant_override("separation", 2)
	box.add_child(rows)
	var causes: Array = rep.get("causes", [])
	if causes.is_empty():
		rows.add_child(UiTheme.make_caption("Nothing much either way.", 470))
	for c in causes.slice(0, MAX_CAUSES):
		rows.add_child(_delta_row(str(c[0]), float(c[1])))
	box.add_child(UiTheme.make_caption(str(rep.get("effects", "")), 470))
	var rest := float(rep.get("rest", 1.0))
	if not (rep.get("here", {}) as Dictionary).is_empty():
		box.add_child(UiTheme.make_caption("Sleeping here: energy x%.2f per hour." % rest, 470, UiTheme.GOOD if rest > 1.0 else (UiTheme.WARN if rest < 1.0 else UiTheme.TEXT_DIM)))


static func _build_house(box: VBoxContainer, rep: Dictionary) -> void:
	box.add_child(UiTheme.make_spacer(4))
	box.add_child(UiTheme.make_section("The house"))
	var hv := float(rep.get("house", 0.0))
	var head := UiTheme.make_label("%s (%.0f)" % [rep.get("house_name", ""), hv], UiTheme.FONT_BODY, level_color(ComfortCatalog.level_of(hv)))
	head.name = "HouseTitle"
	box.add_child(head)
	var list := VBoxContainer.new()
	list.name = "Rooms"
	list.add_theme_constant_override("separation", 1)
	box.add_child(list)
	for st in rep.get("storeys", []):
		var rs: Array = st.get("rooms", [])
		list.add_child(UiTheme.make_label(str(st.get("name", "")), UiTheme.FONT_SMALL, UiTheme.TEXT_DIM))
		if rs.is_empty():
			list.add_child(UiTheme.make_caption("   No closed rooms.", 470, UiTheme.TEXT_FAINT))
		for r in rs:
			var text := "   %s · %s (%.0f)%s" % [r["label"], r["level_name"], float(r["comfort"]), "  open to the outside" if r.get("exposed", false) else ""]
			list.add_child(UiTheme.make_label(text, UiTheme.FONT_SMALL + 1, level_color(int(r["level"]))))


static func _delta_row(text: String, delta: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var mark := "+" if delta >= 0.0 else "−"
	var l := UiTheme.make_label("%s %s" % [mark, text], UiTheme.FONT_SMALL + 1, UiTheme.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 380
	row.add_child(l)
	var v := UiTheme.make_label("%s%.1f" % ["+" if delta >= 0.0 else "", delta], UiTheme.FONT_SMALL + 1, UiTheme.GOOD if delta >= 0.0 else UiTheme.BAD)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.custom_minimum_size.x = 52
	row.add_child(v)
	return row


## Colour of a comfort level or mood band (0..4).
static func level_color(i: int) -> Color:
	return UiTheme.BAD if i <= 0 else (UiTheme.WARN if i == 1 else (UiTheme.GOOD if i >= 3 else UiTheme.TEXT))
