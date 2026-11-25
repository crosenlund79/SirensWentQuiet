extends "res://tests/test_case.gd"
## Experiment 005 (C): room comfort (diminishing returns, light, warmth,
## exposure, labels), mood (drift, memories, effects, save), and one smoke run
## in the real game scene (rooms found on the ground floor, the HUD line, the
## Home tab, F10, damage exposing a room, the sleep bonus, save and continue).

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_comfort.dat"


func _room(items: Array, extra := {}) -> Dictionary:
	var info := {"area": 16.0, "bbox": Rect2(0, 0, 4, 4), "items": items.map(func(t): return {"type": t, "state": "intact"}),
		"light": "day", "windows": {"intact": 1, "broken": 0, "boarded": 0}, "floor": 1.0}
	info.merge(extra, true)
	return HomeComfort.evaluate(info)


func test_diminishing_returns_and_balance() -> void:
	var one := float(_room(["chair"])["comfort"])
	var twenty := []
	for i in 20:
		twenty.append("chair")
	var many := float(_room(twenty)["comfort"])
	check(many - one < ComfortCatalog.value_of("chair") * 1.01, "twenty chairs add less than one more chair's worth (%.1f vs %.1f)" % [many, one])
	var beds := float(_room(["bed", "bed", "bed", "bed"])["comfort"])
	var balanced := float(_room(["bed", "rug", "painting", "chair"])["comfort"])
	check(balanced > beds, "a balanced room beats a room of beds (%.1f > %.1f)" % [balanced, beds])
	var junk := []
	for t in ComfortCatalog.TYPES:
		for i in 6:
			junk.append(t)
	var full := _room(junk)
	var furniture := 0.0
	for f in full["factors"]:
		if not str(f[0]) in ["Finished floor", "Well furnished", "Daylight through the window"]:
			furniture += float(f[1])
	check(furniture <= ComfortCatalog.FURNITURE_CAP + 0.01, "furniture is capped (%.1f)" % furniture)


func test_light_warmth_and_damage() -> void:
	var base := ["bed", "rug"]
	var day := float(_room(base)["comfort"])
	var night_dark := _room(base, {"light": "night"})
	check(float(night_dark["comfort"]) < day, "dark at night is worse than daylight")
	check(not night_dark["lit"] and night_dark["hints"].has("A lamp would help here."), "a dark room hints at a lamp")
	var night_lamp := float(_room(base, {"light": "night", "lamps": 1})["comfort"])
	check(night_lamp > float(night_dark["comfort"]) + 5.0, "a working lamp lifts the dark room")
	var fire := float(_room(base, {"fire": "here"})["comfort"])
	var near := float(_room(base, {"fire": "near"})["comfort"])
	check(fire > near and near > day, "the fireplace warms its room most, the next room a little (%.1f > %.1f > %.1f)" % [fire, near, day])
	var exposed := _room(base, {"exposed": true})
	check(float(exposed["comfort"]) < day - 6.0 and exposed["exposed"], "open to the outside hurts")
	var broken := _room(base, {"windows": {"intact": 0, "broken": 1, "boarded": 0}})
	check(broken["exposed"] and float(broken["comfort"]) < day - 5.0, "a broken window exposes the room")
	var boarded := float(_room(base, {"windows": {"intact": 0, "broken": 0, "boarded": 1}})["comfort"])
	check(boarded < day and boarded > float(broken["comfort"]), "boarded: no daylight, but better than broken")
	var basement := _room([], {"windows": {}, "floor": 0.0})
	check(int(basement["level"]) <= 1, "a bare dark basement is uncomfortable (%s)" % basement["level_name"])
	var cosy := _room(["chair", "rug", "table_lamp", "storage_chest", "painting"], {"windows": {}, "floor": 1.0, "lamps": 1, "light": "night"})
	check(int(cosy["level"]) >= 2, "a lit, furnished basement with a floor is fine (%s)" % cosy["level_name"])


func test_labels() -> void:
	check_eq(HomeComfort.label_for([{"type": "bed"}, {"type": "sofa"}], false, 20.0, Rect2(0, 0, 5, 4)), "Bedroom")
	check_eq(HomeComfort.label_for([{"type": "stove"}], false, 20.0, Rect2(0, 0, 5, 4)), "Kitchen")
	check_eq(HomeComfort.label_for([{"type": "stove"}, {"type": "sofa"}], false, 20.0, Rect2(0, 0, 5, 4)), "Kitchen & living room")
	check_eq(HomeComfort.label_for([], true, 20.0, Rect2(0, 0, 5, 4)), "Living room", "a fireplace makes a living room")
	check_eq(HomeComfort.label_for([{"type": "tool_cabinet"}], false, 20.0, Rect2(0, 0, 5, 4)), "Workshop")
	check_eq(HomeComfort.label_for([{"type": "crate"}, {"type": "shelves"}, {"type": "storage_chest"}], false, 20.0, Rect2(0, 0, 5, 4)), "Storage room")
	check_eq(HomeComfort.label_for([], false, 4.0, Rect2(0, 0, 4, 1)), "Hallway")
	check_eq(HomeComfort.label_for([], false, 20.0, Rect2(0, 0, 5, 4)), "Room")


