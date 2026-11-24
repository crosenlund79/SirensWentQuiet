extends "res://tests/test_case.gd"
## Experiment 004 (H): the electrical dependency rule and its save data, the
## per-night northern-lights roll, the sink and fridge rules, GameState.home in
## saves, and one smoke run in the real game scene (fireplace, switches, lamps,
## sink, fridge, sprint, F10 Home section, save and continue).

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_home.dat"


func test_electrical_dependency_rule() -> void:
	var e := HomeElectrical.create()
	check(e.rooms.get("living", false), "room switches start on")
	check(e.lights.get("living_lamp", false) and not e.lights.get("living_ceiling", true), "the floor lamp starts on, the ceiling light off")
	check(e.shines("living_lamp", true), "switch on + room on + mains on = shines")
	check(not e.shines("living_lamp", false), "no mains (no fuse box, or mains off): dark")
	e.toggle_room("living")
	check(not e.shines("living_lamp", true), "the room switch off: dark")
	e.toggle_room("living")
	e.toggle_light("living_lamp")
	check(not e.shines("living_lamp", true), "its own switch off: dark")
	e.toggle_light("living_lamp")
	check(not e.shines("living_lamp", true, func(id): return id != "floor_lamp"), "the floor lamp destroyed: dark")
	check(e.shines("kitchen_hood", true, func(_id): return false), "lights without furniture ignore it")
	e.set_all(false)
	check(not e.states(true).values().has(true), "all off")
	e.set_all(true)
	check(not e.states(true).values().has(false), "all on")
	check(not e.states(false).values().has(true), "all on but no mains: all dark")
	check_eq(HomeElectrical.light_prompt("living_lamp", true), "[E] Turn the lamp off")
	check_eq(HomeElectrical.light_prompt("living_ceiling", true), "", "ceiling lights only by the wall switch")


func test_electrical_save_round_trip() -> void:
	var e := HomeElectrical.create()
	e.toggle_room("kitchen")
	e.toggle_light("bedside_lamp")
	var r := HomeElectrical.from_dict(JSON.parse_string(JSON.stringify(e.to_dict())))
	check_eq(r.rooms, e.rooms, "rooms survive JSON")
	check_eq(r.lights, e.lights, "lights survive JSON")
	var junk := HomeElectrical.from_dict({"lights": {"nope": true, "living_lamp": "yes"}, "rooms": 5})
	check(not junk.lights.has("nope"), "unknown ids dropped")
	check(not junk.lights["living_lamp"], "non-bool reads as off")
	check(junk.rooms["living"], "bad rooms: defaults")
	check_eq(HomeElectrical.from_dict(null).lights, HomeElectrical.create().lights, "no data: defaults")


func test_northern_lights_roll() -> void:
	var seen := 0
	for k in 2000:
		var s := NorthernSky.aurora_strength(4242, k)
		if s > 0.0:
			seen += 1
			check(s >= NorthernSky.AURORA_MIN and s <= 1.0, "strength in range (%f)" % s)
	check(seen > 1300 and seen < 1500, "about 70 %% of nights (%d of 2000)" % seen)
	check_eq(NorthernSky.aurora_strength(7, 3), NorthernSky.aurora_strength(7, 3), "deterministic")
	check_eq(NorthernSky.night_key(7.0 * 60.0), -1, "Day 1 morning belongs to the night before")
	check_eq(NorthernSky.night_key(23.0 * 60.0), 0, "Day 1 23:00 is night 0")
	check_eq(NorthernSky.night_key(1440.0 + 3.0 * 60.0), 0, "Day 2 03:00 is still night 0")
	check_eq(NorthernSky.tonight_key(7.0 * 60.0), 0, "in the morning, tonight is the coming night")
	check_eq(NorthernSky.tonight_key(1440.0 + 3.0 * 60.0), 0, "after midnight, tonight is the night under way")


func test_sink_and_fridge_rules() -> void:
	var s := GameState.new_run(1)
	s.hydration = 50.0
	var r := Household.drink_from_sink(s)
	check(r["ok"] and is_equal_approx(s.hydration, 80.0), "a drink is one bottle (%s)" % r["text"])
	s.hydration = 100.0
	check(not Household.drink_from_sink(s)["ok"], "not thirsty")
	s.hydration = 10.0
	check(not Household.drink_from_sink(s, false)["ok"] and is_equal_approx(s.hydration, 10.0), "a wrecked sink gives nothing")
	for id in Items.ids("food"):
		s.inventory.remove(id, s.inventory.count(id))
	s.hunger = 40.0
	check_eq(Household.eat_from_fridge(s)["text"], "The fridge is empty.")
	s.inventory.add("snacks", 2)
	s.inventory.add("canned_food", 1)
	check_eq(Household.best_food(s), "canned_food", "the most filling food first")
	var e := Household.eat_from_fridge(s)
	check(e["ok"] and s.inventory.count("canned_food") == 0 and is_equal_approx(s.hunger, 70.0), "eats a can (%s)" % e["text"])
	check_eq(Household.best_food(s), "snacks")
	s.hunger = 100.0
	check(not Household.eat_from_fridge(s)["ok"] and s.inventory.count("snacks") == 2, "full: nothing eaten")
	check(not Household.eat_from_fridge(s, false)["ok"], "a wrecked fridge")


