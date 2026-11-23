extends "res://tests/test_case.gd"
## Invasion schedule: due once, sleep ends exactly at it, next one scheduled,
## size progression, forced (dev) invasions and the readable schedule text.

const T := preload("res://src/survival/survival_tuning.gd")
const DAY3_22 := 2 * 1440.0 + 22 * 60.0
const DAY6_22 := 5 * 1440.0 + 22 * 60.0


func _count(ev: Array, type: String) -> int:
	return ev.filter(func(e): return e["type"] == type).size()


func _state() -> GameState:
	var s := GameState.new_run(9)
	s.cheats["invulnerable"] = true
	return s


func test_first_invasion_due_once_in_small_steps() -> void:
	var s := _state()
	var n := 0
	while s.total_minutes < DAY3_22 + 600.0:
		n += _count(s.advance(7.0), "invasion_due")
	check_eq(n, 1, "invasion_due reported exactly once even if never started")
	check(s.run["invasion_announced"], "announced")
	n = 0
	for i in 20:
		n += _count(s.advance(1440.0), "invasion_due")
	check_eq(n, 0, "not again while the announced one is pending")


func test_long_skip_over_several_slots_reports_one() -> void:
	var s := _state()
	var ev := s.advance(10 * 1440.0)
	check_eq(_count(ev, "invasion_due"), 1, "one invasion_due over 10 days")


func test_plan_sleep_ends_exactly_at_the_invasion() -> void:
	var s := _state()
	for start in [DAY3_22 - 120.0, DAY3_22 - 333.3333333, DAY3_22 - 0.0004, DAY3_22 - 1.0 / 3.0]:
		s = _state()
		s.total_minutes = start
		var plan := s.plan_sleep(600.0)
		check(plan["interrupted"] and plan["reason"] == "invasion", "interrupted by the invasion from %f" % start)
		check(absf(plan["minutes"] - (DAY3_22 - start)) < 1e-6, "minutes until due from %f" % start)
		var ev := s.advance(plan["minutes"], true)
		check_eq(_count(ev, "invasion_due"), 1, "the sleep's advance reports it (from %f)" % start)
		check_eq(s.total_minutes, DAY3_22, "woke exactly at 22:00 (from %f)" % start)
		check_eq(s.advance(0.5), [], "nothing more right after")
	s = _state()
	var plan := s.plan_sleep(300.0)
	check(not plan["interrupted"] and plan["minutes"] == 300.0, "no interruption far from the invasion")
	check_eq(s.plan_sleep(-5.0)["minutes"], 0.0, "negative request")
	check_eq(s.plan_sleep(NAN)["minutes"], 0.0, "NaN request")
	check_eq(s.plan_sleep(1e9)["minutes"], T.MAX_SLEEP_MINUTES, "clamped request")


func test_start_and_end_schedule_the_next() -> void:
	var s := _state()
	s.advance(DAY3_22 - s.total_minutes)
	check_eq(s.invasion_size(), 3, "first invasion: 3")
	s.start_invasion()
	check(s.run["invasion_active"], "active")
	check_eq(s.can_sleep(), "Not with them out there.", "no sleep during an invasion")
	check_eq(s.plan_sleep(60.0)["minutes"], 0.0, "plan_sleep refuses during an invasion")
	check_eq(s.force_invasion_now(), false, "can't force while one runs")
	var ev := s.advance(8 * 60.0)
	check_eq(_count(ev, "invasion_due"), 0, "nothing due while active")
	s.end_invasion(true)
	check(not s.run["invasion_active"] and not s.run["invasion_announced"], "ended")
	check_eq(s.run["invasions_done"], 1, "counted")
	check_eq(s.run["next_invasion_at"], DAY6_22, "next on Day 6 at 22:00")
	s.end_invasion(true)
	check_eq(s.run["invasions_done"], 1, "a second end_invasion is ignored")
	ev = s.advance(DAY6_22 - s.total_minutes)
	check_eq(_count(ev, "invasion_due"), 1, "second invasion due")
	check_eq(s.invasion_size(), 5, "second invasion: 5")


