extends "res://tests/test_case.gd"
## Expedition data and resolution (E): invariants, gating, departure window,
## event option effects, determinism.

const D := preload("res://src/expedition/expedition_data.gd")


func _state(seed := 11, minute := 8 * 60.0) -> GameState:
	var s := GameState.new_run(seed)
	s.total_minutes = minute
	return s


func _random_state(rng: RandomNumberGenerator) -> GameState:
	var s := GameState.new_run(rng.randi_range(1, 1 << 30))
	s.total_minutes = rng.randi_range(0, 6) * 1440.0 + rng.randf_range(5 * 60.0, 13 * 60.0)
	s.energy = rng.randf_range(0.0, 100.0)
	s.run["expeditions"] = rng.randi_range(0, 30)
	s.inventory.storage_crates = rng.randi_range(0, 2)
	s.inventory.counts.clear()
	for id in Items.DEFS:
		if rng.randf() < 0.6:
			var c := s.inventory.cap(id)
			var n := rng.randi_range(0, 30) if c == 0 else rng.randi_range(maxi(c - 6, 0), c)
			if Items.category(id) == "tool":
				n = 1
			if n > 0:
				s.inventory.counts[id] = n
	return s


func _check_result(r: Dictionary, s: GameState, gear: Dictionary, ctx: String) -> void:
	for k in ["id", "destination", "name", "minutes", "gained", "consumed", "lost", "left_behind", "damage", "events", "summary"]:
		if not check(r.has(k), "%s: result has %s" % [ctx, k]):
			return
	check(typeof(r["id"]) == TYPE_STRING and r["id"] != "", "%s: id is a non-empty string" % ctx)
	check(typeof(r["minutes"]) == TYPE_INT and r["minutes"] >= D.MIN_MINUTES, "%s: integer minutes (%s)" % [ctx, r["minutes"]])
	check(typeof(r["damage"]) == TYPE_FLOAT and r["damage"] >= 0.0 and r["damage"] <= D.MAX_DAMAGE, "%s: damage bounded (%s)" % [ctx, r["damage"]])
	for k in ["gained", "consumed", "lost", "left_behind"]:
		for id in r[k]:
			var n = r[k][id]
			check(Items.has(id), "%s: %s has a valid item id (%s)" % [ctx, k, id])
			check(typeof(n) == TYPE_INT and n > 0, "%s: %s[%s] is a positive int (%s)" % [ctx, k, id, n])
	for id in r["gained"]:
		var cap := s.inventory.cap(id)
		if cap > 0:
			check(s.inventory.count(id) + int(r["gained"][id]) <= cap, "%s: gained %s respects the cap" % [ctx, id])
		if Items.category(id) == "tool":
			check(r["gained"][id] == 1 and s.inventory.count(id) == 0 or r["lost"].has(id), "%s: a tool only when missing (%s)" % [ctx, id])
	for id in r["left_behind"]:
		check(s.inventory.cap(id) > 0, "%s: only capped items are left behind (%s)" % [ctx, id])
		check(s.inventory.count(id) + int(r["gained"].get(id, 0)) == s.inventory.cap(id), "%s: left behind only once full (%s)" % [ctx, id])
	for k in ["consumed", "lost"]:
		for id in r[k]:
			check(int(r[k][id]) <= s.inventory.count(id), "%s: %s %s within owned" % [ctx, k, id])
			check(int(r[k][id]) <= int(gear.get(id, 0)), "%s: %s %s within brought" % [ctx, k, id])
	for line in r["events"]:
		check(typeof(line) == TYPE_STRING and line != "", "%s: event lines are strings" % ctx)