func test_mood_drift_memories_and_save() -> void:
	var s := GameState.new_run(1)
	check_eq(s.mood, Mood.START, "a new run starts Content")
	check_eq(Mood.name_of(s.mood), "Content")
	var good := {"house": 24.0}
	var t0 := float(Mood.target(s, good)["target"])
	var t1 := float(Mood.target(s, {"house": 0.0, "cold": true, "exposed_rooms": 2})["target"])
	check(t0 > t1 + 15.0, "a comfortable home vs a cold, open shelter (%.0f vs %.0f)" % [t0, t1])
	Mood.step(s, good, 10.0)
	var after := s.mood
	check(after > Mood.START and after < t0, "it drifts slowly (%.1f)" % after)
	Mood.remember(s, "attack")
	Mood.remember(s, "attack")
	check_eq(s.mood_state["mem"].size(), 1, "the same memory doesn't stack")
	var with_attack := float(Mood.target(s, good)["target"])
	check(with_attack < t0 - 9.0, "an attack lowers the target")
	var s2 := GameState.new_run(1)
	Mood.remember(s2, "attack")
	Mood.step(s, good, 8.0 * 60.0)
	Mood.step(s2, {"house": 0.0}, 8.0 * 60.0)
	check(absf(s.mood_state["mem"][0]["v"]) < absf(s2.mood_state["mem"][0]["v"]), "a comfortable home helps a bad memory fade faster")
	check(Mood.rest_scale(85.0, 4) > Mood.rest_scale(58.0, 2) and Mood.rest_scale(58.0, 2) > Mood.rest_scale(10.0, 0), "rest: good mood and a cosy room help, misery hurts")
	check_eq(Mood.rest_scale(58.0, 2), 1.0, "Content in a Content room: normal sleep")
	# the sleep bonus reaches GameState
	var a := GameState.new_run(1)
	a.energy = 20.0
	a.rest_scale = 1.2
	a.advance(60.0, true)
	check(absf(a.energy - (20.0 + SurvivalTuning.SLEEP_ENERGY_PER_HOUR * 1.2)) < 0.01, "rest_scale scales sleep energy (%.2f)" % a.energy)
	# save
	s.mood = 33.0
	var r := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(r.mood, 33.0, "mood survives a save")
	check_eq(r.mood_state["mem"].size(), s.mood_state["mem"].size(), "memories survive a save")
	var old := s.to_dict()
	old.erase("mood")
	old.erase("mood_state")
	var o := GameState.from_dict(old)
	check_eq(o.mood, Mood.START, "an older save starts Content")
	var junk := s.to_dict()
	junk["mood"] = "lots"
	junk["mood_state"] = {"mem": [{"id": "nope", "v": 3}, {"id": "attack", "v": -999}], "bleak": NAN}
	var j := GameState.from_dict(junk)
	check(j != null and j.mood == Mood.START and j.mood_state["mem"].size() == 1 and j.mood_state["mem"][0]["v"] >= -20.0, "junk mood data is cleaned")


# --- in the game ---------------------------------------------------------------------------

func _boot(mode := "new") -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 4242
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	return g


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()


