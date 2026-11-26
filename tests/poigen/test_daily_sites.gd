extends "res://tests/test_case.gd"
## Exp 009 (D): the daily opportunities (src/poigen/daily_sites.gd), the six
## new map sites, overrun places on the map and in travel, the midnight hook
## and F10 "POI generator".

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_daily_sites.dat"
const TravelFlow := preload("res://src/travel/travel_flow.gd")
const NEW_SITES := {
	"apartments": ["apartment", "suburbs", "residential"], "auto_garage": ["garage", "industrial", "construction"],
	"workshop": ["workshop", "industrial", "construction"], "factory": ["factory", "industrial", "construction"],
	"office_block": ["office", "centre", "knowledge"], "fire_station": ["fire_station", "centre", "medical"],
}


## A stand-in game for the hook and F10: state, where Eli is, toasts.
class FakeGame extends Node:
	var state: GameState
	var site := "home"
	var toasts := []
	var skipped := 0

	func is_home() -> bool:
		return site == "home"

	func site_id() -> String:
		return site

	func toast(text: String, _kind := "info") -> void:
		toasts.append(text)

	func dev_skip_to(_hour: float) -> void:
		skipped += 1
		state.total_minutes = floorf(state.total_minutes / 1440.0) * 1440.0 + 1440.0
		DailySites.on_new_day(self, state.day())


func _state(seed := 9001, all := true) -> GameState:
	var s := GameState.new_run(seed)
	if all:
		s.region.discover_all()
	return s


func _at_day(s: GameState, day: int) -> void:
	s.total_minutes = float(day - 1) * 1440.0 + 600.0


# --- the new sites ------------------------------------------------------------------------

func test_the_six_new_sites_exist_with_data() -> void:
	for id in NEW_SITES:
		var spec: Array = NEW_SITES[id]
		check(RegionLocations.has(id), "%s is on the map" % id)
		check_eq(RegionLocations.get_def(id)["district"], spec[1], "%s: district" % id)
		check_eq(RegionLocations.get_def(id)["category"], spec[2], "%s: category" % id)
		check(ExpeditionData.has_destination(id) and id in ExpeditionData.ORDER, "%s has expedition data" % id)
		check(PoiDefs.has(id), "%s is a POI" % id)
		check_eq(DailySites.archetype_of(id), spec[0], "%s: archetype" % id)
		check(not (ExpeditionData.destination(id)["loot"] as Array).is_empty(), "%s has loot" % id)
	for id in ["auto_garage", "workshop", "factory"]:
		check(DailySites.MATERIALS in DailySites.good_for(id), "%s: building materials (%s)" % [id, DailySites.good_for(id)])
	check("Medical" in DailySites.good_for("fire_station"), "the fire station: medical")
	check(DailySites.FOOD in DailySites.good_for("apartments"), "the apartments: food")
	check("tools" in DailySites.categories_of("fire_station") or "Tools" in DailySites.good_for("fire_station") or "medical" in DailySites.categories_of("fire_station"),
		"the fire station's categories (%s)" % [DailySites.categories_of("fire_station")])
	var t := RegionTerrain.shared()
	for id in NEW_SITES:
		check(t.connected_to_home(id), "%s has a road" % id)
	# existing places keep their ids and positions
	check_eq(RegionLocations.get_def("hardware")["pos"], Vector2(80, 76), "the hardware store didn't move")
	check_eq(RegionLocations.get_def("forest")["pos"], Vector2(47, 70), "the woods didn't move")


# --- the daily selection ----------------------------------------------------------------------

