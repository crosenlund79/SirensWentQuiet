extends "res://tests/test_case.gd"
## Exp 006 (R): the research tree (Research), skill books, gating in build
## mode (pieces, Reinforce steps, plating), the Woodworking repair discount,
## Metalworking at the workbench, saving, older saves (skills inferred from
## the house), the library and the books on expeditions, the gun shop, and
## the inventory's Skills tab.

const RunSave := preload("res://src/game/run_save.gd")
const D := preload("res://src/expedition/expedition_data.gd")


func _build(s: GameState) -> Array:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	var b := BuildMode.new()
	b.setup(w, s, null, null)
	add(b)
	await physics_frames(2)
	return [w, b]


func _reason(b: BuildMode, id: String, p: Vector2) -> String:
	b.select_id(id)
	return b.evaluate(p)["reason"]


func test_tree_books_and_reading() -> void:
	var s := GameState.new_run(5)
	check(s.skills.is_empty(), "a new run knows no skills")
	check_eq(Research.ORDER.size(), 4, "four skills")
	for id in Research.ORDER:
		var book := Research.book_of(id)
		check(Items.has(book) and Items.category(book) == "book" and Items.is_unique(book), "%s has a unique book item" % id)
		check_eq(Research.book_skill(book), id, "the book teaches it")
	check_eq(Research.locked_reason(s, {"id": "metal_door"}), "Requires Metalworking (read 'Metalworking Manual')", "the SPEC's reason format")
	check_eq(Research.locked_reason(s, {"id": "wall"}), "", "plain wood needs nothing")
	check_eq(Research.locked_reason(s, {"id": "spikes_metal", "requires": "metalworking"}), "Requires Metalworking (read 'Metalworking Manual')", "a piece's own requires field")
	check_eq(Research.locked_reason(s, {"id": "drawbridge_2"}), "Requires Basic woodworking (read 'Basic Woodworking')", "drawbridges need woodworking")
	check(Research.can_read(s, "book_woodworking").contains("don't have"), "no book, no reading")
	s.inventory.add("book_metalworking", 1)
	check(Research.can_read(s, "book_metalworking").contains("learn reinforced construction first"), "prerequisite first (%s)" % Research.can_read(s, "book_metalworking"))
	s.inventory.add("book_woodworking", 1)
	var r := Research.read_book(s, "book_woodworking")
	check(r["ok"] and Research.knows(s, "woodworking"), "reading teaches the skill")
	check_eq(s.inventory.count("book_woodworking"), 0, "and uses the book up")
	check(str(r["text"]).contains("Drawbridge") and str(r["text"]).contains("repairs"), "the read text names what it unlocks (%s)" % r["text"])
	check_eq(s.skills["woodworking"], s.day(), "learned today")
	check(not Research.read_book(s, "book_metalworking")["ok"], "still one step missing")
	s.inventory.add("book_reinforced", 1)
	check(Research.read_book(s, "book_reinforced")["ok"] and Research.read_book(s, "book_metalworking")["ok"], "then in order")
	check_eq(Research.known(s), ["woodworking", "reinforced", "metalworking"], "three known")
	check(Research.unlocks("metalworking").has("Metal door"), "metalworking unlocks the metal door")
	check(Research.unlocks("advanced_metal").has("Iron plating on walls"), "the last step: plating")
	Research.forget_all(s)
	check(s.skills.is_empty(), "forget all")
	Research.learn_all(s)
	check_eq(Research.known(s).size(), 4, "learn all")
	# test doubles without a skills property know everything
	check(Research.knows(RefCounted.new(), "advanced_metal"), "no research system: ungated")


