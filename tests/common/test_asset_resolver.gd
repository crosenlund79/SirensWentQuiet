extends "res://tests/test_case.gd"
## AssetResolver contract (assets/README.md): override precedence, fallback
## when missing/invalid/unsupported, override-root selection. Graphics and
## audio (get_audio).

const Catcher := preload("res://tests/audio/warning_catcher.gd")
const SOUND := "impact/wood"

const LOGICAL := "common/crosshair"
var _tmp := ""


func _setup() -> String:
	_tmp = OS.get_user_data_dir().path_join("resolver_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_tmp.path_join("graphics/common"))
	AssetResolver.set_override_root(_tmp)
	return _tmp.path_join("graphics/common")


func _teardown() -> void:
	AssetResolver.set_override_root("")
	for f in DirAccess.get_files_at(_tmp.path_join("graphics/common")):
		DirAccess.remove_absolute(_tmp.path_join("graphics/common").path_join(f))


func test_default_override_root_is_project_custom_folder() -> void:
	AssetResolver.set_override_root("")
	check_eq(AssetResolver.override_root(), ProjectSettings.globalize_path("res://custom"), "editor/dev root")
	check_eq(AssetResolver.fallback_path(LOGICAL), "res://assets/graphics/common/template_crosshair.png", "fallback path")


func test_fallback_when_missing() -> void:
	_setup()
	var tex := AssetResolver.get_texture(LOGICAL)
	check(tex != null, "packaged template found")
	check(not (tex is ImageTexture), "uses the imported template")
	_teardown()


func test_override_takes_precedence() -> void:
	var dir := _setup()
	var img := Image.create_empty(8, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	img.save_png(dir.path_join("crosshair.png"))
	var tex := AssetResolver.get_texture(LOGICAL)
	check(tex is ImageTexture, "override loaded at runtime")
	check_eq(tex.get_size(), Vector2(8, 6), "override size")
	# cached for the session
	check(AssetResolver.get_texture(LOGICAL) == tex, "cached")
	_teardown()


func test_invalid_or_unsupported_override_falls_back() -> void:
	var dir := _setup()
	var f := FileAccess.open(dir.path_join("crosshair.png"), FileAccess.WRITE)
	f.store_string("definitely not a png")
	f.close()
	var tex := AssetResolver.get_texture(LOGICAL)
	check(tex != null and not (tex is ImageTexture), "invalid PNG -> template")
	_teardown()
	dir = _setup()
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.save_jpg(dir.path_join("crosshair.jpg"))
	tex = AssetResolver.get_texture(LOGICAL)
	check(tex != null and not (tex is ImageTexture), "JPG override ignored (PNG only)")
	_teardown()


# ---------------------------------------------------------------- audio

func _audio_setup() -> String:
	_tmp = OS.get_user_data_dir().path_join("resolver_audio_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_tmp.path_join("audio/impact"))
	AssetResolver.set_override_root(_tmp)
	return _tmp.path_join("audio/impact")


func _audio_teardown() -> void:
	AssetResolver.set_override_root("")
	var dir := _tmp.path_join("audio/impact")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))


func _write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _ogg_bytes(logical: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(AssetResolver.audio_fallback_path(logical))


func test_audio_paths_and_formats() -> void:
	AssetResolver.set_override_root("")
	check_eq(AssetResolver.audio_fallback_path(SOUND), "res://assets/audio/impact/template_wood.ogg", "fallback path")
	check_eq(AssetResolver.audio_override_path(SOUND),
			ProjectSettings.globalize_path("res://custom").path_join("audio/impact/wood.ogg"), "override path (editor root)")
	var formats := AssetResolver.audio_override_formats()
	check_eq(formats[0], "ogg", "OGG first")
	check_eq(formats.has("wav"), ClassDB.class_has_method("AudioStreamWAV", "load_from_file"), "WAV iff runtime-loadable")
	AssetResolver.set_override_root("/tmp/some_root")
	check_eq(AssetResolver.audio_override_path(SOUND, "wav"), "/tmp/some_root/audio/impact/wood.wav", "injected root")
	AssetResolver.set_override_root("")


func test_audio_fallback_when_missing() -> void:
	_audio_setup()
	var cat := Catcher.new()
	OS.add_logger(cat)
	var s := AssetResolver.get_audio(SOUND)
	OS.remove_logger(cat)
	check(s is AudioStreamOggVorbis and s.resource_path == AssetResolver.audio_fallback_path(SOUND), "imported template")
	check_eq(cat.lines().size(), 0, "a missing override is silent")
	_audio_teardown()


func test_audio_override_takes_precedence_and_is_cached() -> void:
	var dir := _audio_setup()
	_write(dir.path_join("wood.ogg"), _ogg_bytes("impact/metal"))
	var s := AssetResolver.get_audio(SOUND)
	check(s is AudioStreamOggVorbis and s.resource_path == "", "runtime-loaded override")
	var metal := load(AssetResolver.audio_fallback_path("impact/metal")) as AudioStream
	check(s != null and absf(s.get_length() - metal.get_length()) < 0.01, "the override's content")
	check(AssetResolver.get_audio(SOUND) == s, "cached")
	DirAccess.remove_absolute(dir.path_join("wood.ogg"))
	check(AssetResolver.get_audio(SOUND) == s, "still cached after the file changes (restart to apply)")
	AssetResolver.clear_cache()
	check(AssetResolver.get_audio(SOUND).resource_path != "", "template again after a cache reset")
	check(AssetResolver.get_texture(LOGICAL) != null, "graphics unaffected by the audio cache")
	_audio_teardown()


func test_audio_wav_override_and_ogg_preference() -> void:
	if not AssetResolver.audio_override_formats().has("wav"):
		skip("no runtime WAV loading in this engine build")
		return
	var dir := _audio_setup()
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(4000)  # 0.5 s
	for i in data.size():
		data[i] = int(127.0 * sin(i * 0.3)) & 0xff
	wav.data = data
	wav.save_to_wav(dir.path_join("wood.wav"))
	var s := AssetResolver.get_audio(SOUND)
	check(s is AudioStreamWAV, "WAV override")
	check(s != null and absf(s.get_length() - 0.5) < 0.01, "its length")
	_write(dir.path_join("wood.ogg"), _ogg_bytes("impact/glass"))
	AssetResolver.clear_cache()
	check(AssetResolver.get_audio(SOUND) is AudioStreamOggVorbis, "OGG wins when both exist")
	_audio_teardown()


func test_audio_invalid_override_falls_back_with_warning() -> void:
	var dir := _audio_setup()
	var template := AssetResolver.audio_fallback_path(SOUND)
	var cases := {
		"garbage": "this is not audio".to_utf8_buffer(),
		"empty": PackedByteArray(),
		"fake ogg": "OggS-and-then-nothing-useful".to_utf8_buffer(),
		"truncated ogg": _ogg_bytes("impact/metal").slice(0, 200),
	}
	for label in cases:
		_write(dir.path_join("wood.ogg"), cases[label])
		AssetResolver.clear_cache()
		var cat := Catcher.new()
		OS.add_logger(cat)
		var s := AssetResolver.get_audio(SOUND)
		OS.remove_logger(cat)
		check(s != null and s.resource_path == template, "%s -> template" % label)
		check_eq(cat.count("invalid audio override"), 1, "%s -> one warning" % label)
	DirAccess.remove_absolute(dir.path_join("wood.ogg"))
	# unsupported extension: ignored (not an override at all)
	_write(dir.path_join("wood.mp3"), _ogg_bytes("impact/metal"))
	_write(dir.path_join("wood.flac"), _ogg_bytes("impact/metal"))
	AssetResolver.clear_cache()
	check_eq(AssetResolver.get_audio(SOUND).resource_path, template, "unsupported formats ignored")
	_audio_teardown()


func test_audio_missing_everything_returns_null_with_warning() -> void:
	_audio_setup()
	var cat := Catcher.new()
	OS.add_logger(cat)
	var s := AssetResolver.get_audio("impact/no_such_sound")
	OS.remove_logger(cat)
	check(s == null, "null")
	check_eq(cat.count("no sound for"), 1, "warned")
	_audio_teardown()
