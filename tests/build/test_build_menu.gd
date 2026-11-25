extends "res://tests/test_case.gd"
## Exp 006 (U): the category build menu's data (BuildCatalog), its locks,
## costs against what is available, and the pixel style it is drawn in
## (UiIcons bitmaps, Pixel Operator sizes).


class FakeState:
	extends RefCounted
	var skills := {}


func _build(unlimited := false) -> BuildMode:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	var s := GameState.new_run(7)
	s.cheats["unlimited"] = unlimited
	_learn_all(s)
	var b := BuildMode.new()
	b.setup(w, s, null, null)
	add(b)
	await physics_frames(2)
	return b


## Agent R's research (when merged): a new run knows no skills, so learn them
## all for tests that are not about the locks.
static func _research() -> Variant:
	return load("res://src/research/research.gd") if ResourceLoader.exists("res://src/research/research.gd") else null


static func _learn_all(s: GameState) -> void:
	var r: Variant = _research()
	if r != null:
		r.learn_all(s)


func test_every_piece_has_a_category_and_a_drawable_icon() -> void:
	check_eq(BuildCatalog.count(), 8, "eight categories")
	for c in BuildCatalog.CATEGORIES:
		check(UiIcons.has(c["icon"]), "category %s has a pixel icon" % c["id"])
		check_eq(BuildPieces.SLOTS[BuildCatalog.index_of(c["id"])]["name"], c["name"], "BuildPieces.SLOTS mirrors %s" % c["id"])
	var seen := 0
	for i in BuildPieces.LIST.size():
		var id: String = BuildPieces.LIST[i]["id"]
		check(BuildCatalog.category_index_of(i) >= 0, "%s has a category" % id)
		check(UiIcons.has(BuildCatalog.icon_of(i)), "%s has a pixel icon (%s)" % [id, BuildCatalog.icon_of(i)])
		check(BuildPieces.variants(BuildPieces.slot_of(i)).has(i), "%s is listed in its category" % id)
		seen += 1
	var total := 0
	for c in BuildCatalog.count():
		total += BuildPieces.variants(c).size()
	check_eq(total, seen, "every piece is in exactly one category")
	check_eq(BuildCatalog.category_of(BuildPieces.index_of("rug")), "decor", "the rug is a decoration")
	check_eq(BuildCatalog.category_of(BuildPieces.index_of("move")), "tools", "Move is a tool")
	check_eq(BuildCatalog.category_of(BuildPieces.index_of("fuse_box")), "utilities", "the fuse box is a utility")
	# Exp 006 (D, B): the defences and the new house pieces get their own icons
	for pair in [["spikes_wood", "spikes"], ["trench", "trench"], ["trench_water", "moat"], ["drawbridge_1", "bridge"],
			["timber_footing", "slab"], ["remove_window", "window"], ["tv_stand", "tv"], ["radio", "radio"]]:
		var i := BuildPieces.index_of(pair[0])
		if i >= 0:
			check_eq(UiIcons.resolve(BuildCatalog.icon_of(i)), pair[1], "%s's icon" % pair[0])
	if BuildPieces.index_of("trench") >= 0:
		check_eq(BuildCatalog.category_of(BuildPieces.index_of("trench")), "defense", "trenches are fortifications")
		check_eq(BuildCatalog.note_for(BuildPieces.LIST[BuildPieces.index_of("trench")]), "shovel, free", "a trench tile names its tool")


func test_new_entries_bring_their_own_category_and_icon() -> void:
	# What the other agents add: "cat" and "icon" win; only an old "slot" falls back.
	check_eq(BuildCatalog.category_for({"id": "spikes_wood", "cat": "defense", "slot": 1}), "defense", "cat wins")
	check_eq(BuildCatalog.icon_for({"id": "spikes_wood", "cat": "defense", "icon": "spikes"}), "spikes", "its own icon")
	check_eq(UiIcons.resolve(BuildCatalog.icon_for({"id": "x", "cat": "utilities", "icon": "no_such_icon"})), "gear", "an unknown icon: the category's")
	check_eq(BuildCatalog.category_for({"id": "y", "slot": 9}), "floors", "only a slot: the old slot's category")
	check_eq(BuildCatalog.category_for({"id": "wall", "cat": "nonsense"}), "walls", "an unknown cat: the table")


