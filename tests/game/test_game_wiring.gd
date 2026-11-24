extends "res://tests/test_case.gd"
## Experiment 003 wiring in the real game scene (SPEC-003 §7): the difficulty
## from New Game, weapons through the game's input, the archetypes' blows and
## the bomber's blast on the player, the region map (open, close, input
## blocked, the table, planning), expedition results applied to the region
## once, the F10 tools through the real systems, the sleep wake-up text and an
## Experiment 002 save continued in the game.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_game_wiring.dat"
const FIXTURE := "res://tests/save/fixtures/exp002_save_v1.dat"
const Director := preload("res://src/game/invasion_director.gd")
const LIVING_ROOM := Vector2(6.0, 8.2)
const FRONT_YARD := Vector2(9.0, 11.2)
const AT_TABLE := Vector2(7.8, 6.75)


func _boot(mode := "new", level := "normal") -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 4242
	GameLaunch.difficulty = level
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
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	GameLaunch.difficulty = "normal"
	GameLaunch.notice = ""
	tree.root.disable_3d = false
	await super.cleanup()


func _action(name: String, pressed := true) -> void:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(name: String) -> void:
	_action(name, true)
	await frames(2)
	_action(name, false)
	await frames(1)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await frames(1)


func _wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await frames(1)
	return cond.call()


# --- difficulty --------------------------------------------------------------------------

func test_new_game_starts_on_the_chosen_difficulty_and_continue_keeps_it() -> void:
	var g: Node = await _boot("new", "hard")
	var s: GameState = g.debug_state()
	check_eq(s.difficulty, "hard", "GameLaunch.difficulty reaches GameState.new_run")
	check_eq(s.magazine("handgun"), Difficulty.start_rounds("hard"), "Hard's start rounds in the handgun")
	check_eq(s.first_invasion_day(), 2, "Hard: the first invasion on Day 2")
	check_eq(g.debug_roster().level, "hard", "the roster spawns at the run's difficulty")
	check(str(g.hud.debug_texts()["period"]).ends_with("Hard"), "the HUD shows it (%s)" % g.hud.debug_texts()["period"])
	g.debug_open("pause")
	var sub: Node = g.debug_ui().pause_menu.find_child("Subtitle", true, false)
	check(sub is Label and (sub as Label).text.contains("Hard"), "the pause menu shows it")
	g.debug_close()
	check_eq(g.debug_save(), "", "saved")
	g.queue_free()
	await frames(3)
	var h: Node = await _boot("continue", "easy")   # the menu's last choice must not leak into Continue
	check_eq(h.debug_state().difficulty, "hard", "Continue keeps the run's difficulty")
	check_eq(h.debug_roster().level, "hard", "and the roster follows the loaded run")


func test_easy_starts_with_a_full_magazine() -> void:
	var g: Node = await _boot("new", "easy")
	check_eq(g.debug_state().magazine("handgun"), 12, "Easy: 12 rounds")


# --- weapons ----------------------------------------------------------------------------

