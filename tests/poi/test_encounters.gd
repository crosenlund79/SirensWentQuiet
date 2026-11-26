extends "res://tests/test_case.gd"
## Exp 008 (E): encounters at POIs and saving among them. Quiet visits by
## danger (low-danger places more often), the encounter kinds per layout
## (hidden, peek, enter, arrive, wander; layouts without "peek"/"doorways"
## keep working), the layouts' window and doorway spots, a watcher who sees
## Eli through the glass and comes in by a doorway, someone entering who opens
## the door, noise that brings arrivals sooner but never adds anyone, a hunter
## that loses Eli, and in the real game scene: saving with calm enemies about,
## refused while one hunts, and Continue restoring exactly that (the killed
## stay dead, the calm stand where they stood, arrivals keep their time).

const PREVIEW := "res://src/poi/poi_preview.tscn"
const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_encounters.dat"
const TravelFlow := preload("res://src/travel/travel_flow.gd")
const PLACES := ["forest", "convenience", "library", "homes"]      # the three hand-made layouts and a generated house (Exp 009)
const GamePoi := preload("res://src/poi/game_poi.gd")


func _harness(id: String, at := Vector2.INF) -> Node:
	var h: Node = (load(PREVIEW) as PackedScene).instantiate()
	h.configure(id, false, 4242)
	h.player_at = at
	add(h)
	await physics_frames(3)
	h.roster.kill_all()                # whoever this visit's plan brought: each test sets its own scene
	h.poi.pending.clear()
	await physics_frames(1)
	return h


func _world(id: String) -> PoiWorld:
	var w := PoiWorld.new()
	w.configure(id, null)
	return w


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
	await super.cleanup()


# --- the plan ----------------------------------------------------------------------------------

func test_quiet_visits_by_danger() -> void:
	var w := _world("convenience")
	var shares := []
	for danger in [0.7, 1.05, 1.4, 2.6]:
		var quiet := 0
		var n := 400
		for k in n:
			var p := w.encounter_plan(danger, 1000 + k)
			if p.is_empty():
				quiet += 1
			for e in p:
				check(e["kind"] in ["psycho", "runner", "brute"], "no bombers at POIs (%s)" % e["kind"])
				check(e["kind"] != "brute" or danger >= 1.3, "brutes only from danger 1.3")
		var share := float(quiet) / n
		shares.append(share)
		check(absf(share - PoiWorld.quiet_share(danger)) < 0.07, "danger %.2f: quiet %.2f (expected about %.2f)" % [danger, share, PoiWorld.quiet_share(danger)])
	check(shares[0] > shares[1] and shares[1] > shares[2] and shares[2] >= shares[3], "low-danger places are quiet more often (%s)" % [shares])
	check(shares[0] >= 0.35 and shares[3] > 0.0, "sometimes genuinely quiet, even at the worst places (%s)" % [shares])
	w.free()


func test_kinds_follow_the_layout() -> void:
	var seen := {}
	var store := _world("convenience")
	for k in 300:
		for e in store.encounter_plan(1.4, k):
			seen[e["mode"]] = true
			match str(e["mode"]):
				"peek":
					check(e.get("look") is Vector2, "a watcher knows where it looks")
					check(float(e["when"]) == 0.0 or e.get("spot") is Vector2, "a watcher who comes later knows its window")
				"enter":
					check(e.get("door") is Vector2 and float(e["when"]) > 0.0, "someone entering comes later, by a doorway")
				"arrive":
					check(float(e["when"]) >= 60.0, "arrivals come later")
	for m in ["hidden", "peek", "enter", "arrive", "wander"]:
		check(seen.has(m), "the store has '%s' encounters (%s)" % [m, seen.keys()])
	store.free()
	var woods := _world("forest")
	for k in 200:
		for e in woods.encounter_plan(1.4, k):
			check(e["mode"] != "peek" and e["mode"] != "hidden", "no windows or rooms to hide in at Pine Woods (%s)" % e["mode"])
	woods.free()
	# a layout without the optional keys keeps working (the old kinds only)
	var bare := _world("homes")
	bare.layout = bare.layout.duplicate()
	bare.layout.erase("peek")
	bare.layout.erase("doorways")
	for k in 200:
		for e in bare.encounter_plan(1.4, k):
			check(e["mode"] in ["hidden", "arrive", "wander"], "without peek/doorways: %s" % e["mode"])
	bare.free()


