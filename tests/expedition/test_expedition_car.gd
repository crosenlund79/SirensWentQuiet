extends "res://tests/test_case.gd"
## Experiment 004 (E): the pine woods (the 25th place) and the repaired car as
## expedition equipment: only when repaired and fuelled, one fuel can a trip,
## shorter travel, much more loot (heavy loads too); and its repair rules.

const D := preload("res://src/expedition/expedition_data.gd")
const Car := preload("res://src/game/game_car.gd")


func _state(seed: int) -> GameState:
	var s := GameState.new_run(seed)
	s.total_minutes = 8.0 * 60.0
	s.inventory.storage_crates = 6              # room for big hauls
	return s


func test_the_pine_woods_are_a_known_low_risk_wood_source_on_the_map() -> void:
	check(RegionLocations.has("forest") and D.has_destination("forest"), "the forest is a place")
	check(RegionState.new_region().is_discovered("forest"), "known from the start")
	check("forest" in D.ORDER, "listed")
	var d := D.destination("forest")
	check_eq(D.resources("forest")[0], "wood", "planks first")
	check_eq(D.risk_name(D.danger_for(null, "forest", {})), "Low", "low risk bare-handed")
	check(RegionLocations.travel_minutes("forest") <= 20, "near home (%d min)" % RegionLocations.travel_minutes("forest"))
	for e in d["events"]:
		check(not D.event(e).is_empty(), "event %s exists" % e)
	var t := RegionTerrain.shared()
	var c := RegionTerrain.cell_of(RegionLocations.get_def("forest")["pos"])
	check_eq(t.cover[RegionTerrain.idx(c)], RegionTerrain.C_FOREST, "forest cover on the map")
	var s := _state(31)
	var wood := 0
	for i in 6:
		s.run["expeditions"] = i
		wood += int(ExpeditionRun.simulate(s, "forest", D.default_gear(s, "forest")).get("gained", {}).get("wood", 0))
	check(wood >= 6 * 8, "lots of planks (%d over 6 trips)" % wood)


func test_the_car_comes_along_only_repaired_and_fuelled_and_burns_one_can() -> void:
	var s := _state(41)
	check(not D.default_gear(s, "scrapyard").has(D.CAR), "a broken car stays home")
	s.car_repaired = true
	check(D.car_state(s) != "", "no fuel, no car")
	s.inventory.add("fuel", 2)
	check(D.can_drive(s), "repaired and fuelled")
	var g := D.default_gear(s, "scrapyard")
	check_eq(int(g.get(D.CAR, 0)), 1, "the car comes along by default")
	check(D.nominal_minutes("scrapyard", "general", true) < D.nominal_minutes("scrapyard"), "driving is faster")
	var walk_g := g.duplicate()
	walk_g[D.CAR] = 0
	var walk := ExpeditionRun.simulate(s, "scrapyard", walk_g)
	var drive := ExpeditionRun.simulate(s, "scrapyard", g)
	check(drive["car"] and not walk["car"], "the result says how")
	check_eq(drive["consumed"].get("fuel", 0), D.CAR_FUEL, "one fuel can")
	check(int(drive["minutes"]) < int(walk["minutes"]), "back sooner (%d vs %d min)" % [drive["minutes"], walk["minutes"]])
	var sum := func(r: Dictionary) -> int:
		var n := 0
		for id in ["wood", "stone", "iron", "scrap"]:
			n += int(r["gained"].get(id, 0)) + int(r["left_behind"].get(id, 0))
		return n
	check(sum.call(drive) >= 2 * sum.call(walk), "far more materials by car (%d vs %d)" % [sum.call(drive), sum.call(walk)])
	var before := s.inventory.count("fuel")
	s.apply_expedition(drive)
	check_eq(s.inventory.count("fuel"), before - 1 + int(drive["gained"].get("fuel", 0)), "the can is spent")


func test_the_repair_needs_every_part() -> void:
	var s := _state(51)
	check_eq(Car.missing(s).size(), Car.REPAIR_COST.size() - 1, "only the nails are there at the start (%s)" % Car.missing(s))
	for id in Car.REPAIR_COST:
		s.inventory.add(id, Car.REPAIR_COST[id])
	check(Car.missing(s).is_empty(), "ready with every part")
	check(Car.needs_text(s).contains("Car battery 1/1"), "the list counts what's there")
	var parts := 0
	for loc in ["scrapyard", "hardware", "construction_site", "police", "farmhouse"]:
		var r := D.possible_rewards(loc)
		parts += int("fuel" in r) + int("car_battery" in r)
	check(parts >= 8, "parts and fuel at the fitting places (%d)" % parts)
