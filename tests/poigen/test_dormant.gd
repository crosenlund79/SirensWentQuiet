extends "res://tests/test_case.gd"
## Exp 009 (P): dormant psychos (DormantMind). Each behaviour runs and stays
## dormant with Eli far; a far gunshot makes one listen, then investigate (and
## hunt once it sees him), a close one makes it attack; a quiet sneak at a
## distance doesn't wake it; sensitivity matters; invalid spots fall back;
## the encounter plan mixes them in; save at the POI with a dormant psycho ->
## Continue -> still dormant, with its behaviour; the voice cap holds; the
## inbox maps the suggested file names and still maps the old enemy files.
## Spots come from GamePoi.dormant_spot_near (the hand-made layouts have no
## "dormant" key; agent G's generator provides them for generated places).

const PREVIEW := "res://src/poi/poi_preview.tscn"
const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_dormant.dat"
const TravelFlow := preload("res://src/travel/travel_flow.gd")

var _tmp := ""


func _harness(id: String, at := Vector2.INF) -> Node:
	var h: Node = (load(PREVIEW) as PackedScene).instantiate()
	h.configure(id, false, 4242)
	h.player_at = at
	add(h)
	await physics_frames(3)
	h.roster.kill_all()
	h.poi.pending.clear()
	await physics_frames(1)
	return h


## A dormant psycho doing `behaviour` at the spot the finder picks near `near`.
func _dormant(h: Node, behaviour: String, near: Vector2, sens := 1.0, mumble := false, kind := "psycho") -> AIEnemy:
	var sp: Dictionary = h.poi.dormant_spot_near(behaviour, near, 0.0, false)
	if not check(not sp.is_empty(), "a spot for %s near %s" % [behaviour, near]):
		return null
	var e: Node = h.poi._spawn({"kind": kind, "at": sp["at"], "when": 0.0, "mode": "dormant",
		"dormant": {"behaviour": behaviour, "spot": sp["at"], "target": sp.get("target", Vector2.INF), "radius": sp.get("radius", 1.2),
			"sensitivity": sens, "mumble": mumble}})
	check(e is AIEnemy and (e as AIEnemy).mind is DormantMind, "spawned dormant (%s)" % behaviour)
	return e as AIEnemy


func _dm(e: AIEnemy) -> DormantMind:
	return e.mind as DormantMind if e != null and e.mind is DormantMind else null


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	GameLaunch.notice = ""
	GameLaunch.site = "home"
	GameLaunch.carry = {}
	TravelFlow.skip_animation = false
	PsychoVoice.reset()
	if _tmp != "":
		_rmtree(_tmp)
		_tmp = ""
		AudioInbox.roots_override = []
		AudioInbox.reset()
		Sfx.reset()
	await super.cleanup()


# --- behaviours --------------------------------------------------------------------------------

func test_each_behaviour_runs_and_stays_dormant() -> void:
	var places := {"bang": Vector2(6.0, 1.2), "tap": Vector2(2.0, 4.0), "stare": Vector2(12.6, 7.6), "sway": Vector2(10.0, 4.6), "circle": Vector2(9.5, 4.8)}
	for b in DormantMind.BEHAVIOURS:
		var h: Node = await _harness("convenience", Vector2(7.0, 12.4))     # Eli out front, far
		var e := _dormant(h, b, places[b], 1.0, true)
		var dm := _dm(e)
		if dm == null:
			continue
		check_eq(dm.behaviour, b, "%s: the spot suits it (asked %s)" % [b, dm.asked])
		var start := e.plan_pos()
		var moved := 0.0
		var last := start
		for i in 30:
			await physics_frames(15)
			moved += e.plan_pos().distance_to(last)
			last = e.plan_pos()
		check(e.is_calm() and e.mind is DormantMind, "%s: still dormant after 7.5 s with Eli far (%s)" % [b, e.state_name()])
		check(dm.state == b or (dm.state in ["listen"]), "%s: busy with it (%s, history %s)" % [b, dm.state, dm.history])
		check_eq(h.poi.hunters(), 0, "%s: nobody hunts" % b)
		check_eq(h.poi.save_check(), "", "%s: saving is allowed" % b)
		match b:
			"bang":
				check(dm.bangs >= 2, "it banged its head (%d)" % dm.bangs)
				check(e.plan_pos().distance_to(start) < 0.3, "in place")
			"tap":
				check(dm.taps >= 2, "it tapped (%d, %s)" % [dm.taps, dm.tap_kind])
			"circle":
				check(moved > 1.0, "it walks round (%.1f m)" % moved)
				check(e.plan_pos().distance_to(dm.target) < dm.radius + 1.0, "round its target (%.1f m from it)" % e.plan_pos().distance_to(dm.target))
			"sway", "stare":
				check(e.plan_pos().distance_to(start) < 0.3, "%s: in place" % b)
		await cleanup()


