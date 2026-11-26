extends "res://tests/test_case.gd"
## Exp 011: the voxel people. Every psycho person builds (one variation each;
## the others share the code paths), animates idle / walk / run / attack /
## hit / collapse without errors, the factory and the cache behave, and an
## enemy spawned in the game wears the new rig with a stable appearance.

const Roster := preload("res://src/game/enemy_roster.gd")


func test_every_person_builds() -> void:
	var a := HumanoidLooks.archetype("psycho")
	check(a != null and HumanoidLooks.variety("psycho") >= 24, "the psycho archetype has its looks")
	var names := {}
	for i in a.variety():
		var l := HumanoidLooks.look("psycho", i)
		check(str(l["key"]) == "psycho/%d" % i, "look %d has its key" % i)
		names[str(l["name"])] = true
		check(l.has("body") and l.has("outfit") and l.has("face") and l.has("hair") and l.has("style"), "look %d is complete" % i)
	check(names.size() == a.variety(), "every look has its own name")
	check_eq(HumanoidLooks.look("psycho", 3 + a.variety() * 5), HumanoidLooks.look("psycho", 3), "a seed maps to a stable look")
	var shapes := {}
	for i in 10:
		var l := HumanoidLooks.look("psycho", i)
		var m := HumanoidSculpt.meshes(l, HumanoidRig.enemy_material())
		check(m.size() == HumanoidSculpt.PARTS.size(), "%s: every part" % l["name"])
		for p in m:
			check((m[p] as ArrayMesh).get_surface_count() == 1, "%s: %s has a mesh" % [l["name"], p])
		var st: Dictionary = HumanoidSculpt.stats[l["key"]]
		check(int(st["verts"]) > 20000, "%s: a detailed figure (%d vertices)" % [l["name"], st["verts"]])
		print("    %s: %d vertices, %.0f ms" % [l["name"], st["verts"], st["ms"]])
		# genuinely different bodies: the head and chest meshes differ in size
		var aabb := (m["chest"] as ArrayMesh).get_aabb().size + (m["head"] as ArrayMesh).get_aabb().size * 10.0
		shapes[str(aabb.snapped(Vector3.ONE * 0.01))] = true
	check(shapes.size() >= 8, "the people have different builds and heads (%d distinct)" % shapes.size())


func test_rig_animates_every_state() -> void:
	for i in [0, 4, 5, 7]:
		var r: HumanoidRig = add(HumanoidLooks.make_rig("psycho", i))
		await frames(1)
		check(r.parts.size() == HumanoidSculpt.PARTS.size(), "one mesh per bone")
		check(r.torso != null and r.head != null and r.arm_l != null and r.arm_r != null and r.leg_l != null and r.leg_r != null,
			"the VoxelRig members the AI and dormant poses use")
		for sp in [0.0, 1.2, 1.85, 3.3]:
			r.speed = sp
			for f in 20:
				r.animate(1.0 / 30.0)
		r.speed = 0.0
		r.swing = 1.0
		for f in 16:
			r.swing = maxf(r.swing - 1.0 / 15.0, 0.0)
			r.animate(1.0 / 30.0)
		r.stagger = 1.0
		r.set_flash(1.0)
		for f in 12:
			r.animate(1.0 / 30.0)
		r.rotation.y = 0.0
		for f in 10:
			r.rotation.y += 0.25          # turning on the spot
			r.animate(1.0 / 30.0)
		for f in 40:
			r.collapse(1.0 / 30.0, f / 30.0, Vector3.RIGHT, 0.3)
		check(r.dead, "collapsed")
		check(r.head.global_position.y < 0.6, "lying on the ground (head at %.2f m)" % r.head.global_position.y)
		r.set_fade(0.5)


func test_cache_is_bounded() -> void:
	var before := HumanoidSculpt._lru.size()
	check(before <= HumanoidSculpt.CACHE_MAX, "never more than %d looks cached" % HumanoidSculpt.CACHE_MAX)
	var l := HumanoidLooks.look("psycho", 1)
	var a := HumanoidSculpt.meshes(l, HumanoidRig.enemy_material())
	var b := HumanoidSculpt.meshes(l, HumanoidRig.enemy_material())
	check(a["head"] == b["head"], "the same look shares its meshes")
	check(HumanoidLooks.make_rig("runner", 3) is VoxelRig, "kinds without an archetype keep a VoxelRig figure")


func test_game_enemy_wears_the_new_rig() -> void:
	var world := HouseWorld.new()
	add(world)
	world.build_new()
	var player := VoxelPlayer.new()
	player.input_enabled = false
	add(player)
	player.global_position = Vector3(6, 0, 14)
	var roster: Node3D = Roster.new()
	roster.setup(world, player, 5)
	add(roster)
	await physics_frames(2)
	var e: AIEnemy = roster.spawn_type("psycho", Vector2(6, 11), {"appearance": 7, "mode": "hidden"})
	await physics_frames(2)
	check(e.rig is HumanoidRig, "a psycho in the game is a voxel person")
	check(e.appearance == 7 and str((e.rig as HumanoidRig).look_data["key"]) == "psycho/7", "with its appearance")
	var f: AIEnemy = roster.spawn_type("psycho", Vector2(5, 11))
	check(f.appearance >= 0, "a random appearance by default")
	e.provoke("test")
	for i in 30:
		await physics_frames(1)
	e.take_damage(1, Vector3.FORWARD)
	await physics_frames(5)
	e.kill_quietly()
	for i in 40:
		await physics_frames(1)
	check((e.rig as HumanoidRig).dead, "it collapses")


func test_background_builds_are_adopted_or_cancelled() -> void:
	var host: Node3D = add(Node3D.new())
	HumanoidSculpt.clear_cache()
	HumanoidLooks.warm("psycho", host, 2)
	check(host.get_node_or_null("HumanoidWarmer") != null, "a warmer adopts the builds")
	var key := str(HumanoidLooks.look("psycho", 0)["key"])
	var t0 := Time.get_ticks_msec()
	while not HumanoidSculpt.is_cached(key) and Time.get_ticks_msec() - t0 < 30000:
		await frames(1)                 # real time: the build runs on a worker thread
	check(HumanoidSculpt.is_cached(key), "a look built in the background is adopted")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var s := HumanoidLooks.pick_seed("psycho", rng)
	check(s >= 0, "a seed")
	HumanoidLooks.warm("psycho", host, 12)
	host.free()                         # leaving the tree cancels and waits
	check(HumanoidSculpt._bg.is_empty(), "nothing left building")
