extends "res://tests/test_case.gd"
## Exp 006 (D): defences. Trenches and water (navigation kinds, flooding of
## connected sections, the exit rule), drawbridges (raise, lower, bash, smash
## down, the bomber's weak point, the player's water barrier), spikes (hurt
## with a cooldown, bashed and blasted), waders, persistence, and one smoke
## test in the real game scene through the F10 "Defences" tools.

const Roster := preload("res://src/game/enemy_roster.gd")
const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_defenses_game.dat"
const RING := Rect2i(-2, -2, 18, 14)       ## cells x -2..15, y -2..11 (as the F10 moat)


func _world() -> HouseWorld:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	await physics_frames(2)
	return w


func _build_mode(w: HouseWorld) -> Array:
	var s := GameState.new_run(11)
	s.cheats["unlimited"] = true
	# Exp 006 (R): drawbridges need Woodworking, metal spikes Metalworking
	var research = load("res://src/research/research.gd") if ResourceLoader.exists("res://src/research/research.gd") else null
	if research != null:
		research.learn_all(s)
	var b := BuildMode.new()
	b.setup(w, s, null, null)
	add(b)
	await physics_frames(1)
	return [s, b]


## The F10 moat's ring of cells (with the detour around the tipped bin).
func _ring(g: DefenseGrid) -> Array:
	var out := {}
	for x in range(RING.position.x, RING.end.x):
		for y in range(RING.position.y, RING.end.y):
			if x != RING.position.x and x != RING.end.x - 1 and y != RING.position.y and y != RING.end.y - 1:
				continue
			var c := Vector2i(x, y)
			if g.dig_reason(c) == "":
				out[c] = true
			else:
				for k in [c + Vector2i(1, -1), c + Vector2i(1, 0), c + Vector2i(1, 1)]:
					if g.dig_reason(k) == "":
						out[k] = true
	return out.keys()


func _mid(c: Vector2i) -> Vector2:
	return DefenseGrid.cell_center(c)


func test_trenches_water_and_navigation() -> void:
	var w: HouseWorld = await _world()
	var g := w.defense
	check(g != null, "the ground floor has a defence grid")
	check(g.dig_reason(Vector2i(0, -1)) != "", "not right against the house")
	check(g.dig_reason(Vector2i(-5, 0)) != "", "not outside the lot")
	check(g.dig_reason(Vector2i(16, 9)).contains("car"), "not under the car (%s)" % g.dig_reason(Vector2i(16, 9)))
	check_eq(g.dig_reason(Vector2i(-2, -2)), "", "the yard can be dug")
	var a := Vector2i(-2, 3)
	g.dig([a])
	var nc := w.nav.cell_of(_mid(a))
	check_eq(w.nav.get_raw(nc), GridNav.TRENCH, "a dry trench cell")
	check(w.nav.is_walkable(nc), "can be climbed through")
	check_eq(w.nav.walk_weight(nc), GridNav.TRENCH_WEIGHT, "at a cost")
	var ch := g.fill(a)
	check_eq(ch.size(), 1, "filling floods the section")
	check_eq(w.nav.get_raw(nc), GridNav.WATER, "water")
	check(not w.nav.is_passable(nc), "nobody walks into water")
	check(w.nav.is_wade(nc), "but a wader may")
	var ch2 := g.dig([Vector2i(-2, 4), Vector2i(-2, 5)])
	check(g.is_wet(Vector2i(-2, 4)) and g.is_wet(Vector2i(-2, 5)), "digging next to water floods the new cells (%s)" % str(ch2))
	g.dig([Vector2i(-2, 7)])
	check(not g.is_wet(Vector2i(-2, 7)), "a separate section stays dry")
	g.dig([Vector2i(-2, 6)])
	check(g.is_wet(Vector2i(-2, 7)), "joining it to the water floods it too")
	check(g.backfill(Vector2i(-2, 4)), "backfill")
	check_eq(w.nav.get_raw(w.nav.cell_of(_mid(Vector2i(-2, 4)))), GridNav.OPEN, "the ground is back")
	check(g.is_wet(Vector2i(-2, 5)), "the rest keeps its water")
	check(DefenseGrid.fill_cost(9, false) == {"water": 3} and DefenseGrid.fill_cost(9, true).is_empty(), "water: 1 per 4 cells, free from a collector")
	check(g.barrier_shapes == g.wet_count(), "every wet cell holds the player back (%d / %d)" % [g.barrier_shapes, g.wet_count()])