func test_two_days_the_selection_changes_and_setups_stay() -> void:
	var s := _state()
	_at_day(s, 2)
	var d2 := DailySites.today(s).duplicate(true)
	var n2 := (d2["available"] as Array).size()
	check(n2 >= 4 and n2 <= 6, "4-6 available on day 2 (%d)" % n2)
	check_eq((d2["available"] as Array).size() + (d2["overrun"] as Array).size(), RegionLocations.ids().size(), "every known place is in one list")
	var setups := {}
	for id in RegionLocations.ids():
		setups[id] = DailySites.setup(s, id)
	_at_day(s, 3)
	var d3 := DailySites.today(s)
	var n3 := (d3["available"] as Array).size()
	check(n3 >= 4 and n3 <= 6, "4-6 available on day 3 (%d)" % n3)
	check(d2["available"] != d3["available"], "the selection changes (%s -> %s)" % [d2["available"], d3["available"]])
	for id in d3["overrun"]:
		var st := DailySites.setup(s, id)
		check(not st["available"] and st["overrun_until"] >= 3, "%s: overrun, until day %d" % [id, st["overrun_until"]])
		check(st["archetype"] != "" and st["archetype"] == setups[id]["archetype"], "%s keeps its archetype" % id)
		check_eq(st["seed"], setups[id]["seed"], "%s keeps its seed" % id)
		check(DailySites.is_overrun(s, id), "%s is identifiable as overrun" % id)
	for id in d3["available"]:
		check(DailySites.setup(s, id)["available"], "%s: available" % id)
	var st: Dictionary = DailySites.setup(s, "factory")
	for k in ["id", "archetype", "family", "size", "surroundings", "categories", "risk", "seed", "hand_made", "available", "overrun_until"]:
		check(st.has(k), "a setup has %s" % k)
	check(st["size"] in ["s", "m", "l"] and st["family"] == "light_industry" and not st["hand_made"], "the factory's setup")
	check(DailySites.setup(s, "clinic")["hand_made"], "the clinic is hand-made")
	check_eq(DailySites.setup(s, "nowhere"), {}, "unknown id -> {}")
	check(DailySites.seed_of(s, "factory") != DailySites.seed_of(_state(9002), "factory"), "another run, another seed")


func test_the_first_day_is_open_and_the_start_has_four_to_six() -> void:
	var s := _state(77, false)
	var d1 := DailySites.today(s)
	check_eq((d1["available"] as Array).size(), RegionState.START_KNOWN.size(), "day 1: every known place is open")
	check((d1["overrun"] as Array).is_empty(), "nothing overrun on day 1")
	_at_day(s, 2)
	var d2 := DailySites.today(s)
	var n := (d2["available"] as Array).size()
	check(n >= 4 and n <= 6, "day 2 with the starting places: 4-6 open (%d)" % n)
	check("forest" in d2["available"], "Pine Woods is always open")
	check((d2["overrun"] as Array).size() == RegionState.START_KNOWN.size() - n, "the rest are overrun")
	check(not ("police" in d2["available"] or "police" in d2["overrun"]), "unknown places are in neither list")


func test_the_selection_survives_save_and_load() -> void:
	var s := _state(4242)
	_at_day(s, 5)
	var d := DailySites.today(s).duplicate(true)
	var seeds := {}
	for id in RegionLocations.ids():
		seeds[id] = DailySites.setup(s, id)["seed"]
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(back.region.daily["available"], d["available"], "the open places come back")
	check_eq(back.region.daily["overrun"], d["overrun"], "the overrun places come back")
	check_eq(int(back.region.daily["day"]), 5, "the day comes back")
	for id in RegionLocations.ids():
		check_eq(DailySites.setup(back, id)["seed"], seeds[id], "%s: the same seed after loading" % id)
		check_eq(DailySites.setup(back, id)["archetype"], DailySites.archetype_of(id), "%s: the same archetype" % id)
	# the next day from the loaded state is the same as from the original
	_at_day(s, 6)
	_at_day(back, 6)
	check_eq(DailySites.today(back)["available"], DailySites.today(s)["available"], "the next day is the same either way")
	# an older save has no selection: it is made on first use
	var old := s.to_dict()
	(old["region"] as Dictionary).erase("daily")
	var o := GameState.from_dict(old)
	check(o.region.daily.is_empty(), "no selection in an older save")
	var n := (DailySites.today(o)["available"] as Array).size()
	check(n >= 4 and n <= 6 and int(o.region.daily["day"]) == o.day(), "made on load (%d open)" % n)
	# garbage is dropped
	check(RegionState.from_dict({"daily": {"day": "x"}}).daily.is_empty(), "a bad day is dropped")
	var g := RegionState.from_dict({"daily": {"day": 3, "available": ["forest", "atlantis", 5], "overrun": ["forest", "clinic"], "streak": {"forest": "z", "clinic": 2}}})
	check_eq(g.daily["available"], ["forest"], "unknown ids dropped")
	check_eq(g.daily["overrun"], ["clinic"], "a place is in one list only")
	check_eq(g.daily["streak"], {"clinic": 2}, "non-numbers dropped")


