extends "res://tests/test_case.gd"
## Inventory caps (with crates), atomic removal, untrusted amounts, from_dict.


func test_caps_and_crates() -> void:
	var inv := Inventory.new()
	check_eq(inv.cap("wood"), 40, "wood cap")
	check_eq(inv.add("wood", 100), 40, "only 40 fit")
	check_eq(inv.space_for("wood"), 0, "full")
	inv.storage_crates = 2
	check_eq(inv.cap("wood"), 80, "+20 per crate")
	check_eq(inv.cap("nails"), 160, "+40 per crate")
	check_eq(inv.cap("scrap"), 40, "+10 per crate")
	check_eq(inv.add("wood", 100), 40, "40 more fit with two crates")
	inv.storage_crates = 0
	check_eq(inv.count("wood"), 80, "losing a crate keeps what is stored")
	check_eq(inv.add("wood", 1), 0, "but nothing more fits")
	inv.storage_crates = -4
	check_eq(inv.storage_crates, 0, "crates never negative")
	check_eq(inv.cap("ammo"), 0, "ammo uncapped")
	check_eq(inv.add("ammo", 500), 500, "uncapped add")
	check_eq(inv.cap("hammer"), 1, "one of each tool")
	check_eq(inv.add("hammer", 3), 1, "a second hammer does not fit")
	check_eq(inv.add("unknown_thing", 5), 0, "unknown items refused")
	check_eq(inv.space_for("unknown_thing"), 0, "no space for unknown items")


func test_untrusted_amounts() -> void:
	var inv := Inventory.new()
	for v in [-3, NAN, INF, null, "abc", [1], {"a": 1}, true]:
		check_eq(inv.add("water", v), 0, "add(%s) adds nothing" % [v])
	check_eq(inv.add("water", 2.6), 3, "floats round")
	check_eq(inv.add("water", "4"), 4, "numeric strings parse")
	check_eq(inv.count("water"), 7, "count")
	for v in [-1, NAN, null, "x"]:
		check(not inv.remove("water", v), "remove(%s) fails" % [v])
	check(inv.remove("water", 0), "removing nothing succeeds")
	check_eq(inv.count("water"), 7, "unchanged")
	check(not inv.remove("water", 8), "all or nothing")
	check(inv.remove("water", 7), "remove all")
	check(not inv.counts.has("water"), "zero counts are erased")
	check_eq(inv.count(5), 0, "non-string id")


func test_costs_are_atomic() -> void:
	var inv := Inventory.new()
	inv.add("wood", 10)
	inv.add("nails", 5)
	check(not inv.remove_all({"wood": 4, "nails": 6}), "short on nails")
	check_eq([inv.count("wood"), inv.count("nails")], [10, 5], "nothing taken")
	check(not inv.has_all({"wood": 1, "mystery": 1}), "unknown item can't be paid")
	check(not inv.has_all({"wood": "lots"}), "non-numeric amount can't be paid")
	check(inv.has_all({"wood": 0, "nails": -5}), "zero and negative amounts need nothing")
	check(inv.remove_all({"wood": 4, "nails": 5, "scrap": 0}), "paid")
	check_eq([inv.count("wood"), inv.count("nails")], [6, 0], "taken")
	check(inv.remove_all({"wood": -10}), "negative cost pays nothing")
	check_eq(inv.count("wood"), 6, "and creates nothing")


func test_changed_signal() -> void:
	var inv := Inventory.new()
	var hits := [0]
	inv.changed.connect(func(): hits[0] += 1)
	inv.add("wood", 3)
	inv.add("wood", 0)
	inv.remove("wood", 5)
	inv.remove_all({"wood": 1, "nails": 0})
	check_eq(hits[0], 2, "one signal per real change")


func test_from_dict_sanitises() -> void:
	var inv := Inventory.new()
	inv.from_dict({"counts": {"wood": 12, "nails": -4, "scrap": NAN, "water": "5", "ghost": 3, 7: 2, "ammo": 1e12, "snacks": 2.4}, "storage_crates": "x"})
	check_eq(inv.counts, {"wood": 12, "water": 5, "ammo": Inventory.MAX_COUNT, "snacks": 2}, "only valid, positive, known counts")
	check_eq(inv.storage_crates, 0, "bad crates value")
	for v in [null, [], "junk", 5, {"counts": [1, 2]}]:
		inv.from_dict(v)
		check_eq(inv.counts, {}, "garbage %s gives an empty inventory" % [v])
	inv.from_dict({"counts": {"wood": 70}, "storage_crates": 2})
	check_eq([inv.count("wood"), inv.storage_crates], [70, 2], "values above the base cap restore with their crates")
	var round := Inventory.new()
	round.from_dict(inv.to_dict())
	check_eq(round.to_dict(), inv.to_dict(), "round trip")


func test_catalogue_matches_the_spec() -> void:
	check_eq(Items.DEFS["canned_food"]["hunger"], 30.0, "canned food")
	check_eq(Items.DEFS["water"]["hydration"], 30.0, "water")
	check_eq(Items.DEFS["medkit"]["health"], 50.0, "medkit")
	check_eq(Items.ids("tool"), ["hammer", "crowbar", "flashlight", "backpack"], "tools")
	check_eq(Items.name_of("scrap"), "Scrap metal", "name")
	check_eq(Items.name_of(3), "3", "name of junk")
	check_eq(Items.category(null), "", "category of junk")
	for id in Items.DEFS:
		check(Items.DEFS[id]["category"] in Items.CATEGORIES, "%s has a known category" % id)