func test_window_and_doorway_spots_are_sound() -> void:
	for id in PLACES:
		var h: Node = await _harness(id)
		var w: PoiWorld = h.world
		for d in w.layout.get("doorways", []):
			var c: Vector2i = w.nav.cell_of(d)
			check(w.nav.is_walkable(c), "%s: doorway %s stands on open ground" % [id, d])
			check(not h.poi._indoors(d), "%s: doorway %s is outside" % [id, d])
			check(w.inside_of(d) != d and h.poi._indoors(w.inside_of(d)), "%s: doorway %s leads into a room" % [id, d])
		for pk in w.layout.get("peek", []):
			var at: Vector2 = pk["at"]
			var look: Vector2 = pk["look"]
			check(w.nav.is_walkable(w.nav.cell_of(at)), "%s: window spot %s stands on open ground" % [id, at])
			check(not h.poi._indoors(at) and h.poi._indoors(look), "%s: outside %s looking in at %s" % [id, at, look])
			check(h.poi.sees_through_window(at, look, look), "%s: %s sees in through the glass" % [id, at])
			check(not h.poi.can_see(at, look), "%s: but not through the glass by the old line (it is a window, not a gap)" % id)
			var behind := at + (at - look).normalized() * 3.0
			check(not h.poi.sees_through_window(at, look, behind), "%s: nothing behind its back" % id)


# --- behaviour ---------------------------------------------------------------------------------

func test_a_watcher_sees_eli_through_the_window_and_comes_in() -> void:
	var h: Node = await _harness("convenience", Vector2(11.0, 5.5))
	var e: AIEnemy = h.poi._spawn({"kind": "psycho", "at": Vector2(14.75, 6.0), "mode": "peek", "look": Vector2(11.0, 5.5)})
	var w: Dictionary = h.poi.watch.back()
	check(w.has("peek") and e.is_calm() and e.state_name() == "lurk", "it stands at the window (%s)" % e.state_name())
	await physics_frames(150)
	check(e.is_calm(), "still calm: it saw him through the glass, it isn't on him yet")
	check(not w.has("peek") and w.has("route"), "it comes round (%s)" % [w.keys()])
	check(h.toasts.has("A face at the window. It saw you."), "the player is told (%s)" % [h.toasts])
	var legs: Array = w.get("route", [])
	check(not legs.is_empty() and (legs[0]["p"] as Vector2).distance_to(Vector2(7.0, 9.7)) < 0.1 and legs[0]["door"], "by the doorway nearest Eli (%s)" % [legs])
	# out of sight in the office, a new watcher doesn't notice him
	h.player.global_position = Vector3(2.0, 0, 1.4)
	var e2: AIEnemy = h.poi._spawn({"kind": "psycho", "at": Vector2(11.0, 9.75), "mode": "peek", "look": Vector2(11.0, 6.0)})
	var w2: Dictionary = h.poi.watch.back()
	await physics_frames(90)
	check(w2.has("peek") and e2.is_calm(), "nobody in view: it keeps watching")


func test_someone_entering_opens_the_door() -> void:
	var h: Node = await _harness("homes", Vector2(-3.5, -2.5))
	var w: PoiWorld = h.world
	var front: PoiDoor = w.door("front")
	check(front != null and not front.open, "the house's front door is shut")
	var dw: Vector2 = w.layout["doorways"][0]          # Exp 009 (G): the generated house's front doorway
	var e: AIEnemy = h.poi._spawn({"kind": "psycho", "at": dw + Vector2(0, 1.7), "mode": "enter", "door": dw})
	var ok := false
	for i in 50:
		await physics_frames(12)
		if front.open and w.building_rect().has_point(e.plan_pos()):
			ok = true
			break
	check(front.open, "it opened the front door")
	check(ok, "and walked in (%s)" % e.plan_pos())
	check(e.is_calm(), "without noticing Eli behind the building")


func test_noise_brings_arrivals_sooner_and_never_adds_anyone() -> void:
	var h: Node = await _harness("convenience", Vector2(10.2, 1.5))
	var p := {"kind": "runner", "mode": "arrive", "at": Vector2(-6.4, 12.0), "when": h.poi._clock + 150.0}
	h.poi.pending.append(p)
	h.poi.hear(Vector2(10.2, 1.5), 1.0)
	check(float(p["when"]) > h.poi._clock + 100.0 and not p.has("drawn"), "a faint noise changes nothing")
	h.poi.hear(Vector2(10.2, 1.5), 4.0)
	check(float(p["when"]) <= h.poi._clock + 10.0, "gunfire brings it within seconds (%.1f)" % (float(p["when"]) - h.poi._clock))
	check(p.get("drawn") == Vector2(10.2, 1.5), "drawn to the noise")
	check_eq(h.roster.living(), 0, "noise spawned nobody")
	check_eq(h.poi.pending.size(), 1, "and added nobody")
	p["when"] = h.poi._clock
	await physics_frames(4)
	check_eq(h.roster.living(), 1, "the arrival came")
	var w: Dictionary = h.poi.watch.back()
	var legs: Array = w.get("route", [])
	check(legs.size() == 2 and (legs[0]["p"] as Vector2).distance_to(Vector2(6.5, -0.7)) < 0.1 and (legs[1]["p"] as Vector2) == Vector2(10.2, 1.5),
		"by the back door, nearest the noise, then to it (%s)" % [legs])


