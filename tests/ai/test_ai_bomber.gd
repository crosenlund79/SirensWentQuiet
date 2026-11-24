extends "res://tests/test_case.gd"
## The suicide bomber on a real HouseWorld (SPEC-003 §5): it ignores a nearby
## player, goes for a weak point's outside face, fuses, detonates (a hole and
## a nav opening), hurts nearby enemies; killed early it fizzles or pops.

const Roster := preload("res://src/game/enemy_roster.gd")

var world: HouseWorld
var player: VoxelPlayer
var roster: Node3D
var events := []


func _setup(player_at: Vector2) -> void:
	world = HouseWorld.new()
	add(world)
	world.build_new()
	player = VoxelPlayer.new()
	player.input_enabled = false
	add(player)
	player.global_position = Vector3(player_at.x, 0, player_at.y)
	roster = Roster.new()
	roster.setup(world, player, 5)
	add(roster)
	roster.wall_swing.connect(func(e, t): world.enemy_strike(e.global_position, t))
	roster.fuse_started.connect(func(e, at, s): events.append({"ev": "fuse", "at": at, "s": s, "pos": e.global_position}))
	roster.detonated.connect(func(at, r, d): events.append({"ev": "blast", "at": at, "r": r, "d": d}))
	roster.enemy_died.connect(func(e, k, c): events.append({"ev": "died", "kind": k, "cause": c}))
	await physics_frames(2)


func _door(at: Vector2) -> WorldObject:
	for o in world.objects:
		if o.kind == "door" and o.pos.distance_to(at) < 0.1:
			return o
	return null


## Walkable length along `axis` through `p` (contiguous, on the wall line).
func _open_span(p: Vector2, axis: Vector2) -> float:
	var n := 0
	for side in [-1.0, 1.0]:
		var k := 0 if side < 0 else 1
		while k < 40 and world.nav.is_walkable(world.nav.cell_of(p + axis * side * k * GridNav.CELL)):
			n += 1
			k += 1
	return n * GridNav.CELL


func _ev(kind: String) -> Array:
	return events.filter(func(e): return e["ev"] == kind)


func _run_until(cond: Callable, secs: float) -> float:
	var t := 0.0
	while t < secs and not cond.call():
		await physics_frames(6)
		t += 0.1
	return t


func test_ai_bomber_ignores_the_player_and_blows_the_front_door() -> void:
	await _setup(Vector2(3.4, 11.4))
	var front := _door(Vector2(4.5, 9.0))
	var cell := world.nav.cell_of(Vector2(4.5, 9.0))
	check(front != null and not world.nav.is_walkable(cell), "the front door is closed")
	var solid_before := world.grid.solid_count
	var b: AIEnemy = roster.spawn_type("bomber", Vector2(2.6, 12.6))
	var bh = b.behaviour
	var acc := {"closest": INF, "player_swings": 0}
	var bref: WeakRef = weakref(b)
	var t := await _run_until(func():
		var bb = bref.get_ref()
		if bb != null and bb.alive:
			acc["closest"] = minf(acc["closest"], bb.plan_pos().distance_to(player.plan_pos()))
			acc["player_swings"] = bb.swings["player"]
		return not _ev("blast").is_empty() or bb == null, 20.0)
	var closest: float = acc["closest"]
	print("    bomber: target %s, fuse at %s after %.1f s, closest to the player %.2f m" % [bh.target.get("kind"), _ev("fuse")[0]["at"] if not _ev("fuse").is_empty() else "-", t, closest])
	check(closest < 1.5, "it passed close to the player (%.2f m)" % closest)
	check_eq(acc["player_swings"], 0, "never swung at the player")
	check_eq(bh.target.get("kind"), "door", "it chose the door (the best weak point)")
	var fuse := _ev("fuse")
	check(fuse.size() == 1, "one fuse")
	if fuse.is_empty():
		return
	check(is_equal_approx(fuse[0]["s"], 2.5), "a 2.5 s fuse")
	var fp: Vector3 = fuse[0]["pos"]
	check(Vector2(fp.x, fp.z).distance_to(Vector2(4.5, 9.6)) < 0.5, "lit at the door's outside face (%s)" % fp)
	var blast := _ev("blast")
	check(blast.size() == 1, "detonated")
	if blast.is_empty():
		return
	check(is_equal_approx(blast[0]["r"], 4.0) and is_equal_approx(blast[0]["d"], 60.0), "detonated(at, 4 m, 60) on Normal")
	check(bref.get_ref() == null or not bref.get_ref().alive, "the bomber is gone")
	check(_door(Vector2(4.5, 9.0)) == null, "the door was destroyed")
	check(world.grid.solid_count < solid_before - 50, "voxels blown out (%d)" % (solid_before - world.grid.solid_count))
	check(world.nav.is_walkable(cell), "the doorway is open for navigation")
	var span := _open_span(Vector2(4.5, 9.0), Vector2(1, 0))
	check(span >= 1.5, "a breach wider than the 1 m doorway (%.2f m walkable)" % span)
	check_eq(roster.blasts, 1, "the roster saw the blast")


