class_name GameSettings
extends RefCounted
## Persistent player settings in user://settings.cfg (SPEC §7.8). Owner: U.
## Static (no Autoload). Volumes are linear 0..1 per audio bus.
##
##   GameSettings.apply()                       # load once, then apply buses + window
##   GameSettings.set_value("music", 0.4)       # applies live
##   GameSettings.save_settings()               # persist (the settings panel does it on close)
##   GameSettings.path_override = "user://t.cfg"   # tests

const PATH := "user://settings.cfg"
const BUSES := {"master": "Master", "sfx": "SFX", "ambient": "Ambient", "music": "Music"}
const DEFAULTS := {"master": 0.8, "sfx": 0.8, "ambient": 0.7, "music": 0.6, "fullscreen": false}

static var values := DEFAULTS.duplicate()
static var path_override := ""
static var _loaded := false


static func path() -> String:
	return path_override if path_override != "" else PATH


static func load_settings() -> void:
	values = DEFAULTS.duplicate()
	var cf := ConfigFile.new()
	if cf.load(path()) == OK:
		for k in DEFAULTS:
			values[k] = _sanitize(k, cf.get_value("settings", k, DEFAULTS[k]))
	_loaded = true


static func save_settings() -> Error:
	var cf := ConfigFile.new()
	for k in values:
		cf.set_value("settings", k, values[k])
	return cf.save(path())


## Loads once (if needed) and applies volumes and the window mode.
static func apply() -> void:
	if not _loaded:
		load_settings()
	apply_audio()
	apply_display()


static func apply_audio() -> void:
	for k in BUSES:
		var i := AudioServer.get_bus_index(BUSES[k])
		if i < 0:
			continue
		var v: float = clampf(float(values.get(k, DEFAULTS[k])), 0.0, 1.0)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


## Switches between fullscreen and windowed only when it differs (safe headless).
static func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var want_full := bool(values.get("fullscreen", false))
	if want_full != is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_full else DisplayServer.WINDOW_MODE_WINDOWED)


static func get_value(key: String) -> Variant:
	if not _loaded:
		load_settings()
	return values.get(key, DEFAULTS.get(key))


## Sets one value and applies it live (not saved until save_settings()).
static func set_value(key: String, v: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	if not _loaded:
		load_settings()
	values[key] = _sanitize(key, v)
	if BUSES.has(key):
		apply_audio()
	else:
		apply_display()


## Forgets loaded values (tests): the next access reloads from path().
static func reset() -> void:
	values = DEFAULTS.duplicate()
	_loaded = false


static func _sanitize(key: String, v: Variant) -> Variant:
	if key == "fullscreen":
		if typeof(v) == TYPE_BOOL:
			return v
		return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and float(v) != 0.0
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return DEFAULTS[key]
	return clampf(float(v), 0.0, 1.0)
