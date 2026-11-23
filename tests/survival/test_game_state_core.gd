extends "res://tests/test_case.gd"
## Foundation checks of the survival core contract (S extends in its own files).


func test_new_run_starting_conditions() -> void:
	var s := GameState.new_run(7)
	check_eq(s.day(), 1, "day 1")
	check_eq(s.clock_text(), "07:00", "07:00")
	check_eq(s.inventory.count("ammo"), 9, "nine bullets")
	check(s.night_amount() < 0.01, "daylight at 07:00")


func test_advance_reports_events_once_and_decays() -> void:
	var s := GameState.new_run(7)
	var h0 := s.hunger
	var ev := s.advance(24 * 60.0)
	var kinds := ev.map(func(e): return e["type"])
	check("dusk" in kinds and "new_day" in kinds and "dawn" in kinds, "dusk, new day and dawn crossed (%s)" % [kinds])
	check_eq(s.day(), 2, "day 2")
	check(absf((h0 - s.hunger) - 24 * SurvivalTuning.HUNGER_PER_HOUR) < 0.01, "hunger decayed exactly one day")


func test_costs_are_atomic_and_unlimited_cheat_is_free() -> void:
	var s := GameState.new_run(7)
	check(not s.pay({"wood": 100, "nails": 1}), "can't pay what you don't have")
	check_eq(s.inventory.count("nails"), 12, "nothing deducted on failure")
	s.cheats["unlimited"] = true
	check(s.pay({"wood": 100}), "unlimited pays")
	check_eq(s.inventory.count("wood"), 6, "unlimited deducts nothing")


func test_expedition_applies_once() -> void:
	var s := GameState.new_run(7)
	var r := {"id": "x1", "minutes": 120, "gained": {"water": 2}, "consumed": {"ammo": 50}}
	s.apply_expedition(r)
	s.apply_expedition(r)
	check_eq(s.inventory.count("water"), 6, "water added once")
	check_eq(s.inventory.count("ammo"), 0, "over-consumption clamped to what was there, never negative")
	check_eq(s.clock_text(), "09:00", "time advanced once")


func test_round_trip() -> void:
	var s := GameState.new_run(7)
	s.advance(300)
	s.inventory.add("scrap", 3)
	var t := GameState.from_dict(s.to_dict())
	check(t != null, "restored")
	check_eq(t.clock_text(), s.clock_text(), "clock")
	check_eq(t.inventory.count("scrap"), 3, "inventory")
	check(GameState.from_dict({"bogus": 1}) == null, "invalid dict rejected")