## The first weak point a bomber at `from` may use (same filters as its pick).
func _first_usable(from: Vector2) -> Dictionary:
	var B := load("res://src/ai/bomber_behaviour.gd")
	for p in world.weak_points(from):
		var t: Dictionary = B.describe(world, p)
		if not t.is_empty():
			return t
	return {}


## With both doors open (no door is a defence any more) and the player right
## beside it, the bomber still walks to a wall and blows a hole in it, while a
## psycho from the same spot goes for the player through the open door.
func test_ai_bomber_goes_for_a_wall_not_the_player_unlike_a_psycho() -> void:
	await _setup(Vector2(9.2, 11.0))
	for o in world.objects:
		if o.kind == "door":
			world.set_door_open(o, true)
	# Weaken one south-wall section with a few shots (a "weak wall").
	var seg := Vector3i(0, 9, 9)
	for k in 8:
		var from := Vector3(9.5, Tuning.MUZZLE_HEIGHT, 11.5)
		world.shoot(from, Vector3(9.2 + 0.1 * k, 0.6 + 0.12 * k, 9.0) - from, [])
	await physics_frames(2)
	var integ := world.section_integrity(seg)
	check(integ < 1.0, "the section is damaged (%.2f)" % integ)
	var spawn_at := Vector2(8.4, 12.8)
	var expect := _first_usable(spawn_at)
	check_eq(expect.get("kind"), "wall", "with the doors open the best usable weak point is a wall")
	var psycho: AIEnemy = roster.spawn_type("psycho", spawn_at + Vector2(-1.5, 0.0))
	var b: AIEnemy = roster.spawn_type("bomber", spawn_at)
	var bref: WeakRef = weakref(b)
	var pref: WeakRef = weakref(psycho)
	var acc := {"closest": INF, "bomber_swings": 0, "psycho_player_swings": 0, "psycho_wall_swings": 0}
	var t := await _run_until(func():
		var bb = bref.get_ref()
		if bb != null and bb.alive:
			acc["closest"] = minf(acc["closest"], bb.plan_pos().distance_to(player.plan_pos()))
			acc["bomber_swings"] = bb.swings["player"] + bb.swings["wall"]
		var pp = pref.get_ref()
		if pp != null and pp.alive:
			acc["psycho_player_swings"] = pp.swings["player"]
			acc["psycho_wall_swings"] = pp.swings["wall"]
		return not _ev("blast").is_empty() or bb == null, 25.0)
	var target: Dictionary = b.behaviour.target if is_instance_valid(b) else {}
	print("    bomber blew %s after %.1f s; closest to the player %.2f m; psycho swings at the player %d, at walls %d" % [
		expect.get("seg"), t, acc["closest"], acc["psycho_player_swings"], acc["psycho_wall_swings"]])
	check(acc["closest"] < 2.5, "the bomber came near the player (%.2f m)" % acc["closest"])
	check_eq(acc["bomber_swings"], 0, "the bomber never swung")
	check(acc["psycho_player_swings"] >= 1, "the psycho attacked the player")
	var fuse := _ev("fuse")
	check(fuse.size() == 1, "a fuse was lit")
	if fuse.is_empty():
		return
	var ep: Vector2 = expect["approach"]
	var fp: Vector3 = fuse[0]["pos"]
	check(Vector2(fp.x, fp.z).distance_to(ep) < 0.6, "at the chosen wall's outside face %s (%s)" % [ep, fp])
	check(not _ev("blast").is_empty(), "detonated")
	var s2: Vector3i = expect["seg"]
	check(world.section_integrity(s2) < 0.5, "the wall section is blown out (%.2f)" % world.section_integrity(s2))
	var line := HouseWorld.seg_center(s2)
	var span := _open_span(line, Vector2(1, 0) if s2.x == 0 else Vector2(0, 1))
	check(span >= 1.0, "a walkable hole in the wall (%.2f m)" % span)
	var inside := line - (expect["normal"] as Vector2) * 1.0
	var path := world.nav.find_path(ep + (expect["normal"] as Vector2), inside)
	var bash := 0
	for p in path:
		if not world.nav.is_walkable(world.nav.cell_of(p)):
			bash += 1
	check(not path.is_empty() and bash == 0, "nav: a walk-only path through the hole (%d bash cells)" % bash)


