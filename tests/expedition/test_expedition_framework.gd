extends "res://tests/test_case.gd"
## The Experiment 003 destination framework (X): data for all 24 places,
## the resolver fuzzed over every place and approach, depletion and recovery,
## discovery, equipment effects, the outpost's preparation, difficulty, the
## map API (location_summary, approaches) and once-only region consequences.

const D := preload("res://src/expedition/expedition_data.gd")

const STATS_SEEDS := 160


## A state that can use `has_equipped` (K's equipment API) without K's code:
## equipped items live outside the inventory here.
class EquippedState extends GameState:
	var worn := {}

	func has_equipped(id) -> bool:
		return str(id) in worn.values()


func _state(seed := 11, minute := 7 * 60.0, day := 1) -> GameState:
	var s := GameState.new_run(seed)
	s.total_minutes = (day - 1) * 1440.0 + minute
	s.inventory.add("handgun", 1)
	return s


func _kit(s: GameState, rounds := 12) -> GameState:
	for id in ["crowbar", "flashlight", "backpack", "vest", "shotgun"]:
		s.inventory.add(id, 1)
	s.inventory.add("ammo", rounds)
	s.inventory.add("shells", 6)
	return s


func _total(d: Dictionary) -> int:
	var n := 0
	for id in d:
		n += int(d[id])
	return n


# --- data ----------------------------------------------------------------------------

func test_every_location_is_configured() -> void:
	var ids := RegionLocations.ids()
	ids.sort()
	var order: Array = D.ORDER.duplicate()
	order.sort()
	check_eq(order, ids, "ExpeditionData covers exactly the RegionLocations ids")
	check_eq(D.LOCATIONS.size(), 24, "24 places")
	for p in ["residential", "food", "medical", "construction_wood", "construction_stone", "construction_iron", "weapons", "military"]:
		check(D.PROFILES.has(p), "profile %s" % p)
	var last_cat := -1
	for id in D.ORDER:
		var d := D.destination(id)
		if not check(not d.is_empty(), "%s resolves" % id):
			continue
		check(D.PROFILES.has(D.LOCATIONS[id]["profile"]), "%s has a known profile" % id)
		var ci := D.CATEGORY_ORDER.find(d["category"])
		check(ci >= last_cat, "ORDER is grouped by category (%s)" % id)
		last_cat = ci
		check_eq(d["name"], RegionLocations.name_of(id), "%s: name from the one list" % id)
		check_eq(int(d["travel"]), RegionLocations.travel_minutes(id), "%s: travel from RegionLocations" % id)
		check_eq(D.nominal_minutes(id), 2 * RegionLocations.travel_minutes(id) + D.search_minutes(id), "%s: travel both ways + search" % id)
		check(D.search_minutes(id, "careful") > D.search_minutes(id) and D.search_minutes(id, "raid") < D.search_minutes(id), "%s: careful slower, raid faster" % id)
		check(not (d["loot"] as Array).is_empty() and not D.targets(id).is_empty(), "%s has loot and targets" % id)
		for table in [d["loot"], d["locked"]]:
			for e in table:
				check(Items.has(e[0]), "%s: real item %s" % [id, e[0]])
				check(int(e[1]) >= 1 and int(e[2]) >= int(e[1]) and float(e[3]) > 0.0 and float(e[3]) <= 1.0, "%s: sane entry %s" % [id, e])
		for e in d["events"]:
			check(D.EVENTS.has(e), "%s: event %s exists" % [id, e])
		for r in d["requires"]:
			check(Items.has(r), "%s requires a real item" % id)
		check(float(d["deplete"]) > 0.0 and float(d["regen"]) > 0.0 and float(d["floor"]) >= 0.0 and float(d["floor"]) < 1.0, "%s: depletion data" % id)
		check(D.risk_name(D.danger(id, {})) in D.RISK_NAMES, "%s: a risk tier" % id)
	for ev_id in D.EVENTS:
		for a in D.EVENTS[ev_id].get("only", []):
			check(D.APPROACHES.has(a), "%s: 'only' names an approach" % ev_id)
	check_eq(D.APPROACH_ORDER, ["general", "targeted", "careful", "raid"], "the user's four approaches")


