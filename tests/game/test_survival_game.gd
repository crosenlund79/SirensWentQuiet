extends "res://tests/test_case.gd"
## Game loop contracts (SPEC §7.9) against whatever modules are present:
## launch, firing and ammo, enemy hits, sleep, expeditions, save/continue,
## death, autosave rules, the dev API, invasions and stragglers.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_game_loop.dat"
const Director := preload("res://src/game/invasion_director.gd")
const DAY := 1440.0
const LIVING_ROOM := Vector2(6.0, 8.2)
const FRONT_YARD := Vector2(9.0, 11.2)


func _boot(mode := "new", skip_intro := true) -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 4242
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = skip_intro
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
	GameLaunch.notice = ""
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


func _wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await frames(1)
	return cond.call()


func _set_time(g: Node, total: float) -> void:
	g.debug_state().total_minutes = total


# --- launch ----------------------------------------------------------------------------

func test_new_run_boots_on_day_one_and_writes_the_initial_save() -> void:
	SaveGame.path_override = SAVE
	SaveGame.delete_save()
	var g: Node = await _boot("new", false)       # through the intro overlay
	check(await _wait_until(func(): return g.debug_modal() == "", 1200), "the intro finishes (modal '%s')" % g.debug_modal())
	var s: GameState = g.debug_state()
	check_eq(s.day(), 1, "Day 1")
	check_eq(s.magazine("handgun"), 9, "nine bullets")
	check(g.debug_player_pos().distance_to(Vector2(g.debug_world().bed_position().x, g.debug_world().bed_position().z)) < 2.0, "wakes beside the bed")
	check(SaveGame.info()["valid"], "the initial save exists after the intro")
	check("new_run" in g.autosave_log, "initial save logged (%s)" % [g.autosave_log])
	check(not tree.paused, "the world runs")
	var t0 := s.total_minutes
	await seconds(1.0)
	check(s.total_minutes - t0 > 0.5 and s.total_minutes - t0 < 2.0, "the clock runs at about 1 game minute per second (%.2f)" % (s.total_minutes - t0))


# --- firing ----------------------------------------------------------------------------

func test_firing_consumes_ammo_stops_at_zero_and_the_cheat_keeps_it() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	g.debug_teleport_player(FRONT_YARD)
	await frames(2)
	var ground := FRONT_YARD + Vector2(0, 2.5)
	check_eq(s.magazine("handgun"), 9, "nine rounds in the handgun")
	check_eq(s.reserve("handgun"), 0, "and none in reserve")
	# Real input path: the fire action through _unhandled_input.
	_action("fire", true)
	await physics_frames(3)
	_action("fire", false)
	await physics_frames(2)
	check_eq(s.magazine("handgun"), 8, "one trigger pull through the fire action uses one round")
	for i in 8:
		var r: Dictionary = g.debug_fire_at(ground, 0.0)
		check(r.get("ok", false), "shot %d fires" % (i + 2))
	check_eq(s.magazine("handgun"), 0, "nine rounds, nine shots")
	var r: Dictionary = g.debug_fire_at(ground, 0.0)
	check_eq(r.get("reason", ""), "empty", "an empty gun clicks")
	check(not r.get("reloading", true), "no reserve: no reload")
	check_eq(s.magazine("handgun"), 0, "never negative")
	check_eq(g.last_toast, "Out of ammo", "toast")
	check_eq(g.shots_fired, 9, "shots fired")
	# The unlimited cheat keeps the magazine full (WeaponHandler) and spends nothing.
	s.cheats["unlimited"] = true
	for i in 3:
		check(g.debug_fire_at(ground, 0.0).get("ok", false), "unlimited shot %d" % (i + 1))
	check_eq(s.magazine("handgun"), 12, "unlimited cheat: the magazine stays full")
	check_eq(s.inventory.count("ammo"), 0, "and the reserve untouched")
	check_eq(g.shots_fired, 12, "shots fired (9 + 3 free)")


func test_no_firing_while_a_panel_or_build_mode_is_open() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	g.debug_open("inventory")
	await frames(2)
	check_eq(g.debug_modal(), "inventory", "inventory open")
	check(tree.paused, "inventory pauses the world")
	_action("fire", true)
	await frames(4)
	_action("fire", false)
	await frames(1)
	check_eq(s.magazine("handgun"), 9, "no shot through the inventory panel")
	await _tap("inventory")
	check_eq(g.debug_modal(), "", "I closes the inventory")
	check(not tree.paused, "unpaused")
	s.cheats["unlimited"] = true     # the build stub needs a hammer or the cheat; both fine
	g.debug_open("build")
	if g.build.active:
		_action("fire", true)
		await physics_frames(4)
		_action("fire", false)
		check_eq(g.shots_fired, 0, "no shot in build mode")
		await _tap("pause")
		check(not g.build.active, "Esc leaves build mode")
		check_eq(g.debug_modal(), "", "and does not open the pause menu")