func test_weapons_switch_fire_and_reload_through_the_game() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	var w: WeaponHandler = g.combat.weapons
	g.debug_teleport_player(FRONT_YARD)
	await frames(2)
	var ground := FRONT_YARD + Vector2(0, 2.5)
	check_eq(w.current_id(), "handgun", "the handgun in hand")
	check_eq(g.hud.debug_texts()["weapon"], "Handgun", "HUD: weapon name")
	check_eq(g.hud.debug_texts()["ammo_cap"], "/ 12", "HUD: capacity")
	s.inventory.add("shotgun", 1)
	s.inventory.add("shells", 10)
	check_eq(s.equipped("secondary"), "shotgun", "a found shotgun goes into the free secondary slot")
	await _tap("weapon_2")
	check_eq(w.current_id(), "shotgun", "2 takes the shotgun")
	await frames(2)
	check_eq(g.hud.debug_texts()["weapon"], "Shotgun", "HUD follows the switch")
	check(g.hud.debug_texts()["weapon_other"].contains("Handgun"), "and names the other weapon")
	var r: Dictionary = g.debug_fire_at(ground, 0.0)
	check(r.get("reason", "") == "empty" and r.get("reloading", false), "a found shotgun is empty: the trigger starts a reload")
	check_eq(g.last_toast, "Reloading", "and says so")
	check(await _wait_until(func(): return s.magazine("shotgun") == 5, 60 * 4), "shell by shell to 5 (%d)" % s.magazine("shotgun"))
	check_eq(s.reserve("shotgun"), 5, "5 shells left")
	r = g.debug_fire_at(ground, 0.0)
	check(r.get("ok", false) and int(r.get("pellets", 0)) == 6, "one blast, six pellets through the world (%s)" % [r.get("pellets")])
	check_eq(s.magazine("shotgun"), 4, "one shell spent")
	await _tap("weapon_1")
	check_eq(w.current_id(), "handgun", "1 takes the handgun")
	await _tap("weapon_next")
	check_eq(w.current_id(), "shotgun", "Q: the other weapon")
	await _tap("weapon_next")
	check_eq(w.current_id(), "handgun", "Q again: back")
	await _tap("reload")
	check(g.last_toast.contains("No 9 mm"), "R with nothing in reserve says why (%s)" % g.last_toast)
	s.inventory.add("ammo", 12)
	await _tap("reload")
	check(w.is_reloading(), "R reloads")
	await frames(3)
	check(g.hud.debug_texts()["reloading"], "HUD: reload bar")
	check(await _wait_until(func(): return not w.is_reloading(), 60 * 2), "the reload finishes")
	check_eq(s.magazine("handgun"), 12, "a full magazine")
	check_eq(s.reserve("handgun"), 9, "from the reserve")
	# Build mode keeps 1-9 and R for building.
	g.debug_open("build")
	check(g.build.active, "build mode")
	var slot0: int = g.build.slot()
	await _key(KEY_2)
	check_eq(w.current_id(), "handgun", "in build mode 2 doesn't switch weapons")
	check(g.build.slot() != slot0, "it picks a build class instead")
	var rot0: int = g.build.rot
	await _key(KEY_R)
	check(not w.is_reloading(), "R doesn't reload in build mode")
	check(g.build.rot != rot0, "it rotates the piece")
	g.debug_close()


func test_archetype_blows_by_damage_scale_and_bomber_blast_on_the_player() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	g.debug_teleport_player(FRONT_YARD)
	await frames(2)
	var brute: Node = g.debug_roster().spawn_type("brute", FRONT_YARD + Vector2(0.7, 0))
	check(await _wait_until(func(): return s.health < 100.0, 60 * 6), "a brute's swing lands")
	check(absf((100.0 - s.health) - s.enemy_damage() * brute.damage_scale) < 0.01, "by enemy_damage() x 1.8 (%.1f lost)" % (100.0 - s.health))
	g.debug_kill_enemies()
	await frames(2)
	# A blast near the player: EnemyDefs fall-off, and the vest takes 35 % off.
	s.health = 100.0
	var at := Vector3(FRONT_YARD.x + 1.0, 1.0, FRONT_YARD.y)
	g.debug_roster().detonated.emit(at, 4.0, 60.0)
	check(absf((100.0 - s.health) - 45.0) < 0.01, "1 m from the centre: 45 of 60 (%.1f)" % (100.0 - s.health))
	check(g.last_toast.begins_with("Caught in the blast"), "toast")
	s.health = 100.0
	s.inventory.add("vest", 1)
	check(s.has_equipped("vest"), "vest worn")
	g.debug_roster().detonated.emit(at, 4.0, 60.0)
	check(absf((100.0 - s.health) - 45.0 * Equipment.VEST_FACTOR) < 0.01, "the vest reduces the blast (%.1f)" % (100.0 - s.health))
	s.health = 100.0
	g.debug_roster().detonated.emit(at + Vector3(5, 0, 0), 4.0, 60.0)
	check_eq(s.health, 100.0, "beyond the reach: nothing")


