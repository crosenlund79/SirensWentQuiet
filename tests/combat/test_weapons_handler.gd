extends "res://tests/test_case.gd"
## WeaponHandler with light stand-ins for the world and the player (no
## physics): magazines, fire interval, reload timing, the shotgun's pellets,
## spread and range, the unlimited cheat, switching and persistence.


class FakeWorld extends Node:
	var fx = null
	var calls := []                    ## [origin, dir, exclude, muzzle]
	var far := 100.0                   ## aim_ray distance (the first hit along any ray)

	func shoot(origin: Vector3, dir: Vector3, exclude: Array, muzzle := Vector3.INF) -> Dictionary:
		calls.append([origin, dir, exclude, muzzle])
		return {"kind": "voxel", "pos": origin + dir * far, "collider": null}

	func aim_ray(from: Vector3, dir: Vector3) -> Vector3:
		return from + dir.normalized() * far


class RangedWorld extends Node:
	var fx = null
	var ranges := []

	func shoot(origin: Vector3, dir: Vector3, _exclude: Array, _muzzle := Vector3.INF, max_range := 40.0) -> Dictionary:
		ranges.append(max_range)
		return {"kind": "none", "pos": origin + dir * max_range, "collider": null}


class FakePlayer extends Node3D:
	var rig = null
	var shots := 0

	func on_fired() -> void:
		shots += 1


func _rig(state: GameState, world: Node = null) -> Array:
	var w: Node = world if world != null else FakeWorld.new()
	var p := FakePlayer.new()
	var h := WeaponHandler.new()
	h.auto_tick = false
	h.rng.seed = 1234
	add(w)
	add(p)
	add(h)
	h.setup(state, w, p)
	return [h, w, p]


func _with_shotgun(shells := 0) -> GameState:
	var s := GameState.new_run(8)
	s.inventory.add("shotgun", 1)
	s.inventory.add("shells", shells)
	return s


func test_handgun_magazine_and_fire_interval() -> void:
	var s := GameState.new_run(8)
	var r := _rig(s)
	var h: WeaponHandler = r[0]
	var fired := []
	h.fired.connect(func(id, hits): fired.append([id, hits.size()]))
	var res := h.try_fire(Vector3(0, 1, -10))
	check(res["ok"], "fires")
	check_eq(res["pellets"], 1, "one bullet")
	check_eq(s.magazine("handgun"), 8, "one round spent")
	check_eq(fired, [["handgun", 1]], "fired signal")
	check_eq((r[2] as FakePlayer).shots, 1, "player.on_fired")
	check_eq(h.try_fire(Vector3(0, 1, -10))["reason"], "cooldown", "0.2 s between shots")
	h.tick(0.19)
	check_eq(h.try_fire(Vector3(0, 1, -10))["reason"], "cooldown", "still")
	h.tick(0.011)
	check(h.try_fire(Vector3(0, 1, -10))["ok"], "after 0.2 s")
	for i in 7:
		h.tick(0.2)
		h.try_fire(Vector3(0, 1, -10))
	check_eq(s.magazine("handgun"), 0, "nine shots, nine rounds")
	check_eq(h.shots, 9, "counted")
	var empties := [0]
	h.empty.connect(func(_id): empties[0] += 1)
	h.tick(0.2)
	res = h.try_fire(Vector3(0, 1, -10))
	check_eq(res["reason"], "empty", "dry")
	check(not res["reloading"], "no reserve: no reload")
	check_eq(empties[0], 1, "empty signal")
	h.tick(0.2)
	h.try_fire(Vector3(0, 1, -10))
	check_eq(empties[0], 1, "dry clicks are throttled")
	h.tick(0.3)
	h.try_fire(Vector3(0, 1, -10))
	check_eq(empties[0], 2, "after the throttle")
	check_eq((r[1] as FakeWorld).calls.size(), 9, "every round went through world.shoot")


func test_handgun_reload_timing() -> void:
	var s := GameState.new_run(8)
	var h: WeaponHandler = _rig(s)[0]
	check_eq(h.reload(), "No 9 mm rounds left.", "no reserve")
	s.inventory.add("ammo", 20)
	var log := []
	h.reload_started.connect(func(id): log.append("start " + id))
	h.reloaded.connect(func(id): log.append("done " + id))
	check_eq(h.reload(), "", "starts")
	check_eq(h.reload(), "Already reloading.", "once")
	check(h.current()["reloading"], "reloading")
	h.tick(0.7)
	check(absf(h.current()["reload_progress"] - 0.5) < 1e-6, "half way")
	check_eq(h.try_fire(Vector3(0, 1, -10))["reason"], "reloading", "a magazine reload blocks firing")
	h.tick(0.69)
	check_eq(s.magazine("handgun"), 9, "not yet")
	h.tick(0.02)
	check_eq(s.magazine("handgun"), 12, "full after 1.4 s")
	check_eq(s.inventory.count("ammo"), 17, "three rounds from the reserve")
	check_eq(log, ["start handgun", "done handgun"], "signals")
	check_eq(h.reload(), "Full.", "full")
	check(not h.current()["reloading"], "done")


