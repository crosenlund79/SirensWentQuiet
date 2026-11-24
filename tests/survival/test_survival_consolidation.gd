extends "res://tests/test_case.gd"
## Experiment 003 consolidation fixes (docs/experiment-003/equipment.md):
## sleep never runs through empty needs or an overdue invasion.

const T := preload("res://src/survival/survival_tuning.gd")


func test_sleep_ends_when_a_need_runs_out() -> void:
	var s := GameState.new_run(11)
	s.total_minutes = 22 * 60.0
	s.hydration = 3.0
	var plan := s.plan_sleep(8 * 60.0)
	check(plan["interrupted"] and plan["reason"] == "needs", "cut short (%s)" % [plan])
	var hours := 3.0 / (T.HYDRATION_PER_HOUR * T.SLEEP_DECAY_SCALE)
	check(absf(plan["minutes"] - hours * 60.0) < 1e-6, "exactly when water runs out")
	check_eq(plan["text"], "You wake up parched. You need water.", "text")
	s.advance(plan["minutes"], true)
	check_eq(s.hydration, 0.0, "woke at 0")
	check_eq(s.health, 100.0, "before any harm")
	s.hydration = 50.0
	s.hunger = 2.0
	check_eq(s.plan_sleep(8 * 60.0)["text"], "Hunger wakes you. You need to eat.", "hunger too")


func test_with_a_need_already_out_sleep_ends_before_it_gets_dangerous() -> void:
	var s := GameState.new_run(11)
	s.total_minutes = 22 * 60.0
	s.hunger = 0.0
	s.health = 50.0
	var plan := s.plan_sleep(10 * 60.0)
	check_eq(plan["reason"], "needs", "cut short")
	check(absf(plan["minutes"] - (50.0 - T.HURT_LEVEL) / T.STARVING_DAMAGE * 60.0) < 1e-6, "when health reaches the hurt level")
	s.advance(plan["minutes"], true)
	check(absf(s.health - T.HURT_LEVEL) < 1e-6 and not s.dead, "awake at %s health" % s.health)
	check_eq(s.can_sleep(), "You're too weak to sleep like this. Eat and drink first.", "no more sleeping like this")
	s.cheats["invulnerable"] = true
	check_eq(s.can_sleep(), "", "unless nothing can hurt you")
	check(not s.plan_sleep(8 * 60.0)["interrupted"], "and then it isn't cut short")


func test_fed_and_watered_sleep_is_unchanged() -> void:
	var s := GameState.new_run(11)
	s.total_minutes = 22 * 60.0
	var plan := s.plan_sleep(8 * 60.0)
	check(not plan["interrupted"], "a normal night")
	check_eq(plan["minutes"], 480.0, "eight hours")


func test_no_sleeping_through_an_overdue_invasion() -> void:
	var s := GameState.new_run(11)
	var due: float = s.run["next_invasion_at"]
	s.total_minutes = due + 30.0           # e.g. just loaded: due, not yet reported
	check_eq(s.can_sleep(), "Not with them out there.", "can't sleep")
	var plan := s.plan_sleep(8 * 60.0)
	check(plan["interrupted"] and plan["minutes"] == 0.0 and plan["reason"] == "invasion", "no sleep at all")
	s.cheats["invulnerable"] = true
	check_eq(s.advance(1.0).filter(func(e): return e["type"] == "invasion_due").size(), 1, "the next advance reports it")
