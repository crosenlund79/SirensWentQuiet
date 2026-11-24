extends "res://tests/test_case.gd"
## RegionState (X): discovery, stock with slow recovery, notes and flags, the
## map's plan, once-only application of expedition results, and a robust
## round trip (including garbage and JSON) inside GameState.


func _sample() -> RegionState:
	var r := RegionState.new_region()
	r.discover("quarry")
	r.discover("military")
	r.set_stock("grocery", 0.42, 3)
	r.set_stock("homes", 0.8, 2)
	r.set_flag("grocery", "guarded", 5)
	r.notes["grocery"]["visits"] = 2
	r.plan("quarry", "targeted:stone")
	r.apply_result({"id": "exp-1", "location": "hardware", "stock_after": 0.6, "day": 4, "discovered": ["scrapyard"], "marks": {"cleared": 7}})
	return r


func test_new_region_and_discovery() -> void:
	var r := RegionState.new_region()
	for id in RegionState.START_KNOWN:
		check(r.is_discovered(id) and RegionLocations.has(id), "%s known at the start" % id)
	check(not r.is_discovered("military"), "the outpost starts unknown")
	check_eq(r.undiscovered().size(), 24 - RegionState.START_KNOWN.size(), "the rest is unknown")
	check(r.discover("quarry"), "a new place")
	check(not r.discover("quarry"), "only once")
	check(not r.discover("atlantis"), "unknown ids are ignored")
	check(not r.discovered.has("atlantis"), "and not stored")
	r.discover_all()
	check(r.undiscovered().is_empty(), "reveal all (dev)")


func test_stock_recovers_slowly() -> void:
	var r := RegionState.new_region()
	check_eq(r.stock_on("grocery", 10), 1.0, "unvisited: full")
	r.set_stock("grocery", 0.3, 4)
	var regen := ExpeditionData.regen_per_day("grocery")
	check(regen > 0.0 and regen < 0.1, "slow recovery (%s per day)" % regen)
	check_eq(r.stock_on("grocery", 4), 0.3, "same day: as left")
	check(absf(r.stock_on("grocery", 9) - (0.3 + 5.0 * regen)) < 0.0001, "five days later")
	check_eq(r.stock_on("grocery", 2), 0.3, "never more before the visit day")
	check_eq(r.stock_on("grocery", 4000), 1.0, "capped at 1")
	r.set_stock("grocery", 7.0, 4)
	check_eq(r.stock_of("grocery"), 1.0, "clamped")
	r.set_stock("grocery", NAN, 4)
	check_eq(r.stock_of("grocery"), 1.0, "NaN ignored")


func test_flags_and_plan() -> void:
	var r := RegionState.new_region()
	r.set_flag("police", "guarded", 6)
	check(r.has_flag("police", "guarded", 6) and not r.has_flag("police", "guarded", 7), "guarded through day 6")
	r.set_flag("police", "cleared", 9)
	check(not r.has_flag("police", "guarded", 5), "cleared replaces guarded")
	check_eq(r.flag_until("police", "cleared"), 9, "until day 9")
	r.plan("sawmill", "careful")
	check(r.planned == "sawmill" and r.planned_purpose == "careful", "planned")
	r.plan("nowhere", "raid")
	check(r.planned == "" and r.planned_purpose == "", "an unknown place clears the plan")
	r.plan("sawmill", "x".repeat(200))
	check(r.planned_purpose.length() <= RegionState.PURPOSE_MAX, "purpose length bounded")


func test_apply_result_once() -> void:
	var r := RegionState.new_region()
	r.plan("hardware", "general")
	var res := {"id": "exp-9-0-hardware-general-480", "location": "hardware", "stock_after": 0.55, "return_at": 1440.0 * 2 + 600.0,
		"discovered": ["scrapyard", "nowhere"], "marks": {"guarded": 5}}
	check(r.apply_result(res), "applied")
	check(not r.apply_result(res), "a second time does nothing")
	check_eq(r.visits("hardware"), 1, "one visit")
	check_eq(r.last_day("hardware"), 3, "day from return_at")
	check_eq(r.stock_of("hardware"), 0.55, "stock")
	check(r.is_discovered("scrapyard") and not r.discovered.has("nowhere"), "discoveries (unknown ids ignored)")
	check(r.has_flag("hardware", "guarded", 5), "marks")
	check_eq(r.planned, "", "the plan is used up")
	# an Experiment 002 result (no region fields) still counts as a visit
	check(r.apply_result({"id": "old-1", "destination": "homes", "minutes": 150}), "old result")
	check_eq(r.visits("homes"), 1, "visit recorded")
	check_eq(r.stock_on("homes", 1), 1.0, "stock untouched without stock_after")
	for bad in [null, 5, "x", [], {}, {"id": ""}, {"id": null}, {"id": 3, "location": 7}]:
		r.apply_result(bad)
	check(r.applied.size() <= RegionState.APPLIED_KEPT, "guard list bounded")
	for i in 100:
		r.apply_result({"id": "spam-%d" % i})
	check_eq(r.applied.size(), RegionState.APPLIED_KEPT, "only the last ids are kept")