func test_balance_over_sixty_days() -> void:
	for seed in [11, 12, 13]:
		for all in [true, false]:
			var s := _state(seed, all)
			var food := 0
			var mats := 0
			var bad_n := 0
			var seen := {}
			var streaks := 0
			var prev := []
			for day in range(2, 62):
				DailySites.refresh(s, day)
				var av: Array = s.region.daily["available"]
				if av.size() < 4 or av.size() > 6:
					bad_n += 1
				if DailySites._any_gives(av, DailySites.FOOD):
					food += 1
				if DailySites._any_gives(av, DailySites.MATERIALS):
					mats += 1
				check("forest" in av, "seed %d day %d: the woods are open" % [seed, day])
				for id in av:
					seen[id] = true
					if id in prev and id != "forest":
						streaks += 1
				prev = av.duplicate()
			var known := RegionLocations.ids().size() if all else RegionState.START_KNOWN.size()
			print("    seed %d (%s): food %d/60, materials %d/60, %d places seen of %d, %d carried over" % [seed, "all known" if all else "start", food, mats, seen.size(), known, streaks])
			check_eq(bad_n, 0, "4-6 open every day")
			check(food >= 51, "seed %d: food most days (%d/60)" % [seed, food])
			check(mats >= 48, "seed %d: building materials besides the woods most days (%d/60)" % [seed, mats])
			check(seen.size() >= known - 1, "seed %d: the places rotate (%d of %d seen)" % [seed, seen.size(), known])
			check(streaks > 0, "seed %d: some places stay several days" % seed)


func test_a_running_expedition_is_never_removed() -> void:
	var s := _state(31)
	for day in range(2, 30):
		DailySites.refresh(s, day, ["hospital"])
		check("hospital" in s.region.daily["available"], "day %d: the hospital (Eli is there) stays open" % day)
	# the midnight hook keeps the POI Eli is at, and the leg's destination
	var g := FakeGame.new()
	add(g)
	g.state = _state(32)
	g.site = "military"
	for day in range(2, 20):
		g.state.total_minutes = float(day - 1) * 1440.0
		DailySites.on_new_day(g, day)
		check("military" in g.state.region.daily["available"], "day %d: never ejected" % day)
	# word of an unknown place, now and then, only through the hook
	var h := FakeGame.new()
	add(h)
	h.state = _state(33, false)
	var heard := 0
	for day in range(2, 40):
		h.state.total_minutes = float(day - 1) * 1440.0
		var r := DailySites.on_new_day(h, day)
		if str(r.get("heard", "")) != "":
			heard += 1
			check(h.state.region.is_discovered(r["heard"]) and r["heard"] in h.state.region.daily["available"], "a place heard of is known and open")
	check(heard > 0 and heard < 25, "word of new places now and then (%d in 38 days)" % heard)
	check_eq(h.toasts.size(), heard, "each says so")


func test_travel_refuses_an_overrun_place() -> void:
	var s := _state(51)
	_at_day(s, 4)
	var over: Array = DailySites.overrun_ids(s)
	var open: Array = DailySites.available_ids(s)
	if not check(not over.is_empty() and open.size() >= 2, "something is overrun today"):
		return
	var id: String = over[0]
	check_eq(TravelRules.block_reason(s, id), DailySites.OVERRUN_LINE, "from home: refused")
	var here: String = open[0] if open[0] != "forest" else open[1]
	check_eq(TravelRules.leg_block_reason(s, here, id), DailySites.OVERRUN_LINE, "from a POI: refused")
	check_eq(TravelRules.leg_block_reason(s, id, TravelRules.HOME), "", "home always works")
	var other: String = open[1] if open[0] != "forest" else (open[2] if open.size() > 2 else "forest")
	check_eq(TravelRules.leg_block_reason(s, here, other), "", "an open place: fine")
	DailySites.force_available(s, id)
	check_eq(TravelRules.block_reason(s, id), "", "made available (F10): fine")
	# test sites
	var tid := DailySites.test_id("apartment", 1234)
	check_eq(tid, "gen:apartment:1234", "a test id")
	check_eq(DailySites.parse_test_id(tid), {"archetype": "apartment", "seed": 1234}, "parsed")
	check(DailySites.parse_test_id("gen:apartment").is_empty() and DailySites.parse_test_id("gen:x:y").is_empty(), "malformed ids")
	check_eq(TravelRules.block_reason(s, tid), "", "travel accepts a test site")
	check_eq(TravelRules.minutes(tid), 0, "0 minutes away")
	check(RegionLocations.name_of(tid).contains("Apartment"), "a name: %s" % RegionLocations.name_of(tid))
	var st := DailySites.setup(s, tid)
	check(st["test"] and st["archetype"] == "apartment" and st["seed"] == 1234 and st["like"] == "apartments", "its setup: %s" % st)
	check(not s.region.discover(tid), "never stored in the region")
	s.region.poi[tid] = {"c": {}}
	DailySites.forget_test(s, tid)
	check(not s.region.poi.has(tid), "cleared on leaving")
	check(not s.to_dict()["region"]["poi"].has(tid), "and not saved")