func test_profiles_vary_by_place() -> void:
	var has := func(id: String, item: String) -> bool: return item in D.possible_rewards(id)
	for h in ["homes", "cul_de_sac", "trailer_park", "farmhouse"]:
		check_eq(D.LOCATIONS[h]["profile"], "residential", "%s is a family house" % h)
	check(has.call("cul_de_sac", "medkit") and has.call("cul_de_sac", "hammer"), "cul-de-sac: tools and medicine")
	check(not has.call("homes", "medkit"), "plain homes have no first-aid kits")
	check(has.call("trailer_park", "shells") and not has.call("homes", "shells"), "trailer park: shells sometimes")
	check(has.call("farmhouse", "shotgun") and has.call("farmhouse", "wood"), "farmhouse: wood, rarely a shotgun")
	var farm_cans := 0.0
	var home_cans := 0.0
	for e in D.destination("farmhouse")["loot"]:
		if e[0] == "canned_food":
			farm_cans += float(e[3]) * (e[1] + e[2]) * 0.5
	for e in D.destination("homes")["loot"]:
		if e[0] == "canned_food":
			home_cans += float(e[3]) * (e[1] + e[2]) * 0.5
	check(farm_cans > home_cans * 1.5, "farmhouse: preserves (%.1f vs %.1f)" % [farm_cans, home_cans])
	for id in ["quarry", "construction_site"]:
		check(has.call(id, "stone"), "%s: stone" % id)
	for id in ["scrapyard", "warehouse", "construction_site"]:
		check(has.call(id, "iron") and has.call(id, "scrap"), "%s: iron and scrap" % id)
	for id in ["logging", "sawmill"]:
		check_eq(D.targets(id)[0], "wood", "%s: mostly wood" % id)
	for id in ["military", "police", "gun_shop", "shooting_range"]:
		check(has.call(id, "shells") and has.call(id, "ammo"), "%s: shells and 9 mm" % id)
	for id in ["military", "police", "gun_shop"]:
		check(has.call(id, "shotgun") and has.call(id, "vest"), "%s: the shotgun and the vest" % id)
	check("flashlight" in D.destination("military")["requires"], "the outpost needs a flashlight")


# --- the resolver -------------------------------------------------------------------------

func _random_state(rng: RandomNumberGenerator) -> GameState:
	var s := GameState.new_run(rng.randi_range(1, 1 << 30))
	s.difficulty = Difficulty.LEVELS[rng.randi_range(0, 2)]
	s.total_minutes = rng.randi_range(0, 6) * 1440.0 + rng.randf_range(5 * 60.0, 9 * 60.0)
	s.energy = rng.randf_range(0.0, 100.0)
	s.run["expeditions"] = rng.randi_range(0, 30)
	s.inventory.storage_crates = rng.randi_range(0, 2)
	s.inventory.counts.clear()
	for id in Items.DEFS:
		if rng.randf() < 0.55:
			var c := s.inventory.cap(id)
			var n := rng.randi_range(0, 30) if c == 0 else rng.randi_range(maxi(c - 6, 0), c)
			if n > 0:
				s.inventory.counts[id] = n
	if rng.randf() < 0.3:
		s.weapons = {"handgun": {"loaded": rng.randi_range(0, 12)}}
	for id in RegionLocations.ids():
		if rng.randf() < 0.4:
			s.region.discover(id)
		if rng.randf() < 0.4:
			s.region.set_stock(id, rng.randf(), s.day() - rng.randi_range(0, 5))
		if rng.randf() < 0.15:
			s.region.set_flag(id, "guarded" if rng.randf() < 0.5 else "cleared", s.day() + 1)
	return s


func test_resolver_fuzz_all_locations_and_approaches() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261124
	var ids := {}
	var runs := 0
	var per := {}
	for loc in D.ORDER:
		for ap in D.APPROACH_ORDER:
			for i in 6:
				var s := _random_state(rng)
				var gear := {"ammo": rng.randi_range(0, 14), "shells": rng.randi_range(0, 6)}
				for t in D.BRINGABLE_GEAR:
					gear[t] = rng.randi_range(0, 1)
				var tg := D.targets(loc)
				var target: String = tg[rng.randi_range(0, tg.size() - 1)] if rng.randf() < 0.8 else "nonsense"
				var picks := [rng.randi_range(0, 2), rng.randi_range(0, 2)]
				var before := s.to_dict()
				var r := ExpeditionRun.simulate(s, loc, gear, picks, ap, target)
				check_eq(s.to_dict(), before, "the resolver never mutates the state")
				var brought := D.sanitize_gear(s, loc, gear)
				if not D.approach_state(s, loc, ap, brought)["ok"]:
					check(r.is_empty(), "unavailable -> no result (%s %s)" % [loc, ap])
					continue
				runs += 1
				per[ap] = int(per.get(ap, 0)) + 1
				_check_result(r, s, brought, loc, ap, "%s/%s/%d" % [loc, ap, i])
				check(not ids.has(r["id"]), "unique id %s" % r["id"])
				ids[r["id"]] = true
				check_eq(ExpeditionRun.simulate(s, loc, gear, picks, ap, target), r, "deterministic (%s %s)" % [loc, ap])
				if failures.size() > 12:
					return
	check(runs > 300, "most fuzz runs were possible (%d)" % runs)
	for ap in D.APPROACH_ORDER:
		check(int(per.get(ap, 0)) > 20, "approach %s exercised (%d)" % [ap, per.get(ap, 0)])