func test_comfort_in_the_game() -> void:
	var g: Node = await _boot()
	var c: Node = g.comfort
	check(c != null, "the game has a comfort helper")
	var labels := {}
	for r in c.rooms.get(0, []):
		labels[r["label"]] = r
	print("  rooms: ", c.dev_show())
	print("  timing: ", c.stats)
	for r in c.rooms.get(0, []):
		print("  ", r["label"], " ", r["comfort"], " ", r["factors"], " hints ", r["hints"])
	print("  windows: ", c.windows.get(0, []).map(func(w): return [w["centre"], w["state"]]))
	print("  mood: ", c.mood_info)
	for want in ["Bedroom", "Bathroom", "Kitchen & living room", "Workshop"]:
		check(labels.has(want), "found the %s (%s)" % [want, labels.keys()])
	check_eq(c.rooms.get(0, []).size(), 4, "four rooms on the ground floor")
	for r in c.rooms.get(0, []):
		check(not r["exposed"], "%s is closed (%s)" % [r["label"], r["factors"]])
	var bed: Dictionary = c.room_at(0, Vector2(2.0, 2.5))
	check_eq(bed.get("label", ""), "Bedroom", "room_at in the bedroom")
	check(int(bed.get("level", 0)) >= 3, "the bedroom is comfortable (%s %.1f)" % [bed.get("level_name"), bed.get("comfort", 0.0)])
	var living: Dictionary = c.room_at(0, Vector2(4.0, 6.0))
	check_eq(living.get("fire", ""), "here", "the lit fireplace warms the living room")
	check(c.house_comfort() > 10.0, "the house starts pleasant (%.1f)" % c.house_comfort())
	# the HUD line
	g.debug_teleport_player(Vector2(2.0, 2.5))
	await frames(2)
	c._update_hud(true)
	var hud: Dictionary = g.hud.debug_texts()
	check(str(hud["home_room"]).begins_with("Bedroom · "), "HUD room line (%s)" % hud["home_room"])
	check(str(hud["home_mood"]).begins_with("Mood: "), "HUD mood line (%s)" % hud["home_mood"])
	check(g.state.rest_scale > 1.0, "sleeping in the comfortable bedroom rests better (x%.2f)" % g.state.rest_scale)
	# the Home tab
	g.debug_open("inventory")
	await frames(1)
	g.ui.inventory.show_tab("home")
	await frames(1)
	var title := g.ui.inventory.find_child("RoomTitle", true, false) as Label
	check(title != null and title.text.begins_with("Bedroom"), "the Home tab shows the room (%s)" % (title.text if title else "none"))
	check(g.ui.inventory.find_child("Causes", true, false) != null, "and the mood causes")
	g.debug_close()
	await frames(1)
	# the fire out: the living room cools (signature poll, no signal)
	g.home.fireplace.set_lit(false)
	await frames(2)
	c._poll_t = 1.0
	await frames(2)
	var cold: Dictionary = c.room_at(0, Vector2(4.0, 6.0))
	check(cold.get("fire", "x") == "" and float(cold.get("comfort", 99.0)) < float(living["comfort"]), "the fire out: less comfort (%.1f < %.1f)" % [cold.get("comfort", 0.0), living["comfort"]])
	# damage: blow a hole in the bedroom's north wall -> exposed
	var runs := int(c.stats["rooms_runs"])
	g.world.explode(Vector3(4.0, 0.5, -0.3), 1.6, 3.0)
	for i in 4:
		await frames(10)
	c._rooms_t = 99.0
	await frames(2)
	check(int(c.stats["rooms_runs"]) > runs, "the structure change recomputed the rooms")
	var hit: Dictionary = c.room_at(0, Vector2(2.0, 2.5))
	check(hit.get("exposed", false), "the blast exposed the bedroom (%s)" % [hit.get("factors", [])])
	check(float(hit.get("comfort", 99.0)) < float(bed["comfort"]), "and it is less comfortable")
	# other storeys: the upper floor and a basement are rooms too
	g.levels.dev_build_upper()
	g.levels.dev_dig_basement()
	for i in 3:
		await frames(10)
	c.recompute()
	print("  storeys: ", c.storeys(), " ", c.dev_show())
	check(c.rooms.get(1, []).size() >= 1, "rooms on the upper floor")
	check(c.rooms.get(-1, []).size() >= 1, "a room in the basement")
	for r in c.rooms.get(-1, []):
		check(not r["exposed"], "the basement is bounded by earth (%s)" % [r["factors"]])
		check(int(r["level"]) <= 1, "a bare, dark basement is uncomfortable (%s)" % r["level_name"])
	for r in c.rooms.get(1, []):
		print("  upper: ", r["label"], " ", r["comfort"], " ", r["factors"])
	# F10
	g.debug_open("dev")
	await frames(1)
	var dm: Node = g.ui.dev_menu
	(dm.button("Mood low") as BaseButton).pressed.emit()
	check_eq(Mood.name_of(g.state.mood), "Low", "F10 mood low")
	(dm.button("Recompute") as BaseButton).pressed.emit()
	check(str(dm.last_status).begins_with("Recomputed"), "F10 recompute (%s)" % dm.last_status)
	(dm.button("Show comfort") as BaseButton).pressed.emit()
	check(str(dm.last_status).contains("House"), "F10 show comfort")
	dm.set_open(false)
	# save and continue: mood restored, rooms found again
	g.state.mood = 41.0
	Mood.remember(g.state, "home_safe")
	check_eq(g.debug_save(), "", "saved")
	g.queue_free()
	await frames(2)
	var g2: Node = await _boot("continue")
	check(absf(g2.state.mood - 41.0) < 1.0, "mood restored (%.1f)" % g2.state.mood)
	check(not g2.state.mood_state.get("mem", []).is_empty(), "memories restored")
	check(g2.comfort.rooms.get(0, []).size() >= 3, "rooms found after loading")
