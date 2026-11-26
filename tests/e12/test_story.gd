extends "res://tests/test_case.gd"
## Exp 012 (S): Chapter One, "Someone Is Watching". The story state and its
## save round trip, the scheduling (later encounters after longer gaps), each
## encounter run to its end in the real game (fast-forwarded) with control
## returned, previews that change nothing, the four ropes (exactly 4 in,
## exactly 4 burned, kept without a fire, a pile when the inventory is full),
## the sleep hook, the watcher, the door jolts in sync and the story audio
## mapping.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_e12_story.dat"
const FAST := 80.0


func _boot() -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = "new"
	GameLaunch.seed = 1212
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	g.story.speed = FAST
	return g


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()


func _control_back(g: Node, ctx: String) -> void:
	check_eq(g.debug_modal(), "", "%s: no modal left" % ctx)
	check(g.player.input_enabled, "%s: input back" % ctx)
	check(g.hud.visible, "%s: the HUD back" % ctx)
	check(g.player.rig.visible, "%s: Eli's own figure back" % ctx)
	check(not g.story.stage.active, "%s: the stage is cleared" % ctx)
	check(g.story.audio.playing_count(false) == 0 and g.story.audio.playing_count(true) == 0, "%s: story audio stopped" % ctx)
	check(g.ui.fade.alpha() < 0.01, "%s: the screen is back" % ctx)


func test_state_defaults_round_trip_and_old_saves() -> void:
	var s := GameState.new_run(5)
	var c := StoryState.ch1(s)
	check_eq(c["next"], 1, "starts at encounter 1")
	var day := int(floorf(float(c["next_at"]) / 1440.0)) + 1
	check(day >= 2 and day <= 3 and is_equal_approx(fposmod(float(c["next_at"]), 1440.0), 1200.0), "the first is eligible on a night of days 2-4 (day %d)" % day)
	check(not StoryState.architect_introduced(s) and not StoryState.siege_eligible(s), "not introduced, no siege")
	var gaps := []
	var last := float(c["next_at"])
	for n in [1, 2, 3]:
		s.total_minutes = float(StoryState.ch1(s)["next_at"]) + 300.0
		StoryState.complete(s, n)
		var nx := float(StoryState.ch1(s)["next_at"])
		gaps.append((nx - s.total_minutes) / 1440.0)
		check(nx > s.total_minutes, "encounter %d schedules the next later" % (n + 1))
	check(gaps[0] >= 2.0 and gaps[0] <= 6.5 and gaps[1] >= 4.0 and gaps[1] <= 9.5 and gaps[2] >= 6.0 and gaps[2] <= 12.5,
		"progressively longer randomised gaps (%s days)" % [gaps])
	check(StoryState.architect_introduced(s), "introduced after 1")
	s.total_minutes += 10.0
	StoryState.complete(s, 4)
	var c4 := StoryState.ch1(s)
	check_eq(c4["next"], StoryState.FINISHED, "the chapter is finished")
	check(float(c4["siege_at"]) > s.total_minutes and float(c4["siege_at"]) <= s.total_minutes + 3.0 * 1440.0, "the siege waits 1-3 days")
	check(not StoryState.siege_eligible(s), "not yet")
	s.total_minutes = float(c4["siege_at"]) + 1.0
	check(StoryState.siege_eligible(s), "then eligible")
	StoryState.note_siege(s)
	check(int(StoryState.ch1(s)["sieges"]) == 1 and not StoryState.siege_eligible(s), "a siege is recorded and the next waits")
	c4["rope"] = "burned"
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(JSON.stringify(back.story), JSON.stringify(StoryState.clean(s.story)), "the story survives a save round trip")
	check_eq(StoryState.ch1(back)["rope"], "burned", "the rope decision persists")
	var old := s.to_dict()
	old.erase("story")
	var o := GameState.from_dict(old)
	check(o != null and StoryState.ch1(o)["done"].is_empty() and int(StoryState.ch1(o)["next"]) == 1, "an old save starts the chapter fresh")
	var junk := StoryState.clean({"ch1": {"done": [9, "x", 2, 2, 1], "next": -4, "next_at": NAN, "rope": "eaten", "ropes": 99}})
	check(junk["ch1"]["done"] == [1, 2] and int(junk["ch1"]["next"]) == 3 and junk["ch1"]["rope"] == "" and int(junk["ch1"]["ropes"]) == 4,
		"junk is cleaned (%s)" % [junk])
	StoryState.reset(s)
	check(StoryState.ch1(s)["done"].is_empty(), "reset: only this chapter starts over")