func _check_result(r: Dictionary, s: GameState, gear: Dictionary, loc: String, ap: String, ctx: String) -> void:
	for k in ["id", "destination", "name", "minutes", "gained", "consumed", "lost", "left_behind", "damage", "events", "summary",
			"brought", "depart_at", "return_at", "location", "approach", "target", "stock_before", "stock_after", "discovered", "marks", "day"]:
		if not check(r.has(k), "%s: result has %s" % [ctx, k]):
			return
	check(r["location"] == loc and r["destination"] == loc and r["approach"] == ap, "%s: location and approach" % ctx)
	check(typeof(r["minutes"]) == TYPE_INT and r["minutes"] >= D.MIN_MINUTES and r["minutes"] <= D.nominal_minutes(loc, ap) + 150, "%s: minutes (%s)" % [ctx, r["minutes"]])
	check(r["damage"] >= 0.0 and r["damage"] <= float(D.destination(loc)["max_damage"]), "%s: damage bounded (%s)" % [ctx, r["damage"]])
	for k in ["gained", "consumed", "lost", "left_behind"]:
		for id in r[k]:
			check(Items.has(id), "%s: %s valid id (%s)" % [ctx, k, id])
			check(typeof(r[k][id]) == TYPE_INT and r[k][id] > 0, "%s: %s[%s] positive int (%s)" % [ctx, k, id, r[k][id]])
	for id in r["gained"]:
		var cap := s.inventory.cap(id)
		var lost := int(r["lost"].get(id, 0))
		if cap > 0:
			check(s.inventory.count(id) - lost + int(r["gained"][id]) <= cap, "%s: cap respected (%s)" % [ctx, id])
		if D.is_unique(id):
			check(r["gained"][id] == 1 and (not D.owns(s, id) or lost > 0), "%s: unique item only when missing (%s)" % [ctx, id])
	for id in r["consumed"]:
		check(id in D.AMMO_TYPES, "%s: only rounds are consumed" % ctx)
		check(int(r["consumed"][id]) <= int(gear.get(id, 0)) and int(r["consumed"][id]) <= D.rounds_owned(s, id), "%s: consumed within brought and owned" % ctx)
	for id in r["lost"]:
		check(int(gear.get(id, 0)) > 0 and D.owns(s, id), "%s: lost only what was brought" % ctx)
	check(typeof(r["stock_after"]) == TYPE_FLOAT and r["stock_after"] >= 0.0 and r["stock_after"] <= r["stock_before"] + 0.0001, "%s: stock only goes down (%s -> %s)" % [ctx, r["stock_before"], r["stock_after"]])
	check(absf(float(r["stock_before"]) - D.stock_now(s, loc)) < 0.002, "%s: stock_before is today's stock" % ctx)
	var seen := {}
	for p in r["discovered"]:
		check(RegionLocations.has(p) and not s.region.is_discovered(p) and p != loc and not seen.has(p), "%s: discovered %s is new and unique" % [ctx, p])
		seen[p] = true
	for f in r["marks"]:
		check(D.FLAGS.has(f) and int(r["marks"][f]) >= int(r["day"]), "%s: mark %s" % [ctx, f])
	check(not (r["marks"].has("guarded") and r["marks"].has("cleared")), "%s: guarded and cleared exclude each other" % ctx)
	check_eq(int(r["day"]), int(floor(float(r["return_at"]) / 1440.0)) + 1, "%s: return day" % ctx)
	if ap == "targeted":
		check(r["target"] in D.targets(loc), "%s: a valid target (%s)" % [ctx, r["target"]])
	else:
		check_eq(r["target"], "", "%s: no target" % ctx)


func test_results_apply_cleanly_including_the_region() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		var s := _random_state(rng)
		s.cheats["invulnerable"] = true
		var loc: String = D.ORDER[rng.randi_range(0, 23)]
		var r := ExpeditionRun.simulate(s, loc, D.default_gear(s, loc), [], D.APPROACH_ORDER[rng.randi_range(0, 2)])
		if r.is_empty():
			continue
		s.apply_expedition(r)
		check(D.apply_region(s, r), "region consequences applied")
		check(not D.apply_region(s, r), "only once")
		check(s.region.is_discovered(loc), "the visited place is known")
		check(absf(s.region.stock_of(loc) - float(r["stock_after"])) < 0.0001, "stock stored")
		for p in r["discovered"]:
			check(s.region.is_discovered(p), "discovery applied")
		for id in s.inventory.counts:
			var cap := s.inventory.cap(id)
			check(cap == 0 or s.inventory.count(id) <= cap, "caps respected after applying (%s)" % id)