func test_a_far_gunshot_makes_it_listen_then_look_and_it_hunts_once_it_sees_eli() -> void:
	var h: Node = await _harness("forest", Vector2(1.0, 8.6))
	var e := _dormant(h, "sway", Vector2(9.0, 8.6))
	var dm := _dm(e)
	if dm == null:
		return
	await physics_frames(10)
	var pp: Vector2 = h.player.plan_pos()
	var d := e.plan_pos().distance_to(pp)
	check(d > DormantMind.STARTLE_RANGE + 1.0 and d < 10.0, "about 8 m from Eli (%.1f)" % d)
	var ev := NoiseEvent.emit(h, Vector3(pp.x, 1.0, pp.y), NoiseEvent.weapon_level("handgun"), "gunfire")
	check(ev.get("heard", 0) >= 1, "it heard the shot (%s)" % ev)
	await physics_frames(2)
	check(e.is_calm() and dm.state == "listen", "it stops and listens (%s)" % dm.state)
	var looked := false
	for i in 60:
		await physics_frames(10)
		if dm.state == "investigate" or not e.is_calm():
			looked = true
			break
	check(looked, "then it comes to look (%s, alert %.2f)" % [dm.history, dm.alert])
	var hunted := false
	for i in 80:
		await physics_frames(10)
		if not e.is_calm():
			hunted = true
			break
	check(hunted, "seeing him on the way, it attacks (%s)" % e.state_name())
	check(e.mind == null and e.state_name() == "chase", "ordinary AI now (%s)" % e.state_name())
	check_eq(h.poi.hunters(), 1, "it hunts Eli")
	check(h.poi.save_check() != "", "no saving now")


func test_a_close_gunshot_makes_it_attack_at_once() -> void:
	var h: Node = await _harness("forest", Vector2(5.0, 8.6))
	var e := _dormant(h, "stare", Vector2(8.0, 8.6))
	if _dm(e) == null:
		return
	await physics_frames(5)
	var pp: Vector2 = h.player.plan_pos()
	check(e.plan_pos().distance_to(pp) < DormantMind.STARTLE_RANGE, "close (%.1f m)" % e.plan_pos().distance_to(pp))
	NoiseEvent.emit(h, Vector3(pp.x, 1.0, pp.y), NoiseEvent.weapon_level("handgun"), "gunfire")
	await physics_frames(2)
	check(not e.is_calm() and e.provoked_by.begins_with("startled"), "startled into attacking (%s)" % e.provoked_by)


func test_after_looking_it_goes_back_to_what_it_was_doing() -> void:
	var h: Node = await _harness("forest", Vector2(1.0, 8.6))
	var e := _dormant(h, "sway", Vector2(9.0, 8.6))
	var dm := _dm(e)
	if dm == null:
		return
	await physics_frames(10)
	var at: Vector2 = h.player.plan_pos()
	NoiseEvent.emit(h, Vector3(at.x, 1.0, at.y), NoiseEvent.weapon_level("handgun"), "gunfire")
	h.player.global_position = Vector3(-4.0, 0, -3.0)     # Eli slips away: nothing to find there
	var back := false
	for i in 120:
		await physics_frames(10)
		if dm.history.has("investigate") and dm.state == "sway":
			back = true
			break
	check(back and e.is_calm(), "it looked, found nothing and sways again (%s)" % [dm.history])
	check(e.plan_pos().distance_to(dm.spot) < 1.0, "at its spot (%.1f m away)" % e.plan_pos().distance_to(dm.spot))