func test_auto_reload_on_an_empty_trigger_pull() -> void:
	var s := GameState.new_run(8)
	s.set_magazine("handgun", 0)
	s.inventory.add("ammo", 5)
	var h: WeaponHandler = _rig(s)[0]
	var res := h.try_fire(Vector3(0, 1, -10))
	check_eq(res["reason"], "empty", "click")
	check(res["reloading"] and h.is_reloading(), "and the reload starts")
	h.tick(1.41)
	check_eq([s.magazine("handgun"), s.inventory.count("ammo")], [5, 0], "the last five go in")
	h.auto_reload = false
	s.set_magazine("handgun", 0)
	s.inventory.add("ammo", 5)
	h.tick(1.0)
	check(not h.try_fire(Vector3(0, 1, -10))["reloading"], "auto_reload off")


func test_shotgun_pellets_spread_and_one_round_per_pull() -> void:
	# Exp 013: 8 pellets in an 11 degree cone (flattened vertically), a pump between shots
	var s := _with_shotgun(0)
	s.set_magazine("shotgun", 5)
	var r := _rig(s)
	var h: WeaponHandler = r[0]
	var w: FakeWorld = r[1]
	w.far = 5.0
	check_eq(h.select_slot("secondary"), "", "shotgun in hand")
	h.tick(WeaponHandler.SWITCH_DELAY)
	var aim := Vector3(0, 1.3, -10)
	var res := h.try_fire(aim)
	var n := int(WeaponDefs.get_def("shotgun")["pellets"])
	check(res["ok"], "fires")
	check_eq(res["pellets"], n, "%d pellets" % n)
	check_eq(w.calls.size(), n, "each through world.shoot")
	check_eq(s.magazine("shotgun"), 4, "one shell")
	var axis: Vector3 = h.last_shot["dir"]
	var max_dev := 0.0
	for c in w.calls:
		max_dev = maxf(max_dev, rad_to_deg((c[1] as Vector3).angle_to(axis)))
	check(max_dev <= float(WeaponDefs.get_def("shotgun")["spread"]) * 0.5 + 1e-3, "inside the cone (max %.2f)" % max_dev)
	check(max_dev > 0.5, "and spread out (max %.2f)" % max_dev)
	var iv := float(WeaponDefs.get_def("shotgun")["interval"])
	check_eq(h.try_fire(aim)["reason"], "cooldown", "pump: %.2f s" % iv)
	h.tick(iv - 0.01)
	check_eq(h.try_fire(aim)["reason"], "cooldown", "still")
	h.tick(0.011)
	check(h.try_fire(aim)["ok"], "after the pump")


func test_pellet_pattern_statistics() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var aim := Vector3(1, -0.2, -3).normalized()
	var dirs := WeaponDefs.pellet_dirs(aim, 6000, 9.0, rng)
	var worst := 0.0
	var outer := 0
	var mean := Vector3.ZERO
	for d in dirs:
		var a := rad_to_deg(d.angle_to(aim))
		worst = maxf(worst, a)
		if a > 3.6:
			outer += 1
		mean += d
	check(worst <= 4.5 + 1e-4, "all within half the spread (%.3f)" % worst)
	check(rad_to_deg(mean.normalized().angle_to(aim)) < 0.1, "centred on the aim")
	check(absf(outer / 6000.0 - 0.36) < 0.03, "uniform over the cross-section (outer ring %.3f, expected 0.36)" % (outer / 6000.0))
	var one := WeaponDefs.pellet_dirs(aim, 1, 0.0, rng)
	check(one.size() == 1 and one[0].is_equal_approx(aim), "no spread: the aim itself")
	var a := RandomNumberGenerator.new()
	a.seed = 9
	var b := RandomNumberGenerator.new()
	b.seed = 9
	check_eq(WeaponDefs.pellet_dirs(aim, 6, 9.0, a), WeaponDefs.pellet_dirs(aim, 6, 9.0, b), "deterministic for a seed")


