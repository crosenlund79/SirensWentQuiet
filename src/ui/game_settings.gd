class_name GameSettings
extends RefCounted
## Persistent player settings in user://settings.cfg (SPEC §7.8). Owner: U.

const PATH := "user://settings.cfg"
const BUSES := {"master": "Master", "sfx": "SFX", "ambient": "Ambient", "music": "Music"}

static var values := {"master": 0.8, "sfx": 0.8, "ambient": 0.7, "music": 0.6, "fullscreen": false}
static var _loaded := false


static func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in values:
			values[k] = cf.get_value("settings", k, values[k])
	_loaded = true


static func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in values:
		cf.set_value("settings", k, values[k])
	cf.save(PATH)


static func apply() -> void:
	if not _loaded:
		load_settings()
	for k in BUSES:
		var i := AudioServer.get_bus_index(BUSES[k])
		if i >= 0:
			var v: float = clampf(float(values[k]), 0.0, 1.0)
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(i, v <= 0.001)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if values["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED)