func test_build_mode_gates_pieces_reinforce_and_plating() -> void:
	var s := GameState.new_run(7)
	s.cheats["unlimited"] = true
	var wb: Array = await _build(s)
	var w: HouseWorld = wb[0]
	var b: BuildMode = wb[1]
	check_eq(_reason(b, "metal_door", Vector2(14.0, 3.5)), "Requires Metalworking (read 'Metalworking Manual')", "metal door locked")
	var r := b.evaluate(Vector2(14.0, 3.5))
	check(r.get("locked", false), "the evaluation says it is locked")
	check(_reason(b, "iron_door", Vector2(14.0, 3.5)).begins_with("Requires Reinforced construction"), "reinforced door locked")
	check(_reason(b, "iron_barricade", Vector2(6.5, 11.0)).begins_with("Requires Reinforced construction"), "iron barricade locked")
	check_eq(_reason(b, "door", Vector2(14.0, 3.5)), "", "a wooden door needs nothing")
	# Reinforce: wood -> reinforced needs Reinforced construction
	check(_reason(b, "upgrade", Vector2(14.0, 6.5)).begins_with("Requires Reinforced construction"), "Reinforce on the back door is locked")
	check(_reason(b, "upgrade", Vector2(4.5, -0.05)).begins_with("Requires Advanced metal fabrication"), "plating is locked")
	check_eq(_reason(b, "upgrade", Vector2(1.5, 0.0)), "Windows can't be plated.", "the target's own reason first")
	Research.learn_with_prerequisites(s, "reinforced")
	check_eq(_reason(b, "upgrade", Vector2(14.0, 6.5)), "", "reinforcing allowed now")
	check(b.apply(Vector2(14.0, 6.5)), "reinforced")
	check(_reason(b, "upgrade", Vector2(14.0, 6.5)).begins_with("Requires Metalworking"), "the metal step needs Metalworking")
	Research.learn(s, "metalworking")
	check(b.apply(Vector2(14.0, 6.5)), "now a metal door")
	check_eq(w.object_at(Vector2(14.0, 6.5)).mat, "metal", "metal")
	check_eq(_reason(b, "metal_door", Vector2(14.0, 3.5)), "", "a new metal door is allowed")
	# built structures stay when the skills go
	Research.forget_all(s)
	check_eq(w.object_at(Vector2(14.0, 6.5)).mat, "metal", "the metal door stays after forgetting")


func test_woodworking_repair_discount_and_metalworking_workbench() -> void:
	check_eq(Research.wood_repair_cost({"wood": 4, "nails": 8, "iron": 2}), {"wood": 3, "nails": 6, "iron": 2}, "wood and nails x0.75, iron as it was")
	check_eq(Research.wood_repair_cost({"wood": 1, "nails": 1}), {"wood": 1, "nails": 1}, "never below 1")
	var s := GameState.new_run(7)
	var wb: Array = await _build(s)
	var w: HouseWorld = wb[0]
	var b: BuildMode = wb[1]
	for t in [Vector3(8.3, 1.0, 9.0), Vector3(8.6, 1.3, 9.0), Vector3(8.5, 0.6, 9.0)]:
		var o := Vector3(8.5, 1.3, 11.0)
		w.shoot(o, t - o, [])
	b.select_id("repair")
	var full: Dictionary = b.evaluate(Vector2(8.5, 9.0))["cost"]
	Research.learn(s, "woodworking")
	var cheap: Dictionary = b.evaluate(Vector2(8.5, 9.0))["cost"]
	check(not full.is_empty(), "the wall is damaged (%s)" % full)
	check_eq(cheap, Research.wood_repair_cost(full), "repairs cost a quarter less with woodworking (%s -> %s)" % [full, cheap])
	# the workbench
	s.inventory.add("scrap", 6)
	check_eq(Crafting.inputs(s, "iron"), {"scrap": 3}, "3 scrap without metalworking")
	Research.learn_with_prerequisites(s, "metalworking")
	check_eq(Crafting.inputs(s, "iron"), {"scrap": 2}, "2 with it")
	var iron := s.inventory.count("iron")
	var r := Crafting.convert_scrap(s, 3)
	check(r["ok"] and s.inventory.count("iron") == iron + 3 and s.inventory.count("scrap") == 0, "6 scrap -> 3 iron (%s)" % r)