func test_moat_needs_a_bridge_and_the_bridge_works() -> void:
	var w: HouseWorld = await _world()
	var g := w.defense
	var sb: Array = await _build_mode(w)
	var bm: BuildMode = sb[1]
	var ring := _ring(g)
	check(ring.size() >= 60 and ring.size() <= 80, "a ring of %d cells" % ring.size())
	var ch := {}
	for c in ring:
		ch[c] = DefenseGrid.DRY
	var t0 := Time.get_ticks_usec()
	g.apply_changes(ch)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("    ring of %d cells dug in %.1f ms" % [ring.size(), ms])
	check(w.exit_path_exists(), "a dry trench can be climbed through")
	# filling the closed ring without a bridge would seal the house in
	bm.select_id("trench_water")
	var r := bm.evaluate(_mid(Vector2i(8, 11)))
	check(r["reason"].begins_with(BuildMode.SEAL_REASON), "no water without a crossing (%s)" % r["reason"])
	bm.select_id("drawbridge_1")
	r = bm.evaluate(_mid(Vector2i(4, 11)))
	check(r["ok"], "a drawbridge across the front (%s)" % r["reason"])
	check_eq(r["rot"], 2, "its far end faces away from the house")
	check(bm.apply(_mid(Vector2i(4, 11))), "built")
	var o := g.bridge_over(Vector2i(4, 11))
	check(o != null and o.open, "lowered when built")
	bm.select_id("trench_water")
	r = bm.evaluate(_mid(Vector2i(8, 11)))
	check(r["ok"], "now the moat can be filled (%s)" % r["reason"])
	check_eq(r["cost"], {"water": ceili(ring.size() / 4.0)}, "water for the whole ring")
	check(bm.apply(_mid(Vector2i(8, 11))), "filled")
	check_eq(g.wet_count(), ring.size(), "all of it")
	var mid := w.nav.cell_of(Vector2(4.4, 11.5))
	check(w.nav.is_walkable(mid), "the lowered bridge is walkable")
	check_eq(g.barrier_shapes, ring.size() - 1, "and the player may cross it")
	check_eq(g.toggle_bridge(o), "", "E raises it")
	check(not o.open and w.nav.get_raw(mid) == GridNav.WALL, "raised: enemies must bash it")
	check_eq(g.barrier_shapes, ring.size(), "the water holds the player back")
	check(w.exit_path_exists(), "a raised drawbridge still counts as a way out")
	check(o.bashable(), "bashable while raised")
	var weak := w.weak_points(Vector2(4.5, 14.0))
	var found := false
	for p in weak:
		if p["kind"] == "drawbridge":
			found = true
	check(found, "bombers see the raised drawbridge as a weak point")
	bm.select_id("demolish")
	r = bm.evaluate(o.pos)
	check(r["object"] == o and r["reason"].begins_with(BuildMode.SEAL_REASON), "the only crossing can't be demolished (%s)" % r["reason"])
	# blows: the bridge smashes down instead of vanishing
	var hp0 := o.hp
	w.enemy_strike(Vector3(4.5, 0, 12.6), Vector2(4.5, 11.75))
	check(o.hp < hp0, "a blow hurts it")
	var smashed := []
	g.bridge_smashed.connect(func(b): smashed.append(b))
	for k in 60:
		if o.open:
			break
		w.enemy_strike(Vector3(4.5, 0, 12.6), Vector2(4.5, 11.75))
	check(o.open and o.hp == 1 and w.objects.has(o), "battered down: lowered, 1 HP, still there")
	check_eq(smashed.size(), 1, "the game is told")
	check(w.nav.is_walkable(mid), "enemies can cross now")
	check(g.toggle_bridge(o).contains("too damaged"), "it can't be raised until repaired")
	bm.select_id("repair")
	check(bm.apply(o.pos), "repaired")
	check_eq(g.toggle_bridge(o), "", "and raised again")


