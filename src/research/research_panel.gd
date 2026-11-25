class_name ResearchPanelView
extends RefCounted
## Exp 006 (R): the "Skills" tab of the inventory panel (I / Tab, or K).
## Left: the research tree, one card per skill in order (known / ready to
## learn / locked behind the step before), with what it unlocks. Right: the
## skill books you carry with a Read button each (disabled, with the reason,
## when it can't be read yet), the books still to find and where to look.
## Built from Research.tree(); the inventory panel rebuilds the tab after a
## book is read (InventoryPanel.read_book). Functional styling through
## UiTheme and UiIcons only, so the central restyle applies.

const WIDTH := 470
const WHERE := "Mostly the Public Library (a crowbar opens its locked archive; a flashlight helps in the stacks). Sometimes the hardware store, the construction site or the police station; rarely the military outpost. Electronics manuals: the hardware store, the police station, the military outpost, the site office and the library."   # Exp 007 (S)


## Fills the inventory panel's two columns. `panel` gets the Read presses
## (read_book(id)); may be null (then the buttons do nothing).
static func build(lists: Dictionary, state: GameState, panel: Object) -> void:
	var left: VBoxContainer = lists["left"]
	var right: VBoxContainer = lists["right"]
	if state == null:
		left.add_child(UiTheme.make_caption("Nothing to show.", WIDTH))
		return
	_build_tree(left, state)
	_build_books(right, state, panel)


static func _build_tree(box: VBoxContainer, state: GameState) -> void:
	var tree := Research.tree(state)
	var n := 0
	for t in tree:
		n += 1 if t["known"] else 0
	box.add_child(UiTheme.make_section("Research"))
	var head := UiTheme.make_label("%d of %d skills known" % [n, tree.size()], UiTheme.FONT_BODY)
	head.name = "SkillsKnown"
	box.add_child(head)
	box.add_child(UiTheme.make_caption("Simple wooden building needs no study. Two lines: building (each step needs the one above it) and electronics (Basic electronics first).", WIDTH, UiTheme.TEXT_FAINT))   # Exp 007 (S): two lines
	for t in tree:
		box.add_child(_skill_card(t, state))


static func _skill_card(t: Dictionary, state: GameState) -> Control:
	var card := VBoxContainer.new()
	card.name = "Skill_" + str(t["id"])
	card.add_theme_constant_override("separation", 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var col := UiTheme.GOOD if t["known"] else (UiTheme.ACCENT if t["ready"] else UiTheme.TEXT_FAINT)
	row.add_child(UiTheme.make_icon(_icon("book" if t["known"] else "lock"), 16.0, col))
	var nm := UiTheme.make_label(str(t["name"]), UiTheme.FONT_BODY, UiTheme.TEXT if t["known"] or t["ready"] else UiTheme.TEXT_DIM)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nm)
	var status := "Known"
	if not t["known"]:
		if not t["ready"]:
			var need := []
			for p in t["requires"]:
				if not Research.knows(state, p):
					need.append(Research.name_of(p))
			status = "Needs " + ", ".join(need)
		elif t["have_book"]:
			status = "Ready to read"
		else:
			status = "Find '%s'" % t["book_name"]
	var st := UiTheme.make_label(status, UiTheme.FONT_SMALL, col)
	st.name = "Status"
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(st)
	card.add_child(UiTheme.make_caption(str(t["desc"]), WIDTH, UiTheme.TEXT_DIM))
	var opens: Array = t["unlocks"]
	var lines := []
	if not opens.is_empty():
		lines.append("Unlocks: " + ", ".join(opens) + ".")
	for e in t["effects"]:
		lines.append(str(e))
	var un := UiTheme.make_caption("  ".join(lines), WIDTH, UiTheme.TEXT if t["known"] else UiTheme.TEXT_FAINT)
	un.name = "Unlocks"
	card.add_child(un)
	card.add_child(UiTheme.make_spacer(4))
	return card


static func _build_books(box: VBoxContainer, state: GameState, panel: Object) -> void:
	box.add_child(UiTheme.make_section("Books"))
	var owned := []
	var missing := []
	for b in Research.books():
		if state.inventory.count(b) > 0:
			owned.append(b)
		elif not Research.knows(state, Research.book_skill(b)):
			missing.append(b)
	if owned.is_empty():
		box.add_child(UiTheme.make_caption("You carry no skill books.", WIDTH, UiTheme.TEXT_DIM))
	for b in owned:
		box.add_child(_book_row(b, state, panel))
	if not missing.is_empty():
		box.add_child(UiTheme.make_spacer(4))
		box.add_child(UiTheme.make_section("Still to find"))
		for b in missing:
			box.add_child(UiTheme.make_label("%s  ·  %s" % [Items.name_of(b), Research.name_of(Research.book_skill(b))], UiTheme.FONT_SMALL + 1, UiTheme.TEXT_DIM))
		box.add_child(UiTheme.make_caption(WHERE, WIDTH, UiTheme.TEXT_FAINT))
	box.add_child(UiTheme.make_spacer(4))
	box.add_child(UiTheme.make_caption("Reading a book teaches its skill and uses the book up. Locked pieces show in the build menu with what they need. What you already built stays.", WIDTH, UiTheme.TEXT_FAINT))


static func _book_row(b: String, state: GameState, panel: Object) -> Control:
	var row := HBoxContainer.new()
	row.name = "Book_" + b
	row.add_theme_constant_override("separation", 12)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	texts.add_child(UiTheme.make_label(Items.name_of(b), UiTheme.FONT_BODY))
	var why := Research.can_read(state, b)
	texts.add_child(UiTheme.make_caption(why if why != "" else "Teaches %s." % Research.name_of(Research.book_skill(b)).to_lower(), 330, UiTheme.WARN if why != "" else UiTheme.TEXT_DIM))
	var rb := UiTheme.make_button("Read")
	rb.name = "Read_" + b
	rb.custom_minimum_size.x = 96
	rb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rb.disabled = why != ""
	rb.tooltip_text = why
	if panel != null and panel.has_method("read_book"):
		rb.pressed.connect(Callable(panel, "read_book").bind(b))
	row.add_child(rb)
	return row


## An icon kind UiIcons can draw: the wanted one, or "dot".
static func _icon(kind: String) -> String:
	return kind if kind in UiIcons.KINDS else "dot"