func test_lock_reason_reads_research_or_the_skills() -> void:
	check_eq(BuildCatalog.lock_reason(GameState.new_run(1), {"id": "chair", "cost": {}}), "", "a real state: plain pieces stay open")
	if _research() != null:
		# Agent R's gates (Research.GATES): a new run knows nothing yet.
		var s := GameState.new_run(1)
		var md: Dictionary = BuildPieces.LIST[BuildPieces.index_of("metal_door")]
		check(BuildCatalog.lock_reason(s, md) != "", "the metal door is locked at first (%s)" % BuildCatalog.lock_reason(s, md))
		_learn_all(s)
		check_eq(BuildCatalog.lock_reason(s, md), "", "and open once learned")
		return
	# Without R's code: the entry's "requires" against state.skills.
	var piece := {"id": "metal_spikes", "cat": "defense", "requires": "metalworking", "cost": {}}
	var st := FakeState.new()
	check_eq(BuildCatalog.lock_reason(st, piece), "Requires Metalworking", "the fallback names the skill")
	check_eq(BuildCatalog.lock_reason(st, {"id": "chair", "cost": {}}), "", "no requirement, no lock")
	st.skills["metalworking"] = true
	check_eq(BuildCatalog.lock_reason(st, piece), "", "known skill: unlocked")


func test_tiles_show_costs_against_what_is_available() -> void:
	var b: BuildMode = await _build(false)
	var s: GameState = b.state
	b.set_active(true)
	b.select_id("sofa")
	await frames(1)
	var sofa := BuildPieces.index_of("sofa")
	var have_wood := BuildCatalog.available(b, "wood")
	check_eq(have_wood, s.inventory.count("wood"), "without a house supply, the inventory counts")
	var t = b.palette.tile_of(sofa)
	check(t != null and t.button_pressed, "the sofa's tile is shown and selected")
	var need := BuildCatalog.missing(b, BuildPieces.LIST[sofa]["cost"])
	check_eq(t.dimmed(), not need.is_empty(), "dimmed exactly when something is missing (%s)" % str(need))
	# take everything away: dimmed, the missing numbers named
	for m in BuildCatalog.MATERIALS:
		s.inventory.remove(m, s.inventory.count(m))
	b.palette.refresh()
	check(t.dimmed() and t.missing.has("wood"), "no planks: dimmed, wood missing")
	b._refresh_palette()
	check(b.palette._missing.visible and b.palette._missing.text.contains("planks"), "the detail line says what is missing (%s)" % b.palette._missing.text)
	# the unlimited cheat pays for everything
	s.cheats["unlimited"] = true
	b.palette.refresh()
	check(not t.dimmed(), "unlimited: nothing missing")


func test_quick_keys_recent_row_and_level_header() -> void:
	var b: BuildMode = await _build(true)
	b.set_active(true)
	await frames(1)
	b.select_id("door")
	b.select_id("wall")
	b.select_id("repair")
	check_eq(b.recent.slice(0, 3), ["repair", "wall", "door"], "newest first")
	b.select_previous()
	check_eq(b.piece_id(), "wall", "Q: the piece before")
	b.select_previous()
	check_eq(b.piece_id(), "repair", "Q again: back")
	b.palette.refresh()
	check(b.palette._recent_box.visible, "the Recent row shows")
	b.plane_y = Levels.base_y(1)
	b.palette.refresh()
	check(b.palette.level_text().contains("Level +1"), "building on the first upper floor (%s)" % b.palette.level_text())
	check_eq(b.palette.slot_labels()[4], "5 Furniture", "tab labels carry the key")


func test_pixel_icons_and_font_sizes() -> void:
	for n in UiIcons.names():
		var rows: Array = UiIcons.PIXELS[n]
		check_eq(rows.size(), UiIcons.GRID, "%s: 12 rows" % n)
		for r in rows:
			check(str(r).length() == UiIcons.GRID, "%s: 12 columns" % n)
	for alias in UiIcons.ALIASES:
		check(UiIcons.has(alias), "alias %s resolves" % alias)
	for k in ["inventory", "construction", "demolish", "weapons", "food", "water", "health", "energy", "mood",
			"storage", "skills", "scavenging", "electricity", "defence", "lock"]:
		check(UiIcons.has(k), "the set has %s" % k)
	check_eq(UiIcons.texture("hammer", 24).get_size(), Vector2(24, 24), "textures at 2x")
	check_eq(UiTheme.px(13), 16, "small sizes snap to the font's 16 px design")
	check_eq(UiTheme.px(22), 16, "and so do the old title sizes")
	check_eq(UiTheme.px(26), 32, "big numbers: 2x")
	check(UiTheme.theme().default_font.resource_path.ends_with("PixelOperator.ttf"), "the theme uses Pixel Operator")
	var l := UiTheme.make_label("x", 13)
	check_eq(l.get_theme_font_size("font_size"), 16, "make_label snaps 13 to 16")
	check(UiTheme.make_title("Build").get_theme_font("font").resource_path.ends_with("PixelOperator8.ttf"), "titles: the 8 px face")
	check_eq(UiTheme.make_section("Supplies", "food").get_child_count(), 3, "a section with an icon")
