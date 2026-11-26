extends "res://tests/test_case.gd"
## Exp 009 (G): the building generator (src/poigen/). Every archetype for 20
## seeds: valid (reachable from the entry), its room programme, exactly one
## stash, enough containers, furniture in context, deterministic per seed and
## different for another; the apartment's dark exit; the staged API; PoiDefs
## routing (the same building twice, the recorded seed on revisits, a
## placeholder-era record started afresh); the stash's own roll and no
## refill; a built PoiWorld for five archetypes through the POI harness.

const PREVIEW := "res://src/poi/poi_preview.tscn"
const SEEDS := 20


func _sig(L: Dictionary) -> String:
	return str([L["walls"], L["doors"], L["props"], L["containers"], L["dormant"], L["entry"], L.get("exits", [])])


func _required(a: Dictionary) -> Array:
	var out := []
	var lists := []
	match str(a["plan"]):
		"corridor":
			lists = [a["front"]["rooms"], a["cols"][0], a["cols"][1]]
		"yard":
			for band in a["hut"]["bands"]:
				lists.append(band["rooms"])
		_:
			for band in a["bands"]:
				lists.append(band["rooms"])
	for l in lists:
		for r in l:
			if r.get("req", false) or r.get("grow", false):
				out.append(str(r["type"]))
	return out


func test_every_archetype_generates_valid_buildings() -> void:
	var ms := {}
	for arch in PoiArchetypes.ids():
		var a := PoiArchetypes.get_arch(arch)
		var req := _required(a)
		var total := 0.0
		for k in SEEDS:
			var L := PoiGenerator.generate(PoiArchetypes.test_setup(arch, 500 + k * 13))
			var tag := "%s #%d" % [arch, k]
			var v := PoiGenerator.validate(L)
			check(v["ok"], "%s: valid %s" % [tag, v["problems"]])
			check(not L["diag"]["fallback"], "%s: no fallback needed" % tag)
			total += float(L["diag"]["ms"])
			# the programme: every required room type is there
			var types := {}
			for r in L["rooms"]:
				types[r["type"]] = int(types.get(r["type"], 0)) + 1
			for t in req:
				check(types.has(t), "%s: has its %s (%s)" % [tag, t, types.keys()])
			# exactly one stash, the stash table, its id recorded
			var stashes := (L["containers"] as Array).filter(func(c): return c.get("stash", false))
			check(stashes.size() == 1 and stashes[0]["table"] == "stash" and L["stash"] == stashes[0]["id"], "%s: one main stash" % tag)
			check((L["containers"] as Array).size() >= PoiGenerator.MIN_CONTAINERS, "%s: %d containers" % [tag, (L["containers"] as Array).size()])
			check((L["containers"] as Array).any(func(c): return not c["picked"] and not c.get("stash", false)), "%s: something left to search" % tag)
			# furniture in context (beds in bedrooms and wards, no sofa on a work floor, ...)
			var room_type := {"yard": "yard"}
			for r in L["rooms"]:
				room_type[r["id"]] = r["type"]
			for p in (L["props"] as Array) + (L["containers"] as Array):
				if p.get("stash", false):
					continue
				var rt := str(room_type.get(str(p.get("room", "")), ""))
				check(PoiFurniture.fits_room(str(p["type"]), rt), "%s: a %s in the %s" % [tag, p["type"], rt])
				check(HousePlan.YARD.encloses(p["rect"]), "%s: %s on the lot" % [tag, p["type"]])
			for d in L["dormant"]:
				check(d["behaviour"] in ["bang", "circle", "sway", "stare", "tap"], "%s: dormant behaviour %s" % [tag, d["behaviour"]])
				if d["behaviour"] == "circle":
					check(float(d["radius"]) > 0.5, "%s: circling has room" % tag)
			check(not (L["hide"] as Array).is_empty() and not (L["wander"] as Array).is_empty(), "%s: hiding and wander places" % tag)
			check(L["bounds"] is Rect2 and L["archetype"] == arch, "%s: bounds and archetype" % tag)
			check(L["exit_kind"] == ("dark" if arch == "apartment" else "car"), "%s: exit kind %s" % [tag, L["exit_kind"]])
			if arch == "apartment":
				check(L.get("dark_exit") is Rect2 and (L["dark_exit"] as Rect2).get_area() > 1.0, "%s: the hallway's dark end" % tag)
			check(not (L["exits"] as Array).is_empty() and HousePlan.YARD.has_point(L["entry"]), "%s: an entry and a way out" % tag)
		ms[arch] = total / SEEDS
	print("  generation ms per archetype: ", ms)