func test_ai_bomber_killed_before_the_fuse_fizzles() -> void:
	await _setup(Vector2(4.5, 12.5))
	var solid := world.grid.solid_count
	var b: AIEnemy = roster.spawn_type("bomber", Vector2(2.0, 13.8))
	await physics_frames(20)
	check_eq(b.state_name(), "seek", "still seeking its target")
	b.take_hit(Vector3.FORWARD)
	b.take_hit(Vector3.FORWARD)
	check(not b.alive, "two shots kill it on Normal")
	await physics_frames(30)
	check(_ev("blast").is_empty(), "no blast")
	var died := _ev("died")
	check(died.size() == 1 and died[0]["cause"] == "shot", "died, shot (%s)" % [died])
	check_eq(world.grid.solid_count, solid, "the house is untouched")
	check(_door(Vector2(4.5, 9.0)) != null and _door(Vector2(4.5, 9.0)).hp == _door(Vector2(4.5, 9.0)).max_hp, "the door is untouched")


func test_ai_bomber_killed_during_the_fuse_only_pops() -> void:
	await _setup(Vector2(4.5, 12.5))
	var front := _door(Vector2(4.5, 9.0))
	var solid := world.grid.solid_count
	var b: AIEnemy = roster.spawn_type("bomber", Vector2(3.0, 11.5))
	var t := await _run_until(func(): return not _ev("fuse").is_empty(), 15.0)
	check(not _ev("fuse").is_empty(), "fuse lit (%.1f s)" % t)
	var bystander: AIEnemy = roster.spawn_type("psycho", Vector2(5.4, 10.3))
	await physics_frames(30)                 # 0.5 s into the 2.5 s fuse
	b.take_hit(Vector3.FORWARD)
	b.take_hit(Vector3.FORWARD)
	await physics_frames(10)
	var blasts := _ev("blast")
	check(blasts.size() == 1, "one small pop")
	if blasts.is_empty():
		return
	check(is_equal_approx(blasts[0]["r"], 1.6) and is_equal_approx(blasts[0]["d"], 15.0), "small: 1.6 m, 15 damage (%s)" % [blasts[0]])
	await physics_frames(200)                # past the fuse's end: nothing more
	check_eq(_ev("blast").size(), 1, "no full blast later")
	check_eq(world.grid.solid_count, solid, "no structural damage")
	check(is_instance_valid(front) and front.hp == front.max_hp, "the door is intact")
	check(is_instance_valid(bystander), "the bystander exists")


func test_ai_bomber_blast_hurts_nearby_enemies() -> void:
	await _setup(Vector2(4.5, 13.0))
	roster.spawn_type("bomber", Vector2(3.0, 11.5))
	var near: AIEnemy = null
	var far: AIEnemy = null
	var t := 0.0
	while t < 15.0 and _ev("fuse").is_empty():
		await physics_frames(6)
		t += 0.1
	check(not _ev("fuse").is_empty(), "fuse lit")
	near = roster.spawn_type("brute", Vector2(5.6, 10.6))
	far = roster.spawn_type("psycho", Vector2(12.0, 13.5))
	var near_hp := near.hp
	await _run_until(func(): return not _ev("blast").is_empty(), 5.0)
	check(not _ev("blast").is_empty(), "detonated")
	check(near.hp < near_hp, "the brute near the blast was hurt (%d -> %d)" % [near_hp, near.hp])
	check(far.alive and far.hp == far.max_hp, "the far psycho was not")


## Its target is destroyed on the way (here: the door is broken down by
## something else): it picks another weak point and still blows it.
func test_ai_bomber_repicks_when_its_target_is_gone() -> void:
	await _setup(Vector2(9.0, 13.5))
	var b: AIEnemy = roster.spawn_type("bomber", Vector2(2.4, 13.2))
	await physics_frames(20)
	var first: Dictionary = b.behaviour.target.duplicate()
	check_eq(first.get("kind"), "door", "it went for the front door first")
	var door := _door(Vector2(4.5, 9.0))
	world.damage_object(door, 100)
	await physics_frames(2)
	check(_door(Vector2(4.5, 9.0)) == null, "the door is gone")
	var bref: WeakRef = weakref(b)
	await _run_until(func(): return not _ev("blast").is_empty() or bref.get_ref() == null, 30.0)
	var fuse := _ev("fuse")
	check(fuse.size() == 1, "one fuse, at the new target")
	if fuse.is_empty():
		return
	var at: Vector3 = fuse[0]["at"]
	check(Vector2(at.x, at.z).distance_to(Vector2(4.5, 9.0)) > 0.8, "not at the broken doorway (%s)" % at)
	check_eq(_ev("blast").size(), 1, "and blew it")