func test_a_hunter_that_lost_eli_calms_down() -> void:
	var h: Node = await _harness("library", Vector2(15.0, 8.5))
	var e: AIEnemy = h.poi._spawn({"kind": "brute", "at": Vector2(2.0, 2.0), "mode": "hidden"})
	e.provoke("test")
	e.speed_scale = 0.0                       # it can't get to him: stays out of his sight
	check(not e.is_calm() and h.poi.hunters() == 1, "it hunts")
	check(h.poi.save_check() != "", "no saving while it hunts")
	for i in int(GamePoi.LOSE_TIME * 60.0 * 1.4 / 10.0):
		await physics_frames(10)
		if e.is_calm():
			break
	check(e.is_calm() and e.alive, "out of sight and far away for a while, it lost him (%s)" % e.state_name())
	check_eq(h.poi.save_check(), "", "saving works again")


# --- saving and Continue in the real game -------------------------------------------------------

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


func test_save_and_continue_keep_the_encounters() -> void:
	TravelFlow.skip_animation = true
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 9.0 * 60.0
	await g.travel.depart("convenience")
	check(g.left_to != "", "off to the store")
	g.queue_free()
	await frames(2)
	g = await _boot("carry")
	check(not g.is_home() and g.poi != null and g.poi._started, "at the store, the encounters begun")
	# a known situation: whoever the plan brought is gone; a brute waits in the
	# locked stockroom, a psycho in the office, a runner is still out in the fog
	g.debug_kill_enemies()
	await frames(2)
	g.poi.pending.clear()
	var keep: AIEnemy = g.poi._spawn({"kind": "brute", "at": Vector2(11.6, 1.6), "mode": "hidden"})
	var dead: AIEnemy = g.poi._spawn({"kind": "psycho", "at": Vector2(2.8, 2.2), "mode": "hidden"})
	g.poi.pending.append({"kind": "runner", "mode": "arrive", "at": Vector2(-6.4, 12.0), "when": g.poi._clock + 50.0})
	await physics_frames(2)
	dead.kill_quietly()
	await frames(2)
	check(keep.is_calm(), "the brute doesn't know Eli is here")
	check_eq(g.can_save(), "", "calm enemies about don't stop a save")
	keep.provoke("test")
	check(g.can_save().contains("after you"), "one hunting Eli does (%s)" % g.can_save())
	check(g.debug_save() != "", "and the save is refused")
	keep.set_calm_mode("hidden", 5)
	keep.hp = keep.max_hp - 2
	keep.set_facing(1.0)
	await physics_frames(2)
	var at := keep.plan_pos()
	check_eq(g.debug_save(), "", "calm again: saved")
	var enc: Dictionary = g.debug_state().region.poi["convenience"]["visit"]["enc"]
	check_eq((enc["calm"] as Array).size(), 1, "the visit record holds the calm one")
	check_eq((enc["pending"] as Array).size(), 1, "and the arrival still to come")
	var killed: int = g.poi.killed
	check(killed >= 1, "the dead counted (%d)" % killed)
	g.queue_free()
	await frames(2)
	# Continue
	g = await _boot("continue")
	await physics_frames(2)
	check(not g.is_home() and g.site_id() == "convenience", "Continue: at the store")
	check_eq(g.roster.living(), 1, "only the brute: the dead stayed dead, the plan didn't start again")
	var back: AIEnemy = null
	for e in g.roster.enemies:
		if is_instance_valid(e) and e.alive:
			back = e
	if not check(back != null, "the brute is back"):
		return
	check_eq(back.kind, "brute", "a brute")
	check(back.plan_pos().distance_to(at) < 0.4, "where it stood (%s, saved %s)" % [back.plan_pos(), at])
	check_eq(back.hp, back.max_hp - 2, "hurt as it was")
	check(back.is_calm() and back.mind.mode == "hidden", "calm, waiting (%s)" % back.state_name())
	check_eq(g.poi.killed, killed, "the count of the dead came back")
	check_eq(g.poi.pending.size(), 1, "the arrival is still to come")
	var left: float = float(g.poi.pending[0]["when"]) - g.poi._clock
	check(left > 44.0 and left <= 50.5, "with its time left (%.1f s)" % left)
	# the arrivals resume
	g.poi.pending[0]["when"] = g.poi._clock
	await physics_frames(4)
	check_eq(g.roster.living(), 2, "the runner came")
	check(g.roster.living_by_kind().get("runner", 0) == 1, "a runner (%s)" % [g.roster.living_by_kind()])
	# leaving ends the visit, and its encounters with it
	g.leave_site()
	await frames(2)
	check(not (g.debug_state().region.poi["convenience"] as Dictionary).has("visit"), "the visit (and its encounters) ended")