# --- depletion, recovery, discovery -------------------------------------------------------------

func test_stock_depletion_and_recovery() -> void:
	var s := _state(3)
	s.cheats["invulnerable"] = true
	check_eq(D.stock_now(s, "grocery"), 1.0, "untouched")
	var r := ExpeditionRun.simulate(s, "grocery", {}, [0, 0])
	check(r["stock_after"] < 1.0, "a visit depletes the place (%s)" % r["stock_after"])
	s.apply_expedition(r)
	D.apply_region(s, r)
	var after := D.stock_now(s, "grocery")
	check(absf(after - float(r["stock_after"])) < 0.001, "the region stores it")
	check_eq(s.region.visits("grocery"), 1, "one visit")
	# slow recovery over days, capped at 1
	var regen := D.regen_per_day("grocery")
	var d0: int = s.region.last_day("grocery")
	check(absf(s.region.stock_on("grocery", d0 + 5) - minf(after + 5.0 * regen, 1.0)) < 0.0001, "recovers by regen per day")
	check_eq(s.region.stock_on("grocery", d0 + 1000), 1.0, "never above 1")
	# repeated visits pick a place clean, down to its floor
	var t := _state(4)
	for day in 12:
		t.total_minutes = day * 1440.0 + 7 * 60.0
		var rr := ExpeditionRun.simulate(t, "convenience", {}, [0, 0])
		D.apply_region(t, rr)
	var floor_v := float(D.destination("convenience")["floor"])
	check(t.region.stock_of("convenience") <= floor_v + 0.05, "picked clean after many visits (%s)" % t.region.stock_of("convenience"))
	check(t.region.stock_of("convenience") >= floor_v - 0.0001, "never below the floor")
	check(D.notes_text(t, "convenience").any(func(l): return l.contains("Picked clean")), "the notes say so (%s)" % [D.notes_text(t, "convenience")])
	# loot scales with stock
	var full := 0
	var low := 0
	for seed in range(1, STATS_SEEDS):
		var a := _state(seed)
		full += _total(ExpeditionRun.simulate(a, "grocery", {}, [0, 0])["gained"])
		var b := _state(seed)
		b.region.set_stock("grocery", 0.3, 1)
		low += _total(ExpeditionRun.simulate(b, "grocery", {}, [0, 0])["gained"])
	check(low < full * 0.45, "a depleted place gives much less (%d vs %d)" % [low, full])


func test_careful_exploration_discovers_places() -> void:
	var careful := 0
	var general := 0
	var other := 0
	var runs := 0
	for seed in range(1, STATS_SEEDS):
		var s := _state(seed)
		var known := s.region.discovered.duplicate()
		var r := ExpeditionRun.simulate(s, "homes", {}, [0, 0], "careful")
		careful += r["discovered"].size()
		for p in r["discovered"]:
			check(not known.has(p), "only undiscovered places")
		general += ExpeditionRun.simulate(_state(seed), "homes", {}, [0, 0], "general")["discovered"].size()
		other += ExpeditionRun.simulate(_state(seed), "homes", {}, [0, 0], "targeted")["discovered"].size()
		runs += 1
	check(careful > runs * 0.6, "careful exploration usually finds a place (%d in %d)" % [careful, runs])
	check(general < careful * 0.3 and general > 0, "general scavenging rarely does (%d)" % general)
	check_eq(other, 0, "targeted collection never does")
	# applying makes them visible to the map; nothing left to find -> none
	var s := _state(2)
	var r := {}
	for seed in range(1, 30):
		s.run["seed"] = seed
		r = ExpeditionRun.simulate(s, "homes", {}, [0, 0], "careful")
		if not r["discovered"].is_empty():
			break
	check(not r["discovered"].is_empty(), "found something")
	D.apply_region(s, r)
	for p in r["discovered"]:
		check(s.region.is_discovered(p) and D.location_summary(p, s)["discovered"], "on the map now (%s)" % p)
	var all := _state(3)
	all.region.discover_all()
	for seed in range(1, 20):
		all.run["seed"] = seed
		check(ExpeditionRun.simulate(all, "homes", {}, [0, 0], "careful")["discovered"].is_empty(), "nothing left to discover")
	# discovery prefers nearby places
	var near := 0
	var far := 0
	for seed in range(1, STATS_SEEDS):
		for p in ExpeditionRun.simulate(_state(seed), "homes", {}, [0, 0], "careful")["discovered"]:
			if RegionLocations.distance_km(p) < 1.0:
				near += 1
			else:
				far += 1
	check(near > far, "nearby places are found first (%d near, %d far)" % [near, far])


