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


## Exp 011 (R): the runners and the bombers: every look builds, distinct,
## within the psychos' budget; the bomber carries its pack and light; every
## state animates and collapses without errors (a dormant pose too).
func test_runners_and_bombers() -> void:
	for kind in ["runner", "bomber"]:
		var a := HumanoidLooks.archetype(kind)
		check(a != null and a.variety() >= 4, "%s: an archetype with its looks" % kind)
		var shapes := {}
		for i in a.variety():
			var l := HumanoidLooks.look(kind, i)
			var m := HumanoidSculpt.meshes(l, HumanoidRig.enemy_material())
			check(m.size() == HumanoidSculpt.PARTS.size(), "%s: every part" % l["name"])
			var st: Dictionary = HumanoidSculpt.stats[l["key"]]
			check(int(st["verts"]) > 20000 and int(st["verts"]) < 130000, "%s: %d vertices" % [l["name"], st["verts"]])
			print("    %s / %s: %d vertices, %.0f ms" % [kind, l["name"], st["verts"], st["ms"]])
			var aabb := (m["chest"] as ArrayMesh).get_aabb().size + (m["head"] as ArrayMesh).get_aabb().size * 10.0
			shapes[str(aabb.snapped(Vector3.ONE * 0.01))] = true
		check(shapes.size() == a.variety(), "%s: every look has its own build" % kind)
	# the runner is thin: its upper arms and thighs are narrower than any psycho's
	var thin := HumanoidBody.derive(HumanoidLooks.look("runner", 1)["body"])
	var lean := HumanoidBody.derive(HumanoidLooks.look("psycho", 8)["body"])
	check(float(thin["arm_r0"]) < float(lean["arm_r0"]) * 0.75 and float(thin["thigh_r0"]) < float(lean["thigh_r0"]) * 0.75,
		"a runner is starved thin")
	for kind in ["runner", "bomber"]:
		for i in [0, 1]:
			var r: HumanoidRig = add(HumanoidLooks.make_rig(kind, i))
			await frames(1)
			var ex: Dictionary = HumanoidLooks.archetype(kind).extras(r)
			if kind == "bomber":
				check(ex.get("pack") is Node3D and ex.get("pack_mat") is StandardMaterial3D and ex.get("light") is OmniLight3D,
					"the bomber carries the pack, its glow and its light")
				check((ex["pack"] as Node3D).get_parent() == r.torso, "the pack sits on the torso")
				(ex["light"] as OmniLight3D).light_energy = 3.0         # the fuse: hunched and shaking
			for sp in [0.0, 1.2, 3.3]:
				r.speed = sp
				for f in 20:
					r.animate(1.0 / 30.0)
			r.speed = 0.0
			r.swing = 1.0
			for f in 16:
				r.swing = maxf(r.swing - 1.0 / 15.0, 0.0)
				r.animate(1.0 / 30.0)
			r.stagger = 1.0
			for f in 12:
				r.animate(1.0 / 30.0)
			var e := AIEnemy.new()
			e.rig = r
			var dm := DormantMind.new()
			dm.state = "bang"
			for f in 10:
				r.animate(1.0 / 30.0)
				dm.pose(e, 1.0 / 30.0)
			e.free()
			for f in 40:
				r.collapse(1.0 / 30.0, f / 30.0, Vector3.RIGHT, 0.3)
			check(r.dead and r.head.global_position.y < 0.6, "%s %d collapses to the ground (head at %.2f m)" % [kind, i, r.head.global_position.y])


# --- Exp 011: the brute ------------------------------------------------------------------