func test_deterministic_per_seed_and_different_for_another() -> void:
	for arch in PoiArchetypes.ids():
		var a := PoiGenerator.generate(PoiArchetypes.test_setup(arch, 4711))
		var b := PoiGenerator.generate(PoiArchetypes.test_setup(arch, 4711))
		var c := PoiGenerator.generate(PoiArchetypes.test_setup(arch, 4712))
		check_eq(_sig(a), _sig(b), "%s: the same seed, the same building" % arch)
		check(_sig(a) != _sig(c), "%s: another seed, another building" % arch)


func test_staged_api_steps_to_the_same_layout() -> void:
	var setup := PoiArchetypes.test_setup("hospital", 31)
	var ctx := PoiGenerator.begin(setup)
	var last := -1.0
	var stages := []
	var n := 0
	while not ctx.step():
		check(ctx.progress >= last and ctx.progress < 1.0, "progress grows (%s)" % ctx.progress)
		last = ctx.progress
		if not stages.has(ctx.stage):
			stages.append(ctx.stage)
		n += 1
		if n > 200:
			break
	check(ctx.done and ctx.progress == 1.0 and not ctx.layout.is_empty(), "done")
	check(stages.has("furniture") and stages.has("exterior"), "named stages (%s)" % [stages])
	check_eq(_sig(ctx.layout), _sig(PoiGenerator.generate(setup)), "the same layout as generate()")
	check(float(ctx.layout["diag"]["ms"]) > 0.0, "the time is measured")


func test_routing_and_identity() -> void:
	check_eq(PoiArchetypes.for_site("forest"), "hand_made", "Pine Woods stays hand-made")
	for id in ["apartments", "auto_garage", "workshop", "factory", "office_block", "fire_station"]:
		check(PoiArchetypes.has(PoiArchetypes.for_site(id)), "the new site %s has an archetype" % id)
	for id in PoiDefs.ids():
		check(PoiDefs.HAND_MADE.has(id) or PoiDefs.is_generated(id), "%s: hand-made or generated" % id)
	# a test site: the same definition and containers twice
	var t1 := PoiDefs.get_def("gen:supermarket:77")
	var t2 := PoiDefs.get_def("gen:supermarket:77")
	check(PoiDefs.has("gen:supermarket:77") and t1.get("generated", false), "a test site is generated")
	check_eq(str(t1["layout"]["containers"]), str(t2["layout"]["containers"]), "the same containers twice")
	# a map site with a run: the same building twice, and on a revisit even if the run's seed moved on
	var st := GameState.new_run(321)
	var g1 := PoiDefs.get_def("grocery", st)
	var g2 := PoiDefs.get_def("grocery", st)
	check_eq(str(g1["layout"]["containers"]), str(g2["layout"]["containers"]), "grocery: the same containers twice")
	var r := PoiState.begin_visit(st, "grocery")
	check(r.has("gen") and int(r["gen"]["seed"]) == int(g1["seed"]) and int(r["gen"]["v"]) == PoiGenerator.VERSION, "the first visit records the seed")
	PoiState.finish_visit(st, "grocery")
	st.run["seed"] = 999
	var g3 := PoiDefs.get_def("grocery", st)
	check_eq(g3["gen_key"], g1["gen_key"], "a revisit rebuilds the recorded building")
	check_eq(PoiDefs.get_def("grocery")["gen_key"], g1["gen_key"], "without a state: the building last resolved")