func test_a_quiet_sneak_at_a_distance_does_not_wake_it() -> void:
	var h: Node = await _harness("convenience", Vector2(7.0, 12.4))
	var e := _dormant(h, "bang", Vector2(6.0, 1.2))
	var dm := _dm(e)
	if dm == null:
		return
	await physics_frames(10)
	var me := e.plan_pos()
	# Eli walks to and fro behind it, about 3 m away, at a walking pace
	var a := me + (me - dm.target).normalized() * 3.2 + Vector2(-1.4, 0.0)
	var b := a + Vector2(2.8, 0.0)
	h.player.global_position = Vector3(a.x, 0, a.y)
	for i in 300:
		var t := float(i % 150) / 150.0
		var p := a.lerp(b, t if (i / 150) % 2 == 0 else 1.0 - t)
		h.player.global_position = Vector3(p.x, 0, p.y)
		await physics_frames(1)
	check(e.is_calm() and dm.is_absorbed(), "a quiet walk 3 m away: it keeps banging (%s, alert %.2f)" % [dm.state, dm.alert])
	# running past close behind it, it hears him
	var c := me + (me - dm.target).normalized() * 1.9
	for i in 60:
		var p := c + Vector2(-2.0 + 4.0 * float(i) / 60.0, 0.0)
		h.player.global_position = Vector3(p.x, 0, p.y)
		await physics_frames(1)
	check(not dm.is_absorbed() or not e.is_calm(), "running close by, it notices (%s)" % e.state_name())


func test_sensitivity_matters() -> void:
	var h: Node = await _harness("forest", Vector2(1.0, 0.0))
	var calm := _dormant(h, "sway", Vector2(4.0, 8.0), 0.5)
	var jumpy := _dormant(h, "sway", Vector2(14.0, 8.0), 1.5)
	if _dm(calm) == null or _dm(jumpy) == null:
		return
	await physics_frames(5)
	# the same noise, as heard 5 m away: the sensitive one attacks, the other listens
	calm.hear(calm.plan_pos() + Vector2(5.0, 0.0), 3.2, "gunfire")
	jumpy.hear(jumpy.plan_pos() + Vector2(5.0, 0.0), 3.2, "gunfire")
	check(not jumpy.is_calm(), "sensitivity 1.5: startled at 5 m")
	check(calm.is_calm() and _dm(calm).state == "listen", "sensitivity 0.5: it only listens (%s)" % calm.state_name())
	# a faint noise: the sensitive one listens, the other doesn't notice
	var calm2 := _dormant(h, "stare", Vector2(8.0, 4.0), 0.5)
	var jumpy2 := _dormant(h, "stare", Vector2(4.0, 1.0), 1.5)
	await physics_frames(3)
	calm2.hear(calm2.plan_pos() + Vector2(8.0, 0.0), 0.3, "search")
	jumpy2.hear(jumpy2.plan_pos() + Vector2(8.0, 0.0), 0.3, "search")
	check(_dm(calm2).is_absorbed(), "sensitivity 0.5 ignores a faint search (%s)" % _dm(calm2).state)
	check(_dm(jumpy2).state == "listen", "sensitivity 1.5 stops to listen (%s)" % _dm(jumpy2).state)


func test_invalid_spots_fall_back() -> void:
	var h: Node = await _harness("convenience", Vector2(7.0, 12.4))
	var open := Vector2(8.0, 7.8)
	var cases := [
		["bang", open, open + Vector2(0.6, 0.0), "stare"],    # nothing to bang on: it stares
		["tap", open, Vector2.INF, "sway"],                   # no target at all
		["circle", open, Vector2(-60.0, -60.0), "sway"],      # round something off the map: no room
		["stare", open, Vector2.INF, "sway"],
		["dance", open, open, "sway"],
	]
	for c in cases:
		var e: Node = h.poi._spawn({"kind": "psycho", "at": c[1], "when": 0.0, "mode": "dormant",
			"dormant": {"behaviour": c[0], "spot": c[1], "target": c[2], "radius": 1.0, "sensitivity": 1.0}})
		var dm := _dm(e)
		if not check(dm != null, "%s spawned dormant" % c[0]):
			continue
		check_eq(dm.behaviour, c[3], "%s with a bad target falls back" % c[0])
		check_eq(dm.asked, c[0], "it remembers what was asked")
		check_eq(dm.state, c[3], "and does it")
	await physics_frames(60)
	check_eq(h.roster.living(), cases.size(), "all of them alive")
	check_eq(h.poi.hunters(), 0, "and calm")
	# a plan entry without its spot data waits as a hidden one
	var e2: Node = h.poi._spawn({"kind": "psycho", "at": open, "when": 0.0, "mode": "dormant"})
	check(e2 is AIEnemy and (e2 as AIEnemy).is_calm() and (e2 as AIEnemy).mind.mode == "hidden", "no spot: it waits (hidden)")