## Highest point of a figure's body meshes (global; the club and held items excluded).
static func _extent(r: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in r.find_children("*", "MeshInstance3D", true, false):
		var nm := str(mi.get_parent().name)
		if nm == "Club" or nm == "Held" or nm == "gun" or mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


func test_brute_builds_big_and_distinct() -> void:
	var a := HumanoidLooks.archetype("brute")
	check(a != null and a.variety() >= 6, "the brute archetype has its looks")
	var eli: EliRig = add(EliRig.new(0))
	await frames(1)
	var eli_box := _extent(eli)
	var eli_head := (eli.head.get_child(0) as MeshInstance3D).mesh.get_aabb().size.y / eli_box.end.y
	var shapes := {}
	for i in 4:
		var r: HumanoidRig = add(HumanoidLooks.make_rig("brute", i))
		await frames(1)
		var l: Dictionary = r.look_data
		var st: Dictionary = HumanoidSculpt.stats[l["key"]]
		print("    %s: %d vertices, %.0f ms" % [l["name"], st["verts"], st["ms"]])
		check(int(st["verts"]) < 170000, "%s: within the vertex budget (%d)" % [l["name"], st["verts"]])
		# standing straight (rest pose): height and breadth against Eli's
		for n: Node3D in r.find_children("*", "Node3D", true, false):
			if n.name != "Mesh":
				n.rotation = Vector3.ZERO
		r.pelvis.position = Vector3(0.0, float(r.body["pelvis_y"]), 0.0)
		var box := _extent(r)
		check(box.end.y >= 1.3 * eli_box.end.y, "%s: at least 1.3 x Eli's height (%.2f m vs %.2f m)" % [l["name"], box.end.y, eli_box.end.y])
		check(box.size.x >= 1.6 * eli_box.size.x, "%s: much broader than Eli (%.2f m vs %.2f m)" % [l["name"], box.size.x, eli_box.size.x])
		shapes[str((box.size + (r.head.get_child(0) as MeshInstance3D).mesh.get_aabb().size * 10.0).snapped(Vector3.ONE * 0.01))] = true
		# a small head for the body
		var head_h := (r.head.get_child(0) as MeshInstance3D).mesh.get_aabb().size.y * r.scale.y
		check(head_h / box.end.y < eli_head * 0.92, "%s: a head small for the body (%.3f of his height, Eli %.3f)" % [l["name"], head_h / box.end.y, eli_head])
		r.queue_free()
	check(shapes.size() == 4, "four distinct people (%d)" % shapes.size())


func test_brute_club_and_animation() -> void:
	var host: Node3D = add(Node3D.new())
	var r: HumanoidRig = HumanoidLooks.make_rig("brute", 2)
	host.add_child(r)
	var ex := HumanoidLooks.archetype("brute").extras(r)
	check(ex.get("club") is Node3D and (ex["club"] as Node3D).get_parent() == r.hand_r, "the club is in his right hand")
	check(r.parts.size() == HumanoidSculpt.PARTS.size() + 1, "body parts and the club flash and fade together")
	await frames(1)
	for sp in [0.0, 1.25, 3.3]:
		r.speed = sp
		for f in 20:
			r.animate(1.0 / 30.0)
	r.speed = 0.0
	var hand_y := []
	r.swing = 1.0
	for f in 21:
		r.swing = maxf(r.swing - 1.0 / 21.0, 0.0)          # the game's 0.7 s swing
		r.animate(1.0 / 30.0)
		hand_y.append(r.hand_r.global_position.y)
	check(hand_y.max() > r.head.global_position.y, "the overhead blow raises the club above his head")
	check(hand_y[hand_y.size() - 1] < hand_y.max() - 0.8, "and brings it down")
	var chest := r.torso.global_rotation
	r.stagger = 1.0
	r.animate(1.0 / 60.0)
	check(absf(r.torso.global_rotation.x - chest.x) < 0.3, "a hit barely rocks him")
	for f in 12:
		r.animate(1.0 / 30.0)
	for f in 45:
		r.collapse(1.0 / 30.0, f / 30.0, Vector3.RIGHT, 0.3)
		if f == 15:
			check(r.pelvis.global_position.y < float(r.body["pelvis_y"]) * r.scale.y * 0.75, "first down on his knees")
	check(r.dead, "collapsed")
	check(r.head.global_position.y < 0.6, "lying on the ground (head at %.2f m)" % r.head.global_position.y)
	var club: Node3D = ex["club"]
	check(club.get_parent() == host and club.global_position.y < 0.3, "the club dropped beside him")
	# the showroom replays the collapse: the club goes back into his hand
	r.dead = false
	r.animate(1.0 / 30.0)
	check(club.get_parent() == r.hand_r, "the club back in his hand")
	# dormant poses still apply on top
	var m := DormantMind.new()
	var e := AIEnemy.new()
	e.rig = r
	for st in ["bang", "tap", "sway", "stare"]:
		m.state = st
		r.animate(1.0 / 30.0)
		m.pose(e, 1.0 / 30.0)
	e.free()


func test_brute_ducks_under_a_lintel_in_the_game() -> void:
	var world := HouseWorld.new()
	add(world)
	world.build_new()
	var player := VoxelPlayer.new()
	player.input_enabled = false
	add(player)
	player.global_position = Vector3(2.5, 0, 7.5)
	var roster: Node3D = Roster.new()
	roster.setup(world, player, 5)
	add(roster)
	await physics_frames(2)
	var e: AIEnemy = roster.spawn_type("brute", Vector2(2.5, 4.0), {"appearance": 1, "mode": "hidden"})   # the bedroom doorway
	var f: AIEnemy = roster.spawn_type("brute", Vector2(2.5, 6.5), {"appearance": 3, "mode": "hidden"})   # the open living room
	await physics_frames(2)
	check(e.rig is HumanoidRig and e.extras.get("club") is Node3D, "a brute in the game is a voxel person with his club")
	check(is_equal_approx(float(e.def["radius"]), 0.29), "collision radius unchanged")
	e.set_facing(PI)
	f.set_facing(PI)
	for i in 40:
		await physics_frames(1)
	check(float(e.rig.get("duck")) > 0.6, "he ducks in a doorway (%.2f)" % float(e.rig.get("duck")))
	check(float(f.rig.get("duck")) < 0.05, "not in the open (%.2f)" % float(f.rig.get("duck")))
	e.kill_quietly()
	for i in 45:
		await physics_frames(1)
	check((e.rig as HumanoidRig).dead, "it collapses")