# --- enemies ---------------------------------------------------------------------------

func test_an_enemy_hit_damages_the_player_and_invulnerable_blocks_it() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	g.debug_teleport_player(FRONT_YARD)
	await frames(2)
	g.debug_spawn_enemy(FRONT_YARD + Vector2(0.6, 0))
	check(await _wait_until(func(): return s.health < 100.0, 240), "a psycho's swing hurts (health %.1f)" % s.health)
	check(absf((100.0 - s.health) - s.enemy_damage()) < 0.01 or s.health < 100.0 - s.enemy_damage(), "by enemy_damage() per swing")
	s.cheats["invulnerable"] = true
	var h := s.health
	await seconds(2.5)
	check(s.health >= h, "invulnerable: no damage from further swings (%.2f -> %.2f)" % [h, s.health])
	check(g.debug_living_enemies() == 1, "the psycho is still there")


func test_shooting_an_enemy_kills_it() -> void:
	var g: Node = await _boot()
	g.debug_teleport_player(FRONT_YARD)
	var e: Node = g.debug_spawn_enemy(FRONT_YARD + Vector2(3.0, 0))
	await physics_frames(3)
	for i in 6:
		if not e.alive:
			break
		g.debug_fire_at(e.plan_pos(), 1.1)
		await physics_frames(2)
	check(not e.alive, "three hits kill a psycho")
	check_eq(g.debug_living_enemies(), 0, "no threats left")


# --- sleep -----------------------------------------------------------------------------

func test_sleep_is_refused_with_enemies_alive() -> void:
	var g: Node = await _boot()
	g.debug_spawn_enemy(Vector2(-6.0, -5.0))
	g.open_sleep()
	await frames(1)
	check_eq(g.debug_modal(), "", "no sleep dialog")
	check(g.last_toast.contains("can't sleep"), "told why (%s)" % g.last_toast)


func test_sleep_advances_the_time_once() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	_set_time(g, 10.0 * 60.0)
	s.energy = 40.0
	var e0 := s.energy
	var h0 := s.hunger
	var rest := s.rest_scale           # Exp 005 (C): the sleep bonus of the mood and the bedroom
	var plan: Dictionary = await g.debug_sleep(120.0)
	check(not plan.is_empty(), "slept")
	check(absf(s.total_minutes - (10.0 * 60.0 + 120.0)) < 0.01, "exactly two hours later (%s)" % s.clock_text())
	check(absf((s.energy - e0) - 2.0 * SurvivalTuning.SLEEP_ENERGY_PER_HOUR * rest) < 0.2, "energy restored once (%.1f -> %.1f, rest x%.2f)" % [e0, s.energy, rest])
	check(absf((h0 - s.hunger) - 2.0 * SurvivalTuning.HUNGER_PER_HOUR * SurvivalTuning.SLEEP_DECAY_SCALE) < 0.2, "hunger decayed once, at the sleep rate")
	check_eq(g.debug_modal(), "", "awake")
	check(not tree.paused, "world resumed")
	check("wake" in g.autosave_log, "autosave on waking (%s)" % [g.autosave_log])


func test_sleep_until_morning_crosses_dawn() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	_set_time(g, 21.0 * 60.0)          # Day 1 21:00, no invasion, no straggler on Day 1
	await g.debug_sleep(-1.0)
	check_eq(s.day(), 2, "Day 2")
	check_eq(s.clock_text(), "06:00", "wakes at dawn")
	check("dawn" in g.last_sleep.get("events", []), "dawn processed")


func test_sleep_is_interrupted_by_an_invasion() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	var due := float(s.run["next_invasion_at"])
	_set_time(g, due - 120.0)          # Day 3 20:00
	var plan: Dictionary = await g.debug_sleep(-1.0)
	check(plan.get("interrupted", false), "interrupted")
	check(absf(s.total_minutes - due) < 0.01, "woken at the invasion (%s)" % s.clock_text())
	check(s.run.get("invasion_active", false), "the invasion started")
	check(g.debug_director().active, "the director runs")
	check_eq(g.last_toast, "You wake to something at the door.", "toast")
	check(not ("wake" in g.autosave_log), "no autosave into an invasion")
	g.open_sleep()
	check_eq(g.debug_modal(), "", "can't go back to sleep during the invasion")


