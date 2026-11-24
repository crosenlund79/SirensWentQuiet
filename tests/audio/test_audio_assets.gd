extends "res://tests/test_case.gd"
## Template sounds: every SPEC §7.6 name (and our additions) resolves to a
## decodable stream, variants resolve, loops loop, sizes stay in budget.

const SPEC_NAMES := [
	"player/footstep_1", "player/footstep_2", "player/footstep_3", "player/footstep_4",
	"player/hurt", "player/eat", "player/drink", "player/bandage", "player/sleep", "player/death",
	"weapon/handgun_fire", "weapon/dry_fire",
	"impact/wood", "impact/plaster", "impact/glass", "impact/metal", "impact/flesh", "impact/ground",
	"build/place", "build/hammer", "build/demolish", "build/invalid", "build/upgrade",
	"door/open", "door/close", "door/bash", "structure/break", "structure/crumble",
	"enemy/moan_1", "enemy/moan_2", "enemy/attack", "enemy/hit", "enemy/death",
	"ambient/wind_day", "ambient/night", "ambient/distant_1", "ambient/distant_2", "ambient/distant_3",
	"ui/click", "ui/hover", "ui/open", "ui/close", "ui/error",
	"stinger/invasion", "stinger/dawn",
	"music/menu",
	# Experiment 003
	"weapon/shotgun_fire", "weapon/reload", "weapon/reload_done", "weapon/shell_load", "weapon/switch",
	"enemy/bomber_fuse", "enemy/bomber_blast", "structure/blast",
]
const LOOPS := ["ambient/wind_day", "ambient/night", "ambient/tension", "music/menu"]
const BUDGET_BYTES := 6 * 1024 * 1024


func _check_stream(name: String) -> void:
	var s := AssetResolver.get_audio(name)
	if not check(s != null, "%s resolves" % name):
		return
	check(s is AudioStreamOggVorbis, "%s is Ogg Vorbis" % name)
	check(s.resource_path == AssetResolver.audio_fallback_path(name), "%s uses the packaged template" % name)
	check(s.get_length() > 0.02, "%s has a length" % name)
	check(s.instantiate_playback() != null, "%s decodes" % name)


func test_every_spec_name_resolves_to_a_decodable_stream() -> void:
	var listed := Sfx.names()
	for name in SPEC_NAMES:
		check(listed.has(name), "%s is in Sfx.names()" % name)
		_check_stream(name)


func test_every_listed_name_resolves() -> void:
	var listed := Sfx.names()
	check(listed.size() >= SPEC_NAMES.size() + 1, "names() covers the SPEC plus additions")
	check(listed.has("ambient/tension"), "tension drone added")
	for name in listed:
		_check_stream(name)


func test_variants_resolve() -> void:
	var groups := {"player/footstep": 4, "enemy/moan": 2, "ambient/distant": 3}
	for g in groups:
		var v := Sfx.variants(g)
		check_eq(v.size(), groups[g], "%s variant count" % g)
		check(Sfx.has(g), "%s group is playable" % g)
		for name in v:
			check_eq(Sfx.key_of(name), g, "%s belongs to %s" % [name, g])
			_check_stream(name)
	check_eq(Sfx.key_of("player/footstep_5"), "", "no fifth footstep")
	check_eq(Sfx.key_of("player/footstep_x"), "", "non-numeric suffix")
	check_eq(Sfx.key_of("impact/wood"), "impact/wood", "plain name")
	check_eq(Sfx.variants("impact/wood"), PackedStringArray(["impact/wood"]), "plain name has itself as variant")


func test_loops_have_loop_enabled_and_one_shots_do_not() -> void:
	for name in Sfx.names():
		var s := AssetResolver.get_audio(name) as AudioStreamOggVorbis
		if s == null:
			continue
		var want := LOOPS.has(name)
		check_eq(Sfx.is_loop(name), want, "%s loop flag in DEFS" % name)
		check_eq(s.loop, want, "%s loop flag in the import settings" % name)
		if want:
			check(s.get_length() >= 20.0 and s.get_length() <= 90.0, "%s loop length %.1f s" % [name, s.get_length()])
		else:
			check(s.get_length() <= 15.0, "%s one-shot length %.1f s" % [name, s.get_length()])


func test_template_files_fit_the_budget() -> void:
	var total := 0
	var files := 0
	for name in Sfx.names():
		var f := FileAccess.open(AssetResolver.audio_fallback_path(name), FileAccess.READ)
		if not check(f != null, "%s source file readable" % name):
			continue
		total += f.get_length()
		files += 1
	check_eq(files, Sfx.names().size(), "one file per name")
	check(total < BUDGET_BYTES, "templates total %d bytes (< 6 MB)" % total)
