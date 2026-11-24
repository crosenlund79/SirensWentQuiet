extends "res://tests/test_case.gd"
## Processing raw materials (SPEC-003 §2): the workbench's scrap -> iron.


func test_three_scrap_make_one_iron() -> void:
	var s := GameState.new_run(4)
	s.inventory.add("scrap", 10)
	var r := Crafting.convert_scrap(s)
	check(r["ok"], "made")
	check_eq(r["units"], 1, "one unit")
	check_eq(r["used"], {"scrap": 3}, "used")
	check_eq(r["made"], {"iron": 1}, "made")
	check_eq([s.inventory.count("scrap"), s.inventory.count("iron")], [7, 1], "inventory")
	r = Crafting.convert_scrap(s, 5)
	check_eq(r["units"], 2, "as many as the scrap allows")
	check_eq([s.inventory.count("scrap"), s.inventory.count("iron")], [1, 3], "1 scrap left over")
	r = Crafting.convert_scrap(s)
	check(not r["ok"], "not enough scrap")
	check_eq(r["reason"], "You need 3 scrap metal.", "reason")
	check_eq(Crafting.can_process(s, "iron"), "You need 3 scrap metal.", "can_process agrees")
	check_eq(Crafting.max_units(s, "iron"), 0, "none possible")
	check(Items.is_raw("scrap") and not Items.is_raw("iron"), "scrap is raw, iron is usable")


func test_iron_cap_limits_the_output() -> void:
	var s := GameState.new_run(4)
	s.inventory.add("iron", 19)
	s.inventory.add("scrap", 20)
	check_eq(Crafting.max_units(s, "iron"), 1, "one more iron fits (cap 20)")
	var r := Crafting.convert_scrap(s, 4)
	check_eq(r["units"], 1, "only one made")
	check_eq(s.inventory.count("scrap"), 17, "only its scrap used")
	r = Crafting.convert_scrap(s)
	check(not r["ok"], "iron full")
	check_eq(r["reason"], "No room for more iron.", "reason")
	check_eq(s.inventory.count("scrap"), 17, "nothing used")
	s.inventory.storage_crates = 1
	check_eq(Crafting.max_units(s, "iron"), 5, "a crate makes room for 10 more; 17 scrap make 5")


func test_unlimited_cheat_and_bad_input() -> void:
	var s := GameState.new_run(4)
	s.cheats["unlimited"] = true
	var r := Crafting.convert_scrap(s, 3)
	check(r["ok"] and r["units"] == 3, "free input with the unlimited cheat")
	check_eq(r["used"], {}, "nothing used")
	check_eq(s.inventory.count("scrap"), 0, "no scrap needed")
	check_eq(s.inventory.count("iron"), 3, "the output is real")
	s.inventory.add("iron", 100)
	check(not Crafting.convert_scrap(s)["ok"], "the cap still holds")
	check(not Crafting.process(s, "gold")["ok"], "unknown recipe")
	check(not Crafting.convert_scrap(s, 0)["ok"], "zero units")
	check(not Crafting.convert_scrap(null)["ok"], "no state")
	var d := GameState.new_run(4)
	d.inventory.add("scrap", 9)
	d.dead = true
	check_eq(Crafting.convert_scrap(d)["reason"], "You're dead.", "dead")
	check_eq(d.inventory.count("scrap"), 9, "nothing used")