# --- expeditions -----------------------------------------------------------------------

## Exp 007 (T): the simulated expedition only remains as F10's instant
## mission (apply_expedition_result); play travels to the place instead.
func test_an_expedition_is_applied_once_and_time_advances_once() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	_set_time(g, 9.0 * 60.0)
	g.debug_teleport_player(Vector2(4.5, 12.2))
	await frames(2)
	var t0 := s.total_minutes
	var water := s.inventory.count("water")
	var result := {"id": "test_exp_1", "destination": "homes", "name": "Nearby Homes", "minutes": 90,
		"gained": {"water": 2}, "consumed": {}, "lost": {}, "left_behind": {}, "damage": 0.0, "events": [], "summary": "Quiet."}
	g.apply_expedition_result(result)
	check(absf(s.total_minutes - (t0 + 90.0)) < 0.01, "time advanced once by the result")
	check_eq(s.inventory.count("water"), water + 2, "gains applied")
	check_eq(g.debug_modal(), "", "back in the world")
	check(not tree.paused, "resumed")
	check(FogBoundary.LOT.has_point(g.debug_player_pos()), "returned inside the lot")
	check("expedition" in g.autosave_log, "autosave after the expedition")
	g.apply_expedition_result(result)
	check(absf(s.total_minutes - (t0 + 90.0)) < 0.01, "a second application changes nothing")
	check_eq(s.inventory.count("water"), water + 2, "not applied twice")


## Exp 007 (T): E at the fog edge opens the region map (to travel), and is
## refused with enemies around.
func test_an_expedition_can_be_cancelled_and_is_refused_with_enemies() -> void:
	var g: Node = await _boot()
	g.debug_teleport_player(Vector2(4.5, 12.2))
	await frames(2)
	g.debug_start_expedition()
	check_eq(g.debug_modal(), "map", "the fog opens the map")
	var t0: float = g.debug_state().total_minutes
	g.debug_close()
	check_eq(g.debug_modal(), "", "Esc closes it")
	check_eq(g.debug_state().total_minutes, t0, "no time passed")
	g.debug_spawn_enemy(Vector2(-6.0, -5.0))
	g.debug_start_expedition()
	check_eq(g.debug_modal(), "", "refused with a psycho around")
	check(g.last_toast.contains("Not with them"), "told why")


# --- saving ----------------------------------------------------------------------------

func test_save_then_continue_restores_state_and_position() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	g.debug_teleport_player(LIVING_ROOM)
	await physics_frames(2)
	g.debug_teleport_player(LIVING_ROOM)
	s.advance(200.0)
	s.inventory.add("scrap", 3)
	s.use_item("canned_food")
	g.dev_set_time_scale(2.0)
	# Damage the house and build a crate (the real world and build mode).
	for i in 4:
		g.debug_fire_at(Vector2(9.5, 9.0), 1.0)
	var built := false
	if g.build.has_method("select_id") and g.build.has_method("apply"):
		s.cheats["unlimited"] = true
		g.build.select_id("crate")
		built = g.build.apply(Vector2(11.25, 11.75))
		check(built, "a crate was built (%s)" % str(g.build.last_eval.get("reason", "")))
		s.cheats["unlimited"] = false
	await frames(2)
	var dmg: Dictionary = g.debug_world().damage_summary()
	var crates: int = g.debug_world().count_objects("crate")
	g.debug_teleport_player(LIVING_ROOM)
	g.debug_player().rig.rotation.y = 1.0
	var saved := s.to_dict()
	check_eq(g.debug_save(), "", "save allowed")
	g.queue_free()
	await frames(3)
	var h: Node = await _boot("continue")
	check(h.left_to == "", "no bounce to the menu (%s)" % GameLaunch.notice)
	var t: GameState = h.debug_state()
	# The restored game has already run a few frames (at time scale 2).
	check(absf(t.total_minutes - float(saved["total_minutes"])) < 0.5, "clock restored (%s)" % t.clock_text())
	check(absf(t.hunger - float(saved["hunger"])) < 0.01, "hunger restored")
	check_eq(t.inventory.count("scrap"), 3, "inventory restored")
	check_eq(t.inventory.count("canned_food"), 2, "eaten food stays eaten")
	check(h.debug_player_pos().distance_to(LIVING_ROOM) < 0.05, "player position restored (%s)" % h.debug_player_pos())
	check(absf(h.debug_player().rig.rotation.y - 1.0) < 0.3, "facing restored")
	check_eq(h.time_scale, 2.0, "time scale restored")
	check(int(dmg.get("missing_voxels", 0)) > 0, "the house was damaged before saving")
	check_eq(h.debug_world().damage_summary(), dmg, "house damage restored")
	if built:
		check_eq(h.debug_world().count_objects("crate"), crates, "built crate restored")
		check_eq(t.inventory.storage_crates, crates, "storage caps follow the loaded crates")


