extends "res://tests/test_case.gd"
## Exp 008 (E): the house while Eli is away (OffscreenHome). A turret with
## ammunition spends it on an attack (and its strength counts in the
## defence); a raised drawbridge over a water moat helps, a lowered one much
## less; a trip on which nothing falls due reports nothing alarming, and a
## straggler mostly just prowls round (no blows); not every trip has an
## attack, only those during which one falls due.

const RING := Rect2i(-2, -2, 18, 14)       ## the F10 moat's ring of cells (as tests/defense)


func _world() -> HouseWorld:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	await physics_frames(2)
	return w


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


## An invasion of `size` recorded while away (the schedule moves on as in the game).
func _away_with_invasion(seed: int) -> GameState:
	var s := GameState.new_run(seed)
	var due := float(s.run.get("next_invasion_at", 0.0))
	s.total_minutes = due
	OffscreenHome.begin(s)
	OffscreenHome.record_invasion(s, due)
	return s


func test_a_turret_with_ammo_spends_it() -> void:
	var w: HouseWorld = await _world()
	var bare := OffscreenHome.defence(w)
	var t := w.place_object("turret_mount", Vector2(3.3, 10.3), 1, true)
	var c := Security.config(t)
	c["gun"] = "handgun"
	c["mag"] = WeaponDefs.capacity("handgun")
	c["auto"] = true
	c["on"] = true
	t.items["ammo"] = 30
	var before := Security.usable_rounds(t)
	check(before > 30, "a loaded turret with a full box (%d)" % before)
	var armed := OffscreenHome.defence(w)
	check(float(armed["security"]) > 0.0 and float(armed["score"]) > float(bare["score"]), "it counts in the defence (%.2f > %.2f)" % [armed["score"], bare["score"]])
	var s := _away_with_invasion(31)
	var r := OffscreenHome.resolve(w, s, 5)
	check_eq(int(r["attacks"]), 1, "one attack")
	check(int(r["rounds"]) > 0, "the turret fired (%d rounds)" % r["rounds"])
	check_eq(Security.usable_rounds(t), before - int(r["rounds"]), "real rounds, gone from the turret")
	check(str(r["lines"][0]).contains("the turrets fired"), "and the report says so (%s)" % [r["lines"]])
	# empty, it spends nothing and counts for nothing
	c["mag"] = 0
	t.items.erase("ammo")
	check_eq(Security.usable_rounds(t), 0, "emptied")
	var s2 := _away_with_invasion(32)
	var r2 := OffscreenHome.resolve(w, s2, 5)
	check_eq(int(r2["rounds"]), 0, "no ammo, no shots")
	check_eq(float(OffscreenHome.defence(w)["security"]), 0.0, "and no strength")


