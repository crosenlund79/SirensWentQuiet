class_name SaveGame
extends RefCounted
## Single-slot save file in user:// (SPEC §7.2). Owner: S.
## Foundation version: works, but S hardens it (temp file + verify + rename,
## .bak fallback, schema validation, readable errors).

const PATH := "user://savegame.dat"
const SCHEMA := 1
const GAME_ID := "sirens_went_quiet"

static var path_override := ""


static func _path() -> String:
	return path_override if path_override != "" else PATH


static func write(data: Dictionary) -> Error:
	var d := data.duplicate()
	d["schema"] = SCHEMA
	d["game"] = GAME_ID
	d["saved_at"] = int(Time.get_unix_time_from_system())
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var(d, false)
	f.close()
	return OK


static func read() -> Dictionary:
	if not FileAccess.file_exists(_path()):
		return {"ok": false, "error": "No saved game.", "data": {}}
	var f := FileAccess.open(_path(), FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "The save file could not be opened.", "data": {}}
	var v = f.get_var(false)
	f.close()
	if typeof(v) != TYPE_DICTIONARY or v.get("game", "") != GAME_ID or int(v.get("schema", 0)) != SCHEMA:
		return {"ok": false, "error": "The save file is damaged or from another version.", "data": {}}
	return {"ok": true, "error": "", "data": v}


static func info() -> Dictionary:
	var exists := FileAccess.file_exists(_path())
	if not exists:
		return {"exists": false, "valid": false, "schema": 0, "saved_at": 0, "summary": {}}
	var r := read()
	var d: Dictionary = r["data"]
	return {"exists": true, "valid": r["ok"], "schema": int(d.get("schema", 0)), "saved_at": int(d.get("saved_at", 0)), "summary": d.get("summary", {}), "error": r["error"]}


static func delete_save() -> void:
	if FileAccess.file_exists(_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path()))