func test_skills_save_and_older_saves_infer_from_the_house() -> void:
	var s := GameState.new_run(9)
	Research.learn(s, "woodworking", 3)
	var d := s.to_dict()
	check_eq(d["skills"], {"woodworking": 3}, "saved")
	var t := GameState.from_dict(d)
	check_eq(t.skills, {"woodworking": 3}, "restored")
	d["skills"] = {"woodworking": "x", "ghost": 2, "metalworking": 1e30}
	check_eq(GameState.from_dict(d).skills, {"woodworking": 0, "metalworking": 100000}, "cleaned")
	# an older save: no "skills"; its house has a metal door
	var old := s.to_dict()
	old.erase("skills")
	var world := {"objects": [{"kind": "door", "mat": "metal", "x": 1.0, "y": 2.0}], "upgraded": [], "levels": {}}
	var p := RunSave.parse({"state": old, "world": world, "game": {}})
	check(p["ok"], "parses")
	var st: GameState = p["state"]
	check_eq(Research.known(st), ["woodworking", "reinforced", "metalworking"], "metal door -> metalworking with its prerequisites")
	check_eq(p.get("skills_inferred", []).size(), 3, "reported")
	# plating anywhere (also on another storey) -> everything
	var world2 := {"objects": [], "levels": {"storeys": [{"upgraded": [[1, 2, 0]]}]}}
	check_eq(Research.known(RunSave.parse({"state": old, "world": world2, "game": {}})["state"]).size(), 4, "plating -> advanced metal fabrication")
	var plain := {"objects": [{"kind": "door", "mat": "wood"}, {"kind": "barricade", "mat": "wood"}], "upgraded": []}
	check(Research.known(RunSave.parse({"state": old, "world": plain, "game": {}})["state"]).is_empty(), "a plain wooden house: nothing")
	var iron := {"objects": [{"kind": "barricade", "mat": "iron"}]}
	check_eq(Research.known(RunSave.parse({"state": old, "world": iron, "game": {}})["state"]), ["woodworking", "reinforced"], "iron barricade -> reinforced")
	# a save that has the field keeps exactly it
	var newer := s.to_dict()
	newer["skills"] = {}
	check(Research.known(RunSave.parse({"state": newer, "world": world, "game": {}})["state"]).is_empty(), "a new save with no skills stays without")