func test_dev_tools() -> void:
	var h: Node = await _harness("convenience", Vector2(7.0, 6.0))
	var t: String = h.poi.dev_spawn_dormant("bang")
	check(t.begins_with("A dormant psycho"), t)
	var e: AIEnemy = h.poi.watch.back()["e"]
	check(_dm(e) != null and _dm(e).behaviour == "bang", "it bangs (%s)" % t)
	check(e.plan_pos().distance_to(Vector2(7.0, 6.0)) >= float(h.poi.DEV_NEAR) - 0.2, "not on top of Eli")
	t = h.poi.dev_force_behaviour("sway")
	check(_dm(e).behaviour == "sway" and t.contains("sways"), t)
	t = h.poi.dev_force_behaviour("tap")
	check(_dm(e).asked == "tap", t)
	check(h.poi.dev_force_behaviour("juggle").begins_with("Unknown"), "unknown behaviours are refused")
	t = h.poi.dev_spawn_dormant()
	check(t.begins_with("A dormant psycho"), t)
	check(h.poi.dev_state_text() != "", "the state text still works")


# --- the plan ----------------------------------------------------------------------------------

func test_the_plan_mixes_dormants_in() -> void:
	var w := PoiWorld.new()
	w.configure("convenience", null)
	var plain := w.layout.duplicate()
	var with := w.layout.duplicate()
	# four spots: two beside the locked stockroom shelves, two out in the shop
	with["dormant"] = [{"at": Vector2(10.2, 1.2), "behaviour": "bang", "target": Vector2(10.2, 0.3), "radius": 1.0},
		{"at": Vector2(12.0, 1.2), "behaviour": "tap", "target": Vector2(12.0, 0.3), "radius": 1.0},
		{"at": Vector2(9.0, 5.0), "behaviour": "sway", "target": Vector2.INF, "radius": 1.0},
		{"at": Vector2(5.4, 7.6), "behaviour": "circle", "target": Vector2(4.2, 6.6), "radius": 1.4}]
	var seen := {}
	var dormant := 0
	var total := 0
	var brutes := 0
	for k in 400:
		w.layout = plain
		var a := w.encounter_plan(1.4, 5000 + k)
		w.layout = with
		var b := w.encounter_plan(1.4, 5000 + k)
		check_eq(a.is_empty(), b.is_empty(), "the quiet share is unchanged (seed %d)" % k)
		check_eq(a.size(), b.size(), "and so is the count (seed %d)" % k)
		var n := 0
		var guards := 0
		for e in b:
			seen[e["mode"]] = true
			total += 1
			if e["mode"] != "dormant":
				continue
			n += 1
			dormant += 1
			check(e["kind"] in ["psycho", "brute"], "dormant ones are psychos or brutes (%s)" % e["kind"])
			if e["kind"] == "brute":
				brutes += 1
			var d: Dictionary = e["dormant"]
			check(float(d["sensitivity"]) >= 0.5 and float(d["sensitivity"]) <= 1.5, "sensitivity in 0.5..1.5")
			check(float(e["when"]) == 0.0, "there from the start")
			if (e["at"] as Vector2).distance_to(Vector2(10.2, 0.35)) < 2.2 or (e["at"] as Vector2).distance_to(Vector2(12.0, 0.35)) < 2.2:
				guards += 1
		check(n <= PoiWorld.DORMANT_MAX, "at most %d dormant (%d)" % [PoiWorld.DORMANT_MAX, n])
		check(guards <= 1, "not one beside every valuable container (%d)" % guards)
	check(dormant > total * 0.25 and dormant < total * 0.65, "a share of the occupants are dormant (%d of %d)" % [dormant, total])
	for m in ["hidden", "wander", "arrive", "dormant"]:
		check(seen.has(m), "mixed with '%s' (%s)" % [m, seen.keys()])
	check(brutes > 0 and brutes < dormant / 4, "now and then a brute (%d of %d)" % [brutes, dormant])
	w.layout = plain
	for k in 200:
		for e in w.encounter_plan(1.4, k):
			check(e["mode"] != "dormant", "no spots, no dormants")
	w.free()