func test_data_is_consistent() -> void:
	for id in D.ORDER:
		var d := D.destination(id)
		check(not d.is_empty(), "destination %s exists" % id)
		for k in ["name", "desc", "minutes", "danger", "rewards", "loot", "locked", "events"]:
			check(d.has(k), "%s has %s" % [id, k])
		for table in [d["loot"], d["locked"]]:
			for e in table:
				check(Items.has(e[0]), "%s loot uses a real item (%s)" % [id, e[0]])
				check(e[1] >= 1 and e[2] >= e[1] and e[3] > 0.0 and e[3] <= 1.0, "%s loot entry sane %s" % [id, e])
		for ev in d["events"]:
			check(D.EVENTS.has(ev), "%s event %s exists" % [id, ev])
	for bt in D.BONUS_TABLES.values():
		for e in bt:
			check(Items.has(e[0]), "bonus table item %s" % e[0])
	check(D.EVENTS.size() >= 10, "about ten events (%d)" % D.EVENTS.size())
	for ev_id in D.EVENTS:
		var ev: Dictionary = D.EVENTS[ev_id]
		var opts: Array = ev["options"]
		check(opts.size() >= 2 and opts.size() <= 3, "%s has 2-3 options" % ev_id)
		var free := false
		for o in opts:
			free = free or not o.has("needs")
			for need in o.get("needs", {}):
				check(need == "ammo" or need in D.BRINGABLE_TOOLS, "%s needs bringable gear (%s)" % [ev_id, need])
			if o.has("ammo"):
				check(int(o.get("needs", {}).get("ammo", 0)) >= int(o["ammo"]), "%s: an option that spends rounds needs them" % ev_id)
			if o.has("bonus") and typeof(o["bonus"]) == TYPE_ARRAY:
				for e in o["bonus"]:
					check(Items.has(e[0]), "%s bonus item %s" % [ev_id, e[0]])
		check(free, "%s always has an option without gear" % ev_id)


func test_fuzz_invariants_over_many_seeds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261123
	var ids := {}
	var runs := 0
	for i in 400:
		var s := _random_state(rng)
		var dest: String = D.ORDER[rng.randi_range(0, D.ORDER.size() - 1)]
		var gear := {"ammo": rng.randi_range(0, 12)}
		for t in D.BRINGABLE_TOOLS:
			gear[t] = rng.randi_range(0, 1)
		var picks := [rng.randi_range(0, 2), rng.randi_range(0, 2)]
		var before := s.to_dict()
		var r := ExpeditionRun.simulate(s, dest, gear, picks)
		check_eq(s.to_dict(), before, "simulation never mutates the state")
		if not D.availability(s, dest)["ok"]:
			check(r.is_empty(), "unavailable -> no result")
			continue
		runs += 1
		var brought := D.sanitize_gear(s, dest, gear)
		_check_result(r, s, brought, "run %d %s" % [i, dest])
		check(not ids.has(r["id"]), "unique id %s" % r["id"])
		ids[r["id"]] = true
		check_eq(ExpeditionRun.simulate(s, dest, gear, picks), r, "deterministic for the same seed and choices")
		if failures.size() > 10:
			return
	check(runs > 150, "most fuzz runs were possible (%d)" % runs)


func test_applying_results_keeps_inventory_valid() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 60:
		var s := _random_state(rng)
		s.cheats["invulnerable"] = true
		for dest in D.ORDER:
			if not D.availability(s, dest)["ok"]:
				continue
			var r := ExpeditionRun.simulate(s, dest, D.default_gear(s, dest), [rng.randi_range(0, 2), rng.randi_range(0, 2)])
			var before := s.inventory.counts.duplicate()
			s.apply_expedition(r)
			for id in s.inventory.counts:
				var n = s.inventory.counts[id]
				check(typeof(n) == TYPE_INT and n > 0, "count of %s stays a positive int" % id)
				var cap := s.inventory.cap(id)
				check(cap == 0 or n <= cap, "cap respected for %s" % id)
			for id in r["gained"]:
				var expect := int(before.get(id, 0)) - int(r["consumed"].get(id, 0)) - int(r["lost"].get(id, 0)) + int(r["gained"][id])
				check_eq(s.inventory.count(id), expect, "gained %s applied in full" % id)
			break


func test_unique_ids_through_a_run() -> void:
	var s := _state(5, 6 * 60.0)
	s.cheats["invulnerable"] = true
	var seen := {}
	for day in 8:
		s.total_minutes = day * 1440.0 + 6 * 60.0
		var r := ExpeditionRun.simulate(s, "homes")
		check(not seen.has(r["id"]), "id %s unique" % r["id"])
		seen[r["id"]] = true
		s.apply_expedition(r)
	check_eq(int(s.run["expeditions"]), 8, "eight expeditions applied")


func test_determinism_and_seed_sensitivity() -> void:
	var a := ExpeditionRun.simulate(_state(1234), "grocery", {"ammo": 3, "backpack": 1})
	var b := ExpeditionRun.simulate(_state(1234), "grocery", {"ammo": 3, "backpack": 1})
	check_eq(a, b, "same seed, same everything")
	var differs := false
	for seed in range(1, 12):
		var c := ExpeditionRun.simulate(_state(seed), "grocery", {"ammo": 3})
		differs = differs or c["gained"] != a["gained"] or c["minutes"] != a["minutes"]
	check(differs, "other seeds give other expeditions")
	var s := _state(1234)
	s.run["expeditions"] = 1
	var d := ExpeditionRun.simulate(s, "grocery", {"ammo": 3, "backpack": 1})
	check(d["id"] != a["id"], "the expedition counter changes the id")


