extends "res://tests/test_case.gd"
## GameState clock: event order, no duplicates, long and degenerate advances, death.

const T := preload("res://src/survival/survival_tuning.gd")


func _types(ev: Array) -> Array:
	return ev.map(func(e): return e["type"])


func _ordered(ev: Array) -> bool:
	for i in range(1, ev.size()):
		if ev[i]["at"] < ev[i - 1]["at"]:
			return false
	return true


func test_events_in_order_across_several_days() -> void:
	var s := GameState.new_run(3)
	s.cheats["invulnerable"] = true          # three days without food or water would kill
	var ev := s.advance(3 * 1440.0 + 30.0)   # Day 1 07:00 -> Day 4 07:30
	check_eq(_types(ev), ["dusk", "new_day", "dawn", "dusk", "new_day", "dawn", "dusk", "invasion_due", "new_day", "dawn"], "every boundary once, in order")
	check(_ordered(ev), "sorted by time")
	check_eq(ev[7]["at"], 2 * 1440.0 + 22 * 60.0, "invasion due on Day 3 at 22:00")
	check_eq(s.day(), 4, "day 4")
	check_eq(s.clock_text(), "07:30", "07:30")


func test_small_steps_match_one_big_step() -> void:
	var a := GameState.new_run(11)
	var b := GameState.new_run(11)
	var big := a.advance(2900.0)
	var small := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var left := 2900.0
	while left > 0.0:
		var step := minf(rng.randf_range(0.01, 7.0), left)
		small.append_array(b.advance(step))
		left -= step
	check_eq(_types(small), _types(big), "same events when advanced in random small steps")
	check(_ordered(small), "small-step events in order")
	check(absf(a.total_minutes - b.total_minutes) < 1e-6, "same clock")
	for k in ["health", "hunger", "hydration", "energy"]:
		check(absf(float(a.get(k)) - float(b.get(k))) < 1e-6, "%s identical (%f vs %f): decay applied exactly once" % [k, a.get(k), b.get(k)])


func test_long_advance_and_cap() -> void:
	var s := GameState.new_run(3)
	s.cheats["invulnerable"] = true
	var ev := s.advance(31 * 60.0)   # 31 h
	check_eq(s.day(), 2, "31 h later is Day 2")
	check_eq(s.clock_text(), "14:00", "14:00")
	check_eq(_types(ev).count("dawn"), 1, "one dawn in 31 h")
	check(absf(s.hunger - (75.0 - 31 * T.HUNGER_PER_HOUR)) < 1e-9, "hunger decayed for 31 h (%f)" % s.hunger)
	var t0 := s.total_minutes
	s.advance(1e9)
	check_eq(s.total_minutes, t0 + T.MAX_ADVANCE_MINUTES, "one call skips at most 30 days")
	check(s.hunger == 0.0 and s.hydration == 0.0 and s.health == 100.0, "starved and dehydrated but invulnerable")


func test_zero_negative_and_non_finite_input_do_nothing() -> void:
	var s := GameState.new_run(3)
	var before := s.to_dict()
	var hits := [0]
	s.changed.connect(func(): hits[0] += 1)
	for m in [0.0, -5.0, -INF, NAN, INF]:
		check_eq(s.advance(m), [], "advance(%s) reports nothing" % m)
	check_eq(s.to_dict(), before, "state unchanged")
	check_eq(hits[0], 0, "no changed signal")


func test_death_stops_the_clock_and_reports_only_earlier_events() -> void:
	var s := GameState.new_run(3)
	s.total_minutes = 19 * 60.0
	s.hunger = 0.0
	s.hydration = 100.0
	s.health = 10.0
	var deaths := []
	s.died.connect(func(c): deaths.append([c, s.total_minutes]))
	var ev := s.advance(10 * 60.0)
	check(s.dead, "starved to death")
	check_eq(deaths.size(), 1, "died emitted once")
	check_eq(s.death_cause, "starvation", "cause")
	check(absf(s.total_minutes - (19 * 60.0 + 150.0)) < 1e-6, "clock stopped at the moment of death (21:30), got %f" % s.total_minutes)
	check(absf(deaths[0][1] - s.total_minutes) < 1e-6, "died listeners see the time of death")
	check_eq(_types(ev), ["dusk"], "only the events before death")
	# after death: nothing moves
	var after := s.to_dict()
	check_eq(s.advance(600.0), [], "no events after death")
	check_eq(s.advance(600.0, true), [], "no events asleep after death")
	s.damage(10.0, "psycho")
	s.heal(50.0)
	check_eq(s.to_dict(), after, "no changes after death (the clock does not move either)")
	check_eq(deaths.size(), 1, "still one died signal")


func test_until_morning_lands_on_dawn() -> void:
	var s := GameState.new_run(3)
	s.cheats["invulnerable"] = true
	for start in [7 * 60.0 + 0.123456789, 23 * 60.0 + 59.999999, 1440.0 * 5 + 5 * 60.0 + 59.9999999, 1440.0 * 2 + 6 * 60.0]:
		s.total_minutes = start
		var ev := s.advance(s.until_morning_minutes(), true)
		check_eq(s.clock_text(), "06:00", "woke at 06:00 from %f" % start)
		check_eq(fposmod(s.total_minutes, 1440.0), 360.0, "exactly at dawn from %f" % start)
		check("dawn" in _types(ev), "dawn reported from %f" % start)


func test_night_amount_and_derived_clock() -> void:
	var s := GameState.new_run(3)
	for pair in [[12 * 60.0, 0.0], [23 * 60.0, 1.0], [3 * 60.0, 1.0], [21 * 60.0, 1.0], [19.5 * 60.0, 0.0]]:
		s.total_minutes = 1440.0 + pair[0]
		check(absf(s.night_amount() - pair[1]) < 1e-6, "night amount at %s" % s.clock_text())
	s.total_minutes = 1440.0 + 6 * 60.0
	check(s.night_amount() > 0.0 and s.night_amount() < 1.0, "ramping at 06:00")
	check(not s.is_night(), "06:00 counts as day (amount %f)" % s.night_amount())
	s.total_minutes = 1440.0 * 4 + 61.5
	check_eq(s.day(), 5, "day from total minutes")
	check_eq(s.clock_text(), "01:01", "clock text")
	s.total_minutes = NAN
	check_eq(s.day(), 5, "NaN assignment ignored")
