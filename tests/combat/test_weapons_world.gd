extends "res://tests/test_case.gd"
## WeaponHandler against the real HouseWorld, VoxelPlayer and VoxelEnemy:
## pellets resolve through HouseWorld.shoot, the shotgun's range, and the
## weapon on the rig. The front yard (z 11.8) is clear from x -3.5 to 15.5.

const YARD_Z := 11.8


func _scene() -> Dictionary:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	var p := VoxelPlayer.new()
	p.input_enabled = false
	add(p)
	p.global_position = Vector3(-3.0, 0, YARD_Z)
	var s := GameState.new_run(21)
	s.inventory.add("shotgun", 1)
	s.inventory.add("shells", 10)
	s.set_magazine("shotgun", 5)
	var h := WeaponHandler.new()
	h.auto_tick = false
	h.rng.seed = 77
	add(h)
	h.setup(s, w, p)
	await physics_frames(2)
	return {"world": w, "player": p, "state": s, "handler": h}


func _psycho(sc: Dictionary, x: float) -> VoxelEnemy:
	var e := VoxelEnemy.new()
	e.setup(sc["world"].nav, sc["player"], 1)
	add(e)
	e.global_position = Vector3(x, 0, YARD_Z)
	e.set_physics_process(false)      # stands still
	return e


func _aim(sc: Dictionary, x: float) -> void:
	var p: VoxelPlayer = sc["player"]
	p.aim_point = Vector3(x, 1.0, YARD_Z)
	p.rig.rotation.y = atan2(-(x - p.global_position.x), 0.0)


func test_handgun_and_shotgun_hit_psychos_through_house_world() -> void:
	var sc: Dictionary = await _scene()
	var h: WeaponHandler = sc["handler"]
	var w: HouseWorld = sc["world"]
	var first := _psycho(sc, 5.0)        # 8 m
	await physics_frames(2)
	_aim(sc, 5.0)
	var shots0: int = w._shots
	var res := h.try_fire(Vector3(5.0, 1.0, YARD_Z))
	check(res["ok"] and res["hits"][0]["kind"] == "enemy", "handgun hit (%s)" % [res["hits"]])
	check_eq(first.hp, Tuning.ENEMY_HP - 1, "one damage")
	check_eq(w._shots - shots0, 1, "one HouseWorld.shoot")
	first.queue_free()
	var near := _psycho(sc, 0.0)         # 3 m: the 9 degree cone is 0.47 m across, the body 0.5 m
	await physics_frames(2)
	check_eq(h.switch_to("shotgun"), "", "shotgun")
	h.tick(WeaponHandler.SWITCH_DELAY)
	_aim(sc, 0.0)
	shots0 = w._shots
	res = h.try_fire(Vector3(0.0, 1.0, YARD_Z))
	var enemy_hits: int = res["hits"].filter(func(x): return x["kind"] == "enemy").size()
	var resolved: int = res["hits"].filter(func(x): return x["kind"] != "spent").size()
	check_eq(res["pellets"], 6, "six pellets")
	check_eq(w._shots - shots0, resolved, "every pellet that wasn't spent went through HouseWorld.shoot (%d)" % resolved)
	check(enemy_hits >= Tuning.ENEMY_HP, "at 3 m the pellets hit until it falls (%d)" % enemy_hits)
	check(not near.alive, "one blast at 3 m kills a psycho")
	check_eq(sc["state"].magazine("shotgun"), 4, "one shell")


func test_shotgun_pellets_are_spent_beyond_14_m() -> void:
	var sc: Dictionary = await _scene()
	var h: WeaponHandler = sc["handler"]
	var far := _psycho(sc, 15.0)        # 18 m
	await physics_frames(2)
	h.switch_to("shotgun")
	_aim(sc, 15.0)
	h.tick(WeaponHandler.SWITCH_DELAY)
	for i in 3:
		var res := h.try_fire(Vector3(15.0, 1.0, YARD_Z))
		check(res["ok"], "blast %d" % i)
		for x in res["hits"]:
			check((x["pos"] as Vector3).distance_to(Vector3(-3.0, Tuning.MUZZLE_HEIGHT, YARD_Z)) <= 14.0 + 1e-3, "no pellet lands beyond 14 m (%s)" % [x])
		h.tick(0.9)
		await physics_frames(1)
	check_eq(far.hp, Tuning.ENEMY_HP, "the psycho at 18 m is untouched by three blasts")
	h.switch_to("handgun")
	h.tick(WeaponHandler.SWITCH_DELAY)
	var res := h.try_fire(Vector3(15.0, 1.0, YARD_Z))
	check(res["hits"][0]["kind"] == "enemy", "the handgun reaches it (%s)" % [res["hits"]])
	check_eq(far.hp, Tuning.ENEMY_HP - 1, "one damage")


func test_the_weapon_in_hand_shows_on_the_rig() -> void:
	var sc: Dictionary = await _scene()
	var h: WeaponHandler = sc["handler"]
	var gun: Node3D = (sc["player"] as VoxelPlayer).rig.gun
	var pistol := gun.get_child(0) as Node3D
	check(pistol.visible, "the rig's pistol for the handgun")
	check(gun.get_node_or_null(WeaponHandler.MODEL_NAME) == null, "no shotgun model yet")
	h.switch_to("shotgun")
	var model := gun.get_node_or_null(WeaponHandler.MODEL_NAME) as Node3D
	check(model != null and model.visible, "shotgun placeholder attached to the gun node")
	check(not pistol.visible, "pistol hidden")
	var m := h._muzzle_global(WeaponDefs.get_def("shotgun"))
	check(m.distance_to((sc["player"] as VoxelPlayer).rig.muzzle_global()) > 0.4, "the shotgun's muzzle is further out")
	h.switch_to("handgun")
	check(pistol.visible and not model.visible, "back to the pistol")
	sc["state"].unequip("primary")
	sc["state"].unequip("secondary")
	h.tick(0.01)
	check(not pistol.visible and not model.visible, "nothing in hand, nothing shown")
