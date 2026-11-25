extends "res://tests/test_case.gd"
## Exp 006 (R): research and the shotgun in the real game scene. K opens the
## inventory's Skills tab; F10 Research gives books and learns or forgets
## skills; build mode refuses a locked piece; a book is read; then the
## shotgun from F10 "+ Shotgun & shells" goes on the quick bar, its bar key
## takes it in hand, R reloads shell by shell, a blast hits an enemy; save
## and Continue keep the skills, the magazine, the equipped slot and the bar.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_research_game.dat"
const FRONT_YARD := Vector2(9.0, 11.2)


func _boot(mode := "new") -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 4243
	GameLaunch.difficulty = "normal"
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
	await super.cleanup()


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


func test_research_and_the_shotgun_in_the_game() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	check(s.skills.is_empty(), "a new game knows no skills")
	# K: the Skills tab
	await _key(KEY_K)
	check_eq(g.debug_modal(), "inventory", "K opens the inventory")
	var inv: InventoryPanel = g.debug_ui().inventory
	check_eq(inv.tab, "skills", "on the Skills tab")
	check(inv.find_child("Skill_metalworking", true, false) != null, "the tree is shown")
	g.debug_close()
	await frames(2)
	check_eq(g.debug_modal(), "", "closed")
	# F10 Research
	var m: DevMenu = g.debug_ui().dev_menu
	m.toggle()
	await frames(2)
	check(m.button("+ All books") != null and m.button("Learn all") != null and m.button("Forget all") != null and m.button("Show skills") != null,
		"the Research section")
	m.button("+ All books").pressed.emit()
	for b in Research.books():
		check_eq(s.inventory.count(b), 1, "F10 gives %s" % b)
	check(g.last_toast.contains("New book"), "a toast says where to read it (%s)" % g.last_toast)
	m.button("Show skills").pressed.emit()
	check(m.last_status.contains("none"), "no skills yet (%s)" % m.last_status)
	# build mode: a locked piece
	g.debug_open("build")
	g.build.select_id("metal_door")
	var r: Dictionary = g.build.evaluate(Vector2(14.0, 3.5))
	check(str(r["reason"]).begins_with("Requires Metalworking"), "the metal door is locked (%s)" % r["reason"])
	m.button("Learn all").pressed.emit()
	check_eq(Research.known(s).size(), 4, "F10 learns all")
	r = g.build.evaluate(Vector2(14.0, 3.5))
	check(not str(r["reason"]).begins_with("Requires"), "unlocked (%s)" % r["reason"])
	m.button("Forget all").pressed.emit()
	check(s.skills.is_empty(), "F10 forgets all")
	g.debug_close()
	await frames(1)
	check(not g.build.active, "out of build mode")
	m.toggle()
	await frames(1)
	# read a book from the Skills tab
	await _key(KEY_K)
	inv.read_book("book_woodworking")
	check(Research.knows(s, "woodworking"), "read from the Skills tab")
	g.debug_close()
	await frames(2)
	# the shotgun: F10, the bar, reload, a blast at an enemy
	m.toggle()
	await frames(1)
	m.button("+ Shotgun & shells").pressed.emit()
	m.toggle()
	await frames(2)
	check_eq(s.equipped("secondary"), "shotgun", "equipped as the secondary weapon")
	var slot := Hotbar.slot_of(s.hotbar, "shotgun")
	check(slot >= 0, "on the quick bar (slot %d)" % (slot + 1))
	await _key(KEY_1 + slot)
	var w: Node = g.combat.weapons
	check_eq(w.current_id(), "shotgun", "its bar key takes it in hand")
	check_eq(s.magazine("shotgun"), 0, "found empty")
	await _key(KEY_R)
	check(w.is_reloading(), "R reloads")
	check(await _wait_until(func(): return s.magazine("shotgun") == 5, 60 * 5), "shell by shell to 5 (%d)" % s.magazine("shotgun"))
	check_eq(s.reserve("shotgun"), 5, "5 shells left")
	g.debug_teleport_player(FRONT_YARD)
	var target := FRONT_YARD + Vector2(0.0, 3.0)
	var e: Node = g.debug_spawn_enemy(target)
	await frames(2)
	var hp0: int = e.hp
	var shot: Dictionary = g.debug_fire_at(Vector2(e.global_position.x, e.global_position.z), 1.1)
	check(shot.get("ok", false) and int(shot.get("pellets", 0)) == 6, "one blast, six pellets (%s)" % shot)
	var hits := 0
	for h in shot.get("hits", []):
		if (h as Dictionary).get("enemy") == e or (h as Dictionary).get("node") == e:
			hits += 1
	check(not e.alive or e.hp < hp0, "the enemy is hurt (%d -> %d, %d pellets on it)" % [hp0, e.hp, hits])
	check(hp0 - (e.hp if e.alive else 0) >= 2, "several pellets land at 3 m (%d -> %d)" % [hp0, e.hp])
	check_eq(s.magazine("shotgun"), 4, "one shell spent")
	g.debug_kill_enemies()
	await frames(2)
	# save and Continue
	var bar_slots: Array = (s.hotbar["slots"] as Array).duplicate()
	check_eq(g.debug_save(), "", "save allowed")
	g.queue_free()
	await frames(3)
	var h2: Node = await _boot("continue")
	var t: GameState = h2.debug_state()
	check_eq(Research.known(t), ["woodworking"], "skills restored")
	check_eq(t.inventory.count("book_woodworking"), 0, "the read book stays read")
	check_eq(t.inventory.count("book_metalworking"), 1, "unread books restored")
	check_eq(t.magazine("shotgun"), 4, "the magazine restored")
	check_eq(t.reserve("shotgun"), 5, "the shells restored")
	check_eq(t.equipped("secondary"), "shotgun", "still the secondary weapon")
	check_eq(t.hotbar["slots"], bar_slots, "the bar restored")
	check_eq(Hotbar.slot_of(t.hotbar, "shotgun"), slot, "the shotgun in its slot")