func test_continue_with_a_bad_save_returns_to_the_menu_with_a_notice() -> void:
	SaveGame.path_override = SAVE
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string("not a save")
	f.close()
	var g: Node = await _boot("continue")
	check_eq(g.left_to, GameLaunch.MENU_SCENE, "back to the menu")
	check(GameLaunch.notice.begins_with("The save could not be loaded"), "readable notice (%s)" % GameLaunch.notice)
	g.queue_free()
	await frames(2)
	GameLaunch.notice = ""
	SaveGame.write({"summary": {}, "state": {"bogus": 1}, "world": {}})
	var h: Node = await _boot("continue")
	check_eq(h.left_to, GameLaunch.MENU_SCENE, "an invalid state also bounces")
	check(GameLaunch.notice.contains("survival state"), "and says why (%s)" % GameLaunch.notice)


func test_autosave_rules() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	check(g.autosave_log.has("new_run"), "new run saved")
	var e: Node = g.debug_spawn_enemy(Vector2(-6.0, -5.0))
	check(g.can_save().contains("enemies"), "no saving with a psycho alive (%s)" % g.can_save())
	check(g.save_now() != "", "save_now refuses too")
	_set_time(g, 23.9 * 60.0)
	g.dev_advance(10.0)                # crosses midnight with the psycho alive
	check(g.autosave_log.has("skip:new_day"), "new-day autosave skipped (%s)" % [g.autosave_log])
	g.debug_kill_enemies()
	await frames(2)
	g.dev_skip_to(6.0)                 # dawn
	check(g.autosave_log.has("dawn"), "dawn autosave (%s)" % [g.autosave_log])
	g.debug_open("pause")
	check_eq(g.debug_modal(), "pause", "paused")
	check_eq(g.can_save(), "", "saving from the pause menu is allowed")
	g.debug_close()
	g.dev_trigger_invasion()
	check(g.can_save().contains("invasion"), "no saving during an invasion")
	g.debug_set_spawn_gap(Vector2(0.05, 0.1))
	check(await _wait_until(func(): return g.debug_director().all_spawned(), 300), "all invaders spawned")
	await frames(2)
	g.debug_kill_enemies()
	check(await _wait_until(func(): return not g.debug_director().active, 30), "the invasion ends when they're all dead")
	check(g.autosave_log.has("invasion_end"), "autosave after the invasion (%s)" % [g.autosave_log])
	check(not s.run.get("invasion_active", true), "state: invasion over")
	check_eq(int(s.run.get("invasions_done", 0)), 1, "one invasion survived")
	check_eq(g.last_toast, "They're gone… for now", "toast")
	check(not is_instance_valid(e) or not e.alive, "cleanup")


# --- death -----------------------------------------------------------------------------

func test_death_deletes_the_save_and_shows_the_death_screen() -> void:
	var g: Node = await _boot()
	check(SaveGame.info()["exists"], "a save exists")
	g.debug_state().damage(500.0, "psycho")
	check(await _wait_until(func(): return tree.paused, 60), "the world stops")
	check_eq(g.debug_modal(), "death", "death screen")
	check(g.debug_ui().death_screen.visible, "death screen visible")
	check(not SaveGame.info()["exists"], "the run's save is deleted")
	check(g.can_save() != "", "no saving when dead")
	g.debug_ui().death_screen.main_menu_requested.emit()
	check_eq(g.left_to, GameLaunch.MENU_SCENE, "the death screen leads to the main menu")


# --- dev API ---------------------------------------------------------------------------

