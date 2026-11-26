extends "res://tests/test_case.gd"
## Experiment 012 (A), ASSIGNMENT §8: the user's story recordings (the
## visitor's voice lines and his followers) never reach a generic pool:
## psycho voices, the menu siege, ambience beds, random pools. Runs the real
## discovery over the real inbox, an export-style listing (only ".import"
## names, as an exported game lists res://) and tricky names, and checks
## that story audio stops on menu return and load.
##
## Root cause (before Exp 011's guard): the inbox matched file names word by
## word. "... human heavy breathing" and "... banging on tin trash can" hit
## door/bash ("heavy", "bang"); "... bat hammers door" hit build/hammer; and
## "... Wakey wakey sunshine - ... with this enemy" in voice/ hit enemy/moan
## ("enemy" in the name + the folder word "voice"). The menu siege plays
## enemy/moan and door/bash all the time, so the main menu played them.

const STORY_WORD := "architect"

var _tmp := ""


func _temp_dir(tag: String) -> String:
	var d := OS.get_user_data_dir().path_join("leak_test_%s_%d" % [tag, Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _touch(file: String, text := "[remap]") -> void:
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	var f := FileAccess.open(file, FileAccess.WRITE)
	f.store_string(text)
	f.close()


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
	Sfx.reset()


func _bad(path: String) -> bool:
	return STORY_WORD in path.to_lower() or "/story/" in path.to_lower()


## The real inbox: every story file is held back, none is in any pool, no
## pool is a story/* name, and every clip any generic name can play is clean.
func test_real_inbox_pools_never_hold_story_files() -> void:
	_restore()
	var story_on_disk := []
	for root in AudioInbox.ROOTS:
		for p in AudioInbox.list_audio_files(root):
			if STORY_WORD in p.to_lower():
				story_on_disk.append(p)
	check(story_on_disk.size() >= 23, "the user's story recordings are in the inbox (%d)" % story_on_disk.size())
	var reserved := AudioInbox.reserved_files()
	for p in story_on_disk:
		check(reserved.has(p), "reserved: %s" % p.get_file())
	for n in AudioInbox.names():
		check(not AudioInbox.is_story_name(n), "no generic pool is a story name (%s)" % n)
		for p in AudioInbox.files_of(n):
			check(not _bad(p), "%s holds no story file (%s)" % [n, p.get_file()])
	# every name the game can play, many times (random picks): never a story file
	var names := Sfx.all_names()
	for n in names:
		for i in 6:
			var c := Sfx.clip(n)
			check(not _bad(str(c.get("path", ""))), "Sfx.clip(%s) never draws a story file" % n)
	check_eq(AudioInbox.refused, 0, "nothing even reached the play-time refusal")
	# the story namespace is never a generic pool, even by alias or group
	for n in ["story/architect_wakey", "story/follower_bark", "story/follower_bat_1"]:
		check_eq(AudioInbox.pool_name(n), "", "%s is no inbox pool" % n)
		check(Sfx.clip(n).is_empty(), "Sfx plays nothing for %s" % n)
	_restore()


## Without the guard the same names land in the pools the main menu plays:
## the proof of the cause (and that the guard is what stops it).
func test_without_the_guard_the_menu_pools_would_take_them() -> void:
	var root := "res://assets/audio/_inbox"
	var want := {
		"voice/The Architect - Wakey wakey sunshine - for first encounter (scripted) with this enemy.mp3": "enemy/moan",
		"Architect followers - human heavy breathing 1.wav": "door/bash",
		"Architect followers - banging on tin trash can 2.wav": "door/bash",
		"Architect followers - basebal bat hammers door (must be aligned with actual sound) 3.wav": "build/hammer",
	}
	for f in want:
		var path: String = root.path_join(f)
		check_eq(AudioInbox.match_path(path, root, false)["name"], want[f], "unguarded: %s" % f.get_file())
		check_eq(AudioInbox.match_path(path, root)["name"], "", "guarded: %s" % f.get_file())
	# what the menu siege plays: enemy/moan (enemies) and door/bash (wall strikes)
	for n in ["enemy/moan", "door/bash", "build/hammer"]:
		for p in AudioInbox.files_of(n):
			check(not _bad(p), "%s is clean now (%s)" % [n, p.get_file()])


## An exported game lists only "X.wav.import" / "X.mp3.import" in res://.
## The same guard holds on such a listing, and on names that dodge a
## word-start match ("TheArchitect"), story folders, and plain names inside
## a story folder that would otherwise match a rule ("Heavy breathing").
func test_export_style_listing_and_tricky_names() -> void:
	var d := _temp_dir("export")
	for f in [
		"Architect followers - human heavy breathing 1.wav.import",
		"Architect followers - human bark like a dog 2.wav.remap",
		"voice/The Architect - Wakey wakey sunshine - for first encounter (scripted) with this enemy.mp3.import",
		"voice/TheArchitect enemy voice 1.wav.import",
		"The Architect/Heavy breathing 2.wav.import",
		"story/Enemy - Vocal 7.wav.import",
		"foley/Enemy - Vocal 1.wav.import",
		"foley/Enemy - Heavy impact wood 1.wav.import",
	]:
		_touch(d.path_join(f))
	AudioInbox.roots_override = [d]
	AudioInbox.reset()
	var listed := AudioInbox.list_audio_files(d)
	check_eq(listed.size(), 8, "the export listing is read (suffixes stripped): %s" % str(listed))
	check_eq(AudioInbox.files_of("enemy/moan"), PackedStringArray([d.path_join("foley/Enemy - Vocal 1.wav")]), "only the real enemy vocal pools")
	check_eq(AudioInbox.files_of("door/bash"), PackedStringArray([d.path_join("foley/Enemy - Heavy impact wood 1.wav")]), "only the real impact pools")
	check_eq(AudioInbox.reserved_files().size(), 6, "six story files held back")
	for n in AudioInbox.names():
		for p in AudioInbox.files_of(n):
			check(not _bad(p), "%s holds no story file" % n)
	_restore()
	_rmtree(d)


## Play-time refusal: even a pool that somehow holds a story file (a future
## rule, a hand-made pool) never hands it out.
func test_clip_refuses_a_story_file_at_play_time() -> void:
	var d := _temp_dir("refuse")
	_copy("res://assets/audio/door/template_open.ogg", d.path_join("Door open 1.ogg"))
	AudioInbox.roots_override = [d]
	AudioInbox.reset()
	check(not AudioInbox.clip("door/open").is_empty(), "a clean pool plays")
	# poison the pool's clip as a stand-in for a future mistake
	var clips: Array = AudioInbox.clips_of("door/open")
	clips[0]["path"] = d.path_join("architect/Door open 1.ogg")
	check(AudioInbox.clip("door/open").is_empty(), "a story path is refused at play time")
	check_eq(AudioInbox.refused, 1, "and counted")
	_restore()
	_rmtree(d)


## Story audio stops on menu return and load: StoryAudioGuard stops every
## player in the "story_audio" group and frees the ones that would outlive
## a scene change; the main menu and the game call it in _ready.
func test_story_audio_stops_on_menu_and_load() -> void:
	var gen := AudioStreamGenerator.new()
	var loose := AudioStreamPlayer.new()          # under the root: outlives scenes
	loose.stream = gen
	loose.add_to_group(StoryAudioGuard.GROUP)
	tree.root.add_child(loose)
	loose.play()
	var scene: Node3D = add(Node3D.new())         # stands in for the game scene
	var holder := Node3D.new()                    # a scene node holding a 3D voice
	holder.add_to_group(StoryAudioGuard.GROUP)
	scene.add_child(holder)
	var p3 := AudioStreamPlayer3D.new()
	p3.stream = gen
	holder.add_child(p3)
	p3.play()
	await frames(1)
	check_eq(StoryAudioGuard.playing_count(tree), 2, "two story players playing")
	check_eq(StoryAudioGuard.stop_all(tree), 2, "both stopped")
	await frames(1)
	check(not is_instance_valid(loose), "the root-level one is freed")
	check(is_instance_valid(holder) and not p3.playing, "the scene's one is stopped (the scene frees it)")
	check_eq(StoryAudioGuard.playing_count(tree), 0, "nothing left playing")
	for path in ["res://src/menu/main_menu.gd", "res://src/game/survival_game.gd"]:
		check(FileAccess.get_file_as_string(path).contains("StoryAudioGuard.stop_all("), "%s stops story audio in _ready" % path.get_file())