# --- equipment --------------------------------------------------------------------------------

func _avg(loc: String, gear: Dictionary, prep: Callable, field := "damage", picks := [0, 0], approach := "general") -> float:
	var sum := 0.0
	for seed in range(1, STATS_SEEDS):
		var s := _state(seed)
		prep.call(s)
		var r := ExpeditionRun.simulate(s, loc, gear, picks, approach)
		sum += float(r["damage"]) if field == "damage" else float(_total(r["gained"]))
	return sum / float(STATS_SEEDS - 1)


func test_equipment_effects_when_owned() -> void:
	var own := func(s: GameState): _kit(s)
	# backpack: more loot
	var with_bp := _avg("grocery", {"backpack": 1}, own, "loot")
	var without := _avg("grocery", {}, own, "loot")
	check(with_bp > without * 1.3, "backpack carries more (%.1f vs %.1f)" % [with_bp, without])
	# crowbar: the locked table
	var with_cb := _avg("hardware", {"crowbar": 1}, own, "loot", [2, 2])
	var no_cb := _avg("hardware", {}, own, "loot", [2, 2])
	check(with_cb > no_cb * 1.3, "crowbar opens the stockroom (%.1f vs %.1f)" % [with_cb, no_cb])
	# vest: fewer injuries in fights (walking through the dogs, no rounds)
	var hurt_vest := 0.0
	var hurt_bare := 0.0
	for seed in range(1, STATS_SEEDS):
		for k in 2:
			var s := _kit(_state(seed))
			var r := ExpeditionRun.create(s, "homes", {"vest": k})
			r.event_ids.assign(["dogs"])
			r.step = 0
			r.choose(2)
			if k == 1:
				hurt_vest += r.result()["damage"]
			else:
				hurt_bare += r.result()["damage"]
	check(hurt_vest < hurt_bare * 0.75 and hurt_vest > 0.0, "the vest takes the edge off (%.0f vs %.0f)" % [hurt_vest, hurt_bare])
	# flashlight: fewer falls in dark places; required at the clinic and the outpost
	var dark := [0, 0]
	for seed in range(1, STATS_SEEDS):
		for k in 2:
			var s := _kit(_state(seed))
			var r := ExpeditionRun.create(s, "homes", {"flashlight": k})
			r.event_ids.assign(["collapsed_floor"])
			r.step = 0
			r.choose(1)
			if r.result()["damage"] > 0.0:
				dark[k] += 1
	check(dark[1] < dark[0], "the flashlight lowers dark-place injuries (%s)" % [dark])
	# risk shown drops with gear
	var s := _kit(_state())
	check(D.danger_for(s, "grocery", D.default_gear(s, "grocery")) < D.danger_for(s, "grocery", {}), "gear lowers the shown risk")


func test_equipment_counts_when_equipped() -> void:
	var s := EquippedState.new()
	s.total_minutes = 8 * 60.0
	s.worn = {"body": "vest", "utility": "flashlight", "primary": "handgun"}
	check(D.owns(s, "vest") and D.owns(s, "flashlight"), "has_equipped counts as owned")
	check_eq(s.inventory.count("vest"), 0, "(not in the inventory)")
	check(D.availability(s, "clinic")["ok"], "an equipped flashlight opens the clinic")
	var g := D.sanitize_gear(s, "homes", {"vest": 1})
	check_eq(g.get("vest", 0), 1, "the equipped vest can be brought")
	s.weapons = {"handgun": {"loaded": 9}}
	check_eq(D.rounds_owned(s, "ammo"), 9, "rounds in the magazine count")
	s.inventory.add("ammo", 3)
	check_eq(D.rounds_owned(s, "ammo"), 12, "reserve plus magazine")
	check_eq(D.rounds_owned(s, "shells"), 0, "no shotgun, no shells")
	var r := ExpeditionRun.simulate(s, "homes", {"ammo": 12, "vest": 1})
	check(not r.get("gained", {}).has("vest"), "an equipped vest is never found again")
	# the foundation's equipment dictionary also counts
	var t := _state()
	t.equipment = {"back": "backpack"}
	check(D.owns(t, "backpack"), "GameState.equipment counts as owned")
	check_eq(D.sanitize_gear(t, "homes", {"backpack": 1}).get("backpack", 0), 1, "and can be brought")
	# no handgun: rounds can't be brought
	var u := GameState.new_run(1)
	u.total_minutes = 8 * 60.0
	check_eq(D.rounds_owned(u, "ammo"), 0, "no weapon, no rounds")
	check_eq(D.sanitize_gear(u, "homes", {"ammo": 5})["ammo"], 0, "rounds clamped to 0 without a handgun")