func test_dev_api() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	g.dev_spawn(2)
	check_eq(g.debug_living_enemies(), 2, "dev_spawn(2)")
	for p in g.debug_enemy_positions():
		check(not FogBoundary.LOT.has_point(p) and HousePlan.YARD.has_point(p), "spawned in the fog band (%s)" % p)
	g.debug_kill_enemies()
	var t0 := s.total_minutes
	g.dev_advance(60.0)
	check(absf(s.total_minutes - t0 - 60.0) < 0.001, "dev_advance(60)")
	g.dev_skip_to(21.0)
	check_eq(s.clock_text(), "21:00", "dev_skip_to(21)")
	g.dev_skip_to(9.5)
	check_eq(s.clock_text(), "09:30", "dev_skip_to next occurrence")
	check_eq(s.day(), 2, "on the next day")
	g.dev_set_time_scale(30.0)
	t0 = s.total_minutes
	await seconds(1.0)
	check(s.total_minutes - t0 > 20.0, "time scale 30 runs the clock faster (%.1f min in 1 s)" % (s.total_minutes - t0))
	g.dev_set_time_scale(1.0)
	g.debug_teleport_player(Vector2(3.6, 1.2))
	await frames(2)
	for i in 4:
		g.debug_fire_at(Vector2(4.0, 0.0), 1.0)
	check(int(g.debug_world().damage_summary()["missing_voxels"]) > 0, "shots damage the house")
	g.dev_repair_house()
	check_eq(int(g.debug_world().damage_summary()["missing_voxels"]), 0, "dev_repair_house")
	var info: String = g.dev_info()
	check(info.contains("Day 2") and info.contains("invasion"), "dev_info (%s)" % info)
	g.dev_trigger_invasion()
	check(s.run.get("invasion_active", false) and g.debug_director().active, "dev_trigger_invasion")
	# Experiment 003: the threat-budget wave for the difficulty and invasion index.
	var d = g.debug_director()
	check_eq(d.total, d.wave.size(), "the wave's size")
	var seed := int(s.run.get("seed", 0)) * 31 + int(s.run.get("invasions_done", 0))
	check_eq(d.wave, Director.compose(s.difficulty, s.invasion_index(), seed), "composed from the budget (%s)" % [d.wave])
	check(d.total >= 1 and d.total <= Director.max_count(s.difficulty, s.invasion_index()), "a small first wave (%d)" % d.total)


# --- invasions -------------------------------------------------------------------------

func test_invasion_survivors_retreat_at_dawn() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	_set_time(g, float(s.run["next_invasion_at"]) - 1.0)
	g.dev_advance(2.0)
	check(g.debug_director().active, "invasion_due starts the invasion")
	g.debug_set_spawn_gap(Vector2(0.05, 0.1))
	check(await _wait_until(func(): return g.debug_living_enemies() >= 1, 120), "invaders arrive")
	g.dev_skip_to(6.0)
	check(not g.debug_director().active, "the invasion ends at dawn")
	check(not s.run.get("invasion_active", true), "state agrees")
	check_eq(g.debug_living_enemies(), 0, "survivors are no longer a threat")
	check(g.autosave_log.has("invasion_end") or g.autosave_log.has("dawn"), "autosaved at dawn (%s)" % [g.autosave_log])
	check(await _wait_until(func(): return g.debug_roster().present() == 0, 60 * 20), "they walk into the fog and are gone")


# --- stragglers ------------------------------------------------------------------------

func test_stragglers_are_deterministic() -> void:
	var next := 2 * DAY + 22 * 60.0                # Day 3 22:00
	var hits := 0
	for d in range(2, 202):
		var a := Director.straggler_at(77, d, next)
		check_eq(a, Director.straggler_at(77, d, next), "same seed and day, same answer")
		if a >= 0.0:
			hits += 1
			var m := fposmod(a, DAY)
			check(m >= 23 * 60.0 or m <= 3 * 60.0, "between 23:00 and 03:00 (%.0f)" % m)
			check(a >= (d - 1) * DAY + 23 * 60.0 and a <= d * DAY + 3 * 60.0, "on that night")
	check(hits >= 50 and hits <= 90, "about 35 %% of nights (%d / 200)" % hits)
	check_eq(Director.straggler_at(77, 1, next), -1.0, "none on Day 1")
	check_eq(Director.straggler_at(77, 3, next), -1.0, "none on an invasion night")
	# In the game: crossing tonight's straggler time spawns one psycho.
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	var day := -1
	var at := -1.0
	for d in range(2, 40):
		at = g.debug_straggler_time(d)
		if at >= 0.0:
			day = d
			break
	check(day >= 2, "this seed has a straggler night")
	_set_time(g, at - 5.0)
	g.dev_advance(10.0)
	check_eq(g.debug_living_enemies(), 1, "one straggler on night %d" % day)
	check(g.last_toast.contains("moving out there"), "a quiet warning")
	g.dev_advance(5.0)
	check_eq(g.debug_living_enemies(), 1, "only one")


