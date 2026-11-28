extends "res://tests/test_case.gd"
## Experiment 013: the essential gunplay checks (the real game scene): every
## gun fires from its muzzle along a level line, the shotgun fires 8 pellets,
## the long guns work a pump / bolt that ejects the case, RMB aiming tightens
## the spread, recoil reaches the rig.

const SCENE := "res://src/game/game.tscn"


func _boot() -> Node:
	GameLaunch.mode = "new"
	GameLaunch.seed = 1313
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	return g


func cleanup() -> void:
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	WeaponHandler.debug_traces = false
	await super.cleanup()


func test_every_gun_fires_from_its_muzzle() -> void:
	var g: Node = await _boot()
	var w: WeaponHandler = g.combat.weapons
	g.debug_kill_enemies()
	g.debug_teleport_player(Vector2(8.0, 11.5))      # the front yard, clear to the east
	WeaponHandler.debug_traces = true
	for id in ["handgun", "shotgun", "rifle"]:
		var said: String = g.dev.dev_give_weapon(id)
		await physics_frames(20)
		check_eq(w.current_id(), id, "%s in hand (%s)" % [id, said])
		var aim: Vector3 = g.player.global_position + Vector3(0.0, 0.2, 6.0)      # a point low on the floor ahead (south, down the open road)
		var r: Dictionary = w.try_fire(aim)
		if not check(r.get("ok", false), "%s fires (%s)" % [id, r.get("reason", "")]):
			continue
		var sh := w.last_shot
		var m: Vector3 = sh["muzzle"]
		var d: Vector3 = sh["dir"]
		check(absf(d.y) < 1e-4, "%s: the shot flies level, not into the floor at the cursor" % id)
		var o: Vector3 = sh["origin"]
		var back := (m - o)
		check(back.length() < 0.01 or back.normalized().dot(d) > 0.999, "%s: the ray runs through the muzzle (origin on the muzzle line)" % id)
		var want := Vector3(aim.x - m.x, 0, aim.z - m.z).normalized()
		check(d.dot(want) > 0.999, "%s: towards the aim from the muzzle" % id)
		var far := 0.0
		for h in r["hits"]:
			far = maxf(far, o.distance_to(h["pos"]))
		print("    %s: %d pellet(s), farthest %.1f m, kinds %s" % [id, r["hits"].size(), far, r["hits"].map(func(h): return h["kind"])])
		check(far > 14.0, "%s: no short range (%.1f m)" % [id, far])
		check(float(g.player.rig.get("recoil")) > 0.5, "%s: recoil reached the rig" % id)
		if id == "shotgun":
			check_eq(r["pellets"], 8, "the shotgun fires 8 pellets")
			var spread := 0.0
			for pd in sh["dirs"]:
				spread = maxf(spread, rad_to_deg((pd as Vector3).angle_to(d)))
			check(spread > 1.0, "the pellets spread (%.1f deg)" % spread)
		if id != "handgun":
			check(w.cycling(), "%s: the pump / bolt is pending after the shot" % id)
			await physics_frames(50)
			check(not w.cycling(), "%s: the cycle completes" % id)
		await physics_frames(int(WeaponDefs.get_def(id)["interval"] * 60) + 5)


func test_ads_tightens_the_spread() -> void:
	var g: Node = await _boot()
	var w: WeaponHandler = g.combat.weapons
	g.debug_kill_enemies()
	g.debug_teleport_player(Vector2(8.0, 11.5))
	g.dev.dev_give_weapon("rifle")
	await physics_frames(20)
	Input.action_press("secondary")                  # the game sets ads from RMB each frame
	await physics_frames(20)
	check(w.ads, "RMB held: aiming down the sights")
	check(float(g.player.rig.get("ads")) > 0.9, "the rig raises the rifle while aiming")
	var aim: Vector3 = g.player.global_position + Vector3(8.0, 0.0, 0.0)
	var worst_ads := 0.0
	for i in 4:
		w.try_fire(aim)
		worst_ads = maxf(worst_ads, rad_to_deg((w.last_shot["dirs"][0] as Vector3).angle_to(w.last_shot["dir"])))
		await physics_frames(75)
	Input.action_release("secondary")
	await physics_frames(20)
	check(not w.ads, "RMB released")
	check(float(g.player.rig.get("ads")) < 0.1, "released: the rig lowers it again")
	check(worst_ads <= WeaponDefs.get_def("rifle")["spread_ads"] * 0.5 + 0.01, "aimed shots stay within the ADS cone (%.2f deg)" % worst_ads)
