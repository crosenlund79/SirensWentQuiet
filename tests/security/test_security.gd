extends "res://tests/test_case.gd"
## Exp 007 (S): electronic security. Installing a gun takes it out of the
## inventory (equipment, quick bar) with its magazine and removing it gives
## both back; a destroyed mount drops the gun, the magazine and the box in a
## pile. A turret with the auto-loader reloads from its box and fires at an
## enemy in the open with real ammunition, and never through a wall. A sensor
## triggers on an enemy in its cone and not on Eli; a linked standby turret
## wakes. Settings, the gun, the magazine and the box survive save and load.
## One smoke test in the real game scene through the F10 "Security" tools.

const Roster := preload("res://src/game/enemy_roster.gd")
const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_security_game.dat"


func _world() -> HouseWorld:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	await physics_frames(2)
	return w


## [player, roster] on world `w`.
func _actors(w: HouseWorld, eli_at: Vector2) -> Array:
	var player := VoxelPlayer.new()
	player.input_enabled = false
	add(player)
	player.global_position = Vector3(eli_at.x, 0, eli_at.y)
	var roster: Node3D = Roster.new()
	roster.setup(w, player, 7)
	add(roster)
	await physics_frames(1)
	return [player, roster]


## A still enemy (its AI off) at plan point p.
func _still_enemy(roster: Node3D, p: Vector2, hp := 40) -> AIEnemy:
	var e: AIEnemy = roster.spawn_type("psycho", p, {"hp": hp})
	e.set_physics_process(false)
	e.set_process(false)
	e.global_position = Vector3(p.x, 0, p.y)
	return e


func _system(w: HouseWorld, roster: Node3D, player: Node3D) -> SecuritySystem:
	var sys := SecuritySystem.new()
	sys.auto_tick = false
	sys.rng.seed = 5
	add(sys)
	sys.setup_parts(func(): return [w], func(): return roster.enemies, player, func(): return true)
	return sys


func _run(sys: SecuritySystem, seconds: float) -> void:
	var n := int(seconds * 60.0)
	for i in n:
		sys.tick(1.0 / 60.0)
		await physics_frames(1)


func test_install_and_remove_a_gun() -> void:
	var w: HouseWorld = await _world()
	var s := GameState.new_run(3)
	s.inventory.add("handgun", 1)
	s.set_magazine("handgun", 7)
	Hotbar.fill(s.hotbar, s)
	check(s.equipped("primary") == "handgun" or s.equipped("secondary") == "handgun", "the handgun starts equipped")
	check(Hotbar.slot_of(s.hotbar, "handgun") >= 0, "and on the quick bar")
	var t := w.place_object("turret_mount", Vector2(7.0, 11.0), 2, true)
	check(t.uid != "", "a turret has a stable id")
	check_eq(Security.install_gun(s, t, "shells"), "That doesn't fit a turret mount.", "only firearms")
	check_eq(Security.install_gun(s, t, "handgun"), "", "installed")
	check_eq(s.inventory.count("handgun"), 0, "the gun left the inventory")
	check(s.equipped("primary") != "handgun" and s.equipped("secondary") != "handgun", "and the equipment")
	check(Hotbar.slot_of(s.hotbar, "handgun") < 0, "and the quick bar")
	check_eq(Security.gun(t), "handgun", "on the mount")
	check_eq(Security.mag(t), 7, "with its magazine")
	check(Security.install_gun(s, t, "shotgun") != "", "one gun per mount")
	var r := Security.remove_gun(s, t)
	check(r["ok"] and not r["pile"], "removed into the inventory")
	check_eq(s.inventory.count("handgun"), 1, "the gun is back")
	check_eq(s.magazine("handgun"), 7, "with the same magazine")
	check_eq(Security.gun(t), "", "the mount is empty")
	Hotbar.fill(s.hotbar, s)
	check(Hotbar.slot_of(s.hotbar, "handgun") >= 0, "back on the quick bar")
	# a second handgun: removing it can't duplicate or lose anything
	Security.install_gun(s, t, "handgun")
	s.inventory.add("handgun", 1)
	r = Security.remove_gun(s, t)
	check(r["pile"], "Eli already carries one: it goes on the ground")
	var pile: WorldObject = null
	for o in w.objects:
		if o.kind == "loot_pile":
			pile = o
	check(pile != null and int(pile.items.get("handgun", 0)) == 1 and int(pile.items.get("ammo", 0)) == 7, "in a pile with its rounds")
	if pile != null:
		w.remove_object(pile)
	# destroyed: the gun, the magazine and the box drop into a pile
	s.set_magazine("handgun", 7)
	check_eq(Security.install_gun(s, t, "handgun"), "", "installed again")
	t.items["ammo"] = 15
	w.damage_object(t, 999, Vector3(7, 1, 14))
	check(not w.objects.has(t), "the mount was destroyed")
	pile = null
	for o in w.objects:
		if o.kind == "loot_pile":
			pile = o
	check(pile != null and int(pile.items.get("handgun", 0)) == 1 and int(pile.items.get("ammo", 0)) == 15 + 7,
		"the gun, its magazine and the box in a pile (%s)" % (str(pile.items) if pile != null else "none"))


