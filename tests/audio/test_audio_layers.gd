extends "res://tests/test_case.gd"
## Experiment 005 (A): layered ambience (outside / inside / basement mix, the
## fireplace bed only while lit, details), Eli's voice (no overlap, ducking)
## and gait-synced, surface-aware footsteps.

const Footsteps := preload("res://src/game/footsteps.gd")


func _ambience() -> Ambience:
	Sfx.reset()
	var root := add(Node3D.new())
	Sfx.attach(root)
	var a := Ambience.new()
	root.add_child(a)
	return a


func _settle(a: Ambience, seconds := 8.0) -> void:
	for i in int(seconds / 0.25):
		a._step_layers(0.25)
		for b in a.beds.values():
			(b as AmbienceBed).step(0.25)


func test_place_sets_the_outdoor_mix() -> void:
	var a := _ambience()
	await frames(1)
	_settle(a)
	check(absf(AudioMix.outdoor_volume_db()) < 0.1, "outside: outdoor at full level")
	check(AudioMix.outdoor_cutoff() >= AudioMix.OPEN_CUTOFF - 1.0, "outside: no filter")
	a.set_place("inside")
	a._step_layers(0.1)
	check(AudioMix.outdoor_volume_db() > -9.0 and AudioMix.outdoor_volume_db() < 0.0, "a glide, not a jump")
	_settle(a)
	check(absf(AudioMix.outdoor_volume_db() - Ambience.PLACES["inside"]["outdoor_db"]) < 0.2, "inside: outdoor quieter")
	check(AudioMix.outdoor_cutoff() < 1600.0, "inside: muffled (%.0f Hz)" % AudioMix.outdoor_cutoff())
	a.set_place("basement")
	_settle(a)
	check(AudioMix.outdoor_volume_db() < -17.0 and AudioMix.outdoor_cutoff() < 600.0, "basement: further muffled")
	a.set_tension(1.0)
	_settle(a, 4.0)
	check(AudioMix.outdoor_volume_db() < Ambience.PLACES["basement"]["outdoor_db"] - 2.0, "the outdoor beds dip during an invasion")
	check(a.beds["forest"].available(), "the recorded forest bed is mapped")
	check(a.beds["forest"].playing(), "the forest bed plays")
	a.set_layer("outdoor", false)
	_settle(a)
	check(not a.beds["forest"].playing(), "outdoor layer off: forest bed stops")
	a.set_layer("outdoor", true)
	a.get_parent().remove_child(a)
	check(AudioMix.outdoor_cutoff() >= AudioMix.OPEN_CUTOFF - 1.0 and absf(AudioMix.outdoor_volume_db()) < 0.1, "leaving the game resets the Outdoor bus")
	a.free()


func test_fireplace_bed_only_while_lit() -> void:
	var a := _ambience()
	var hearth := Node3D.new()
	a.get_parent().add_child(hearth)
	hearth.global_position = Vector3(1.1, 0, 4.55)
	await frames(1)
	a.set_fireplace(hearth, true, true)
	_settle(a, 2.0)
	var fire: AmbienceBed = a.beds["fire"]
	check(fire.playing(), "lit: the fire crackles")
	check(fire.positional, "positional")
	var p := fire.get_child(0) as AudioStreamPlayer3D
	check(p != null and p.global_position.distance_to(hearth.global_position) < 1.0, "at the hearth")
	a.set_fireplace(hearth, false, true)
	_settle(a, 8.0)
	check(not fire.playing(), "out: silent")
	a.set_fireplace(hearth, true, false)
	_settle(a, 8.0)
	check(fire.playing() and fire.level() < 0.5, "from another storey: quieter (%.2f)" % fire.level())


func test_details_need_their_conditions() -> void:
	var a := _ambience()
	await frames(1)
	check(a.play_detail("owl"), "an owl recording exists")
	check(a.play_detail("creak"), "a creak recording exists")
	check_eq(Sfx.active_count("ambient/owl"), 1, "the owl plays")
	var before: int = a.details_played["wolf"]
	a.set_night_amount(0.0)
	a._next_detail["wolf"] = 0.0
	a._step_details(0.1)
	check_eq(a.details_played["wolf"], before, "no wolves by day")
	a.set_night_amount(1.0)
	a._next_detail["wolf"] = 0.0
	a._step_details(0.1)
	check_eq(a.details_played["wolf"], before + 1, "a wolf at night")
	a.set_tension(1.0)
	a._next_detail["wolf"] = 0.0
	a._step_details(0.1)
	check_eq(a.details_played["wolf"], before + 1, "the animals fall silent during an invasion")


func test_voice_never_overlaps_and_ducks() -> void:
	Sfx.reset()
	Voice.stop()
	await seconds(0.1)
	AudioMix.duck(0.0, 0.0)
	check(Voice.say("voice/eli_new_game"), "the welcome plays")
	check(Voice.speaking(), "speaking")
	check(not Voice.say("voice/eli_continue"), "a second line does not overlap")
	check_eq(Voice.last_line, "voice/eli_new_game", "the first line kept")
	await seconds(0.6)
	check(AudioMix.duck_db() < -5.0, "ambience and music ducked (%.1f dB)" % AudioMix.duck_db())
	var bus := AudioServer.get_bus_index("Voice")
	check(bus >= 0, "a Voice bus exists")
	Voice.stop()
	await seconds(1.4)
	check(absf(AudioMix.duck_db()) < 0.1, "the duck lifts after the line")
	check(not Voice.say("voice/nobody"), "unknown line: nothing")


func test_gait_and_surface_drive_the_steps() -> void:
	var f := Footsteps.new()
	var steps := 0
	var phase := 0.0
	for i in 120:                       # 2 s at 60 fps, phase speed 2 PI per second
		phase += TAU / 60.0
		if f.gait(phase, 2.0):
			steps += 1
	check_eq(steps, 4, "two steps per gait cycle")
	for i in 30:
		phase += TAU / 60.0
		check(not f.gait(phase, 0.0), "standing: no steps")
	check_eq(Footsteps.surface(0, Vector2(9.0, 11.2)), "snow", "the yard is snow")
	check_eq(Footsteps.surface(0, Vector2(6.0, 8.2)), "wood", "the living room is wood")
	check_eq(Footsteps.surface(0, Vector2(12.0, 6.5)), "cement", "the utility room is concrete")
	check_eq(Footsteps.surface(-1, Vector2(3.0, 3.0)), "cement", "the basement is cement")
	check_eq(Footsteps.surface(1, Vector2(3.0, 3.0)), "wood", "the upper floor is wood")
	check_eq(Footsteps.sound_for("snow"), "player/step_snow", "the inbox snow steps")
	var c := Sfx.clip("player/step_snow")
	check(float(c["to"]) - float(c["from"]) <= AudioAnalysis.MAX_STEP + 0.01, "one short step, not the recording")
