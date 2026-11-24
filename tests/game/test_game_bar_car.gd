extends "res://tests/test_case.gd"
## Experiment 004 (E) in the real game scene: the quick-access bar through the
## game's input (1-8, X, LMB use), empty hands holster the weapon, and the yard
## car's inspect -> repair flow and the F10 car tools.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_game_bar_car.dat"
const BY_THE_CAR := Vector2(15.3, 10.6)


func _boot() -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = "new"
	GameLaunch.seed = 777
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


func _key(code: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await frames(1)


func _click() -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = "fire"
		e.pressed = pressed
		Input.parse_input_event(e)
		await frames(2)


func test_the_bar_selects_uses_and_holsters_through_the_game_input() -> void:
	var g := await _boot()
	var s: GameState = g.debug_state()
	var w: WeaponHandler = g.combat.weapons
	check(g.bar.view.visible, "the bar shows in play")
	check_eq(w.current_id(), "handgun", "1: the handgun in hand")
	check(g.player.rig.aiming, "aiming pose with a weapon")
	await _key(KEY_X)
	check_eq(w.current_id(), "", "X: holstered")
	check(not g.player.rig.aiming, "arms hang with empty hands")
	var r: Dictionary = g.debug_fire_at(Vector2(6.0, 2.0))
	check(not r.get("ok", false), "nothing fires with empty hands")
	var wi := Hotbar.slot_of(s.hotbar, "water")
	await _key(KEY_1 + wi)
	check_eq(g.bar.in_hand(), "water", "the water's key takes it in hand")
	check_eq(g.player.rig.held, "water", "held in the right hand")
	s.hydration = 40.0
	var n := s.inventory.count("water")
	await _click()
	check_eq(s.inventory.count("water"), n - 1, "LMB drinks one")
	check(s.hydration > 40.0, "and it helps")
	check(g.last_toast.begins_with("Bottled water"), "with a toast (%s)" % g.last_toast)
	await _key(KEY_1)
	check_eq(w.current_id(), "handgun", "back to the handgun")
	g.debug_open("build")
	await frames(2)
	check(not g.bar.view.visible, "hidden in build mode")
	g.debug_close()
	await frames(2)
	g.debug_open("inventory")
	await frames(2)
	check(not g.bar.view.visible, "hidden behind panels")
	check_eq(g.debug_ui().inventory.put_on_bar("bandage"), "", "Put on bar from the inventory")
	check_eq(Hotbar.at(s.hotbar, int(s.hotbar["selected"])), "bandage", "into the selected slot")
	g.debug_close()
	await frames(2)


func test_the_car_is_inspected_repaired_and_saved() -> void:
	var g := await _boot()
	var s: GameState = g.debug_state()
	g.debug_teleport_player(BY_THE_CAR)
	await frames(3)
	check_eq(g.debug_prompt(), "[E] Inspect the car", "the car's prompt")
	g.debug_interact()
	check(g.last_toast.contains("Car battery 0/1"), "inspecting lists the parts (%s)" % g.last_toast)
	g.car.dev_give_parts()
	await frames(2)
	check_eq(g.debug_prompt(), "[E] Repair the car (2 h)", "ready to repair")
	var t0 := s.total_minutes
	g.debug_interact()
	check(await _wait(func(): return s.car_repaired, 120), "repaired")
	check(absf(s.total_minutes - t0 - 120.0) < 1.0, "two hours passed (%.1f)" % (s.total_minutes - t0))
	check_eq(s.inventory.count("car_battery"), 0, "the battery went in")
	check_eq(s.inventory.count("fuel"), 2, "two cans spent, two spare left")
	check(ExpeditionData.can_drive(s), "the car can go on expeditions")
	await frames(3)
	check_eq(g.debug_prompt(), "[E] Check the car", "repaired prompt")
	check_eq(g.debug_save(), "", "saved")
	var back := GameState.from_dict(SaveGame.read().get("data", {}).get("state", {}))
	check(back != null and back.car_repaired, "the repair is in the save")


func _wait(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await frames(1)
	return cond.call()