func test_round_trip() -> void:
	var r := _sample()
	var d := r.to_dict()
	var back := RegionState.from_dict(d)
	check_eq(back.to_dict(), d, "to_dict -> from_dict -> to_dict")
	check(back.is_discovered("scrapyard") and back.is_discovered("military"), "discovered")
	check_eq(back.stock_of("grocery"), 0.42, "stock")
	check(back.has_flag("grocery", "guarded", 5) and back.has_flag("hardware", "cleared", 7), "flags")
	check_eq(back.planned, "quarry", "plan")
	check_eq(back.planned_purpose, "targeted:stone", "purpose")
	check(not back.apply_result({"id": "exp-1"}), "the once-only guard survives a save")
	# through JSON (save files): ints become floats, keys stay strings
	var json = JSON.parse_string(JSON.stringify(d))
	check_eq(RegionState.from_dict(json).to_dict(), d, "JSON round trip")
	# inside GameState
	var s := GameState.new_run(5)
	s.region = r
	var s2 := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(s2 != null, "GameState loads")
	check_eq(s2.region.to_dict(), d, "the region survives the GameState round trip")


func test_garbage_input_never_breaks() -> void:
	var garbage := [
		null, 3, "region", [], [1, 2],
		{"discovered": "homes"}, {"discovered": [3, null, {}, "military", "atlantis"]},
		{"discovered": {"quarry": true, "police": "yes"}},
		{"stock": [1, 2]}, {"stock": {"grocery": "lots", "homes": NAN, "clinic": INF, "atlantis": 0.5, "diner": -4, "hardware": 0.25}},
		{"notes": 7}, {"notes": {"grocery": 5, "homes": {"visits": "many", "last_day": -3, "flags": [1]}, "atlantis": {}}},
		{"notes": {"police": {"visits": 1e12, "last_day": 2.5, "flags": {"guarded": "x", "cleared": 4, 5: 6}}}},
		{"layout": 5, "planned": 9, "planned_purpose": ["raid"]},
		{"planned": "atlantis", "planned_purpose": "raid"},
		{"planned": "police", "planned_purpose": "y".repeat(500)},
		{"applied": "exp-1"}, {"applied": [1, null, "", "ok"]},
	]
	for g in garbage:
		var r := RegionState.from_dict(g)
		check(r != null, "from_dict(%s) gives a region" % str(g).left(40))
		for id in RegionState.START_KNOWN:
			check(r.is_discovered(id), "start places stay known")
		for id in r.discovered:
			check(RegionLocations.has(id) and r.discovered[id] == true, "only known ids, true values")
		for id in r.stock:
			var v = r.stock[id]
			check(RegionLocations.has(id) and typeof(v) == TYPE_FLOAT and v >= 0.0 and v <= 1.0, "clean stock %s=%s" % [id, v])
		for id in r.notes:
			var n: Dictionary = r.notes[id]
			check(RegionLocations.has(id) and typeof(n["visits"]) == TYPE_INT and n["visits"] >= 0 and typeof(n["last_day"]) == TYPE_INT and n["last_day"] >= 0, "clean note %s" % id)
			for f in n["flags"]:
				check(typeof(f) == TYPE_STRING and typeof(n["flags"][f]) == TYPE_INT, "clean flag %s" % f)
		check(r.planned == "" or RegionLocations.has(r.planned), "plan is a real place or empty")
		check(r.planned_purpose.length() <= RegionState.PURPOSE_MAX, "purpose bounded")
		check(typeof(r.layout) == TYPE_STRING, "layout is a string")
		for x in r.applied:
			check(typeof(x) == TYPE_STRING and x != "", "applied ids are strings")
		check_eq(RegionState.from_dict(r.to_dict()).to_dict(), r.to_dict(), "a cleaned region round-trips")
		# everything that reads it still works
		var s := GameState.new_run(1)
		s.region = r
		for id in RegionLocations.ids():
			var sm := ExpeditionData.location_summary(id, s)
			check(not sm.is_empty(), "summary works on a cleaned region (%s)" % id)
			if failures.size() > 10:
				return
	check_eq(RegionState.from_dict({"discovered": {"quarry": true}}).is_discovered("quarry"), true, "a dictionary of discoveries is accepted")
	check_eq(RegionState.from_dict({"stock": {"hardware": 0.25}}).stock_of("hardware"), 0.25, "valid stock kept")
	check_eq(RegionState.from_dict({"planned": "police", "planned_purpose": "raid"}).planned_purpose, "raid", "valid plan kept")
