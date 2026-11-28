extends "res://tests/test_case.gd"
## Exp 012 (G): whole-group hordes and coordinated sieges (ASSIGNMENT §9-10).
## A wave exists all at once and a kill spawns nobody; its start points are
## out of view; a siege splits into groups with tactics and goals; an enemy
## barricade goes up in a doorway (the trap's worker) and can be destroyed;
## eligibility follows the story state.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_e12_siege.dat"
const Director := preload("res://src/game/invasion_director.gd")
const ELI := Vector2(6.5, 7.8)


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()


func _boot() -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = "new"
	GameLaunch.seed = 4242
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	return g


## Out of view, or deep in the fog bank and far from Eli (the director's rule).
func _hidden(at: Vector2, view: Callable) -> bool:
	if not view.call(at):
		return true
	return not FogBoundary.LOT.grow(Director.FOG_DEEP - 0.35).has_point(at) and at.distance_to(ELI) >= Director.HIDDEN_IN_FOG - 0.5


func _wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await frames(1)
	return cond.call()


func test_e12_wave_exists_at_once_and_a_kill_spawns_nobody() -> void:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	var p := VoxelPlayer.new()
	p.input_enabled = false
	add(p)
	p.global_position = Vector3(ELI.x, 0, ELI.y)
	var roster: Node3D = load("res://src/game/enemy_roster.gd").new()
	roster.setup(w, p, 3)
	add(roster)
	await physics_frames(2)
	var d := Director.new()
	d.nav = w.nav
	d.view_check = func(q: Vector2) -> bool: return q.distance_to(ELI) < 15.0 and q.y > 2.0     # a pretend camera
	d.begin_wave("normal", 6, 11)
	var kinds := d.tick_kinds(0.1)
	check_eq(kinds, d.wave, "the first tick releases the whole wave")
	check(d.all_spawned() and d.remaining_to_spawn() == 0, "nobody left to come later")
	for k in kinds:
		d.note_spawned(roster.spawn_type(k, d.pick_spawn(ELI), d.spawn_opts(k)))
	check_eq(roster.invaders_alive(), d.total, "every member exists from the start (%d)" % d.total)
	var sides := {}
	for e in d.plan:
		sides[e["side"]] = true
		var at: Vector2 = e["pos"]
		check(at.distance_to(ELI) >= Director.MIN_SPAWN_DISTANCE - 0.5, "away from Eli (%s)" % at)
		check(not HousePlan.FOOTPRINT.grow(1.0).has_point(at), "not in the house (%s)" % at)
		check(e["hidden"] and _hidden(at, d.view_check), "out of view or deep in the fog far off (%s, %s)" % [at, e["zone"]])
	check(sides.size() >= 2, "from several sides (%s)" % [sides.keys()])
	var dists := d.plan.map(func(e): return (e["pos"] as Vector2).distance_to(ELI))
	check(dists.max() - dists.min() > 3.0, "at varied distances (%s)" % [dists])
	check(not d.released.is_empty(), "some wait a moment before they set off")
	var waiting: AIEnemy = d.released[0]["enemy"]
	check(waiting.has_goal() and waiting.directed_why == "wait", "a waiting member holds its spot")
	var victim: AIEnemy = roster.enemies[0]
	victim.kill_quietly()
	var before: int = roster.enemies.size()
	var later := []
	for i in 300:
		later.append_array(d.tick_kinds(0.1))
	check_eq(later, [], "no one released after the start")
	await physics_frames(2)
	check_eq(roster.invaders_alive(), d.total - 1, "a kill spawned nobody")
	check(roster.enemies.size() <= before, "no new bodies")
	check(d.released.is_empty() and not waiting.has_goal(), "the start delays ran out: everyone on the move")
	roster.kill_all()