func test_no_gun_has_a_short_range() -> void:
	# Exp 013: every gun's ray is the same long reach; only obstructions stop it
	for id in WeaponDefs.ids():
		check_eq(float(WeaponDefs.get_def(id)["range"]), WeaponDefs.RANGE, "%s: the full range" % id)
	var t := _with_shotgun(0)
	t.set_magazine("shotgun", 5)
	t.set_active_weapon_slot("secondary")
	var r2 := _rig(t, RangedWorld.new())
	(r2[0] as WeaponHandler).try_fire(Vector3(0, 1.3, -30))
	var ranges: Array = (r2[1] as RangedWorld).ranges
	check(ranges.size() == int(WeaponDefs.get_def("shotgun")["pellets"]) and ranges.all(func(x): return x == WeaponDefs.RANGE), "every pellet gets the full range (%s)" % [ranges])


func test_shotgun_reloads_shell_by_shell_and_firing_interrupts() -> void:
	var s := _with_shotgun(10)
	s.set_active_weapon_slot("secondary")
	var h: WeaponHandler = _rig(s)[0]
	var log := []
	h.reloaded.connect(func(id): log.append("done " + id))
	h.reload_interrupted.connect(func(id): log.append("interrupted " + id))
	check_eq(h.reload(), "", "starts")
	h.tick(0.49)
	check_eq(s.magazine("shotgun"), 0, "not yet")
	h.tick(0.02)
	check_eq(s.magazine("shotgun"), 1, "one shell after 0.5 s")
	h.tick(0.5)
	check_eq([s.magazine("shotgun"), s.reserve("shotgun")], [2, 8], "two in, eight left")
	check(h.is_reloading(), "still loading")
	var res := h.try_fire(Vector3(0, 1.3, -5))
	check(res["ok"], "firing interrupts the reload")
	check(not h.is_reloading(), "stopped")
	check_eq(s.magazine("shotgun"), 1, "one shell left")
	check_eq(log, ["interrupted shotgun"], "interrupted, not reloaded")
	h.tick(1.0)
	h.reload()
	h.tick(2.0)
	check_eq(s.magazine("shotgun"), 5, "full after four more shells (2.0 s)")
	check_eq(log.back(), "done shotgun", "reloaded")
	check(not h.is_reloading(), "stops when full")
	s.set_magazine("shotgun", 0)
	s.inventory.remove("shells", s.reserve("shotgun"))
	s.inventory.add("shells", 2)
	h.reload()
	h.tick(0.5)
	check_eq(h.try_fire(Vector3(0, 1.3, -5))["ok"], true, "one shell is enough to interrupt")
	h.reload()
	h.tick(0.5)
	check_eq([s.magazine("shotgun"), s.reserve("shotgun")], [1, 0], "the reserve ran out")
	check(not h.is_reloading(), "so the reload ends")
	s.set_magazine("shotgun", 0)
	s.inventory.add("shells", 3)
	h.reload()
	check_eq(h.try_fire(Vector3(0, 1.3, -5))["reason"], "reloading", "with no shell loaded, the trigger waits for the reload")


func test_unlimited_cheat_keeps_the_magazine_full() -> void:
	var s := _with_shotgun(0)
	s.set_magazine("handgun", 0)
	s.cheats["unlimited"] = true
	var h: WeaponHandler = _rig(s)[0]
	var ok := 0
	for i in 30:
		if h.try_fire(Vector3(0, 1, -10))["ok"]:
			ok += 1
		h.tick(0.2)
	check_eq(ok, 30, "every pull fires")
	check_eq(h.shots, 30, "thirty shots from an empty magazine")
	check_eq(s.magazine("handgun"), 12, "kept full")
	check_eq(s.inventory.count("ammo"), 0, "no rounds created in the inventory")
	check_eq(h.current()["unlimited"], true, "current() says so")
	h.switch_to("shotgun")
	h.tick(0.3)
	check(h.try_fire(Vector3(0, 1, -10))["ok"], "the shotgun too")
	check_eq(s.magazine("shotgun"), 5, "full")
	s.cheats["unlimited"] = false
	h.tick(1.0)
	h.try_fire(Vector3(0, 1, -10))
	check_eq(s.magazine("shotgun"), 4, "normal rules once the cheat is off")