func test_a_real_bomber_goes_for_the_house_warns_and_its_blast_hurts_the_player() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	g.debug_teleport_player(LIVING_ROOM)
	await frames(2)
	var b: AIEnemy = g.dev.dev_spawn_type("bomber")
	check(b != null and b.kind == "bomber", "F10: a bomber through roster.spawn_type")
	check(g.last_toast.begins_with("Dev:") or g.last_toast.contains("bomber"), "noticed")
	var missing0 := int(g.debug_world().damage_summary()["missing_voxels"])
	check(await _wait_until(func(): return not g.combat.markers().is_empty(), 60 * 40), "it reaches the house and lights its fuse")
	check(g.hud.debug_texts()["alert"].contains("BOMBER"), "HUD alert (%s)" % g.hud.debug_texts()["alert"])
	var target: Dictionary = b.behaviour.target
	check(target.get("kind", "") in ["door", "barricade", "wall"], "its target is a defence, not the player (%s)" % target.get("kind", ""))
	var h0 := s.health
	check(await _wait_until(func(): return g.debug_roster().blasts > 0, 60 * 5), "it detonates")
	await frames(2)
	var lb: Dictionary = g.combat.last_blast
	check(not lb.is_empty(), "the game handled the blast")
	var want := EnemyDefs.blast_damage_at(float(lb.get("dist", 99.0)), 60.0 * float(Difficulty.get_value("normal", "enemy_damage")), 4.0)
	check(absf(float(lb.get("hurt", -1.0)) - want) < 0.01, "fall-off damage %.1f at %.1f m" % [want, lb.get("dist", 0.0)])
	check(absf((h0 - s.health) - want) < 0.01, "the player took it (%.1f)" % (h0 - s.health))
	check(g.combat.markers().is_empty(), "the marker goes")
	check_eq(g.hud.debug_texts()["alert"], "", "the alert goes")
	var dmg: Dictionary = g.debug_world().damage_summary()
	check(int(dmg["missing_voxels"]) > missing0 or g.debug_world().count_objects("door") < 2, "the house took structural damage (%s)" % [dmg])


# --- region map ---------------------------------------------------------------------------

func test_map_opens_with_m_blocks_input_and_closes_with_esc_or_m() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	g.debug_teleport_player(FRONT_YARD)
	await frames(2)
	await _tap("open_map")
	check_eq(g.debug_modal(), "map", "M opens the map")
	check(g.map.is_open() and tree.paused, "the world pauses")
	check(tree.root.disable_3d, "the game's 3D view is off under the map")
	var t0 := s.total_minutes
	var p0: Vector2 = g.debug_player_pos()
	_action("fire", true)
	_action("move_up", true)
	await frames(20)
	_action("fire", false)
	_action("move_up", false)
	await frames(1)
	check_eq(g.shots_fired, 0, "no shot while the map is open")
	check(g.debug_player_pos().distance_to(p0) < 0.01, "no movement (WASD pans the map)")
	check_eq(s.total_minutes, t0, "the clock stops")
	await _tap("pause")
	check_eq(g.debug_modal(), "", "Esc closes the map")
	check(not g.debug_ui().pause_menu.is_open, "and does not open the pause menu")
	check(not tree.paused and not tree.root.disable_3d, "the world runs and renders again")
	await _tap("open_map")
	check(g.map.is_open(), "M again")
	await _tap("open_map")
	check(not g.map.is_open() and g.debug_modal() == "", "M closes it too")
	g.debug_open("build")
	await _tap("open_map")
	check(g.map.is_open() and not g.build.active, "M from build mode leaves build mode")
	g.debug_close()