func test_e12_siege_groups_tactics_goals_and_story() -> void:
	var g := await _boot()
	var siege: SiegeDirector = g.siege
	if not check(siege != null, "the game has a siege helper at home"):
		return
	var s: GameState = g.debug_state()
	# eligibility: no story -> no siege; the documented keys (or StoryState)
	check(not SiegeStory.eligible(s), "a fresh run is not siege-eligible")
	var ss: Variant = SiegeStory.story_state()
	if ss == null:
		# without agent S's StoryState: the documented keys, read defensively
		s.set_meta("story", {"ch1": {"done": [1, 2, 3], "next": 4, "siege_at": -1.0, "sieges": 0}})
		check(not SiegeStory.eligible(s) and SiegeStory.introduced(s), "before Encounter 4: no siege (introduced)")
		SiegeStory.ch1(s)["done"] = [1, 2, 3, 4]
		SiegeStory.ch1(s)["siege_at"] = s.total_minutes + 60.0
		check(not SiegeStory.eligible(s), "Encounter 4 done, the delay not over yet")
		s.total_minutes += 61.0
	else:
		# StoryState (agent S): Encounter 4 schedules the first siege after a delay
		ss.complete(s, 4)
		check(not SiegeStory.eligible(s) and SiegeStory.introduced(s), "Encounter 4 done, the delay not over yet")
		ss.make_siege_eligible_now(s)
	check(SiegeStory.eligible(s), "eligible after the delay")
	g.dev_trigger_invasion()
	check(siege.active and siege.counted, "the invasion slot became an organised siege")
	check_eq(SiegeStory.sieges(s), 1, "the siege was noted in the story state")
	check(not SiegeStory.eligible(s), "and the next waits")
	check_eq(g.last_toast, SiegeDirector.BANNER, "the organised banner")
	if not check(siege.active, "a siege runs"):
		return
	check(await _wait_until(func(): return not siege._pending, 30), "all members joined their groups")
	if SiegeStory.introduced(s):
		var w: Node = g.get_node_or_null("SiegeWatcher")
		check(w != null and not w in g.debug_roster().enemies, "he watches from the fog: a figure, not an attacker")
		if w != null:
			var wp := Vector2(w.global_position.x, w.global_position.z)
			check(not FogBoundary.LOT.has_point(wp), "out in the fog (%s)" % wp)
	var d = g.debug_director()
	check(d.all_spawned() and g.debug_roster().invaders_alive() == d.total, "the whole siege exists at once (%d)" % d.total)
	check(siege.groups.size() >= 3, "3-4 approach groups (%d)" % siege.groups.size())
	var sides := {}
	var roles := {}
	for gr in siege.groups:
		sides[gr["side"]] = true
		roles[gr["role"]] = true
	check_eq(sides.size(), siege.groups.size(), "each group on its own side")
	check(roles.has("breach") and roles.has("pressure") and roles.has("contain"), "breach, pressure and contain (%s)" % [roles.keys()])
	for e in d.plan:
		check(e["hidden"] and _hidden(e["pos"], siege.in_view), "spawned out of view or deep in the fog far off (%s)" % e["pos"])
	siege.update(0.3)
	check(siege.tactic_counts().get("encircle", 0) >= 3, "they encircle first (%s)" % siege.tactic_counts())
	var with_goals := siege.marker_entries().filter(func(en): return en["goal"] != Vector2.INF)
	check(with_goals.size() >= 3, "members have goals (%d)" % with_goals.size())
	# everyone at their rally spots: the groups go on to their tactics
	for gr in siege.groups:
		for k in (gr["members"] as Array).size():
			var e: AIEnemy = gr["members"][k]
			var spot: Vector2 = siege._rally_spot(gr, k, (gr["members"] as Array).size())
			e.global_position = Vector3(spot.x, 0, spot.y)
	for gr in siege.groups:
		gr["t"] = SiegeDirector.ENCIRCLE_MIN      # they have gathered long enough
	siege.update(0.3)
	siege.update(0.3)
	var states := siege.groups.map(func(gr): return gr["state"])
	check(not states.has("encircle"), "all groups moved on (%s)" % [states])
	var tc := siege.tactic_counts()
	check(tc.keys().size() >= 3, "several tactics at once (%s)" % tc)
	var breach: Dictionary = siege.groups[0]
	check(breach["role"] == "breach" and not (breach["target"] as Dictionary).is_empty(), "the breach group picked an entrance it saw (%s)" % [breach["target"]])
	check(siege.observed.size() >= 1, "entrances observed (%d)" % siege.observed.size())
	# the markers and the F10 text
	siege.set_markers(true)
	check(siege._markers.tag_count() >= 3, "tactic markers over the enemies")
	check(siege.tactics_text().contains("breach"), "F10 tactics text")
	siege.set_markers(false)
	g.debug_kill_enemies()
	check(await _wait_until(func(): return not siege.active, 120), "the siege ends with the invasion")
	check(g.get_node_or_null("SiegeWatcher") == null or g.get_node("SiegeWatcher").is_queued_for_deletion(), "the watcher leaves with the siege")
	check(not g.debug_director().active, "the invasion ended")