# --- saving ------------------------------------------------------------------------------------

func _boot(mode: String) -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 7007
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


func test_save_and_continue_keep_it_dormant() -> void:
	TravelFlow.skip_animation = true
	var g: Node = await _boot("new")
	g.debug_state().total_minutes = 9.0 * 60.0
	await g.travel.depart("convenience")
	g.queue_free()
	await frames(2)
	g = await _boot("carry")
	if not check(g.poi != null and g.poi._started, "at the store"):
		return
	g.debug_kill_enemies()
	await frames(2)
	g.poi.pending.clear()
	g.player.global_position = Vector3(7.0, 0, 12.4)
	var t: String = g.poi.dev_spawn_dormant("bang")
	var e: AIEnemy = g.poi.watch.back()["e"]
	if not check(_dm(e) != null, "a dormant psycho (%s)" % t):
		return
	var dm := _dm(e)
	dm.sensitivity = 0.73
	dm.mumble = true
	await physics_frames(30)
	check_eq(g.can_save(), "", "a dormant one doesn't stop a save")
	check_eq(g.debug_save(), "", "saved")
	var enc: Dictionary = g.debug_state().region.poi["convenience"]["visit"]["enc"]
	var calm: Array = enc["calm"]
	check(calm.size() == 1 and typeof(calm[0].get("dormant")) == TYPE_DICTIONARY, "the visit record holds it, dormant (%s)" % [calm])
	var b0 := dm.behaviour
	var spot := dm.spot
	var target := dm.target
	g.queue_free()
	await frames(2)
	g = await _boot("continue")
	await physics_frames(2)
	check(not g.is_home() and g.site_id() == "convenience", "Continue: at the store")
	var back: AIEnemy = null
	for x in g.roster.enemies:
		if is_instance_valid(x) and x.alive:
			back = x
	if not check(back != null and _dm(back) != null, "it is back, dormant"):
		return
	var dm2 := _dm(back)
	check_eq(dm2.behaviour, b0, "with its behaviour")
	check(dm2.spot.distance_to(spot) < 0.01 and dm2.target.distance_to(target) < 0.01, "at its spot, facing its wall")
	check(is_equal_approx(dm2.sensitivity, 0.73) and dm2.mumble, "as sensitive as it was, still mumbling")
	await physics_frames(120)
	check(back.is_calm() and dm2.state == b0, "busy again (%s)" % dm2.state)
	check(dm2.bangs >= 1, "banging (%d)" % dm2.bangs)
	# once it hunts, no saving
	back.provoke("test")
	check(g.can_save().contains("after you"), "a hunter stops the save (%s)" % g.can_save())


# --- audio -------------------------------------------------------------------------------------

func test_inbox_maps_the_psycho_files_and_keeps_the_old_ones() -> void:
	var want := {
		"Psycho - Incoherent Mumbling 01.mp3": ["psycho/mumble", 1],
		"Psycho - Nervous Humming.mp3": ["psycho/hum", 0],
		"Psycho - Rhythmic Head Banging.mp3": ["psycho/bang", 0],
		"Psycho - Disturbed Whispering.mp3": ["psycho/whisper", 0],
		"Psycho - Sudden Silence Reaction.mp3": ["psycho/startle", 0],
		"Psycho - Scratching.mp3": ["psycho/scratch", 0],
		"Psycho - Repetitive Tapping.mp3": ["psycho/tap", 0],
		"Enemy - Vocal 1.wav": ["enemy/moan", 1],
		"Enemy - Vocal 4.wav": ["enemy/moan", 4],
		"Enemy - Heavy impact wood 1.wav": ["door/bash", 1],
		"Enemy - Heavy impact wood 4.wav": ["door/bash", 4],
	}
	for f in want:
		var m := AudioInbox.match_path("res://x/" + f, "res://x")
		check_eq([m["name"], m["variant"]], want[f], f)
	for n in ["psycho/mumble", "psycho/hum", "psycho/bang", "psycho/whisper", "psycho/startle", "psycho/scratch", "psycho/tap"]:
		check(Sfx.has(n), "%s is a sound the game knows" % n)
		check(not bool(Sfx.DEFS[n].get("tpl", true)), "%s has no generated template" % n)
	# the user's upload still maps as before (nothing stolen)
	AudioInbox.roots_override = []
	AudioInbox.reset()
	check_eq(AudioInbox.files_of("enemy/moan").size(), 4, "the four enemy vocals")
	check_eq(AudioInbox.files_of("door/bash").size(), 4, "the four heavy wood impacts")