func test_events_do_not_depend_on_gear() -> void:
	for seed in range(1, 30):
		var a := ExpeditionRun.create(_state(seed), "hardware", {})
		var b := ExpeditionRun.create(_state(seed), "hardware", {"ammo": 9})
		check_eq(a.event_ids, b.event_ids, "same events whatever you bring (seed %d)" % seed)
		check(a.event_ids.size() >= 1 and a.event_ids.size() <= 2, "one or two events")


func test_clinic_requires_a_flashlight() -> void:
	var s := _state()
	var av := D.availability(s, "clinic")
	check(not av["ok"], "no flashlight, no clinic")
	check(av["reason"].to_lower().contains("flashlight"), "the reason names the flashlight (%s)" % av["reason"])
	check(ExpeditionRun.create(s, "clinic") == null, "a run can't be created")
	s.inventory.add("flashlight", 1)
	check(D.availability(s, "clinic")["ok"], "with a flashlight the clinic opens")
	var r := ExpeditionRun.create(s, "clinic", {"flashlight": 0})
	check(r.has_tool("flashlight"), "the required flashlight is always brought")


func test_departure_window() -> void:
	var s := _state(3, 4 * 60.0 + 59.0)
	for id in D.ORDER:
		check(not D.availability(s, id)["ok"], "%s closed before 05:00" % id)
	s.total_minutes = 5 * 60.0
	check(D.availability(s, "homes")["ok"], "homes open at 05:00")
	s.total_minutes = 1440.0 + 17 * 60.0 + 30.0     # day 2, 17:30
	check(D.availability(s, "homes")["ok"], "homes: 17:30 + 2.5 h = 20:00 is fine")
	var g := D.availability(s, "grocery")
	check(not g["ok"], "grocery would return after 20:00")
	check(g["reason"].contains("coming back in the dark"), "explains the dark (%s)" % g["reason"])
	s.total_minutes = 1440.0 + 18 * 60.0 + 1.0
	var h := D.availability(s, "homes")
	check(not h["ok"] and h["reason"].contains("coming back in the dark"), "nothing after 18:00 (%s)" % h["reason"])
	s.total_minutes = 2 * 1440.0 + 12 * 60.0
	s.inventory.add("flashlight", 1)
	check(D.availability(s, "clinic")["ok"], "clinic: 12:00 + 5 h = 17:00")
	s.total_minutes = 2 * 1440.0 + 15 * 60.0 + 1.0
	check(not D.availability(s, "clinic")["ok"], "clinic closes after 15:00")
	s.total_minutes = 2 * 1440.0 + 9 * 60.0
	s.run["invasion_active"] = true
	check(not D.availability(s, "homes")["ok"], "not during an invasion")


func _run_with(dest: String, gear: Dictionary, event_id: String, seed := 7) -> ExpeditionRun:
	var s := _state(seed)
	s.inventory.add("crowbar", 1)
	s.inventory.add("flashlight", 1)
	s.inventory.add("backpack", 1)
	s.inventory.add("ammo", 20)
	var r := ExpeditionRun.create(s, dest, gear)
	r.event_ids.assign([event_id])
	r.step = 0
	return r


func test_option_gating_and_reasons() -> void:
	var r := _run_with("grocery", {"ammo": 1}, "storage_door")
	var st := r.option_state(2)
	check(not st["ok"] and st["reason"].contains("crowbar"), "forcing the door needs the crowbar (%s)" % st["reason"])
	check(st["reason"].contains("at home"), "owned but not brought says so (%s)" % st["reason"])
	r = _run_with("homes", {"ammo": 1}, "lone_psycho")
	st = r.option_state(0)
	check(not st["ok"] and st["reason"].contains("2 rounds"), "shooting needs two rounds (%s)" % st["reason"])
	check(r.option_state(1)["ok"], "sneaking needs nothing")
	r = _run_with("homes", {"ammo": 2}, "lone_psycho")
	check(r.option_state(0)["ok"], "two rounds brought: can shoot")
	check(not r.choose(5)["ok"], "invalid option refused")
	check_eq(r.step, 0, "refused choice doesn't advance")


