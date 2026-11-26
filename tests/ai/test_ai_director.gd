extends "res://tests/test_case.gd"
## The threat-budget invasion director (SPEC-003 §5): budgets, compositions
## per difficulty and invasion, the rules (bombers, specials, small first
## waves), determinism, group pacing, and the Experiment 002 call.

const Director := preload("res://src/game/invasion_director.gd")
const SEEDS := [1, 7, 42, 1123, 9001, 31337, 65535, 123456, 2024, 77]


func test_ai_budget_follows_the_difficulty_table() -> void:
	for lv in Difficulty.LEVELS:
		var base := float(Difficulty.get_value(lv, "threat_budget"))
		var step := float(Difficulty.get_value(lv, "threat_budget_step"))
		for inv in range(1, 9):
			check(is_equal_approx(Director.threat_budget(lv, inv), base + step * (inv - 1)), "%s invasion %d budget" % [lv, inv])
	check(Director.threat_budget("easy", 3) < Director.threat_budget("normal", 3), "easy < normal")
	check(Director.threat_budget("normal", 3) < Director.threat_budget("hard", 3), "normal < hard")
	check_eq(EnemyDefs.cost("psycho"), 1.0, "psycho costs 1")
	check_eq(EnemyDefs.cost("runner"), 1.5, "runner costs 1.5")
	check_eq(EnemyDefs.cost("brute"), 3.0, "brute costs 3")
	check_eq(EnemyDefs.cost("bomber"), 4.0, "bomber costs 4")


func test_ai_compositions_respect_budget_caps_and_unlock_rules() -> void:
	var bombers_hard := 0
	for lv in Difficulty.LEVELS:
		var special := int(Difficulty.get_value(lv, "special_from_invasion"))
		var bomber_from := int(Difficulty.get_value(lv, "bomber_from_invasion"))
		for inv in range(1, 11):
			for s in SEEDS:
				var w := Director.compose(lv, inv, s)
				var tag := "%s inv %d seed %d %s" % [lv, inv, s, w]
				if not check(not w.is_empty(), "never empty: " + tag):
					continue
				check(Director.wave_cost(w) <= Director.threat_budget(lv, inv) + 1e-6, "within budget: " + tag)
				check(w.size() <= Director.max_count(lv, inv), "within the head-count cap: " + tag)
				check_eq(w[0], "psycho", "starts with a psycho: " + tag)
				if inv < bomber_from:
					check(not w.has("bomber"), "no bomber before invasion %d: %s" % [bomber_from, tag])
				if inv < special:
					check(not w.has("runner") and not w.has("brute"), "no specials yet: " + tag)
				if inv == 1:
					check(not w.has("brute"), "no brute in the first wave: " + tag)
				check(w.count("brute") <= Director.kind_cap(lv, inv, "brute"), "brute cap: " + tag)
				check(w.count("bomber") <= Director.kind_cap(lv, inv, "bomber"), "bomber cap: " + tag)
				if w.has("bomber"):
					check(w.find("bomber") >= maxi(1, int(w.size() / 3.0)), "bombers come later in the wave: " + tag)
					if lv == "hard" and inv <= 3:
						bombers_hard += 1
	check(bombers_hard >= 1, "Hard does field bombers early (invasion 2-3) for some seeds (%d)" % bombers_hard)


func test_ai_easy_opening_days_have_no_bombers_and_first_waves_are_small() -> void:
	check(int(Difficulty.get_value("easy", "bomber_from_invasion")) >= 4, "Easy: bombers from invasion 4 at the earliest")
	for s in range(200):
		for inv in range(1, 4):
			check(not Director.compose("easy", inv, s).has("bomber"), "Easy invasion %d seed %d: no bomber" % [inv, s])
	for lv in Difficulty.LEVELS:
		var first := Director.compose(lv, 1, 5)
		check(first.size() <= 4, "%s: the first wave is small (%s)" % [lv, first])
		check(first.size() < Director.compose(lv, 6, 5).size(), "%s: later waves are bigger" % lv)
	check_eq(Director.compose("easy", 1, 3), ["psycho", "psycho"], "Easy's first wave: two psychos")


func test_ai_compositions_are_deterministic_and_vary_by_seed() -> void:
	var differ := false
	for inv in range(1, 8):
		var a := Director.compose("normal", inv, 1123)
		check_eq(Director.compose("normal", inv, 1123), a, "same seed, same wave (invasion %d)" % inv)
		if Director.compose("normal", inv, 99) != a:
			differ = true
	check(differ, "another seed gives another wave somewhere")
	var d1 := Director.new()
	var d2 := Director.new()
	d1.begin_wave("hard", 4, 77)
	d2.begin_wave("hard", 4, 77)
	var p1 := []
	var p2 := []
	for i in 1200:
		for k in d1.tick_kinds(0.25):
			p1.append([k, d1.pick_spawn(Vector2(6.5, 7.8))])
		for k in d2.tick_kinds(0.25):
			p2.append([k, d2.pick_spawn(Vector2(6.5, 7.8))])
	check(p1.size() == d1.total and p1 == p2, "the same kinds, times and places")


## Exp 012 (G): was "pacing in groups" (one alone, then groups 25-40 s apart,
## a kill letting the next one come). The assignment (§10) replaced the
## trickle: the whole wave is released on the first tick, in approach groups
## on different sides, with short start delays instead of spawn gaps.
func test_ai_wave_released_whole_in_approach_groups() -> void:
	var d := Director.new()
	d.begin_wave("normal", 5, 3)
	var w: Array = d.wave
	check_eq(w.size(), d.total, "total = wave size")
	check(is_equal_approx(d.budget, Director.threat_budget("normal", 5)), "budget recorded")
	var out := []
	for k in d.tick_kinds(0.1):
		out.append({"kind": k, "at": d.pick_spawn(Vector2(6.5, 7.8))})
	check(d.all_spawned(), "all released at once")
	check_eq(out.map(func(o): return o["kind"]), w, "in wave order")
	check_eq(d.tick_kinds(30.0), [], "nobody later")
	var sum := 0
	for g in d.groups:
		sum += int(g)
	check_eq(sum, d.total, "groups cover the wave")
	check(d.groups.size() >= 2, "several approach groups (%s)" % [d.groups])
	var sides := {}
	for e in d.plan:
		sides[e["side"]] = true
		check(float(e["delay"]) >= 0.0 and float(e["delay"]) <= Director.GROUP_DELAY * 4 + Director.GROUP_GAP.y * 14 + Director.BOMBER_DELAY, "a short start delay (%.1f)" % e["delay"])
	check_eq(sides.size(), d.groups.size(), "one side per group")
	var o := d.spawn_opts("brute")
	check(o["level"] == "normal" and o["invasion"] == 5 and o["invader"], "spawn options carry level and invasion")


func test_ai_legacy_begin_and_dev_compositions() -> void:
	var d := Director.new()
	d.begin(3, 4, 1.1, 9)
	check_eq(d.wave, ["psycho", "psycho", "psycho"], "Experiment 002 call: psychos")
	check_eq(d.spawn_opts(), {"hp": 4, "speed": 1.1, "invader": true}, "with the given hp and speed")
	d.begin_wave("normal", 2, 1, ["bomber", "nonsense", "brute"])
	check_eq(d.wave, ["bomber", "brute"], "a chosen composition (unknown kinds dropped)")
	check_eq(d.total, 2, "its size")