func test_spikes_hurt_with_a_cooldown_and_break() -> void:
	var w: HouseWorld = await _world()
	var sb: Array = await _build_mode(w)
	var bm: BuildMode = sb[1]
	bm.select_id("spikes_wood")
	var r := bm.evaluate(Vector2(3.5, -2.0), Vector2(1.2, -2.0))
	check(r["ok"] and r["segs"].size() == 3, "a 3 m run (%s)" % r["reason"])
	check_eq(r["cost"], {"wood": 9, "nails": 6}, "3 m of wooden spikes")
	check(bm.apply(Vector2(3.5, -2.0), Vector2(1.2, -2.0)), "built")
	var sp := w.object_at(Vector2(2.5, -2.0))
	check(sp != null and sp.kind == "spikes_wood", "spikes stand there")
	check_eq(w.nav.get_raw(w.nav.cell_of(Vector2(2.5, -2.0))), GridNav.WALL, "bashed through like a barricade")
	check(sp.bashable(), "bashable")
	var player := VoxelPlayer.new()
	player.input_enabled = false
	add(player)
	player.global_position = Vector3(2.5, 0, 3.0)
	var roster: Node3D = Roster.new()
	roster.setup(w, player, 3)
	add(roster)
	await physics_frames(1)
	var e: AIEnemy = roster.spawn_type("psycho", Vector2(2.5, -3.4), {"hp": 6})
	await physics_frames(1)
	e.global_position = Vector3(2.5, 0, -2.45)
	e.spike_cd = 0.0
	w.defense.enemy_step(e, 0.016)
	check_eq(e.hp, 5, "pressing against the spikes hurts")
	w.defense.enemy_step(e, 0.016)
	check_eq(e.hp, 5, "but only once per cooldown")
	e.spike_cd = 0.0
	w.defense.enemy_step(e, 0.016)
	check_eq(e.hp, 4, "again after it")
	e.global_position = Vector3(2.5, 0, -3.4)
	e.spike_cd = 0.0
	w.defense.enemy_step(e, 0.016)
	check_eq(e.hp, 4, "not from a distance")
	e.global_position = Vector3(2.5, 0, -2.75)
	e.spike_cd = 0.0
	w.defense.spike_swing(e, Vector2(2.5, -2.0))
	check_eq(e.hp, 3, "bashing them from arm's length hurts too")
	var hp0 := sp.hp
	w.enemy_strike(Vector3(2.5, 0, -2.6), Vector2(2.5, -2.0))
	check(sp.hp < hp0, "blows wear them down")
	w.explode(Vector3(2.5, 0.8, -2.6), 1.6, 24.0)
	check(not w.objects.has(sp), "a blast destroys them")
	bm.select_id("spikes_metal")
	check_eq(str(BuildPieces.LIST[bm.piece].get("requires", "")), "metalworking", "metal spikes need Metalworking")
	check_eq(WorldObject.max_hp_of("spikes_metal"), 26, "and are tougher")


func test_waders_cross_water_others_dont() -> void:
	var w: HouseWorld = await _world()
	var g := w.defense
	var ch := {}
	for c in _ring(g):
		ch[c] = DefenseGrid.WET
	g.apply_changes(ch)              # no crossing at all (set directly, past the exit rule)
	var from := Vector2(8.5, 13.6)
	var goal := Vector2(8.5, 10.4)
	var p := (WeightedNav.for_nav(w.nav, 12.0) as Object).find_path(from, goal) as PackedVector2Array
	check(p.is_empty() or p[p.size() - 1].distance_to(goal) > 1.0, "a psycho can't reach across the moat")
	var bp := (WeightedNav.for_nav(w.nav, 4.0, true) as Object).find_path(from, goal) as PackedVector2Array
	check(not bp.is_empty() and bp[bp.size() - 1].distance_to(goal) < 0.5, "a brute wades across")
	var wet := false
	for q in bp:
		if g.state_at(q) == DefenseGrid.WET:
			wet = true
	check(wet, "through the water")
	var r := WeightedNav.for_nav(w.nav, 60.0)
	check(r != WeightedNav.for_nav(w.nav, 60.0, true), "wading layers are separate")
	check(not g.ground_at(Vector2(8.5, 11.5), true).is_empty() and float(g.ground_at(Vector2(8.5, 11.5), true)[1]) < 0.5, "wading is slow")