func test_turret_fires_in_the_open_and_not_through_walls() -> void:
	var w: HouseWorld = await _world()
	var a: Array = await _actors(w, Vector2(-2.0, -2.0))
	var player: Node3D = a[0]
	var roster: Node3D = a[1]
	var sys := _system(w, roster, player)
	# in the open: a mount in the front yard facing south, an enemy 5 m away
	var t := w.place_object("turret_mount", Vector2(10.5, 9.8), 2, true)
	var c := Security.config(t)
	c["gun"] = "handgun"
	c["mag"] = 0
	c["auto"] = true
	t.items["ammo"] = 30
	var e := _still_enemy(roster, Vector2(11.0, 12.3), 40)
	await physics_frames(2)
	check(Security.is_target(e), "a hostile target")
	check(sys.pick_target(t, w, 0, roster.enemies) == null or Security.mag(t) == 0, "nothing loaded yet")
	await _run(sys, 6.0)
	var rounds_left := Security.mag(t) + Security.box(t)
	check(sys.shots > 0, "the auto-loader reloaded and the turret fired (%d shots)" % sys.shots)
	check_eq(rounds_left, 30 - sys.shots, "every shot spent a real round")
	check(e.hp < 40, "hits through the same path as Eli's weapon (enemy HP %d)" % e.hp)
	# Eli in the line of fire: it holds
	var before := sys.shots
	player.global_position = Vector3(10.8, 0, 11.1)
	await physics_frames(2)
	await _run(sys, 1.5)
	check_eq(sys.shots, before, "never fires through Eli")
	player.global_position = Vector3(-2.0, 0, -2.0)
	# switched off: it stops
	c["on"] = false
	await _run(sys, 1.0)
	check_eq(sys.shots, before, "switched off, it doesn't fire")
	c["on"] = true
	e.kill_quietly()
	# behind a wall: a mount in the living room facing the solid south wall
	var t2 := w.place_object("turret_mount", Vector2(9.3, 8.1), 2, true)
	var c2 := Security.config(t2)
	c2["gun"] = "handgun"
	c2["mag"] = 12
	w.remove_object(t)
	var e2 := _still_enemy(roster, Vector2(9.3, 11.3), 40)
	await physics_frames(2)
	var shots0 := sys.shots
	check(Security.in_arc(t2, e2.plan_pos(), Security.TURRET_ARC), "the enemy is in its arc and range")
	await _run(sys, 2.0)
	check(sys._rt.has(t2.get_instance_id()), "the mount was ticked")
	check_eq(sys.shots, shots0, "it doesn't fire through a wall")
	check_eq(Security.mag(t2), 12, "and spends nothing")
	check_eq(e2.hp, 40, "the enemy is unhurt")