func test_sleep_is_cut_short_by_a_straggler() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	var at := -1.0
	for d in range(2, 40):
		at = g.debug_straggler_time(d)
		if at >= 0.0 and not Director.is_invasion_night(d, float(s.run["next_invasion_at"])):
			break
	_set_time(g, at - 90.0)
	var plan: Dictionary = await g.debug_sleep(-1.0)
	check(plan.get("interrupted", false) and plan.get("reason", "") == "straggler", "interrupted by the straggler (%s)" % [plan])
	check(absf(s.total_minutes - at) < 0.05, "woken at its arrival")
	check_eq(g.debug_living_enemies(), 1, "it is there")


# --- interactions and panels -----------------------------------------------------------

func test_bed_prompt_and_panels() -> void:
	var g: Node = await _boot()
	var bed: Vector3 = g.debug_world().bed_position()
	g.debug_teleport_player(Vector2(bed.x, bed.z + 1.2))
	await frames(2)
	check(g.debug_prompt() != "", "a prompt near the bed (%s)" % g.debug_prompt())
	await _tap("interact")
	check_eq(g.debug_modal(), "sleep", "E at the bed opens the sleep dialog")
	await _tap("pause")
	check_eq(g.debug_modal(), "", "Esc closes it")
	await _tap("pause")
	check_eq(g.debug_modal(), "pause", "Esc opens the pause menu")
	check(tree.paused, "paused")
	var t0: float = g.debug_state().total_minutes
	await frames(20)
	check_eq(g.debug_state().total_minutes, t0, "no clock while paused")
	await _tap("pause")
	check_eq(g.debug_modal(), "", "Esc resumes")
	g.debug_open("pause")
	SaveGame.delete_save()
	g.debug_ui().pause_menu.save_requested.emit()
	check(SaveGame.info()["valid"], "Save from the pause menu writes the save")
	var status: Node = g.debug_ui().pause_menu.find_child("Status", true, false)
	if status is Label:
		check_eq((status as Label).text, "Game saved.", "and the menu reports it (report_save)")
	g.debug_ui().pause_menu.main_menu_requested.emit()
	check_eq(g.left_to, GameLaunch.MENU_SCENE, "Main Menu leaves")
	g.debug_close()                  # (stay_in_scene: still here) resume
	check_eq(g.debug_modal(), "", "resumed")
	g.debug_open("inventory")
	check_eq(g.debug_prompt(), "", "no prompt while a panel is open")
	g.debug_close()
	await _tap("dev_menu")
	check(g.debug_ui().dev_menu.visible, "F10 opens the dev menu")
	g.debug_teleport_player(Vector2(4.5, 12.2))
	await frames(3)
	check(g.debug_prompt() != "", "a prompt at the fog edge (%s)" % g.debug_prompt())


func test_a_freed_psycho_in_the_roster_is_not_an_error() -> void:
	var g: Node = await _boot()
	var e: Node = g.debug_spawn_enemy(Vector2(-6.0, -5.0), true)
	await frames(1)
	e.free()                         # as after a corpse's queue_free, before the roster prunes
	check_eq(g.debug_living_enemies(), 0, "living() skips it")
	check_eq(g.debug_roster().invaders_alive(), 0, "invaders_alive() skips it")
	check_eq(g.debug_enemy_positions().size(), 0, "positions() skips it")
	check_eq(g.can_save(), "", "and saving is allowed")
	await frames(2)


func test_settings_opens_from_the_pause_menu_and_returns_to_it() -> void:
	var g: Node = await _boot()
	g.debug_open("settings")               # the pause menu's own Settings button
	await frames(2)
	var pause: Node = g.debug_ui().pause_menu
	var panel: Node = pause.settings_panel() if pause.has_method("settings_panel") else null
	check(panel != null and panel.is_open, "the pause menu's built-in settings panel is open")
	check_eq(g.debug_modal(), "pause", "the game stays in the pause state")
	check(tree.paused, "still paused")
	await _tap("pause")
	check(panel == null or not panel.is_open, "Esc closes settings")
	check_eq(g.debug_modal(), "pause", "back on the pause menu")
	await _tap("pause")
	check_eq(g.debug_modal(), "", "Esc again resumes (resume_requested)")
	check(not tree.paused, "unpaused")