func test_size_and_strength_progression() -> void:
	var s := _state()
	var sizes := []
	var hps := []
	for k in 7:
		sizes.append(s.invasion_size())
		hps.append(s.invasion_enemy_hp())
		s.run["invasions_done"] = k + 1
	check_eq(sizes, [3, 5, 7, 9, 11, 11, 11], "3 + 2 (k - 1), capped at 11")
	check_eq(hps, [3, 3, 4, 4, 5, 5, 6], "HP 3 + floor((k - 1) / 2)")
	s.run["invasions_done"] = 2
	check(absf(s.invasion_speed_scale() - 1.1) < 1e-9, "speed x1.1 in invasion 3")
	check(absf(s.enemy_damage() - 12.0 * 1.2) < 1e-9, "hit 14.4 in invasion 3")


func test_due_soon_window() -> void:
	var s := _state()
	s.total_minutes = DAY3_22 - 10 * 60.0 - 1.0
	check(not s.invasion_due_soon(), "not before 12:00")
	s.total_minutes = DAY3_22 - 10 * 60.0
	check(s.invasion_due_soon(), "from 12:00")
	s.total_minutes = DAY3_22 - 1.0
	check(s.invasion_due_soon(), "until it is due")
	s.advance(2.0)
	check(not s.invasion_due_soon(), "not once announced")


func test_force_invasion_now() -> void:
	var s := _state()
	s.advance(180.0)   # Day 1 10:00
	check(s.force_invasion_now(), "forced")
	check(s.invasion_due_soon(), "warned")
	check_eq(s.plan_sleep(60.0)["reason"], "invasion", "no sleeping through a forced invasion")
	check_eq(s.next_invasion_text(), "Due now (invasion 1)", "text while forced")
	var ev := s.advance(0.5)
	check_eq(_count(ev, "invasion_due"), 1, "the next advance reports it")
	check_eq(ev[0]["at"], 600.0, "due now")
	check_eq(s.force_invasion_now(), false, "can't force twice")
	check_eq(_count(s.advance(1.0), "invasion_due"), 0, "not twice")
	s.start_invasion()
	check_eq(s.next_invasion_text(), "In progress (invasion 1)", "text while active")
	s.advance(30.0)
	s.end_invasion(true)
	check_eq(s.run["next_invasion_at"], DAY6_22, "a forced invasion replaces the upcoming one")
	check_eq(s.invasion_size(), 5, "it counted")
	var n := 0
	while s.total_minutes < DAY6_22 + 60.0:
		n += _count(s.advance(240.0), "invasion_due")
	check_eq(n, 1, "only the Day 6 invasion afterwards")


func test_next_invasion_text() -> void:
	var s := _state()
	check_eq(s.next_invasion_text(), "Day 3, 22:00 (in 63 h 00 min)", "from Day 1 07:00")
	s.total_minutes = DAY3_22 - 45.0
	check_eq(s.next_invasion_text(), "Day 3, 22:00 (in 45 min)", "close")


func test_restored_overdue_invasion_is_reported_once() -> void:
	var s := _state()
	s.total_minutes = DAY3_22 + 60.0       # a save made at 23:00 with the invasion not yet reported
	var t := GameState.from_dict(s.to_dict())
	t.cheats["invulnerable"] = true
	var ev := t.advance(1.0)
	check_eq(_count(ev, "invasion_due"), 1, "late invasion reported on the next advance")
	check_eq(_count(t.advance(60.0), "invasion_due"), 0, "only once")
	t.start_invasion()                     # saved mid-invasion (the game blocks this, but be safe)
	t = GameState.from_dict(t.to_dict())
	t.cheats["invulnerable"] = true
	check(not t.run["invasion_active"], "restored without a running invasion")
	check_eq(_count(t.advance(1.0), "invasion_due"), 1, "it is due again")
	t.start_invasion()
	t.end_invasion(true)
	check_eq(t.run["next_invasion_at"], DAY6_22, "and the schedule moves on")
	check_eq(t.run["invasions_done"], 1, "counted once")
	s = _state()
	s.advance(DAY3_22 - s.total_minutes)   # announced, never started, then saved
	t = GameState.from_dict(s.to_dict())
	check_eq(_count(t.advance(1.0), "invasion_due"), 1, "an announced invasion is reported again after loading")
	s.total_minutes = DAY3_22 + 20 * 60.0  # long stale: rescheduled instead of a daytime attack
	s.run["invasion_announced"] = false
	t = GameState.from_dict(s.to_dict())
	check_eq(t.run["next_invasion_at"], DAY6_22, "stale schedule moved to the next slot")
