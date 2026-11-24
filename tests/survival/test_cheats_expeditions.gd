extends "res://tests/test_case.gd"
## Cheat semantics and expedition results (applied once, clamped, fuzzed).

const T := preload("res://src/survival/survival_tuning.gd")


func test_invulnerable_blocks_every_damage() -> void:
	var s := GameState.new_run(1)
	s.cheats["invulnerable"] = true
	var deaths := []
	s.died.connect(func(c): deaths.append(c))
	s.damage(500.0, "psycho")
	check_eq(s.health, 100.0, "enemy damage blocked")
	s.hunger = 0.0
	s.hydration = 0.0
	s.advance(48 * 60.0)
	check_eq(s.health, 100.0, "starvation and dehydration blocked")
	s.apply_expedition({"id": "inv1", "minutes": 60, "damage": 90.0})
	check_eq(s.health, 100.0, "expedition damage blocked")
	check(not s.dead and deaths.is_empty(), "never dies")
	s.cheats["invulnerable"] = false
	s.advance(60.0)
	check(s.health < 100.0, "damage resumes once the cheat is off")


func test_unlimited_is_free_but_creates_nothing() -> void:
	var s := GameState.new_run(1)
	s.cheats["unlimited"] = true
	var before := s.inventory.to_dict()
	check(s.can_pay({"wood": 999, "scrap": 50}), "can pay anything")
	check(s.pay({"wood": 999, "scrap": 50}), "pays anything")
	check(s.pay({"wood": -50}), "negative cost")
	s.set_magazine("handgun", 0)
	check(s.use_ammo(), "fires with no ammo")
	check(s.use_ammo(5), "fires five")
	check_eq(s.inventory.count("ammo"), 0, "no rounds created")
	check_eq(s.magazine("handgun"), 0, "none in the magazine either")
	check_eq(s.inventory.count("wood"), before["counts"]["wood"], "no wood taken or created")
	check(not s.use_ammo(-1), "negative ammo use refused")
	s.cheats["unlimited"] = false
	check(not s.use_ammo(), "normal rules again")
	check(not s.can_pay({"scrap": 1}), "normal costs again")


func test_expedition_application() -> void:
	var s := GameState.new_run(1)
	s.inventory.add("ammo", 9)
	s.inventory.add("wood", 29)   # 35 of 40
	var r := {"id": "e1", "name": "Hardware Store", "minutes": 300, "summary": "Planks and rain.",
		"gained": {"wood": 20, "scrap": 3, "ghost_item": 5, "water": -2},
		"consumed": {"water": 2, "canned_food": 10}, "lost": {"ammo": 4},
		"left_behind": {}, "damage": 15.0, "events": []}
	var rep := s.apply_expedition_report(r)
	check(rep["applied"], "applied")
	check_eq(rep["added"], {"wood": 5, "scrap": 3}, "gains up to the cap")
	check_eq(rep["left_behind"], {"wood": 15}, "the rest is reported")
	check_eq(rep["consumed"], {"water": 2, "canned_food": 3}, "consumption clamped to what was owned")
	check_eq(rep["lost"], {"ammo": 4}, "losses")
	check_eq(s.inventory.count("wood"), 40, "wood full")
	check_eq(s.inventory.count("canned_food"), 0, "never negative")
	check_eq(s.inventory.count("ammo"), 5, "lost 4 rounds")
	check_eq(s.health, 85.0, "damage applied")
	check_eq(s.clock_text(), "12:00", "five hours passed")
	check_eq(s.run["expeditions"], 1, "counted")
	check_eq(s.apply_expedition(r), [], "second application ignored")
	check_eq(s.run["expeditions"], 1, "counted once")
	check_eq(s.inventory.count("scrap"), 3, "gains once")
	check_eq(s.clock_text(), "12:00", "time once")
	check(not s.apply_expedition_report({"minutes": 60, "gained": {"water": 5}})["applied"], "no id, not applied")
	check(not s.apply_expedition_report({"id": "", "gained": {"water": 5}})["applied"], "empty id")
	check(s.apply_expedition_report({"id": 77, "minutes": "abc", "gained": "junk", "damage": NAN})["applied"], "odd types are tolerated")
	check_eq(s.clock_text(), "12:00", "non-numeric minutes take no time")
	var ev := s.apply_expedition({"id": "e2", "minutes": 1e12})
	check_eq(s.clock_text(), "12:00", "very long trips are clamped to one day")
	check_eq(s.day(), 2, "next day")
	check(ev.size() >= 3, "events of the trip are returned (%d)" % ev.size())


func test_expedition_can_kill_and_dead_state_ignores_results() -> void:
	var s := GameState.new_run(1)
	var deaths := []
	s.died.connect(func(c): deaths.append(c))
	s.apply_expedition({"id": "k1", "minutes": 60, "damage": 1e9})
	check(s.dead and deaths == ["expedition"], "killed on the trip")
	check(not s.apply_expedition_report({"id": "k2", "minutes": 60, "gained": {"water": 3}})["applied"], "the dead don't loot")


func _junk(rng: RandomNumberGenerator):
	var pool := [-7, 0, 1, 3, 250, 1e15, -1e15, NAN, INF, -INF, 2.5, "9", "x", null, true, [], {}, Vector2.ONE, "-4", 99999999999]
	return pool[rng.randi() % pool.size()]


func _junk_items(rng: RandomNumberGenerator):
	if rng.randf() < 0.1:
		return _junk(rng)
	var ids := Items.ids() + ["ghost", 12, null, ""]
	var d := {}
	for i in rng.randi_range(0, 6):
		d[ids[rng.randi() % ids.size()]] = _junk(rng)
	return d


func test_fuzzed_results_never_break_the_state() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var s := GameState.new_run(4)
	s.cheats["invulnerable"] = true
	var last_t := s.total_minutes
	for i in 400:
		var r := {}
		for key in ["id", "minutes", "gained", "consumed", "lost", "left_behind", "damage", "name", "summary", "events"]:
			if rng.randf() < 0.8:
				r[key] = _junk_items(rng) if key in ["gained", "consumed", "lost", "left_behind"] else _junk(rng)
		if rng.randf() < 0.7:
			r["id"] = "f%d" % (i % 300)
		s.inventory.storage_crates = rng.randi_range(0, 3)
		s.apply_expedition(r)
		for id in s.inventory.counts:
			var n = s.inventory.counts[id]
			if not check(Items.has(id) and typeof(n) == TYPE_INT and n > 0, "valid count %s=%s after %s" % [id, n, r]):
				return
		for k in ["health", "hunger", "hydration", "energy", "total_minutes"]:
			var v: float = s.get(k)
			check(is_finite(v) and v >= 0.0, "%s finite and non-negative" % k)
		check(s.total_minutes >= last_t, "time never runs backwards")
		last_t = s.total_minutes
	check(s.run["applied_expeditions"].size() <= GameState.APPLIED_IDS_KEPT, "id memory bounded")
	check(GameState.from_dict(s.to_dict()) != null, "fuzzed state still saves and restores")