func test_library_books_and_the_gun_shop_on_expeditions() -> void:
	check(D.has_destination("library") and "library" in D.ORDER and "knowledge" in D.CATEGORY_ORDER, "the library is a destination")
	var lib := D.destination("library")
	check_eq(lib["category"], "knowledge", "books and knowledge")
	var rewards := D.possible_rewards("library")
	for b in Research.books():
		check(b in rewards, "the library has %s" % b)
	check(str(lib["rewards"]).contains("a book on basic woodworking"), "rewards text names the books (%s)" % lib["rewards"])
	for e in D.event_pool("library"):
		check(not D.event(e).is_empty(), "event %s exists" % e)
	check(D.possible_rewards("hardware").has("book_woodworking") and D.possible_rewards("construction_site").has("book_reinforced")
		and D.possible_rewards("police").has("book_metalworking"), "occasional books elsewhere")
	var fresh := RegionState.new_region()
	check(fresh.is_discovered("library") and fresh.is_discovered("gun_shop"), "the library and the gun shop are known from the start")
	check(RegionState.from_dict({"discovered": ["homes"]}).is_discovered("gun_shop"), "also in an older save")
	# books turn up, but never for a known skill
	var found := 0
	var found_known := 0
	for k in 40:
		var s := GameState.new_run(100 + k)
		s.total_minutes = 8.0 * 60.0
		s.inventory.add("crowbar", 1)
		s.inventory.add("flashlight", 1)
		var res := ExpeditionRun.simulate(s, "library", {"crowbar": 1, "flashlight": 1}, [], "general", "", true)
		for b in Research.books():
			found += int(res["gained"].get(b, 0))
		Research.learn_all(s)
		var res2 := ExpeditionRun.simulate(s, "library", {"crowbar": 1, "flashlight": 1}, [], "general", "", true)
		for b in Research.books():
			found_known += int(res2["gained"].get(b, 0))
	check(found >= 20, "books are common at the library (%d in 40 trips)" % found)
	check_eq(found_known, 0, "never a book whose skill is known")
	# the gun shop: shotgun uncommon but real, shells and 9 mm likely
	var gs := D.destination("gun_shop")
	var odds := {}
	for e in gs["loot"]:
		odds[e[0]] = 1.0 - (1.0 - float(odds.get(e[0], 0.0))) * (1.0 - float(e[3]))
	check(odds.get("shotgun", 0.0) >= 0.08 and odds.get("shotgun", 0.0) <= 0.2, "shotgun on the shelves: uncommon (%s)" % odds.get("shotgun"))
	check(odds.get("ammo", 0.0) >= 0.6 and odds.get("shells", 0.0) >= 0.5, "ammunition likely")
	check(D.event_pool("gun_shop").has("gun_counter"), "the gun counter event")
	var shotguns := 0
	for k in 60:
		var s := GameState.new_run(300 + k)
		s.total_minutes = 8.0 * 60.0
		s.inventory.add("crowbar", 1)
		var res := ExpeditionRun.simulate(s, "gun_shop", {"crowbar": 1, "ammo": 6}, [], "general", "", true)
		shotguns += int(res["gained"].get("shotgun", 0))
	check(shotguns >= 6 and shotguns <= 50, "with a crowbar the shotgun turns up now and then (%d of 60)" % shotguns)


func test_skills_tab_reads_books() -> void:
	var s := GameState.new_run(11)
	var inv: InventoryPanel = add(InventoryPanel.new())
	s.inventory.add("book_woodworking", 1)
	s.inventory.add("book_metalworking", 1)
	inv.open(s, "skills")
	await frames(2)
	check_eq(inv.tab, "skills", "opens on the Skills tab")
	var rb := inv.find_child("Read_book_woodworking", true, false) as Button
	var mb := inv.find_child("Read_book_metalworking", true, false) as Button
	check(rb != null and not rb.disabled, "Read for a book that can be read")
	check(mb != null and mb.disabled and mb.tooltip_text.contains("first"), "a book read too early is disabled, with the reason")
	check(inv.find_child("Skill_advanced_metal", true, false) != null, "the tree shows every skill")
	rb.pressed.emit()
	await frames(1)
	check(Research.knows(s, "woodworking"), "Read learns the skill")
	check(inv.find_child("Read_book_woodworking", true, false) == null, "the book is gone from the tab")
	var known := inv.find_child("SkillsKnown", true, false) as Label
	check(known != null and known.text.begins_with("1 of 4"), "the tab is rebuilt (%s)" % (known.text if known != null else "?"))
	inv.close()


func test_supplies_tab_lists_carried_books_with_read() -> void:
	var s := GameState.new_run(12)
	var inv: InventoryPanel = add(InventoryPanel.new())
	inv.open(s, "supplies")
	await frames(2)
	check(inv.find_child("Row_book_woodworking", true, false) == null, "no book rows without books")
	inv.close()
	s.inventory.add("book_woodworking", 1)
	inv.open(s, "supplies")
	await frames(2)
	var rb := inv.use_button("book_woodworking")
	check(rb != null and rb.text == "Read", "a carried book has Read")
	rb.pressed.emit()
	await frames(1)
	check(Research.knows(s, "woodworking") and s.inventory.count("book_woodworking") == 0, "Read on the Supplies tab learns it")
	check(inv.find_child("Row_book_woodworking", true, false) == null, "the row is gone after the rebuild")
	inv.close()
