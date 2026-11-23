class_name AssetResolver
extends RefCounted
## Single entry point for replaceable graphics and audio (see assets/README.md).
##
## Logical name "illustrated/floor_wood" resolves, in order, to:
##   1. <override root>/graphics/illustrated/floor_wood.png   (user file, PNG)
##   2. res://assets/graphics/illustrated/template_floor_wood.png (packaged fallback)
## Logical sound "impact/wood" (get_audio) resolves, in order, to:
##   1. <override root>/audio/impact/wood.ogg  (then .wav where the engine can
##      load WAV at runtime; see audio_override_formats())
##   2. res://assets/audio/impact/template_wood.ogg (packaged fallback)
## Override root: the project's custom/ folder when running from the editor
## binary, or custom/ next to the executable in an exported Windows/Linux game.
## A missing override falls back silently; an undecodable one falls back with
## a warning. Results are cached for the session: override changes apply after
## a game restart.

const FALLBACK_ROOT := "res://assets/graphics"
const AUDIO_FALLBACK_ROOT := "res://assets/audio"
const TEMPLATE_PREFIX := "template_"

static var _root_override := ""
static var _cache := {}


## Where user overrides are looked up (computed in one place).
static func override_root() -> String:
	if _root_override != "":
		return _root_override
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://custom")
	return OS.get_executable_path().get_base_dir().path_join("custom")


## Tests (or tools) inject a temporary root; "" restores the default.
static func set_override_root(path: String) -> void:
	_root_override = path
	_cache.clear()


static func clear_cache() -> void:
	_cache.clear()


static func override_path(logical: String) -> String:
	return override_root().path_join("graphics").path_join(logical + ".png")


static func fallback_path(logical: String) -> String:
	var dir := logical.get_base_dir()
	var file := TEMPLATE_PREFIX + logical.get_file() + ".png"
	return FALLBACK_ROOT.path_join(dir).path_join(file) if dir != "" else FALLBACK_ROOT.path_join(file)


## Returns the texture for `logical`, or null if neither override nor fallback
## exists. `mipmaps` builds mipmaps for override images (use for 3D surfaces).
static func get_texture(logical: String, mipmaps := false) -> Texture2D:
	var key := logical + ("#mip" if mipmaps else "")
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var user_file := override_path(logical)
	if FileAccess.file_exists(user_file):
		var img := Image.load_from_file(user_file)
		if img != null and not img.is_empty():
			if mipmaps:
				img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
		else:
			push_warning("AssetResolver: invalid override %s, using template" % user_file)
	if tex == null:
		var packaged := fallback_path(logical)
		if ResourceLoader.exists(packaged):
			tex = load(packaged)
		else:
			push_warning("AssetResolver: no asset for '%s'" % logical)
	_cache[key] = tex
	return tex


## Convenience for code that needs pixels (e.g. palettes, masks).
static func get_image(logical: String) -> Image:
	var tex := get_texture(logical)
	return tex.get_image() if tex != null else null


# ---------------------------------------------------------------- audio

## Supported audio override formats, in lookup order. OGG Vorbis always; WAV
## only where this engine build can load WAV files at runtime (Godot 4.7 can).
static func audio_override_formats() -> PackedStringArray:
	var out := PackedStringArray(["ogg"])
	if ClassDB.class_has_method("AudioStreamWAV", "load_from_file"):
		out.append("wav")
	return out


static func audio_override_path(logical: String, ext := "ogg") -> String:
	return override_root().path_join("audio").path_join(logical + "." + ext)


static func audio_fallback_path(logical: String) -> String:
	var dir := logical.get_base_dir()
	var file := TEMPLATE_PREFIX + logical.get_file() + ".ogg"
	return AUDIO_FALLBACK_ROOT.path_join(dir).path_join(file) if dir != "" else AUDIO_FALLBACK_ROOT.path_join(file)


## Returns the stream for `logical` (e.g. "impact/wood"), or null with a
## warning if neither an override nor the packaged template exists. An
## override of a looping template (ambience, music) is looped as well.
static func get_audio(logical: String) -> AudioStream:
	var key := "audio:" + logical
	if _cache.has(key):
		return _cache[key]
	var template: AudioStream = null
	var packaged := audio_fallback_path(logical)
	if ResourceLoader.exists(packaged):
		template = load(packaged) as AudioStream
	var stream: AudioStream = null
	for ext in audio_override_formats():
		var user_file := audio_override_path(logical, ext)
		if not FileAccess.file_exists(user_file):
			continue
		stream = _load_audio_file(user_file, ext)
		if stream != null:
			_inherit_loop(stream, template)
			break
		push_warning("AssetResolver: invalid audio override %s, using template" % user_file)
	if stream == null:
		stream = template
		if stream == null:
			push_warning("AssetResolver: no sound for '%s'" % logical)
	_cache[key] = stream
	return stream


## Runtime load of a user file. Null unless it has the right signature,
## decodes, has a length and can start playback.
static func _load_audio_file(path: String, ext: String) -> AudioStream:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var head := f.get_buffer(12)
	f.close()
	var stream: AudioStream = null
	if ext == "ogg":
		if head.size() < 4 or head.slice(0, 4).get_string_from_ascii() != "OggS":
			return null
		stream = AudioStreamOggVorbis.load_from_file(path)
	elif ext == "wav":
		if head.size() < 12 or head.slice(0, 4).get_string_from_ascii() != "RIFF" \
				or head.slice(8, 12).get_string_from_ascii() != "WAVE":
			return null
		stream = AudioStreamWAV.load_from_file(path)
	if stream == null or stream.get_length() <= 0.0 or stream.instantiate_playback() == null:
		return null
	return stream


static func _is_looping(stream: AudioStream) -> bool:
	if stream is AudioStreamOggVorbis:
		return (stream as AudioStreamOggVorbis).loop
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	return false


static func _inherit_loop(stream: AudioStream, template: AudioStream) -> void:
	if template == null or not _is_looping(template):
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