func test_story_audio_mapping_and_door_data() -> void:
	StoryAudio.scan(true)
	for n in StoryLines.VOICE_FILES:
		check(StoryAudio.has_recording(n), "%s has its recording" % n)
	for n in StoryAudio.FOLLOWERS:
		check(StoryAudio.variants(n) >= 3, "%s has its variants (%d)" % [n, StoryAudio.variants(n)])
	check(not StoryAudio.has_recording("story/architect_warning_01"), "the warning lines are slots (no recording yet)")
	for id in StoryLines.CUES:
		var c: Dictionary = StoryLines.CUES[id]
		var files := StoryAudio.files_of(c["name"])
		if files.is_empty():
			continue
		var len := StoryAudio.stream_of(files[0]).get_length()
		check(float(c["from"]) >= 0.0 and float(c["from"]) < len and (float(c["to"]) < 0.0 or float(c["to"]) <= len + 0.01), "cue %s lies inside its recording" % id)
	# the stored door impacts match what the recordings say
	var bats := StoryAudio.files_of("story/follower_bat")
	for i in bats.size():
		var stored: Array = StoryAudio.onsets_of(i).filter(func(o): return float(o[1]) >= 1.0).map(func(o): return float(o[0]))
		var found: Array = StoryAudio.impact_onsets(StoryAudio.stream_of(bats[i]))
		var miss := 0
		for t in stored:
			if not found.any(func(f): return absf(float(f) - float(t)) < 0.06):
				miss += 1
		check(stored.size() >= 3 and miss == 0, "bat %d: %d stored blows all found in the recording" % [i + 1, stored.size()])


func test_encounters_run_to_the_end_and_return_control() -> void:
	var g := await _boot()
	var s: GameState = g.debug_state()
	var st: StoryDirector = g.story
	s.total_minutes = 2 * 1440.0 + 23.0 * 60.0
	var inv0 := JSON.stringify(s.inventory.to_dict())
	s.run["next_invasion_at"] = 30 * 1440.0
	for n in [1, 3]:
		g.debug_kill_enemies()
		var r: String = await st.trigger(n)
		check(r.contains("done"), "trigger %d: %s" % [n, r])
		check(StoryState.is_done(s, n), "encounter %d recorded" % n)
		_control_back(g, "encounter %d" % n)
	check(st.overlay.said.has("Wakey, wakey, sunshine.") and st.overlay.said.has("Night nighty.") and st.overlay.said.has("What the fuck just happened?"),
		"the Visitor's lines and Eli's thoughts were shown")
	check(st.overlay.said.has("They can become terribly inconvenient.") and st.overlay.said.has("Well, I think that's enough for tonight."), "the Warning's lines")
	check_eq(JSON.stringify(s.inventory.to_dict()), inv0, "no items from 1 and 3")
	var jolts0: int = st.stage.jolts
	var r4: String = await st.trigger(4)
	check(r4.contains("done") and StoryState.is_done(s, 4), "encounter 4: " + r4)
	check(st.stage.jolts - jolts0 >= 8, "the door jolted on the bat blows (%d)" % (st.stage.jolts - jolts0))
	check(st.audio.history.has("silence"), "the coordinated silence happened")
	check(st.overlay.said.has("I've asked them to leave you alone.") and st.overlay.said.has("While you still can."), "his speech")
	_control_back(g, "encounter 4")
	check_eq(s.inventory.count("rope"), 4, "exactly four ropes")
	check(st.ropes_pending(), "the choice waits")
	check(float(StoryState.ch1(s)["siege_at"]) > s.total_minutes, "the first siege is scheduled")
	await frames(40)
	check(st.overlay.choice_visible(), "the keep / burn card shows")
	var r5: String = await st.trigger(4)
	check_eq(s.inventory.count("rope"), 4, "a second night while the choice waits gives no more ropes (%s)" % r5)


func test_previews_change_nothing() -> void:
	var g := await _boot()
	var s: GameState = g.debug_state()
	var st: StoryDirector = g.story
	g.time_scale = 0.0                 # the clock stands still between the previews too
	await frames(2)
	var before := JSON.stringify(s.to_dict())
	var house := JSON.stringify(g.world.save_data())
	for n in [1, 3, 4]:
		var r: String = await st.preview_encounter(n)
		check(r.contains("previewed"), r)
		_control_back(g, "preview %d" % n)
	var rb: String = await st.burn_ropes(true)
	check(rb.contains("previewed"), rb)
	_control_back(g, "preview burning")
	check_eq(JSON.stringify(s.to_dict()), before, "the state (story, inventory, clock) is unchanged")
	check_eq(JSON.stringify(g.world.save_data()), house, "the house is unchanged")
	check(s.inventory.count("rope") == 0 and not st.ropes_pending(), "no ropes from a preview")


