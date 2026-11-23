extends "res://tests/test_case.gd"
## Sleep rules, straggler rolls (deterministic) and rain collectors.

const T := preload("res://src/survival/survival_tuning.gd")


func _night_minute(s: float, day: int) -> float:
	return s - (day - 1) * 1440.0


func test_can_sleep() -> void:
	var s := GameState.new_run(2)
	s.energy = 50.0
	check_eq(s.can_sleep(), "", "tired by day")
	s.energy = 96.0
	check_eq(s.can_sleep(), "You're not tired.", "rested by day")
	s.total_minutes = 23 * 60.0
	check_eq(s.can_sleep(), "", "anyone can sleep at night")
	s.force_invasion_now()
	check_eq(s.can_sleep(), "Not with them out there.", "not with an invasion due")


func test_straggler_rolls_are_deterministic_and_follow_the_rules() -> void:
	var a := GameState.new_run(1234)
	var b := GameState.new_run(1234)
	var hits := 0
	for d in range(1, 40):
		check_eq(a.roll_straggler(d), b.roll_straggler(d), "same seed, same night %d" % d)
	check_eq(a.roll_straggler(1), -1.0, "never on Day 1")
	for d in [3, 6, 9, 12]:
		check_eq(a.roll_straggler(d), -1.0, "never on invasion night %d" % d)
	for seed_i in range(1, 2001):
		var s := GameState.new_run(seed_i)
		var m := s.roll_straggler(2)
		if m >= 0.0:
			hits += 1
			var local := _night_minute(m, 2)
			check(local >= T.STRAGGLER_WINDOW.x and local < T.STRAGGLER_WINDOW.y, "between 23:00 and 03:00 (seed %d: %f)" % [seed_i, local])
			check_eq(m, floorf(m), "whole minute")
	check(hits > 600 and hits < 800, "about 35 %% of nights (%d of 2000)" % hits)
	var differs := false
	for d in range(2, 30):
		if GameState.new_run(1).roll_straggler(d) != GameState.new_run(2).roll_straggler(d):
			differs = true
	check(differs, "different seeds, different nights")


func test_round_trip_keeps_straggler_rolls() -> void:
	var s := GameState.new_run(77)
	var t := GameState.from_dict(s.to_dict())
	for d in range(2, 20):
		check_eq(t.roll_straggler(d), s.roll_straggler(d), "night %d" % d)


func test_sleep_is_interrupted_by_a_straggler() -> void:
	var seed_i := 1
	while GameState.new_run(seed_i).roll_straggler(2) < 0.0:
		seed_i += 1
	var s := GameState.new_run(seed_i)
	var at := s.roll_straggler(2)
	s.total_minutes = 1440.0 + 22 * 60.0     # Day 2 22:00
	var plan := s.plan_sleep(8 * 60.0)
	check(plan["interrupted"] and plan["reason"] == "straggler", "woken by the straggler (%s)" % [plan])
	check(absf(plan["minutes"] - (at - s.total_minutes)) < 1e-3, "minutes until it arrives")
	s.advance(plan["minutes"], true)
	check(s.total_minutes >= at, "the clock reached the straggler's minute")
	var again := s.plan_sleep(8 * 60.0)
	check(not again["interrupted"], "the same straggler does not wake you twice (%s)" % [again])
	# from after midnight the same night's straggler still counts
	s = GameState.new_run(seed_i)
	s.total_minutes = at - 30.0
	check_eq(s.plan_sleep(600.0)["reason"], "straggler", "from 30 min before (day %d)" % s.day())


func test_on_dawn_rain_collectors() -> void:
	var s := GameState.new_run(5)
	s.cheats["invulnerable"] = true
	s.advance(s.until_morning_minutes())   # Day 2 06:00
	check_eq(s.on_dawn(2), {"water": 2}, "+1 water per collector")
	check_eq(s.inventory.count("water"), 6, "added")
	check_eq(s.on_dawn(2), {}, "once per day")
	check_eq(s.on_dawn(0), {}, "no collectors")
	check_eq(s.on_dawn(-3), {}, "negative")
	s.advance(1440.0)
	check_eq(s.on_dawn(1), {"water": 1}, "next dawn")
	var ev := s.advance(3 * 1440.0)
	var got := 0
	for e in ev:
		if e["type"] == "dawn":
			got += s.on_dawn(2, e["at"]).get("water", 0)
	check_eq(got, 6, "every dawn of a three-day skip counts")
	check_eq(s.on_dawn(2), {}, "and today is done")
	check_eq(s.on_dawn(2, 1e12), {}, "a future time is treated as today")