func test_shells_fire_and_are_consumed() -> void:
	var s := _state()
	s.inventory.add("shotgun", 1)
	s.inventory.add("shells", 3)
	s.inventory.counts.erase("ammo")
	var r := ExpeditionRun.create(s, "homes", {"shells": 3})
	r.event_ids.assign(["lone_psycho"])
	r.step = 0
	check(r.option_state(0)["ok"], "one shell covers 'Shoot it' (2 rounds)")
	var out := r.choose(0)
	check_eq(out["shells"], 1, "one shell used")
	check_eq(r.result()["consumed"].get("shells", 0), 1, "consumed as shells")
	var t := _state()
	t.inventory.counts.erase("ammo")
	var r2 := ExpeditionRun.create(t, "homes", {})
	r2.event_ids.assign(["lone_psycho"])
	r2.step = 0
	check(r2.option_state(0)["reason"].contains("2 rounds"), "without rounds it says why (%s)" % r2.option_state(0)["reason"])


# --- dangerous places ---------------------------------------------------------------------------

func test_outpost_demands_preparation() -> void:
	var s := _state()
	s.inventory.counts.erase("ammo")      # unprepared: no rounds, no vest
	var av := D.availability(s, "military")
	check(not av["ok"] and av["reason"].contains("flashlight"), "no flashlight, no outpost (%s)" % av["reason"])
	s.inventory.add("flashlight", 1)
	check(D.availability(s, "military")["ok"], "with a flashlight it opens")
	var bare := D.default_gear(s, "military")
	var k := _kit(_state())
	var full := D.default_gear(k, "military")
	var vest_only := full.duplicate()
	vest_only["ammo"] = 0
	vest_only["shells"] = 0
	var gun_only := full.duplicate()
	gun_only.erase("vest")
	var r_bare := D.danger_for(s, "military", bare)
	var r_full := D.danger_for(k, "military", full)
	check_eq(D.risk_name(r_bare), "Severe", "unprepared: severe")
	check(D.risk_tier(r_full) <= 2, "vest and a loaded weapon: high at most (%s)" % D.risk_name(r_full))
	check(D.trip_danger(k, "military", "general", full) < 0.6 * D.trip_danger(s, "military", "general", bare), "preparation sharply lowers the trip's danger")
	check(D.trip_danger(k, "military", "general", vest_only) < D.trip_danger(s, "military", "general", bare), "the vest alone helps")
	check(D.trip_danger(k, "military", "general", gun_only) < D.trip_danger(s, "military", "general", bare), "a loaded weapon alone helps")
	check(D.risk_tier(D.danger_for(k, "military", full, "careful")) >= 1, "never low at the outpost (risk floor)")
	# a fight there can go badly; preparation changes the outcome
	var dmg_bare := 0.0
	var dmg_full := 0.0
	var hurt_bare := 0
	var badly := 0
	var shotguns := 0
	var n := 0
	for seed in range(1, STATS_SEEDS):
		var a := _state(seed)
		a.inventory.counts.erase("ammo")
		a.inventory.add("flashlight", 1)
		var ra := ExpeditionRun.simulate(a, "military", D.default_gear(a, "military"), [1, 1])
		dmg_bare += ra["damage"]
		if ra["damage"] > 0.0:
			hurt_bare += 1
		if ra["damage"] >= 20.0:
			badly += 1
		var b := _kit(_state(seed))
		b.inventory.remove("shotgun", 1)
		b.inventory.counts.erase("shells")
		var rb := ExpeditionRun.simulate(b, "military", D.default_gear(b, "military"), [0, 0])
		dmg_full += rb["damage"]
		if rb["gained"].has("shotgun"):
			shotguns += 1
		n += 1
	check(hurt_bare > n * 0.6, "unprepared, you usually get hurt (%d of %d)" % [hurt_bare, n])
	check(badly > 0, "it can go badly (%d trips with 20+ damage)" % badly)
	check(dmg_full < dmg_bare * 0.5, "prepared, far fewer injuries (%.0f vs %.0f)" % [dmg_full, dmg_bare])
	check(shotguns > 0 and shotguns < n / 2, "a shotgun is possible but not guaranteed (%d of %d trips)" % [shotguns, n])
	check(D.destination("military")["max_damage"] > D.MAX_DAMAGE, "the outpost can cost more health")