func test_game_state_home_is_optional_in_saves() -> void:
	var s := GameState.new_run(3)
	s.home = {"fire": false, "rooms": {"living": false}}
	var d := s.to_dict()
	var r := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(r != null and r.home.get("fire") == false and r.home["rooms"]["living"] == false, "home round-trips")
	d.erase("home")
	var old := GameState.from_dict(d)
	check(old != null and old.home.is_empty(), "an older save without home loads with an empty home")


# --- the real game ---------------------------------------------------------------------

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
	for a in ["sprint", "move_right"]:
		Input.action_release(a)
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()


func _at(g: Node, p: Vector2) -> String:
	g.debug_teleport_player(p)
	await frames(2)
	return g.debug_prompt()


func test_home_in_the_game() -> void:
	var g: Node = await _boot()
	var h: Node = g.home
	check(h != null and h.fireplace.lit, "the fireplace is lit on a new game")
	check(g.lighting.northern and g.lighting.electric, "northern palette and electric lights")
	check(g.lighting.practical_on("living_lamp"), "the floor lamp shines (no fuse box API yet = mains on)")
	var nav: GridNav = g.debug_world().nav
	check(not nav.is_walkable(nav.cell_of(Fireplace.RECT.get_center())), "enemies path around the fireplace")
	# the fireplace
	var fp: Vector2 = Vector2(Fireplace.RECT.get_center().x, Fireplace.RECT.end.y + 0.5)
	check_eq(await _at(g, fp), "[E] Put out the fire")
	g.debug_interact()
	check(not h.fireplace.lit and g.debug_state().home["fire"] == false, "put out, and recorded for the save")
	g.debug_state().inventory.add("wood", 1)
	var planks: int = g.debug_state().inventory.count("wood")
	await frames(1)
	g.debug_interact()
	check(h.fireplace.lit and g.debug_state().inventory.count("wood") == planks - 1, "relit for a plank")
	# a room switch
	var sw: Vector2 = h.SWITCHES["living"]["pos"]
	check_eq(await _at(g, sw + Vector2(0, -0.5)), "[E] Lights off")
	g.debug_interact()
	await frames(1)
	check(not g.lighting.practical_on("living_lamp"), "the living-room switch darkens the floor lamp")
	g.debug_interact()
	await frames(1)
	check(g.lighting.practical_on("living_lamp"), "and lights it again")
	# a lamp's own switch
	check_eq(await _at(g, Vector2(1.75, 7.35)), "[E] Turn the lamp off")
	g.debug_interact()
	await frames(1)
	check(not g.lighting.practical_on("living_lamp"), "the lamp's own switch")
	# the kitchen
	var s: GameState = g.debug_state()
	s.hydration = 40.0
	check_eq(await _at(g, Vector2(11.0, 1.4)), "[E] Drink from the sink")
	var t0 := s.total_minutes
	g.debug_interact()
	check(s.hydration > 65.0 and s.total_minutes >= t0 + 0.99, "a drink from the tap takes a minute (%.1f)" % s.hydration)
	s.hunger = 30.0
	s.inventory.add("canned_food", 1)
	var cans := s.inventory.count("canned_food")
	check_eq(await _at(g, Vector2(8.6, 1.5)), "[E] Eat from the fridge")
	g.debug_interact()
	check(s.inventory.count("canned_food") == cans - 1 and s.hunger > 55.0, "ate a can from the fridge")
	# sprint
	g.debug_teleport_player(Vector2(-2.0, 6.0))
	var e0 := s.energy
	Input.action_press("move_down")
	Input.action_press("sprint")
	await physics_frames(30)
	var v := Vector2(g.player.velocity.x, g.player.velocity.z).length()
	check(g.player.sprinting and v > Tuning.PLAYER_SPEED * 1.3, "Shift sprints (%.2f m/s)" % v)
	check(s.energy < e0, "sprinting drains energy")
	Input.action_release("sprint")
	Input.action_release("move_down")
	# F10
	g.debug_open("dev")
	var dm: Node = g.debug_ui().dev_menu
	for label in ["Toggle fireplace", "Northern lights tonight", "All lights on", "All lights off", "Time 23:00", "Snow on/off"]:
		check(dm.button(label) != null, "F10 has '%s'" % label)
	dm.button("All lights on").pressed.emit()
	check(g.lighting.practical_on("living_ceiling"), "F10 all lights on")
	dm.button("Northern lights tonight").pressed.emit()
	dm.button("Time 23:00").pressed.emit()
	await frames(2)
	check(h.sky.tonight == 1.0 and h.sky.shown > 0.3, "forced northern lights at 23:00 (%.2f)" % h.sky.shown)
	check(g.lighting.aurora > 0.3, "the night ambient takes the aurora tint")
	dm.button("Toggle fireplace").pressed.emit()
	check(not h.fireplace.lit, "F10 puts the fire out")
	g.debug_open("dev")
	# save and continue
	check_eq(g.debug_save(), "", "saved")
	g.queue_free()
	await frames(2)
	var g2: Node = await _boot("continue")
	check(not g2.home.fireplace.lit, "the fire stays out after Continue")
	check(g2.home.electrical.lights.get("living_ceiling", false), "switch states survive Continue")
	check(g2.lighting.practical_on("living_ceiling"), "and the light shines again")
