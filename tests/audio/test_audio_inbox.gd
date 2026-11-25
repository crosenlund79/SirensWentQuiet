extends "res://tests/test_case.gd"
## Experiment 005 (A): the audio inbox. Descriptive file names map to logical
## sounds through AudioInbox.RULES, numbered variants pool, the drop folder
## wins over the first upload, unknown files are reported and never played,
## custom/ > inbox > template, footsteps are sliced into single steps.

var _tmp := ""


func _temp_dir(tag: String) -> String:
	var d := OS.get_user_data_dir().path_join("inbox_test_%s_%d" % [tag, Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _copy(from_res: String, to_file: String) -> void:
	DirAccess.make_dir_recursive_absolute(to_file.get_base_dir())
	var f := FileAccess.open(to_file, FileAccess.WRITE)
	f.store_buffer(FileAccess.get_file_as_bytes(from_res))
	f.close()


func _rmtree(dir: String) -> void:
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_rmtree(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _restore() -> void:
	AudioInbox.roots_override = []
	AudioInbox.reset()
	AssetResolver.set_override_root("")
	Sfx.reset()


func test_file_names_map_through_the_table() -> void:
	var cases := {
		"Footsteps - wood floor.wav": ["player/step_wood", 0],
		"Footsteps - Wood.mp3": ["player/step_wood", 0],          # tolerant: a shorter name, another format
		"footsteps_SNOW_2.ogg": ["player/step_snow", 2],
		"Footsteps - Cement floor.wav": ["player/step_cement", 0],
		"Enemy - Footsteps Snow 3.wav": ["enemy/step_snow", 3],
		"Weapon - Handgun Shot 03.wav": ["weapon/handgun_fire", 3],
		"Weapon - HAndgun Reload 1.wav": ["weapon/reload", 1],
		"Door open 4.wav": ["door/open", 4],
		"Door close 1.wav": ["door/close", 1],
		"Enemy - Heavy impact wood 2.wav": ["door/bash", 2],
		"Enemy - Vocal 1.wav": ["enemy/moan", 1],
		"Destruction - Glass Shatter 1.wav": ["impact/glass", 1],
		"Destruction - Wooden Wall 2.wav": ["structure/break", 2],
		"Building or constructing 3.wav": ["build/hammer", 3],
		"Hammer on metal 1.wav": ["build/upgrade", 1],
		"Nighttime - Owl howling 2.wav": ["ambient/owl", 2],
		"Nighttime - Wolf howl 4.wav": ["ambient/wolf", 4],
		"Wooden house periodic ambiance 1.wav": ["ambient/house_creak", 1],
		"Natural ambiance 3.wav": ["ambient/forest", 3],
		"Fireplace 2.wav": ["ambient/fireplace", 2],
		"Eli - Welcome to a new game.mp3": ["voice/eli_new_game", 0],
		"Eli - Continue saved game.mp3": ["voice/eli_continue", 0],
	}
	for file in cases:
		var m := AudioInbox.match_path("res://x/" + file, "res://x")
		check_eq([m["name"], m["variant"]], cases[file], file)
	# no rule: reported, never assigned
	var unknown := AudioInbox.match_path("res://x/Mystery noise.wav", "res://x")
	check_eq(unknown["name"], "", "an unknown file maps to nothing")
	check(str(unknown["reason"]).contains("no rule"), "with a reason")
	# two rules equally good: ambiguous, never assigned
	var amb := AudioInbox.match_path("res://x/Impact - wood and metal.wav", "res://x")
	check_eq(amb["name"], "", "an ambiguous file maps to nothing")
	check(str(amb["reason"]).begins_with("ambiguous"), "reported as ambiguous (%s)" % amb["reason"])
	# a folder name helps when the file name alone matches nothing
	var theme := AudioInbox.match_path("res://x/Theme/Sirens went quiet - Warmth in the freeze.mp3", "res://x")
	check_eq(theme["name"], "music/menu", "a song in Theme/ is the menu theme")
	check_eq(AudioInbox.split_variant("Weapon - Handgun Shot 01"), ["Weapon - Handgun Shot", 1], "01 is variant 1")
	check_eq(AudioInbox.split_variant("Footsteps - Snow"), ["Footsteps - Snow", 0], "no number, no variant")


func test_the_user_upload_maps_completely() -> void:
	_restore()
	var r := AudioInbox.report()
	var total := 0
	for n in r["mapped"]:
		total += (r["mapped"][n] as Array).size()
	check_eq(total, 64, "every uploaded file is used")
	check_eq((r["unknown"] as Array).size(), 0, "nothing unknown (%s)" % str(r["unknown"]))
	var pools := {"door/open": 4, "door/close": 4, "weapon/handgun_fire": 3, "weapon/reload": 4, "enemy/moan": 4,
		"door/bash": 4, "ambient/owl": 4, "ambient/wolf": 4, "ambient/fireplace": 3, "ambient/forest": 3,
		"player/step_snow": 1, "player/step_wood": 1, "player/step_cement": 1, "music/menu": 1}
	for n in pools:
		check_eq(AudioInbox.files_of(n).size(), pools[n], "%s pool" % n)
	check(AudioInbox.report_text().contains("door/open"), "F10 text lists the mapping")


func test_drop_folder_wins_and_unknown_files_are_reported() -> void:
	var a := _temp_dir("drop")
	var b := _temp_dir("upload")
	_copy("res://assets/audio/door/template_open.ogg", a.path_join("Door open.ogg"))
	_copy("res://assets/audio/door/template_close.ogg", b.path_join("foley/Door open 1.ogg"))
	_copy("res://assets/audio/door/template_close.ogg", b.path_join("foley/Door close 2.ogg"))
	_copy("res://assets/audio/door/template_close.ogg", b.path_join("Strange thing.ogg"))
	var f := FileAccess.open(b.path_join("foley/Hammer on metal 1.wav.import"), FileAccess.WRITE)   # as listed in an export
	f.store_string("[remap]")
	f.close()
	AudioInbox.roots_override = [a, b]
	AudioInbox.reset()
	check(AudioInbox.list_audio_files(b).has(b.path_join("foley/Hammer on metal 1.wav")), ".import suffix stripped when listing")
	check_eq(AudioInbox.files_of("door/open"), PackedStringArray([a.path_join("Door open.ogg")]), "the drop folder provides door/open")
	check_eq(AudioInbox.files_of("door/close").size(), 1, "the upload still provides door/close")
	var reasons := {}
	for u in AudioInbox.report()["unknown"]:
		reasons[(u["path"] as String).get_file()] = u["reason"]
	check(reasons.has("Strange thing.ogg"), "unknown file reported")
	check(str(reasons.get("Door open 1.ogg", "")).begins_with("shadowed"), "the upload's door/open reported as shadowed")
	# a file loaded straight from disk (not imported) plays through Sfx
	var c := Sfx.clip("door/open")
	check(c.get("source") == "inbox" and c.get("stream") is AudioStreamOggVorbis, "inbox clip from a dropped file")
	_restore()
	_rmtree(a)
	_rmtree(b)


func test_custom_beats_inbox_beats_template() -> void:
	_restore()
	check_eq(Sfx.source_of("door/open"), "inbox", "door/open from the inbox")
	check_eq(Sfx.source_of("impact/wood"), "template", "impact/wood still the template")
	check_eq(Sfx.source_of("ambient/room_tone"), "", "no room tone recorded yet")
	check(not Sfx.available("ambient/room_tone"), "so it is unavailable")
	check_eq(Sfx.source_of("player/footstep_2"), "inbox", "the old footstep group borrows the wooden steps")
	var c := Sfx.clip("weapon/handgun_fire")
	check(float(c["from"]) > 0.5, "the shot's leading silence is skipped (%.2f s)" % c["from"])
	var root := _temp_dir("custom")
	DirAccess.make_dir_recursive_absolute(root.path_join("audio/door"))
	_copy("res://assets/audio/door/template_close.ogg", root.path_join("audio/door/open.ogg"))
	AssetResolver.set_override_root(root)
	Sfx.reset()
	check_eq(Sfx.source_of("door/open"), "custom", "custom/ wins over the inbox")
	var cc := Sfx.clip("door/open")
	check(cc.get("source") == "custom" and (cc["stream"] as AudioStream).resource_path == "", "the custom file plays")
	_restore()
	_rmtree(root)


func test_footstep_recordings_are_sliced_into_single_steps() -> void:
	_restore()
	for n in ["player/step_wood", "player/step_snow", "player/step_cement", "enemy/step_snow"]:
		var clips := AudioInbox.clips_of(n)
		check(clips.size() >= 3, "%s: several steps from the recordings (%d)" % [n, clips.size()])
		for c in clips:
			var len := float(c["to"]) - float(c["from"])
			check(len >= AudioAnalysis.MIN_STEP and len <= AudioAnalysis.MAX_STEP + 0.01, "%s step length %.2f s" % [n, len])
			check(float(c["to"]) <= (c["stream"] as AudioStream).get_length() + 0.01, "inside the file")
			check(absf(float(c["db"])) <= AudioInbox.GAIN_RANGE.y, "gain within range")


func test_analysis_trims_and_slices_a_synthetic_envelope() -> void:
	var env := PackedFloat32Array()
	var w := 0.005
	for i in 600:                       # 3 s: noise, then three steps 0.7 s apart
		var t := i * w
		var v := 0.0005
		for s in [0.5, 1.2, 1.9]:
			if t >= s and t < s + 0.15:
				v = 0.2 * exp(-(t - s) * 20.0)
		env.append(v)
	var a := AudioAnalysis.analyse_envelope(env, w, true)
	check_eq((a["steps"] as Array).size(), 3, "three steps found")
	check(absf(float(a["start"]) - 0.5) < 0.03, "start at the first sound (%.3f)" % a["start"])
	for k in (a["steps"] as Array).size():
		var s: Array = a["steps"][k]
		check(absf(float(s[0]) - [0.5, 1.2, 1.9][k]) < 0.03, "onset %d at %.3f" % [k, s[0]])
		check(float(s[1]) - float(s[0]) < 0.4, "short window")


func test_loops_are_set_in_code_on_copies() -> void:
	_restore()
	var theme := AudioInbox.load_stream(AudioInbox.files_of("music/menu")[0])
	check(not AudioInbox.is_looping(theme), "the imported theme itself is a one-shot")
	check(AudioInbox.is_looping(AudioInbox.looped(theme)), "the music copy loops")
	var wav := AudioInbox.load_stream(AudioInbox.files_of("ambient/forest")[0]) as AudioStreamWAV
	var lw := AudioInbox.looped(wav) as AudioStreamWAV
	check(lw.loop_mode == AudioStreamWAV.LOOP_FORWARD and lw.loop_end > 0, "a WAV copy loops forward")
	check(wav.loop_mode == AudioStreamWAV.LOOP_DISABLED, "the original stays one-shot")
	var m := Sfx.clip("music/menu")
	check(AudioInbox.is_looping(m["stream"]), "the menu theme loops")