func test_trenches_and_bridges_survive_save_and_load() -> void:
	var w: HouseWorld = await _world()
	var g := w.defense
	var ring := _ring(g)
	var ch := {}
	for c in ring:
		ch[c] = DefenseGrid.DRY
	g.apply_changes(ch)
	var fit := g.bridge_fit(Vector2i(4, 11), 1, 0)
	var o := w.place_object("drawbridge_1", fit["pos"], fit["rot"], true)
	g.set_bridge(o, true, true)
	g.fill(Vector2i(8, 11))
	g.set_bridge(o, false, true)
	w.place_object("spikes_metal", Vector2(2.5, -3.0), 0, true)
	var d := w.save_data()
	check(d.has("defense"), "the save has the trenches")
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(bytes_to_var(var_to_bytes(d))), "loads (as SaveGame stores it)")
	await physics_frames(1)
	var g2 := w2.defense
	check_eq(g2.cells.size(), ring.size(), "every trench cell")
	check_eq(g2.wet_count(), ring.size(), "with its water")
	var o2 := g2.bridge_over(Vector2i(4, 11))
	check(o2 != null and not o2.open, "the drawbridge, still raised")
	check_eq(w2.nav.get_raw(w2.nav.cell_of(Vector2(4.4, 11.5))), GridNav.WALL, "and its navigation")
	check_eq(w2.nav.get_raw(w2.nav.cell_of(Vector2(8.5, 11.5))), GridNav.WATER, "the water's too")
	check_eq(g2.barrier_shapes, ring.size(), "the player's barrier")
	var sp := w2.object_at(Vector2(2.5, -3.0))
	check(sp != null and sp.kind == "spikes_metal", "the spikes")
	var old := d.duplicate(true)
	old.erase("defense")
	var w3 := HouseWorld.new()
	add(w3)
	check(w3.load_data(old), "a save without trenches loads")
	check(w3.defense.cells.is_empty(), "with none")


func _boot() -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = "new"
	GameLaunch.seed = 6006
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
	await super.cleanup()


func test_moat_in_the_game_through_the_dev_tools() -> void:
	var g: Node = await _boot()
	var w: HouseWorld = g.debug_world()
	var m: DevMenu = g.debug_ui().dev_menu
	m.toggle()
	await frames(2)
	check(m.button("Moat ring + bridge") != null, "the Defences section is there")
	m.button("Shovel, water, wood").pressed.emit()
	m.button("Moat ring + bridge").pressed.emit()
	m.button("Fill the moat").pressed.emit()
	await frames(2)
	check(w.defense.cells.size() >= 60 and w.defense.wet_count() == w.defense.cells.size(), "a full moat (%d m)" % w.defense.cells.size())
	check(w.exit_path_exists(), "the house keeps its way out (the bridge)")
	m.button("Raise / lower bridges").pressed.emit()
	var o := w.defense.bridge_over(Vector2i(4, 11))
	check(o != null and not o.open, "the bridge is raised")
	m.button("Psycho at the moat").pressed.emit()
	m.toggle()
	await physics_frames(5)
	# the player walks toward the water: the barrier stops them at the edge
	var pl: VoxelPlayer = g.debug_player()
	g.debug_teleport_player(Vector2(8.5, 10.4))
	await physics_frames(2)
	pl.velocity = Vector3.ZERO
	for k in 40:
		pl.velocity = Vector3(0, 0, 3.0)
		pl.move_and_slide()
		await physics_frames(1)
	check(pl.global_position.z < 11.0, "the player can't walk into the water (z %.2f)" % pl.global_position.z)
	check(g.debug_living_enemies() >= 1, "the psycho is there")
	var e: AIEnemy = null
	for x in g.debug_roster().threats():
		e = x
	await physics_frames(60)
	check(e == null or e.plan_pos().y > 12.0 or not e.alive, "the psycho stays outside the moat (%s)" % (str(e.plan_pos()) if e != null else "-"))