func test_the_map_on_the_dining_table_and_planning() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	g.debug_teleport_player(AT_TABLE)
	await frames(3)
	check_eq(g.debug_prompt(), "[E] Study the region map", "the table's prompt")
	await _tap("interact")
	check_eq(g.debug_modal(), "map", "E opens the map")
	var screen: RegionMapScreen = g.map.screen
	screen.select("hardware")
	check(screen.plan_selected(), "plan an expedition")
	check_eq(s.region.planned, "hardware", "RegionState holds the plan")
	check(g.last_toast.begins_with("Planned: %s (" % RegionLocations.name_of("hardware")), "toast (%s)" % g.last_toast)
	check(g.autosave_log.has("plan"), "autosaved (%s)" % [g.autosave_log])
	g.debug_close()
	check_eq(g.debug_modal(), "", "closed")
	g.debug_teleport_player(Vector2(4.5, 12.2))
	await frames(2)
	g.debug_start_expedition()
	check_eq(g.debug_modal(), "expedition", "the expedition screen opens at the fog")
	check_eq(g.debug_ui().expedition.selected, "hardware", "and preselects the map's plan")
	g.debug_cancel_expedition()


# --- expeditions and the region ---------------------------------------------------------

func test_an_expedition_result_reaches_the_region_exactly_once() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	s.total_minutes = 9.0 * 60.0
	s.region.plan("homes", "general")
	g.debug_teleport_player(Vector2(4.5, 12.2))
	await frames(2)
	g.debug_start_expedition()
	var r := ExpeditionRun.simulate(s, "homes", ExpeditionData.default_gear(s, "homes"))
	check(not r.is_empty(), "a real result")
	g.debug_finish_expedition(r)
	check(g.last_expedition.get("region_applied", false), "apply_region ran")
	check_eq(s.region.visits("homes"), 1, "one visit")
	check_eq(s.region.planned, "", "the plan is used up")
	check(float(s.region.stock_of("homes")) <= 1.0, "stock recorded")
	var stock := s.region.stock_of("homes")
	var t := s.total_minutes
	g.debug_finish_expedition(r)       # a repeated signal
	check(ExpeditionData.apply_region(s, r) == false, "a second apply_region is refused")
	check_eq(s.region.visits("homes"), 1, "still one visit")
	check_eq(s.region.stock_of("homes"), stock, "stock unchanged")
	check_eq(s.total_minutes, t, "no second time advance")


# --- F10 ----------------------------------------------------------------------------------

func test_dev_tools_use_the_real_systems() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	g.debug_teleport_player(LIVING_ROOM)
	await frames(2)
	for k in EnemyDefs.KINDS:
		g.dev.dev_spawn_type(k)
	var by: Dictionary = g.debug_roster().living_by_kind()
	for k in EnemyDefs.KINDS:
		check_eq(int(by.get(k, 0)), 1, "one %s" % k)
	for p in g.debug_enemy_positions():
		check(not FogBoundary.LOT.has_point(p), "spawned in the fog band (%s)" % p)
	g.debug_kill_enemies()
	await frames(2)
	# A chosen composition through the director.
	check(g.dev.dev_wave(["bomber", "brute", "runner"]), "wave started")
	check_eq(g.debug_director().wave, ["bomber", "brute", "runner"], "exactly the chosen wave")
	check(s.run.get("invasion_active", false), "an invasion in the state")
	g.debug_set_spawn_gap(Vector2(0.05, 0.1))
	check(await _wait_until(func(): return g.debug_director().all_spawned(), 600), "all spawned")
	by = g.debug_roster().living_by_kind()
	check(by.get("bomber", 0) == 1 and by.get("brute", 0) == 1 and by.get("runner", 0) == 1, "the three of them (%s)" % by)
	g.debug_kill_enemies()
	check(await _wait_until(func(): return not g.debug_director().active, 60), "the invasion ends")
	# Map, missions, difficulty, magazines.
	check(g.dev.dev_reveal_map() > 0, "places revealed")
	check_eq(s.region.discovered.size(), RegionLocations.ids().size(), "all of them")
	s.total_minutes = float(s.day() - 1) * 1440.0 + 8.0 * 60.0
	var stone := s.inventory.count("stone")
	var t := s.total_minutes
	var r: Dictionary = g.dev.dev_instant_mission("quarry", "targeted")
	check(not r.is_empty(), "an instant mission to the quarry")
	check(g.last_expedition.get("region_applied", false), "applied through the game's own path")
	check_eq(s.region.visits("quarry"), 1, "the quarry visited")
	check(absf(s.total_minutes - t - float(r.get("minutes", 0))) < 0.01, "time advanced by the trip")
	check(s.inventory.count("stone") > stone or int(r.get("gained", {}).get("stone", 0)) == 0, "stone brought home (%d -> %d)" % [stone, s.inventory.count("stone")])
	g.dev.dev_set_difficulty("hard")
	check(s.difficulty == "hard" and g.debug_roster().level == "hard", "difficulty and roster")
	s.inventory.add("shotgun", 1)
	g.dev.dev_fill_magazines()
	check_eq(s.magazine("shotgun"), 5, "magazines filled")
	# The F10 menu's own buttons reach the helper.
	var m: DevMenu = g.debug_ui().dev_menu
	m.toggle()
	await frames(2)
	m.button("+ Runner").pressed.emit()
	check_eq(int(g.debug_roster().living_by_kind().get("runner", 0)), 1, "the + Runner button")
	m.button("Hard").pressed.emit()
	m.button("+10 stone").pressed.emit()
	check(m.inspect_text().contains("Enemies by type"), "inspect shows the Experiment 003 line")
	m.toggle()