func test_the_map_shows_overrun_places() -> void:
	var s := _state(61)
	_at_day(s, 3)
	var over: String = DailySites.overrun_ids(s)[0]
	var open: String = DailySites.available_ids(s)[0]
	var m := RegionMapScreen.new()
	add(m)
	m.open(s)
	await frames(2)
	m.select(over, false)
	await frames(1)
	var line: Label = m.find_child("Overrun", true, false)
	check(line != null and line.text == DailySites.OVERRUN_LINE, "the panel says it's overrun")
	var tb: Button = m.find_child("Travel", true, false)
	check(tb != null and tb.disabled, "Travel is disabled")
	check(not m.request_travel(), "and refused")
	var e := {}
	for x in m.markers.entries:
		if x["id"] == over:
			e = x
	check(bool(e.get("overrun", false)), "the marker is marked overrun")
	check(over in m.shown_ids(), "still on the map")
	m.select(open, false)
	await frames(1)
	check(m.find_child("Overrun", true, false) == null, "an open place: no overrun line")
	tb = m.find_child("Travel", true, false)
	check(tb != null and not tb.disabled, "Travel works there")
	check(DailySites.availability_text(s, open).begins_with("Open"), "today's line: %s" % DailySites.availability_text(s, open))
	m.close()


func test_the_f10_poi_generator_section() -> void:
	var g := FakeGame.new()
	add(g)
	g.state = _state(71)
	_at_day(g.state, 2)
	var m := DevMenu.new()
	add(m)
	m.setup(g.state, g)
	m.set_open(true)
	await frames(2)
	for t in ["Today's places", "Next day (00:00)", "Inspect setup", "Generate test site", "Dormant psycho", "Force behaviour",
			"Reveal stash", "Diagnostics", "Return home (POI gen)"]:
		check(m.button(t) != null, "F10 has '%s'" % t)
	m.button("Today's places").pressed.emit()
	check(m.last_status.begins_with("Day 2 · open"), "today: %s" % m.last_status)
	m.button("Next day (00:00)").pressed.emit()
	check(g.skipped == 1 and m.last_status.begins_with("Day 3"), "next day: %s" % m.last_status)
	var site: OptionButton = m.find_child("PoigenSite", true, false)
	site.select(ExpeditionData.ORDER.find("factory"))
	m.button("Inspect setup").pressed.emit()
	check(m.last_status.contains("archetype=factory") and m.last_status.contains("seed="), "inspect: %s" % m.last_status)
	m.button("Generate test site").pressed.emit()
	check(m.last_status != "", "generate says something: %s" % m.last_status)
	m.button("Dormant psycho").pressed.emit()
	check(m.last_status.contains("No dormant"), "no POI here: %s" % m.last_status)
	m.button("Diagnostics").pressed.emit()
	check_eq(m.last_status, "Not at a POI.", "diagnostics at home")
	check((m.find_child("PoigenArchetype", true, false) as OptionButton).item_count >= 10, "archetypes listed")


## The game itself: midnight makes the new day's selection, and Eli at a
## POI is not ejected (the place stays open).
func test_midnight_in_the_game_refreshes_and_never_ejects() -> void:
	TravelFlow.skip_animation = true
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 23.0 * 60.0 + 50.0
	g._advance_clock(20.0)
	check_eq(int(s.region.daily.get("day", 0)), 2, "the hook made day 2's selection")
	var n := (s.region.daily["available"] as Array).size()
	check(n >= 4 and n <= 6, "4-6 open (%d)" % n)
	# at a POI over midnight
	var id: String = (s.region.daily["available"] as Array).filter(func(x): return x != "forest")[0]
	s.total_minutes = 1440.0 + 10.0 * 60.0
	check_eq(await g.travel.depart(id), "", "sets out for %s" % id)
	g.queue_free()
	await frames(2)
	g = await _boot(GameLaunch.mode)
	s = g.debug_state()
	check(not g.is_home() and g.site_id() == id, "at %s" % id)
	g.debug_kill_enemies()
	s.total_minutes = 2.0 * 1440.0 - 5.0
	g._advance_clock(10.0)
	check_eq(int(s.region.daily.get("day", 0)), 3, "day 3's selection")
	check(id in s.region.daily["available"], "the place Eli is at stays open")
	check(not g.is_home() and g.site_id() == id and g.left_to == "", "Eli is still there")
	g.queue_free()
	await frames(2)


func _boot(mode: String) -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 9009
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.death_delay = 0.05
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	return g


func cleanup() -> void:
	tree.paused = false
	DailySites.PER_DAY = DailySites.PER_DAY_DEFAULT
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	GameLaunch.notice = ""
	GameLaunch.site = "home"
	GameLaunch.carry = {}
	TravelFlow.skip_animation = false