func test_e12_trap_barricade_in_a_doorway_and_destroyed() -> void:
	var g := await _boot()
	var siege: SiegeDirector = g.siege
	var world: HouseWorld = g.world
	check_eq(siege.dev_siege().begins_with("Siege"), true, "F10: a siege now")
	check(await _wait_until(func(): return not siege._pending, 30), "members joined")
	# Eli in the bedroom (an inner room): they believe so, then trap it
	g.player.global_position = Vector3(1.0, 0, 1.0)
	siege.last_known = Vector2(1.0, 1.0)
	siege.known_age = 0.0
	siege.known_by = "sight"
	var room := HouseRooms.room_index_at(siege.rooms(), world.nav, Vector2(1.0, 1.0), 2)
	check(siege.inner_room(room), "the bedroom is an inner room")
	siege._start_trap(room)
	var exits: Array = siege.trap["exits"]
	var door := exits.filter(func(x): return x["kind"] == "doorway" and x["open"])
	if not check(not door.is_empty(), "the bedroom has an open doorway (%s)" % [exits]):
		return
	siege.update(0.3)
	var x: Dictionary = door[0]
	var worker: AIEnemy = x["worker"]
	if not check(worker != null, "a worker was sent to the doorway"):
		return
	check(worker.has_goal() and worker.directed_goal.distance_to(x["spot"]) < 0.1, "its goal is the work spot")
	worker.global_position = Vector3(x["spot"].x, 0, x["spot"].y)
	for i in 10:
		worker.global_position = Vector3(x["spot"].x, 0, x["spot"].y)
		await physics_frames(1)
		siege.update(0.5)
	var bars := EnemyBarricades.all_in(world)
	if not check(bars.size() == 1, "a barricade stands in the doorway (%d)" % bars.size()):
		return
	var o: WorldObject = bars[0]
	check(o.kind == "barricade" and not o.built and o.uid.begins_with(EnemyBarricades.UID_PREFIX), "an enemy (non-player) wooden barricade")
	check(o.pos.distance_to(x["pos"]) < 0.6, "in that doorway (%s vs %s)" % [o.pos, x["pos"]])
	check(not world.nav.is_walkable(world.nav.cell_of(o.pos)), "it blocks the way")
	check(g.last_toast.contains("barricading"), "Eli is told (%s)" % g.last_toast)
	# saved with the house (uid kept)
	var saved: Array = world.save_data()["objects"]
	check(saved.any(func(e): return str(e.get("uid", "")).begins_with(EnemyBarricades.UID_PREFIX)), "saved with the house")
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(world.save_data()), "the house loads back")
	var back := EnemyBarricades.all_in(w2)
	check(back.size() == 1 and back[0].hp == o.hp and not back[0].built, "the enemy barricade persists through a load")
	EnemyBarricades.harden(w2)
	check(back.size() == 1 and (back[0].body.collision_layer & EnemyBarricades.SHOT_LAYER) != 0, "and still stops bullets")
	w2.queue_free()
	# counterplay: bullets damage it, enough of them break it
	var hp := o.hp
	world.shoot(Vector3(1.0, 1.2, 1.0), Vector3(o.pos.x - 1.0, -0.4, o.pos.y - 1.0), [g.player])
	check(not is_instance_valid(o) or o.hp < hp, "a shot damages it (%d -> %d)" % [hp, o.hp if is_instance_valid(o) else 0])
	for i in 20:
		if not world.objects.has(o):
			break
		world.damage_object(o, 3, Vector3(1, 1, 1))
	check(not world.objects.has(o), "it can be destroyed")
	check(world.nav.is_walkable(world.nav.cell_of(x["pos"])), "the doorway is open again")
	# F10: one by hand, then cleared
	check(siege.dev_barricade_nearest().begins_with("Enemy barricade"), "F10: a barricade in the nearest doorway")
	check(siege.dev_clear_barricades().begins_with("Removed 1"), "F10: cleared")
	g.debug_kill_enemies()