func test_option_effects() -> void:
	# shooting spends the rounds, and they show up as consumed
	var r := _run_with("homes", {"ammo": 4}, "lone_psycho")
	var out := r.choose(0)
	check(out["ok"] and out["ammo"] >= 2, "shot with two rounds")
	check(r.is_finished(), "one event answered")
	var res := r.result()
	check(int(res["consumed"].get("ammo", 0)) >= 2, "rounds consumed (%s)" % [res["consumed"]])
	check(int(res["consumed"].get("ammo", 0)) <= 4, "never more than brought")
	# leaving early shortens the trip compared with waiting out the fog
	var early := _run_with("homes", {}, "lone_psycho")
	early.choose(2)
	var wait := _run_with("homes", {}, "fog_bank")
	wait.choose(0)
	check(early.result()["minutes"] < wait.result()["minutes"], "leaving early is quicker than waiting (%d vs %d)" % [early.result()["minutes"], wait.result()["minutes"]])
	# the crowbar's forced entry adds the locked table on top of the stockroom
	var forced := _run_with("grocery", {"crowbar": 1}, "storage_door")
	forced.choose(2)
	var plain := _run_with("grocery", {"crowbar": 1}, "storage_door")
	plain.choose(0)
	var total := func(d: Dictionary) -> int:
		var n := 0
		for id in d:
			n += int(d[id])
		return n
	check(total.call(forced.result()["gained"]) > total.call(plain.result()["gained"]), "forcing the door finds more than leaving early")
	check(forced.result()["events"].any(func(l): return l.contains("stockroom") or l.contains("storage-room")), "the report mentions it")


func test_flashlight_lowers_dark_risk_and_ammo_lowers_fight_injury() -> void:
	var hurt_dark := [0, 0]
	var dmg_fight := [0.0, 0.0]
	for seed in range(1, 200):
		for k in 2:
			var r := _run_with("homes", {"flashlight": k}, "collapsed_floor", seed)
			r.choose(1)        # climb down in the dark
			if r.result()["damage"] > 0.0:
				hurt_dark[k] += 1
			var f := _run_with("homes", {"ammo": 3 * k}, "dogs", seed)
			f.choose(2)        # walk straight through
			dmg_fight[k] += f.result()["damage"]
	check(hurt_dark[1] < hurt_dark[0], "a flashlight means fewer falls in the dark (%s)" % [hurt_dark])
	check(dmg_fight[1] < dmg_fight[0] * 0.75, "brought ammo lowers injuries in fights (%s)" % [dmg_fight])


func test_backpack_and_caps() -> void:
	var with := 0
	var without := 0
	for seed in range(1, 60):
		for k in 2:
			var s := _state(seed)
			s.inventory.add("backpack", 1)
			var r := ExpeditionRun.simulate(s, "grocery", {"backpack": k})
			var n := 0
			for id in r["gained"]:
				n += r["gained"][id]
			if k == 1:
				with += n
			else:
				without += n
	check(with > without * 1.3, "the backpack carries clearly more (%d vs %d)" % [with, without])
	# full storage: materials are left behind
	var s := _state(8)
	s.inventory.add("wood", 100)
	s.inventory.add("nails", 100)
	s.inventory.add("scrap", 100)
	var r := ExpeditionRun.simulate(s, "hardware", {})
	check(not r["gained"].has("wood") and not r["gained"].has("nails"), "nothing gained over the cap (%s)" % [r["gained"]])
	check(r["left_behind"].has("wood") or r["left_behind"].has("nails"), "the excess is left behind (%s)" % [r["left_behind"]])
	check(r["events"].any(func(l): return l.contains("Storage full")), "the report says so")


func test_tool_loss_only_when_brought() -> void:
	var lost := 0
	for seed in range(1, 80):
		var r := _run_with("hardware", {"crowbar": 1}, "timber_rack", seed)
		r.choose(1)
		var res := r.result()
		if res["lost"].has("crowbar"):
			lost += 1
			check_eq(res["lost"]["crowbar"], 1, "one crowbar lost")
	check(lost > 5 and lost < 60, "bracing the rack sometimes costs the crowbar (%d / 79)" % lost)
	var r2 := _run_with("clinic", {"flashlight": 1}, "waiting_room", 3)
	r2.gear.erase("flashlight")
	check(r2.option_state(1)["ok"], "running needs nothing")
	r2.choose(1)
	check(not r2.result()["lost"].has("flashlight"), "a tool left at home can't be lost")