func test_sensor_triggers_on_enemies_not_on_eli() -> void:
	var w: HouseWorld = await _world()
	var a: Array = await _actors(w, Vector2(6.0, 12.0))
	var player: Node3D = a[0]
	var roster: Node3D = a[1]
	var sys := _system(w, roster, player)
	var sn := w.place_object("motion_sensor", Vector2(6.15, 10.15), 2, true)
	check(Security.config(sn)["name"] == "in the front yard" or str(Security.config(sn)["name"]).begins_with("at the"), "named by where it stands (%s)" % Security.config(sn)["name"])
	var got := []
	sys.sensor_triggered.connect(func(o, e): got.append(e))
	await _run(sys, 1.0)
	check_eq(sys.triggers, 0, "Eli right in front of it: nothing")
	# a standby turret linked to it
	var t := w.place_object("turret_mount", Vector2(3.3, 10.3), 2, true)
	var tc := Security.config(t)
	tc["gun"] = "handgun"
	tc["mag"] = 12
	tc["standby"] = true
	Security.config(sn)["link"] = t.uid
	var e := _still_enemy(roster, Vector2(5.0, 12.0), 40)
	await physics_frames(2)
	check(not sys.is_awake(t), "the standby turret sleeps")
	await _run(sys, 0.6)
	check_eq(sys.triggers, 1, "an enemy in its cone triggers it")
	check(got.size() == 1 and got[0] == e, "with that enemy")
	check(sys.is_awake(t), "the linked turret woke")
	await _run(sys, 1.0)
	check_eq(sys.triggers, 1, "one notification per cooldown")
	# behind it (outside the cone): nothing
	e.kill_quietly()
	sys.time += Security.SENSOR_COOLDOWN
	var e2 := _still_enemy(roster, Vector2(6.15, 7.0), 40)
	await physics_frames(2)
	await _run(sys, 0.6)
	check_eq(sys.triggers, 1, "not behind it (and not through the wall)")
	e2.kill_quietly()
	# no power: blind
	sys.power_fn = func(): return false
	_still_enemy(roster, Vector2(6.5, 12.5), 40)
	await physics_frames(2)
	await _run(sys, 0.6)
	check_eq(sys.triggers, 1, "an unpowered sensor sees nothing")


func test_settings_survive_save_and_load() -> void:
	var w: HouseWorld = await _world()
	var sn := w.place_object("motion_sensor", Vector2(6.15, 10.15), 2, true)
	var t := w.place_object("turret_mount", Vector2(3.3, 10.3), 1, true)
	var sc := Security.config(sn)
	sc["alarm"] = false
	sc["link"] = t.uid
	var tc := Security.config(t)
	tc["gun"] = "shotgun"
	tc["mag"] = 3
	tc["auto"] = true
	tc["on"] = false
	t.items["shells"] = 11
	t.hp = 20
	var d := w.save_data()
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(bytes_to_var(var_to_bytes(d))), "loads")
	await physics_frames(1)
	var sn2: WorldObject = null
	var t2: WorldObject = null
	for o in w2.objects:
		if o.kind == "motion_sensor":
			sn2 = o
		elif o.kind == "turret_mount":
			t2 = o
	check(sn2 != null and t2 != null, "both are back")
	if sn2 == null or t2 == null:
		return
	check_eq(t2.uid, t.uid, "the turret keeps its id")
	check_eq(Security.config(sn2)["link"], t2.uid, "the link")
	check_eq(Security.config(sn2)["alarm"], false, "silent")
	check_eq(t2.rot, 1, "its facing")
	check_eq(Security.gun(t2), "shotgun", "the installed gun")
	check_eq(Security.mag(t2), 3, "its magazine")
	check_eq(Security.box(t2), 11, "the ammo box")
	check(bool(Security.config(t2)["auto"]) and not bool(Security.config(t2)["on"]), "the upgrade and the switch")
	check_eq(t2.hp, 20, "its HP")
	check(SecurityObjects.head_of(t2) != null and SecurityObjects.head_of(t2).get_node_or_null("Gun_shotgun") != null, "the shotgun shows on the head")
	# offscreen strength (agent T)
	var off := Security.offscreen_strength(w2)
	check_eq(off["turrets"], 0, "a switched-off turret doesn't count")
	Security.config(t2)["on"] = true
	off = Security.offscreen_strength(w2)
	check(off["turrets"] == 1 and off["ammo"] == 14 and off["sensors"] == 1 and float(off["score"]) > 0.0, "one turret, 14 shells, one sensor (%s)" % str(off))
	check_eq(Security.consume_offscreen(w2, 5), 5, "fights offscreen with real shells")
	check_eq(Security.usable_rounds(t2), 9, "and they are gone")
	# a malformed save drops the settings, never the object
	d["objects"].append({"kind": "turret_mount", "x": 1.0, "y": 11.0, "rot": 0, "hp": 30, "sec": {"gun": "rocket", "mag": 99, "on": "yes"}})
	var w3 := HouseWorld.new()
	add(w3)
	check(w3.load_data(d), "a damaged setting still loads")