func test_ropes_burn_keep_no_fire_and_full_inventory() -> void:
	var g := await _boot()
	var s: GameState = g.debug_state()
	var st: StoryDirector = g.story
	await st.trigger(4)
	check_eq(s.inventory.count("rope"), 4, "four ropes")
	g.home.fireplace.set_lit(false)
	check(st.burn_block_reason().contains("fire is out"), "no fire: can't burn (%s)" % st.burn_block_reason())
	var r0: String = await st.burn_ropes()
	check(s.inventory.count("rope") == 4 and st.ropes_pending(), "no fire: he keeps them (%s)" % r0)
	g.home.fireplace.set_lit(true)
	s.inventory.add("rope", 3)          # a few from elsewhere: only the four go
	check_eq(st.burn_block_reason(), "", "lit and reachable: he can burn them")
	var r: String = await st.burn_ropes()
	check(r == "The ropes burn.", r)
	check_eq(s.inventory.count("rope"), 3, "exactly four burned")
	check_eq(StoryState.ch1(s)["rope"], "burned", "the decision is saved")
	var fp: Vector2 = st.fire_stand()
	check(g.player.plan_pos().distance_to(fp) < 0.6, "he walked to the fireplace (%s)" % g.player.plan_pos())
	_control_back(g, "burning")
	# full inventory: the rest goes into a pile by the bed; keep
	StoryState.reset(s)
	s.inventory.counts["rope"] = s.inventory.cap("rope") - 1
	var held: int = s.inventory.count("rope")
	await st.trigger(4)
	check_eq(s.inventory.count("rope"), held + 1, "one fits")
	var pile: WorldObject = st._pile()
	check(pile != null and int(pile.items.get("rope", 0)) == 3, "three in a pile by the bed")
	check_eq(st.ropes_available() - held, 4, "nothing is lost")
	st.keep_ropes()
	check(StoryState.ch1(s)["rope"] == "kept" and not st.ropes_pending(), "kept")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(back.inventory.count("rope") == held + 1 and StoryState.ch1(back)["rope"] == "kept", "save and load: no duplicates, no loss")


func test_the_sleep_hook_runs_the_visitor_at_night() -> void:
	var g := await _boot()
	var s: GameState = g.debug_state()
	var st: StoryDirector = g.story
	s.total_minutes = 2 * 1440.0 + 22.5 * 60.0          # day 3, 22:30
	s.run["next_invasion_at"] = 9 * 1440.0 + 22.0 * 60.0   # no invasion tonight
	StoryState.make_eligible_now(s)
	s.energy = 20.0
	var due: float = st.encounter_time(s.until_morning_minutes())
	check(due > s.total_minutes and fposmod(due, 1440.0) >= 40.0 and fposmod(due, 1440.0) <= 240.0, "tonight, in the small hours")
	g.debug_teleport_player(Vector2(2.0, 2.7))
	var plan: Dictionary = await g.debug_sleep(-1)
	check(StoryState.is_done(s, 1), "the Visitor came in the night")
	check(fposmod(s.total_minutes, 1440.0) >= 5.9 * 60.0 and fposmod(s.total_minutes, 1440.0) < 7.0 * 60.0, "he wakes in the morning (%s)" % s.clock_text())
	check(not plan.is_empty(), "the sleep plan comes back")
	_control_back(g, "the night")
	check(g.autosave_log.has("wake"), "saved on waking")
	check(not st.takes_sleep(s.until_morning_minutes()), "the next one isn't due tonight")


func test_the_watcher_appears_watches_and_walks_away() -> void:
	var g := await _boot()
	var s: GameState = g.debug_state()
	var st: StoryDirector = g.story
	StoryState.complete(s, 1)
	s.total_minutes = float(StoryState.ch1(s)["next_at"]) + 3.5 * 60.0
	s.run["next_invasion_at"] = s.total_minutes + 5000.0
	g.debug_teleport_player(Vector2(5.0, 10.5))
	await frames(2)
	check(st.observer_due(), "due at dusk, awake at home")
	await frames(160)
	var f: StoryFigure = st.figure
	if not check(f != null, "he appears"):
		return
	var out: float = -FogBoundary.edge_distance(f.plan_pos())
	check(out > 0.5, "beyond the lot edge (%.1f m out)" % out)
	check(f.find_children("*", "AudioStreamPlayer3D", true, false).is_empty() and f.find_children("*", "AudioStreamPlayer", true, false).is_empty()
		and not f in g.roster.enemies, "not an enemy, silent himself")
	st._obs["seen"] = 2.0
	await frames(10)
	check(st.overlay.said.has("That's him..."), "Eli knows him")
	var pos0 := f.global_position
	# Eli walks up to him: he turns and walks calmly away
	var toward: Vector2 = f.plan_pos() + (Vector2(7.0, 4.5) - f.plan_pos()).normalized() * 3.0
	g.debug_teleport_player(toward)
	await frames(30)
	check_eq(f.mode, "leave", "approached, he leaves")
	await frames(330)
	check(is_instance_valid(f) and st.figure == f, "still there while he walks (never vanishes in plain sight)")
	var walked: float = f.walked if is_instance_valid(f) else 0.0
	check(walked > 0.3 and walked < 7.0, "walking calmly away (%.1f m)" % walked)
	f.global_position = Vector3(f.exit_at.x, 0.0, f.exit_at.z)
	await frames(5)
	check(st.figure == null, "gone once deep in the fog")
	check(StoryState.is_done(s, 2), "encounter 2 recorded")