# --- sleep ------------------------------------------------------------------------------

func test_waking_for_thirst_does_not_blame_the_door() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	s.total_minutes = 21.0 * 60.0
	s.hydration = 4.0
	s.energy = 20.0
	var plan: Dictionary = await g.debug_sleep(-1.0)
	check_eq(plan.get("reason", ""), "needs", "the body wakes the player")
	check_eq(g.last_toast, str(plan.get("text", "?")), "GameState's own words (%s)" % g.last_toast)
	check(not g.last_toast.contains("door"), "not 'something at the door'")


# --- an Experiment 002 save -------------------------------------------------------------

func test_an_experiment_002_save_continues_and_is_resaved_as_schema_2() -> void:
	SaveGame.path_override = SAVE
	SaveGame.delete_save()
	var bytes := FileAccess.get_file_as_bytes(FIXTURE)
	check(bytes.size() > 0, "fixture present")
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	check_eq(SaveGame.info()["schema"], 1, "a schema 1 file")
	check(SaveGame.info()["valid"], "Continue is offered for it")
	var g: Node = await _boot("continue")
	check_eq(g.left_to, "", "no bounce to the menu (%s)" % GameLaunch.notice)
	var s: GameState = g.debug_state()
	check_eq(s.difficulty, "normal", "Normal by default")
	check_eq(s.equipped("primary"), "handgun", "the handgun equipped")
	check_eq(s.magazine("handgun"), 12, "its magazine filled from the 15 rounds")
	check_eq(s.reserve("handgun"), 3, "the rest in reserve")
	check_eq(s.clock_text(), "12:30", "the clock")
	check_eq(g.debug_world().count_objects("crate"), 1, "the built crate")
	check_eq(g.debug_world().count_objects("barricade"), 1, "the built barricade")
	check_eq(int(g.debug_world().damage_summary()["missing_voxels"]), 156, "the shot wall")
	check(g.debug_player_pos().distance_to(LIVING_ROOM) < 0.05, "where the player stood")
	check(g.autosave_log.has("migrated"), "re-saved at once (%s)" % [g.autosave_log])
	check_eq(SaveGame.info()["schema"], SaveGame.SCHEMA, "the file is schema 2 now")
	var r := SaveGame.read()
	check(r["ok"] and int(r["migrated_from"]) == 0, "and reads without migration")
	check(r["data"]["state"].has("equipment") and int(r["data"]["world"].get("version", 0)) == 2, "with equipment and a version 2 world")
