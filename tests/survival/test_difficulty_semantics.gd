extends "res://tests/test_case.gd"
## Difficulty in the survival core (SPEC-003 §2, §5): the start, enemy damage,
## the Experiment 002 wave numbers and the invasion schedule.

const T := preload("res://src/survival/survival_tuning.gd")
const DAY := 1440.0


func _slot(day: int) -> float:
	return (day - 1) * DAY + T.INVASION_HOUR * 60.0


func test_start_rounds_per_level() -> void:
	check_eq(GameState.new_run(3, "easy").magazine("handgun"), 12, "Easy: a full magazine")
	check_eq(GameState.new_run(3, "normal").magazine("handgun"), 9, "Normal: nine bullets still means nine")
	check_eq(GameState.new_run(3, "hard").magazine("handgun"), 9, "Hard: nine")
	check_eq(GameState.new_run(3).difficulty, "normal", "default Normal")
	check_eq(GameState.new_run(3, "nightmare").difficulty, "normal", "unknown level: Normal")
	for lv in Difficulty.LEVELS:
		var s := GameState.new_run(3, lv)
		check_eq(s.inventory.count("ammo"), 0, "%s: no reserve" % lv)
		check_eq(s.magazine("handgun"), mini(Difficulty.start_rounds(lv), 12), "%s: start_rounds" % lv)
		check_eq(s.summary()["difficulty"], lv, "%s in the save summary" % lv)


func test_invasion_schedule_per_level() -> void:
	check_eq(GameState.new_run(3, "normal").run["next_invasion_at"], _slot(3), "Normal: Day 3")
	check_eq(GameState.new_run(3, "easy").run["next_invasion_at"], _slot(4), "Easy: Day 4")
	check_eq(GameState.new_run(3, "hard").run["next_invasion_at"], _slot(2), "Hard: Day 2")
	for c in [["easy", [4, 8, 12]], ["normal", [3, 6, 9]], ["hard", [2, 4, 6]]]:
		var s := GameState.new_run(3, c[0])
		s.cheats["invulnerable"] = true
		var days := []
		for i in 3:
			var due: float = s.run["next_invasion_at"]
			days.append(int(floorf(due / DAY)) + 1)
			s.advance(due - s.total_minutes)
			s.start_invasion()
			s.advance(60.0)
			s.end_invasion(true)
		check_eq(days, c[1], "%s: invasion days" % c[0])


func test_invasion_nights_have_no_stragglers() -> void:
	var s := GameState.new_run(77, "hard")
	for d in [2, 4, 6, 8]:
		check_eq(s.roll_straggler(d), -1.0, "Hard: no straggler on invasion night %d" % d)
	var e := GameState.new_run(77, "easy")
	for d in [4, 8]:
		check_eq(e.roll_straggler(d), -1.0, "Easy: no straggler on invasion night %d" % d)


func test_enemy_damage_and_wave_numbers() -> void:
	var n := GameState.new_run(3, "normal")
	var e := GameState.new_run(3, "easy")
	var h := GameState.new_run(3, "hard")
	check(absf(n.enemy_damage() - 12.0) < 1e-9, "Normal: 12 per hit")
	check(absf(e.enemy_damage() - 12.0 * 0.7) < 1e-9, "Easy: x0.7")
	check(absf(h.enemy_damage() - 12.0 * 1.3) < 1e-9, "Hard: x1.3")
	h.run["invasions_done"] = 2
	check(absf(h.enemy_damage() - 12.0 * 1.2 * 1.3) < 1e-9, "progression and difficulty multiply")
	check_eq([e.invasion_size(), n.invasion_size(), GameState.new_run(3, "hard").invasion_size()], [2, 3, 4], "wave sizes (x0.75, x1, x1.3)")
	check_eq([e.invasion_enemy_hp(), n.invasion_enemy_hp(), GameState.new_run(3, "hard").invasion_enemy_hp()], [2, 3, 4], "psycho HP (x0.8, x1, x1.25)")
	check_eq(h.enemy_hp_scale(), 1.25, "HP scale for archetypes")
	check_eq(e.difficulty_value("loot"), 1.25, "difficulty_value")
	h.inventory.add("vest", 1)
	h.damage(h.enemy_damage(), "psycho")
	check(absf((100.0 - h.health) - 12.0 * 1.2 * 1.3 * 0.65) < 1e-6, "the vest applies after the difficulty")


func test_set_difficulty_reschedules_a_waiting_invasion() -> void:
	var s := GameState.new_run(3, "normal")
	s.cheats["invulnerable"] = true
	s.set_difficulty("hard")
	check_eq(s.difficulty, "hard", "changed")
	check_eq(s.run["next_invasion_at"], _slot(2), "moved onto the Hard grid")
	s.advance(_slot(2) - s.total_minutes)
	check(s.run["invasion_announced"], "due")
	s.set_difficulty("easy")
	check_eq(s.run["next_invasion_at"], _slot(2), "an announced invasion isn't moved")
	s.start_invasion()
	s.end_invasion(true)
	check_eq(s.run["next_invasion_at"], _slot(4), "the next one follows the Easy grid (Day 4, 8, ...)")
	var t := GameState.from_dict(s.to_dict())
	check_eq(t.run["next_invasion_at"], _slot(4), "kept after loading")
	t.total_minutes = _slot(4) + 20 * 60.0
	var u := GameState.from_dict(t.to_dict())
	check_eq(u.run["next_invasion_at"], _slot(8), "a stale invasion moves to the next slot of its own grid")


func test_sleep_never_skips_an_invasion_on_any_level() -> void:
	for lv in Difficulty.LEVELS:
		var s := GameState.new_run(9, lv)
		s.cheats["invulnerable"] = true
		var due: float = s.run["next_invasion_at"]
		s.advance(due - 120.0 - s.total_minutes)
		var plan := s.plan_sleep(10 * 60.0)
		check(plan["interrupted"] and plan["reason"] == "invasion", "%s: the sleep is cut short" % lv)
		var ev := s.advance(plan["minutes"], true)
		check(ev.any(func(x): return x["type"] == "invasion_due"), "%s: woken by it" % lv)
		check_eq(s.total_minutes, due, "%s: exactly on time" % lv)
