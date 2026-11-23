extends "res://tests/test_case.gd"
## Creator overrides at runtime (assets/README.md): a file dropped into
## <override root>/audio/<logical>.ogg replaces the template for Sfx; a
## corrupt one falls back with a warning; overrides of loops still loop.

const Catcher := preload("res://tests/audio/warning_catcher.gd")
var _tmp := ""


func _setup() -> String:
	Sfx.reset()
	_tmp = OS.get_user_data_dir().path_join("audio_override_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_tmp.path_join("audio"))
	AssetResolver.set_override_root(_tmp)
	return _tmp.path_join("audio")


func _teardown() -> void:
	AssetResolver.set_override_root("")
	_rmtree(_tmp)


func _rmtree(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_rmtree(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _copy_template(from_logical: String, to_file: String) -> void:
	DirAccess.make_dir_recursive_absolute(to_file.get_base_dir())
	var bytes := FileAccess.get_file_as_bytes(AssetResolver.audio_fallback_path(from_logical))
	var f := FileAccess.open(to_file, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func test_dropped_file_replaces_the_sound() -> void:
	var dir := _setup()
	var template_len := (load(AssetResolver.audio_fallback_path("ui/click")) as AudioStream).get_length()
	var other_len := (load(AssetResolver.audio_fallback_path("weapon/dry_fire")) as AudioStream).get_length()
	_copy_template("player/eat", dir.path_join("ui/click.ogg"))
	var s := AssetResolver.get_audio("ui/click")
	check(s is AudioStreamOggVorbis and s.resource_path == "", "loaded at runtime from the override folder")
	var eat_len := (load(AssetResolver.audio_fallback_path("player/eat")) as AudioStream).get_length()
	check(absf(s.get_length() - eat_len) < 0.01, "it is the dropped file (%.3f s)" % s.get_length())
	check(absf(s.get_length() - template_len) > 0.1, "not the template")
	Sfx.ui("ui/click")
	var host := tree.root.get_node_or_null("SfxPersistent")
	var used := false
	if host != null:
		for c in host.get_children():
			if c.playing and c.get_meta("sfx_key", "") == "ui/click":
				used = c.stream == s
	check(used, "Sfx plays the override")
	# a variant of a group, positional
	_copy_template("weapon/dry_fire", dir.path_join("player/footstep_2.ogg"))
	var v := AssetResolver.get_audio("player/footstep_2")
	check(v != null and absf(v.get_length() - other_len) < 0.01, "variant override")
	_teardown()


func test_corrupt_override_falls_back_with_a_warning() -> void:
	var dir := _setup()
	DirAccess.make_dir_recursive_absolute(dir.path_join("impact"))
	var f := FileAccess.open(dir.path_join("impact/wood.ogg"), FileAccess.WRITE)
	f.store_string("OggS but certainly not a vorbis stream")
	f.close()
	var cat := Catcher.new()
	OS.add_logger(cat)
	var s := AssetResolver.get_audio("impact/wood")
	OS.remove_logger(cat)
	check(s != null and s.resource_path == AssetResolver.audio_fallback_path("impact/wood"), "template used")
	check_eq(cat.count("invalid audio override"), 1, "one warning")
	_root_and_play("impact/wood")
	_teardown()


func _root_and_play(name: String) -> void:
	var root := add(Node3D.new())
	Sfx.attach(root)
	Sfx.play(name, Vector3.ZERO)
	check_eq(Sfx.active_count(name), 1, "%s still plays" % name)


func test_override_of_a_loop_still_loops() -> void:
	var dir := _setup()
	_copy_template("impact/metal", dir.path_join("ambient/night.ogg"))
	var s := AssetResolver.get_audio("ambient/night") as AudioStreamOggVorbis
	check(s != null and s.resource_path == "", "override used")
	check(s != null and s.loop, "inherits the template's loop flag")
	var one_shot := AssetResolver.get_audio("impact/metal") as AudioStreamOggVorbis
	check(one_shot != null and not one_shot.loop, "the template itself is untouched")
	_teardown()


func test_wav_override_when_supported() -> void:
	if not AssetResolver.audio_override_formats().has("wav"):
		skip("this engine build cannot load WAV at runtime")
		return
	var dir := _setup()
	DirAccess.make_dir_recursive_absolute(dir.path_join("ui"))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(5513 * 2)  # 0.25 s of 16-bit mono
	for i in range(0, data.size(), 2):
		data.encode_s16(i, int(sin(i * 0.05) * 8000.0))
	wav.data = data
	wav.save_to_wav(dir.path_join("ui/hover.wav"))
	var s := AssetResolver.get_audio("ui/hover")
	check(s is AudioStreamWAV, "WAV override loaded")
	check(s != null and absf(s.get_length() - 0.25) < 0.01, "its length")
	DirAccess.make_dir_recursive_absolute(dir.path_join("ambient"))
	wav.save_to_wav(dir.path_join("ambient/night.wav"))
	AssetResolver.clear_cache()
	var night := AssetResolver.get_audio("ambient/night") as AudioStreamWAV
	check(night != null and night.loop_mode == AudioStreamWAV.LOOP_FORWARD, "WAV override of a loop loops")
	check(night != null and night.loop_end > 0, "over the whole file")
	_teardown()