func test_other_dangerous_places_reward_preparation() -> void:
	for loc in ["police", "hospital", "gun_shop"]:
		var s := _state()
		s.inventory.add("flashlight", 1)
		var k := _kit(_state())
		check(D.danger_for(k, loc, D.default_gear(k, loc)) < D.danger_for(s, loc, {}), "%s: gear lowers the risk" % loc)
		check(D.risk_tier(D.danger_for(s, loc, {})) >= 2, "%s: high risk bare-handed" % loc)


# --- approaches -------------------------------------------------------------------------------

func test_approaches_change_time_loot_and_danger() -> void:
	var s := _kit(_state())
	check(D.nominal_minutes("hardware", "careful") > D.nominal_minutes("hardware") and D.nominal_minutes("hardware", "raid") < D.nominal_minutes("hardware"), "time by approach")
	var g := D.default_gear(s, "hardware")
	check(D.trip_danger(s, "hardware", "careful", g) < D.trip_danger(s, "hardware", "general", g), "careful is safer")
	check(D.trip_danger(s, "hardware", "raid", g) > D.trip_danger(s, "hardware", "general", g), "a raid is more dangerous")
	var raid := _avg("hardware", {"ammo": 6}, func(x): _kit(x), "loot", [0, 0], "raid")
	var gen := _avg("hardware", {"ammo": 6}, func(x): _kit(x), "loot", [0, 0], "general")
	check(raid > gen * 1.2, "a raid brings more (%.1f vs %.1f)" % [raid, gen])
	# targeted: much more of the target, less of everything else
	var tgt := 0
	var tgt_other := 0
	var gen_t := 0
	var gen_other := 0
	for seed in range(1, STATS_SEEDS):
		var a: Dictionary = ExpeditionRun.simulate(_state(seed), "construction_site", {}, [2, 2], "targeted", "iron")["gained"]
		var b: Dictionary = ExpeditionRun.simulate(_state(seed), "construction_site", {}, [2, 2], "general")["gained"]
		tgt += int(a.get("iron", 0))
		gen_t += int(b.get("iron", 0))
		tgt_other += _total(a) - int(a.get("iron", 0))
		gen_other += _total(b) - int(b.get("iron", 0))
	check(tgt > gen_t * 1.5, "targeted: more iron (%d vs %d)" % [tgt, gen_t])
	check(tgt_other < gen_other * 0.6, "targeted: less else (%d vs %d)" % [tgt_other, gen_other])
	# the approach changes the events: raids are loud, careful trips find lookouts
	var alarm := 0
	var lookout := 0
	for seed in range(1, 80):
		var x := _kit(_state(seed))
		if "alarm" in ExpeditionRun.create(x, "grocery", {"ammo": 6}, "raid").event_ids:
			alarm += 1
		if "lookout" in ExpeditionRun.create(x, "grocery", {}, "careful").event_ids:
			lookout += 1
		var gen_run := ExpeditionRun.create(x, "grocery", {}, "general")
		check(not "alarm" in gen_run.event_ids and not "lookout" in gen_run.event_ids, "approach-only events stay with their approach")
	check(alarm > 10 and lookout > 10, "approach events happen (alarm %d, lookout %d)" % [alarm, lookout])
	# raids leave the place guarded; the guard raises the danger next time
	var t := _kit(_state(5))
	var rr := ExpeditionRun.simulate(t, "grocery", {"ammo": 6}, [0, 0], "raid")
	check(rr["marks"].has("guarded"), "a raid leaves the place guarded (%s)" % [rr["marks"]])
	var before := D.trip_danger(t, "grocery", "general", {})
	D.apply_region(t, rr)
	t.total_minutes = float(rr["return_at"])
	check(t.region.has_flag("grocery", "guarded", t.day()), "guarded flag stored")
	check(D.trip_danger(t, "grocery", "general", {}) > before * 1.2, "guarded raises the danger")
	check(D.notes_text(t, "grocery").any(func(l): return l.contains("Guarded")), "and the notes say so")
	t.total_minutes += 5 * 1440.0
	check(not t.region.has_flag("grocery", "guarded", t.day()), "the guard wears off")
	# fighting your way through clears a place (and wins over the raid's guard)
	var c := _kit(_state(6))
	var run := ExpeditionRun.create(c, "clinic", {"ammo": 12, "flashlight": 1}, "raid")
	run.event_ids.assign(["waiting_room"])
	run.step = 0
	run.choose(0)
	var res := run.result()
	check(res["marks"].has("cleared") and not res["marks"].has("guarded"), "cleared beats guarded (%s)" % [res["marks"]])