func test_switching() -> void:
	var s := _with_shotgun(0)
	var h: WeaponHandler = _rig(s)[0]
	var log := []
	h.switched.connect(func(id): log.append(id))
	check_eq(h.current()["id"], "handgun", "handgun in hand")
	check_eq(h.next(), "shotgun", "next")
	check_eq(h.current()["id"], "shotgun", "shotgun in hand")
	check_eq(s.active_weapon_slot, "secondary", "state follows")
	check_eq(h.try_fire(Vector3(0, 1, -5))["reason"], "cooldown", "a moment to bring it up")
	check_eq(h.select_slot("primary"), "", "key 1")
	check_eq(h.current()["id"], "handgun", "handgun")
	check_eq(h.switch_to("handgun"), "", "already in hand")
	check_eq(log, ["shotgun", "handgun"], "switched signals")
	check_eq(h.switch_to("vest"), "That isn't equipped.", "not a weapon")
	s.inventory.add("ammo", 10)
	s.set_magazine("handgun", 0)
	h.reload()
	h.next()
	check(not h.is_reloading(), "switching cancels the reload")
	check_eq(s.magazine("handgun"), 0, "nothing was loaded")
	s.unequip("secondary")
	check_eq(h.current()["id"], "handgun", "the unequipped shotgun leaves the hand")
	check_eq(h.next(), "", "nothing to switch to")
	check_eq(h.select_slot("secondary"), "Nothing in the secondary weapon slot.", "empty slot")
	check_eq(h.switch_to("shotgun"), "Pump shotgun isn't equipped.", "owned but not equipped")


func test_current_and_no_weapon() -> void:
	var s := GameState.new_run(8)
	s.inventory.add("ammo", 7)
	var h: WeaponHandler = _rig(s)[0]
	var c := h.current()
	check_eq(c["id"], "handgun", "id")
	check_eq(c["name"], "Handgun", "name")
	check_eq([c["loaded"], c["capacity"], c["reserve"]], [9, 12, 7], "rounds")
	check_eq([c["ammo"], c["ammo_name"], c["mode"], c["slot"]], ["ammo", "9 mm rounds", "magazine", "primary"], "ammo and slot")
	check_eq([c["reloading"], c["reload_progress"]], [false, 0.0], "not reloading")
	s.unequip("primary")
	check_eq(h.current()["id"], "", "nothing in hand")
	check_eq(h.try_fire(Vector3.ZERO)["reason"], "no_weapon", "can't fire")
	check_eq(h.reload(), "No weapon.", "can't reload")
	s.equip("handgun")
	s.dead = true
	check_eq(h.try_fire(Vector3.ZERO)["reason"], "dead", "not when dead")


func test_magazines_survive_a_save_round_trip() -> void:
	var s := _with_shotgun(7)
	s.inventory.add("ammo", 4)
	var h: WeaponHandler = _rig(s)[0]
	h.try_fire(Vector3(0, 1, -5))
	h.tick(0.2)
	h.try_fire(Vector3(0, 1, -5))
	h.next()
	h.reload()
	h.tick(1.0)
	var t := GameState.from_dict(s.to_dict())
	var h2: WeaponHandler = _rig(t)[0]
	var c := h2.current()
	check_eq(c["id"], "shotgun", "the shotgun is still in hand")
	check_eq([c["loaded"], c["reserve"]], [2, 5], "two shells loaded, five in reserve")
	check_eq(t.magazine("handgun"), 7, "handgun magazine")
	check_eq(t.inventory.count("ammo"), 4, "9 mm reserve")
	check(not c["reloading"], "a reload in progress isn't saved")


func test_a_held_trigger_interrupts_only_when_the_next_shot_is_due() -> void:
	var s := _with_shotgun(6)
	s.set_magazine("shotgun", 3)
	s.set_active_weapon_slot("secondary")
	var h: WeaponHandler = _rig(s)[0]
	check(h.try_fire(Vector3(0, 1.3, -5))["ok"], "first blast")
	check_eq(h.reload(), "", "reload right away")
	h.tick(0.5)
	check_eq(s.magazine("shotgun"), 3, "a shell went in")
	var res := h.try_fire(Vector3(0, 1.3, -5))
	check_eq(res["reason"], "cooldown", "the pump isn't ready yet")
	check(h.is_reloading(), "so the reload goes on")
	h.tick(float(WeaponDefs.get_def("shotgun")["interval"]) - 0.5 + 0.01)
	check(h.try_fire(Vector3(0, 1.3, -5))["ok"], "now the trigger interrupts it and fires")
	check(not h.is_reloading(), "reload stopped")
	check_eq(s.magazine("shotgun"), 2, "one shell spent")