func _temp_inbox(files: Array) -> void:
	_tmp = OS.get_user_data_dir().path_join("dormant_inbox_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_tmp)
	for f in files:
		var out := FileAccess.open(_tmp.path_join(f), FileAccess.WRITE)
		out.store_buffer(FileAccess.get_file_as_bytes("res://assets/audio/_inbox/foley/Enemy - Vocal 1.wav"))
		out.close()
	AudioInbox.roots_override = [_tmp]
	AudioInbox.reset()
	Sfx.reset()


func _rmtree(dir: String) -> void:
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func test_the_voice_cap_and_pauses_hold() -> void:
	var h: Node = await _harness("convenience", Vector2(7.0, 6.0))
	_temp_inbox(["Psycho - Incoherent Mumbling 01.wav", "Psycho - Nervous Humming.wav", "Psycho - Disturbed Whispering.wav"])
	Sfx.attach(h)
	check(Sfx.available("psycho/mumble"), "the test recording maps to psycho/mumble")
	PsychoVoice.reset()
	var es := []
	for near in [Vector2(3.0, 4.0), Vector2(11.0, 4.0), Vector2(3.0, 7.8), Vector2(11.5, 7.8)]:
		var e := _dormant(h, "sway", near, 1.0, true)
		if e != null:
			es.append(e)
	await physics_frames(2)
	var said := 0
	for e in es:
		var v: PsychoVoice = _dm(e).voice
		v.pause = 0.0
		if v.say(e, [["psycho/mumble", 0.0, 1.0]]) != "":
			said += 1
			check(v.speaking() and v.pause > 0.0, "a line, then a pause")
			check(v.say(e, [["psycho/mumble", 0.0, 1.0]], Vector2(1, 2), true) == "", "one line at a time per enemy")
	check_eq(said, PsychoVoice.CAP, "only %d start at once" % PsychoVoice.CAP)
	check(PsychoVoice.refused >= es.size() - PsychoVoice.CAP, "the rest are held back (%d)" % PsychoVoice.refused)
	var top := 0
	for i in 60:
		await physics_frames(10)
		top = maxi(top, PsychoVoice.active())
	check(top <= PsychoVoice.CAP, "never more than %d voices while they mumble on their own (max %d)" % [PsychoVoice.CAP, top])
	check(PsychoVoice.started >= 2, "they do mumble (%d lines)" % PsychoVoice.started)
	# provoked: it falls silent at once
	var e0: AIEnemy = es[0]
	var v0: PsychoVoice = _dm(e0).voice
	v0.stop()
	v0.pause = 0.0
	PsychoVoice.reset()
	v0.say(e0, [["psycho/mumble", 0.0, 1.0]])
	e0.provoke("test")
	check(not v0.speaking(), "a provoked one stops mumbling")


func test_voice_falls_back_without_recordings() -> void:
	var h: Node = await _harness("convenience", Vector2(7.0, 6.0))
	var e := _dormant(h, "sway", Vector2(9.0, 5.0), 1.0, true)
	if _dm(e) == null:
		return
	check(not Sfx.available("psycho/mumble"), "no psycho recordings in the project")
	var v: PsychoVoice = _dm(e).voice
	v.pause = 0.0
	check_eq(v.say(e, [["psycho/mumble", 0.0, 1.0], ["enemy/moan", -14.0, 1.0]]), "enemy/moan", "the quiet enemy vocal stands in")
	v.stop()
	v.pause = 0.0
	check_eq(v.say(e, [["psycho/whisper", 0.0, 1.0]]), "", "a whisper without a file: nothing")