func test_security_in_the_game() -> void:
	SaveGame.path_override = SAVE
	GameLaunch.mode = "new"
	GameLaunch.seed = 4250
	GameLaunch.difficulty = "normal"
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	check(g.security is SecuritySystem, "the game has a security helper")
	var s: GameState = g.state
	var dev: Node = g.security
	check(dev.dev_unlock().begins_with("Learned"), "F10 unlocks the research")
	check(Research.knows(s, "electronics") and Research.knows(s, "automation"), "both skills")
	dev.dev_give_components()
	check(s.inventory.count("electronics") > 0, "components")
	g.player.global_position = Vector3(8.0, 0, 11.5)
	await physics_frames(2)
	check(dev.dev_place_turret().contains("placed"), "F10 places a loaded turret")
	check(dev.dev_place_sensor().contains("placed"), "and a sensor")
	var t: WorldObject = dev._nearest("turret_mount")
	var sn: WorldObject = dev._nearest("motion_sensor")
	check(t != null and sn != null, "both stand in the yard")
	# the build menu gates and places a sensor
	g.build.select_id("motion_sensor")
	g.build.rot = 2
	var r: Dictionary = g.build.evaluate(Vector2(2.5, 11.0))
	check(r["reason"] == "" or not bool(r.get("locked", false)), "not locked any more (%s)" % r["reason"])
	# E on the turret opens its panel; the panel installs the shotgun after a removal
	t.interact(g)
	await frames(1)
	check_eq(str(g.get("_modal")), "security", "E opens the security panel")
	var p: SecurityPanel = dev.panel
	check(p.is_open and p.object == t, "for that turret")
	var rm := p.act("remove")
	check(rm.contains("taken off") or rm.contains("on the ground"), "the panel removes the gun (%s)" % rm)
	s.inventory.add("shotgun", 1)
	s.inventory.add("shells", 6)
	check(p.act("install", "shotgun").contains("mounted"), "and installs the shotgun (%s)" % p.last_text)
	await frames(4)
	check_eq(Security.gun(t), "shotgun", "the shotgun is on the mount")
	check_eq(s.inventory.count("shotgun"), 0, "and not in the inventory")
	check(str(g.get("_modal")) == "", "the panel closed for the job")
	check(dev.act_fill(t, 10).contains("shells"), "shells into the box")
	check(dev.dev_trigger_nearest().contains("Triggered"), "F10 triggers the nearest sensor")
	check(dev.dev_restore_power().contains("Power restored"), "F10 restores power")
	check(dev.dev_info().contains("Turret"), "info")
	check(g.save_now() is String, "saves")
	g.ui.dev_menu.set_open(true)
	await frames(1)
	check(g.ui.dev_menu.button("Sensor here") != null, "the F10 Security section")
	g.ui.dev_menu.set_open(false)


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()