func test_difficulty_scales_loot_and_danger() -> void:
	var levels := {}
	for lv in Difficulty.LEVELS:
		var loot := 0
		var hurt := 0
		for seed in range(1, STATS_SEEDS):
			var s := _state(seed)
			s.difficulty = lv
			var r := ExpeditionRun.simulate(s, "grocery", {}, [1, 1])
			loot += _total(r["gained"])
			if r["damage"] > 0.0:
				hurt += 1
		levels[lv] = [loot, hurt]
	check(levels["easy"][0] > levels["normal"][0] and levels["normal"][0] > levels["hard"][0], "loot easy > normal > hard (%s)" % [levels])
	check(levels["easy"][1] < levels["hard"][1], "injuries easy < hard (%s)" % [levels])
	var e := _state()
	e.difficulty = "easy"
	var h := _state()
	h.difficulty = "hard"
	var n := _state()
	check(absf(D.trip_danger(h, "grocery") / D.trip_danger(n, "grocery") - float(Difficulty.get_value("hard", "scavenge_danger"))) < 0.001, "danger x scavenge_danger (hard)")
	check(absf(D.trip_danger(e, "grocery") / D.trip_danger(n, "grocery") - float(Difficulty.get_value("easy", "scavenge_danger"))) < 0.001, "danger x scavenge_danger (easy)")
	check_eq(D.loot_scale(h), float(Difficulty.get_value("hard", "loot")), "loot x Difficulty.loot")


# --- the map API --------------------------------------------------------------------------------

func test_location_summary_for_every_id() -> void:
	var s := _state()
	s.inventory.add("flashlight", 1)
	var keys := ["risk_name", "risk_value", "travel_minutes", "search_minutes", "resources", "equipment", "approaches", "stock", "discovered",
		"name", "category", "category_name", "district", "desc", "minutes", "rewards", "targets", "notes", "available", "reason", "risk_bare_name", "requires"]
	for id in D.ORDER:
		for st in [s, null]:
			var sm := D.location_summary(id, st)
			for k in keys:
				check(sm.has(k), "%s summary has %s" % [id, k])
			if not sm.has("approaches"):
				continue
			check(sm["risk_name"] in D.RISK_NAMES and typeof(sm["risk_value"]) == TYPE_FLOAT, "%s: risk" % id)
			check_eq(sm["travel_minutes"], RegionLocations.travel_minutes(id), "%s: travel" % id)
			check(int(sm["search_minutes"]) > 0, "%s: search time" % id)
			check(not (sm["resources"] as Array).is_empty() and (sm["resources"] as Array).all(func(x): return Items.has(x)), "%s: resources are item ids" % id)
			check(not (sm["equipment"] as Array).is_empty(), "%s: equipment" % id)
			for e in sm["equipment"]:
				check(Items.has(e["id"]) and typeof(e["effect"]) == TYPE_STRING and e["effect"] != "", "%s: equipment entry %s" % [id, e])
			check_eq((sm["approaches"] as Array).map(func(a): return a["id"]), D.APPROACH_ORDER, "%s: four approaches in order" % id)
			for a in sm["approaches"]:
				for k in ["id", "name", "desc", "available", "reason"]:
					check(a.has(k), "%s approach has %s" % [id, k])
				check(a["available"] or a["reason"] != "", "%s: an unavailable approach says why" % id)
			check(float(sm["stock"]) >= 0.0 and float(sm["stock"]) <= 1.0, "%s: stock" % id)
			check_eq(sm["discovered"], (st if st != null else GameState.new()).region.is_discovered(id), "%s: discovered" % id)
	check(D.location_summary("nowhere", s).is_empty(), "unknown id -> {}")
	# equipment and rounds change the approaches
	var bare := _state()
	bare.inventory.counts.erase("ammo")
	var raid: Dictionary = D.location_summary("grocery", bare)["approaches"][3]
	check(not raid["available"] and raid["reason"].contains("loaded weapon"), "raid needs a loaded weapon (%s)" % raid["reason"])
	var armed := _kit(_state())
	check(D.location_summary("grocery", armed)["approaches"][3]["available"], "with rounds the raid is available")
	check(D.location_summary("military", armed)["equipment"][0]["id"] == "flashlight", "the outpost lists its requirement first")
	# approaches() for the map
	var aps := D.approaches()
	check_eq(aps.map(func(a): return a["id"]), D.APPROACH_ORDER, "approaches() ids")
	for a in aps:
		check(a["name"] != "" and a["desc"] != "", "approach texts")
	check(aps[2]["discovers"] and not aps[3]["discovers"], "careful discovers, raids don't")
	check_eq(D.parse_purpose("targeted:stone"), {"approach": "targeted", "target": "stone"}, "parse targeted")
	check_eq(D.parse_purpose("nonsense"), {"approach": "general", "target": ""}, "unknown -> general")
	check_eq(D.purpose_of("targeted", "iron"), "targeted:iron", "purpose_of")
