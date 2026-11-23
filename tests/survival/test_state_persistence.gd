extends "res://tests/test_case.gd"
## GameState.to_dict / from_dict: round trip and untrusted input.

const T := preload("res://src/survival/survival_tuning.gd")


func _played() -> GameState:
	var s := GameState.new_run(31)
	s.cheats["invulnerable"] = true
	s.advance(3000.0)
	s.inventory.add("scrap", 4)
	s.inventory.storage_crates = 1
	s.apply_expedition({"id": "p1", "minutes": 60, "gained": {"medkit": 1}, "name": "Clinic", "summary": "Quiet."})
	s.run["director_note"] = "kept"    # another module's key
	return s


func test_round_trip_is_exact() -> void:
	var s := _played()
	var t := GameState.from_dict(s.to_dict())
	check(t != null, "restored")
	check_eq(t.to_dict(), s.to_dict(), "identical after a round trip")
	check_eq(t.run["director_note"], "kept", "unknown run keys survive")
	var hits := [0]
	t.changed.connect(func(): hits[0] += 1)
	t.inventory.add("water", 1)
	check_eq(hits[0], 1, "inventory signal wired after restore")


func test_unusable_input_returns_null() -> void:
	var good := _played().to_dict()
	check(GameState.from_dict(null) == null, "null")
	check(GameState.from_dict([]) == null, "array")
	check(GameState.from_dict("state") == null, "string")
	check(GameState.from_dict({}) == null, "empty")
	for k in ["total_minutes", "health", "hunger", "hydration", "energy", "inventory", "run"]:
		var d := good.duplicate(true)
		d.erase(k)
		check(GameState.from_dict(d) == null, "missing %s" % k)
	for pair in [["health", NAN], ["hunger", INF], ["total_minutes", "1000"], ["energy", null], ["inventory", []], ["run", "x"]]:
		var d := good.duplicate(true)
		d[pair[0]] = pair[1]
		check(GameState.from_dict(d) == null, "%s = %s" % pair)


func test_out_of_range_and_garbage_fields_are_cleaned() -> void:
	var d := _played().to_dict()
	d["health"] = 900
	d["hunger"] = -50.0
	d["total_minutes"] = -100.0
	d["cheats"] = {"invulnerable": "yes", "unlimited": 1}
	d["dead"] = "no"
	d["inventory"] = {"counts": {"wood": -5, "water": 3, "ghost": 9}, "storage_crates": 1e9}
	d["run"] = {"seed": "abc", "invasions_done": -3, "invasion_active": 7, "next_invasion_at": NAN,
		"expeditions": "x", "applied_expeditions": [1, "ok", null], "log": ["a", 5, "b".repeat(500)], "dawn_collected_day": INF}
	var s := GameState.from_dict(d)
	check(s != null, "usable")
	check_eq(s.health, 100.0, "health clamped")
	check_eq(s.hunger, 0.0, "hunger clamped")
	check_eq(s.total_minutes, T.START_MINUTE, "clock clamped to the start")
	check_eq(s.cheats, {"invulnerable": false, "unlimited": true}, "cheat flags parsed strictly")
	check(not s.dead, "not dead")
	check_eq(s.inventory.counts, {"water": 3}, "inventory cleaned")
	check_eq(s.inventory.storage_crates, Inventory.MAX_CRATES, "crates bounded")
	check_eq(s.run["seed"], 0, "seed fallback")
	check_eq(s.run["invasions_done"], 0, "invasions clamped")
	check_eq(s.run["invasion_active"], true, "int flag")
	check_eq(s.run["next_invasion_at"], 2 * 1440.0 + 22 * 60.0, "schedule rebuilt")
	check_eq(s.run["applied_expeditions"], ["ok"], "ids cleaned")
	check_eq(s.run["log"].size(), 2, "log cleaned")
	check_eq(s.run["log"][1].length(), 200, "log lines bounded")
	check_eq(s.run["dawn_collected_day"], 0, "dawn day cleaned")
	d["health"] = 0.0
	s = GameState.from_dict(d)
	check(s.dead, "zero health restores as dead")


func _mutate(v, rng: RandomNumberGenerator):
	var pool := [null, NAN, -INF, 1e300, -1, "x", [], {}, true, 0, Vector3.ZERO]
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v.duplicate()
			for k in d.keys():
				if rng.randf() < 0.25:
					d[k] = _mutate(d[k], rng)
				elif rng.randf() < 0.05:
					d.erase(k)
			return d
	return pool[rng.randi() % pool.size()]


func test_fuzzed_dicts_never_crash() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var good := _played().to_dict()
	var restored := 0
	for i in 500:
		var s := GameState.from_dict(_mutate(good, rng))
		if s == null:
			continue
		restored += 1
		for k in ["health", "hunger", "hydration", "energy"]:
			var v: float = s.get(k)
			check(v >= 0.0 and v <= 100.0, "%s in range" % k)
		check(is_finite(s.total_minutes) and is_finite(float(s.run["next_invasion_at"])), "finite clock and schedule")
		check(typeof(s.run["log"]) == TYPE_ARRAY and typeof(s.run["seed"]) == TYPE_INT, "run fields typed")
		s.advance(600.0)   # and it still runs
	check(restored > 50, "many mutated states were still usable (%d)" % restored)