func test_a_raised_drawbridge_over_water_helps() -> void:
	var w: HouseWorld = await _world()
	var plain := float(OffscreenHome.defence(w)["score"])
	var g := w.defense
	var ch := {}
	for cell in _ring(g):
		ch[cell] = DefenseGrid.DRY
	g.apply_changes(ch)
	var fit := g.bridge_fit(Vector2i(4, 11), 1, 0)
	var o := w.place_object("drawbridge_1", fit["pos"], fit["rot"], true)
	g.set_bridge(o, false, true)
	var dry := OffscreenHome.defence(w)
	check(float(dry["score"]) > plain and int(dry["trench"]) > 40 and int(dry["bridges"]) == 1, "a dry trench and a raised bridge help a little (%s)" % [dry])
	g.fill(Vector2i(8, 11))
	var raised := OffscreenHome.defence(w)
	check(int(raised["moat"]) > 40, "the moat is full (%d cells)" % raised["moat"])
	check(float(raised["score"]) >= plain + 3.0, "a full moat and a raised drawbridge help a lot (%.2f vs %.2f)" % [raised["score"], plain])
	g.set_bridge(o, true, true)
	var lowered := OffscreenHome.defence(w)
	check(int(lowered["lowered"]) == 1 and int(lowered["bridges"]) == 0, "lowered")
	check(float(lowered["score"]) < float(raised["score"]) - 1.5, "a lowered drawbridge is a way in (%.2f vs %.2f)" % [lowered["score"], raised["score"]])
	check(float(lowered["score"]) > plain, "the water still counts for something")
	for size in [4.0, 6.0]:
		var n_plain := OffscreenHome.strikes_for(size, plain, true)
		var n_raised := OffscreenHome.strikes_for(size, float(raised["score"]), true)
		var n_lowered := OffscreenHome.strikes_for(size, float(lowered["score"]), true)
		check(n_raised < n_plain and n_raised < n_lowered, "%d of them: fewer blows behind a raised drawbridge and water (%d, lowered %d, none %d)" % [size, n_raised, n_lowered, n_plain])
	# the same invasion against the moated house and a plain one
	g.set_bridge(o, false, true)
	var r_moat := OffscreenHome.resolve(w, _away_with_invasion(41), 9)
	var w2: HouseWorld = await _world()
	var r_plain := OffscreenHome.resolve(w2, _away_with_invasion(41), 9)
	check(int(r_moat["strikes"]) < int(r_plain["strikes"]), "the moat keeps blows off (%d vs %d)" % [r_moat["strikes"], r_plain["strikes"]])


func test_a_trip_with_nothing_due_reports_nothing_alarming() -> void:
	var w: HouseWorld = await _world()
	# a morning trip on day 2: no invasion falls due, so nothing is recorded
	var s := GameState.new_run(51)
	s.total_minutes = 1440.0 + 9.0 * 60.0
	var due := float(s.run.get("next_invasion_at", INF))
	OffscreenHome.begin(s)
	var evs: Array = s.advance(180.0)
	for e in evs:
		check(str(e.get("type", "")) != "invasion_due", "no invasion falls due on a morning trip")
	check(due > s.total_minutes, "the next one is later (%.0f > %.0f)" % [due, s.total_minutes])
	var r := OffscreenHome.resolve(w, s, 3)
	check(int(r["attacks"]) == 0 and int(r["strikes"]) == 0 and (r["lines"] as Array).is_empty(), "nothing happened, nothing to report (%s)" % [r])
	OffscreenHome.finish(s)
	# a night away with a dawn and a straggler who only prowled round
	var seed := -1
	for k in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = k
		if rng.randf() >= OffscreenHome.PROWL_ATTACK:
			seed = k
			break
	var s2 := GameState.new_run(52)
	OffscreenHome.begin(s2)
	OffscreenHome.record_straggler(s2, s2.total_minutes)
	OffscreenHome.record_dawn(s2, s2.total_minutes + 60.0)
	var r2 := OffscreenHome.resolve(w, s2, seed)
	check(int(r2["attacks"]) == 0 and int(r2["strikes"]) == 0 and int(r2["prowlers"]) == 1, "it prowled round and left (%s)" % [r2])
	check_eq(int(w.damage_summary()["missing_voxels"]), 0, "the house is untouched")
	var text := " ".join(r2["lines"])
	check(text.contains("prowled round the house and left") and not text.contains("they came") and not text.contains("broke"), "a short, calm line (%s)" % text)
	check((r2["lines"] as Array).size() <= 2, "concise")
	# stragglers turn on the empty house only sometimes, as they do at home
	var attacks := 0
	for k in 100:
		var s3 := GameState.new_run(60 + k)
		OffscreenHome.begin(s3)
		OffscreenHome.record_straggler(s3, s3.total_minutes)
		attacks += int(OffscreenHome.resolve(w, s3, 1000 + k)["attacks"])
	check(attacks >= 15 and attacks <= 45, "about 30 %% of stragglers turn on the empty house (%d / 100)" % attacks)