func test_placeholder_era_record_starts_afresh() -> void:
	var st := GameState.new_run(55)
	st.region.poi["homes"] = {"c": {"slot_1": {"items": {"snacks": 2}, "searched": true, "day": 1}}, "taken": {"loose": 1},
		"forced": {"rear": true}, "visits": 2, "last_day": 1}
	var r := PoiState.begin_visit(st, "homes")
	var L: Dictionary = PoiDefs.get_def("homes", st)["layout"]
	var ids := (L["containers"] as Array).map(func(c): return c["id"])
	check(not r["c"].has("slot_1") and r["c"].size() == ids.size(), "the old containers are gone, the new ones generated")
	for id in ids:
		check(r["c"].has(id), "container %s has its record" % id)
	check(r["forced"].is_empty() and int(r["visits"]) == 3, "forced doors dropped, the visits kept")
	# a save made at the place mid-visit (placeholder era) is regenerated in place
	var st2 := GameState.new_run(56)
	st2.region.poi["cul_de_sac"] = {"c": {"slot_3": {"items": {}, "searched": false, "day": 1}}, "visit": {"day": 1, "car": false, "pack": {"water": 1}, "cargo": {}}}
	var r2 := PoiState.begin_visit(st2, "cul_de_sac")
	check(PoiState.in_visit(r2) and r2["visit"]["pack"].get("water", 0) == 1 and not r2["c"].has("slot_3"), "the visit goes on in the new building")


func test_the_stash_rolls_its_own_and_never_refills() -> void:
	var filled := 0
	for k in 20:
		var st := GameState.new_run(700 + k)
		var r := PoiState.begin_visit(st, "gen:police:%d" % k)
		var L: Dictionary = PoiDefs.get_def("gen:police:%d" % k, st)["layout"]
		var box: Dictionary = r["c"][L["stash"]]
		if not (box["items"] as Dictionary).is_empty():
			filled += 1
	check(filled >= 6 and filled <= 20, "the stash is useful, not guaranteed (%d / 20)" % filled)
	check(not PoiState.best_unique(PoiDefs.get_def("gun_shop")).is_empty(), "the gun shop's best one-of-a-kind item")
	# loot it, come back a month later: still empty
	var st := GameState.new_run(808)
	var r := PoiState.begin_visit(st, "gun_shop")
	var stash := "gun_locker"
	r["c"][stash]["items"].clear()
	r["c"][stash]["searched"] = true
	for c in r["c"]:
		r["c"][c]["searched"] = true
	PoiState.finish_visit(st, "gun_shop")
	st.total_minutes += 30.0 * 1440.0
	r = PoiState.begin_visit(st, "gun_shop")
	check((r["c"][stash]["items"] as Dictionary).is_empty() and r["c"][stash]["searched"], "looted stays looted")
	for id in ["forest", "convenience", "library", "hardware", "gun_shop", "clinic"]:
		var L: Dictionary = PoiDefs.get_def(id)["layout"]
		check(PoiState.stash_of(L).get("id", "") == L.get("stash", "-"), "%s: one marked stash (%s)" % [id, L.get("stash", "")])


func test_built_worlds_load() -> void:
	for arch in ["house_small", "supermarket", "workshop", "hospital", "apartment"]:
		var id := PoiArchetypes.test_id(arch, 2024)
		var h: Node = (load(PREVIEW) as PackedScene).instantiate()
		h.configure(id, false, 4242)
		add(h)
		await physics_frames(3)
		var w: PoiWorld = h.world
		check(w is PoiWorld and w.is_inside_tree(), "%s: built" % arch)
		check(w.nav.is_walkable(w.nav.cell_of(w.entry_point())), "%s: the entry is walkable" % arch)
		for e in w.exit_points():
			check(not w.nav.find_path(w.entry_point(), e).is_empty(), "%s: a way to exit %s" % [arch, e])
		check(w.spots_of("container").size() >= PoiGenerator.MIN_CONTAINERS, "%s: containers (%d)" % [arch, w.spots_of("container").size()])
		check(w.grid.solid_count > 5000 and not w.rooms().is_empty(), "%s: voxel walls and rooms" % arch)
		var L: Dictionary = w.layout
		var st: Dictionary = PoiState.stash_of(L)
		check(not w.nav.find_path(w.entry_point(), PoiLayouts.front_point(st["rect"], st["facing"])).is_empty(), "%s: the game's navigation reaches the stash" % arch)
		h.queue_free()
		await frames(2)
