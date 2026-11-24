class_name SaveGame
extends RefCounted
## Single-slot save file in user:// (SPEC §7.2). Owner: S.
##
## File layout (little-endian), see docs/experiment-002/survival.md:
##   0  "SWQS" magic        4  u32 format (1)     8  u32 schema (SCHEMA)
##   12 u64 saved_at        20 u32 codec (0 raw, 1 zstd)
##   24 u32 raw size        28 u32 summary size   32 u32 payload size
##   36 16-byte MD5 of summary + payload
##   52 summary: var_to_bytes(data.summary)  (read by info() without the payload)
##   .. payload: var_to_bytes(data) (Godot binary Variant, no objects), zstd-compressed
## Writes go to <path>.tmp, are re-read and verified, the previous good save is
## rotated to <path>.bak, then the tmp file is renamed into place. A crash at
## any step leaves the last good save readable (as the main file or the .bak).
##
## Schema 2 (Experiment 003): the same layout; "state" now carries difficulty,
## equipment, weapons and the region, "world" is HouseWorld save version 2.
## Schema 1 files (Experiment 002) still load: read() returns them with
## "migrated_from": 1 and the data marked schema 2 (GameState.from_dict and
## HouseWorld.load_data take the version 1 contents as they are); the game
## re-saves at once, so the file on disk becomes schema 2.

const PATH := "user://savegame.dat"
const SCHEMA := 2
const MIN_SCHEMA := 1                  ## the oldest schema read() still accepts (and migrates)
const GAME_ID := "sirens_went_quiet"
const FORMAT := 1
const MAGIC := "SWQS"
const HEADER_SIZE := 52
const CODEC_RAW := 0
const CODEC_ZSTD := 1
const MAX_FILE_BYTES := 256 * 1024 * 1024
const MAX_RAW_BYTES := 512 * 1024 * 1024

static var path_override := ""         ## tests
static var last_error := ""            ## readable reason for the last failed write()
static var fault_injection := ""       ## tests only: "corrupt_tmp" | "fail_rename"


static func _path() -> String:
	return path_override if path_override != "" else PATH


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)


## Writes `data` ({"summary", "state", "world", "game"}) safely. Adds "schema",
## "game_id" and "saved_at". "state" must be a Dictionary; "world" and "game"
## default to {}. Returns OK, or an error with `last_error` set; on any error
## the previous save is untouched.
static func write(data: Dictionary) -> Error:
	last_error = ""
	if typeof(data.get("state")) != TYPE_DICTIONARY:
		return _fail(ERR_INVALID_PARAMETER, "There is no game state to save.")
	var d := data.duplicate()
	for k in ["world", "game"]:
		if d.get(k) == null:
			d[k] = {}
		elif typeof(d[k]) != TYPE_DICTIONARY:
			return _fail(ERR_INVALID_PARAMETER, "The %s data can't be saved." % k)
	if typeof(d.get("summary")) != TYPE_DICTIONARY:
		d["summary"] = {}
	d["schema"] = SCHEMA
	d["game_id"] = GAME_ID
	d["saved_at"] = int(Time.get_unix_time_from_system())
	var raw := var_to_bytes(d)
	if raw.size() > MAX_RAW_BYTES:
		return _fail(ERR_OUT_OF_MEMORY, "The game is too large to save.")
	var summary := var_to_bytes(d["summary"])
	var payload := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var p := _path()
	var tmp := p + ".tmp"
	DirAccess.make_dir_recursive_absolute(_abs(p).get_base_dir())
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _fail(ERR_FILE_CANT_WRITE, "The save file could not be created (%s)." % error_string(FileAccess.get_open_error()))
	var header := PackedByteArray()
	header.resize(HEADER_SIZE)
	header.fill(0)
	for i in 4:
		header[i] = MAGIC.unicode_at(i)
	header.encode_u32(4, FORMAT)
	header.encode_u32(8, SCHEMA)
	header.encode_u64(12, d["saved_at"])
	header.encode_u32(20, CODEC_ZSTD)
	header.encode_u32(24, raw.size())
	header.encode_u32(28, summary.size())
	header.encode_u32(32, payload.size())
	var digest := _digest(summary, payload)
	for i in 16:
		header[36 + i] = digest[i]
	var ok := f.store_buffer(header) and f.store_buffer(summary) and f.store_buffer(payload)
	ok = ok and f.get_error() == OK
	f.close()
	if not ok:
		_remove(tmp)
		return _fail(ERR_FILE_CANT_WRITE, "The save file could not be written (is the disk full?).")
	if fault_injection == "corrupt_tmp":
		_corrupt(tmp)
	var check := _load(tmp, true)
	if not check["ok"] or check["raw"] != raw:
		_remove(tmp)
		return _fail(ERR_FILE_CORRUPT, "The new save did not verify; the previous save was kept.")
	# rotate the previous good save to .bak (a damaged one is dropped, keeping the older .bak)
	var bak := p + ".bak"
	if FileAccess.file_exists(p):
		if _load(p, false)["ok"]:
			_remove(bak)
			if DirAccess.rename_absolute(_abs(p), _abs(bak)) != OK:
				_remove(tmp)
				return _fail(ERR_CANT_CREATE, "The previous save could not be backed up; it was kept.")
		else:
			_remove(p)
	if fault_injection == "fail_rename" or DirAccess.rename_absolute(_abs(tmp), _abs(p)) != OK:
		_remove(tmp)
		return _fail(ERR_CANT_CREATE, "The save file could not be replaced; the previous save was kept.")
	return OK


## {"ok", "error", "data", "restored_from_backup", "migrated_from"}. Falls back
## to the .bak when the main file is missing or unusable ("backup_reason" then
## says why). "migrated_from" is the file's schema when it was older than
## SCHEMA (the data is migrated; the caller should save again), else 0.
static func read() -> Dictionary:
	var p := _path()
	var main := _load(p, true) if FileAccess.file_exists(p) else {}
	if main.get("ok", false):
		return {"ok": true, "error": "", "data": main["data"], "restored_from_backup": false, "migrated_from": main["migrated_from"]}
	var bak := _load(p + ".bak", true) if FileAccess.file_exists(p + ".bak") else {}
	if bak.get("ok", false):
		var why: String = main.get("error", "The latest save file is missing.")
		return {"ok": true, "error": "", "data": bak["data"], "restored_from_backup": true, "backup_reason": why, "migrated_from": bak["migrated_from"]}
	return {"ok": false, "error": _first_error(p, main, bak), "data": {}, "restored_from_backup": false, "migrated_from": 0}


## Brings a decoded older save up to SCHEMA in place. Schema 1 -> 2 needs no
## change of the contents: an Experiment 002 state (no equipment or weapons)
## and a version 1 world are migrated by GameState.from_dict and
## HouseWorld.load_data. Returns the schema it came from.
static func migrate(data: Dictionary) -> int:
	var from := int(data.get("schema", SCHEMA))
	if from < SCHEMA:
		data["schema"] = SCHEMA
		data["migrated_from"] = from
	return from


## Cheap slot check for the main menu: reads the header, summary and checksum,
## not the payload. {"exists", "valid", "schema", "saved_at", "summary",
## "error", "restored_from_backup"} ("valid" also when only the .bak is good).
static func info() -> Dictionary:
	var p := _path()
	var out := {"exists": false, "valid": false, "schema": 0, "saved_at": 0, "summary": {}, "error": "", "restored_from_backup": false}
	var main := _load(p, false) if FileAccess.file_exists(p) else {}
	var bak := {}
	var use := main
	if not main.get("ok", false) and FileAccess.file_exists(p + ".bak"):
		bak = _load(p + ".bak", false)
		if bak.get("ok", false):
			use = bak
			out["restored_from_backup"] = true
	out["exists"] = not main.is_empty() or not bak.is_empty()
	out["valid"] = use.get("ok", false)
	if not use.is_empty():
		out["schema"] = use["schema"]
		out["saved_at"] = use["saved_at"]
		out["summary"] = use["summary"]
	if not out["valid"]:
		out["error"] = _first_error(p, main, bak)
	return out


## Removes the save, its backup and any leftover temp file (a dead run can't be continued).
static func delete_save() -> void:
	var p := _path()
	for f in [p, p + ".bak", p + ".tmp"]:
		_remove(f)


# --- internals -------------------------------------------------------------------

## Reads and checks one file. `full` also decompresses and decodes the payload.
## {"ok", "error", "data", "raw", "summary", "schema", "saved_at"}.
static func _load(path: String, full: bool) -> Dictionary:
	var out := {"ok": false, "error": "", "data": {}, "raw": PackedByteArray(), "summary": {}, "schema": 0, "saved_at": 0, "migrated_from": 0}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		out["error"] = "The save file could not be opened."
		return out
	var size := f.get_length()
	if size == 0 or size > MAX_FILE_BYTES:
		f.close()
		out["error"] = "The save file is empty." if size == 0 else "The save file is too large to be a save."
		return out
	var buf := f.get_buffer(size)
	f.close()
	if buf.size() != size:
		out["error"] = "The save file could not be read completely."
		return out
	if size < 4 or buf.slice(0, 4).get_string_from_ascii() != MAGIC:
		var old := size >= 8 and buf[4] == TYPE_DICTIONARY   # the foundation's plain store_var layout
		out["error"] = "The save is from an older version of the game." if old else "This is not a Sirens Went Quiet save file."
		return out
	if size < HEADER_SIZE:
		out["error"] = "The save file is damaged (it was cut off)."
		return out
	var format := buf.decode_u32(4)
	var schema := buf.decode_u32(8)
	out["schema"] = schema
	out["saved_at"] = buf.decode_u64(12)
	if format != FORMAT or schema < MIN_SCHEMA or schema > SCHEMA:
		var newer := format > FORMAT or schema > SCHEMA
		out["error"] = "The save is from a %s version of the game." % ("newer" if newer else "older")
		return out
	var codec := buf.decode_u32(20)
	var raw_size := buf.decode_u32(24)
	var summary_size := buf.decode_u32(28)
	var payload_size := buf.decode_u32(32)
	if HEADER_SIZE + summary_size + payload_size != size:
		out["error"] = "The save file is damaged (it was cut off or extended)."
		return out
	if codec > CODEC_ZSTD or raw_size > MAX_RAW_BYTES or raw_size == 0:
		out["error"] = "The save file is damaged (bad header)."
		return out
	var summary := buf.slice(HEADER_SIZE, HEADER_SIZE + summary_size)
	var payload := buf.slice(HEADER_SIZE + summary_size)
	if _digest(summary, payload) != buf.slice(36, 52):
		out["error"] = "The save file is damaged (it failed its integrity check)."
		return out
	var sv = bytes_to_var(summary) if summary_size > 0 else {}
	out["summary"] = sv if typeof(sv) == TYPE_DICTIONARY else {}
	if not full:
		out["ok"] = true
		return out
	var raw := payload if codec == CODEC_RAW else payload.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size:
		out["error"] = "The save file is damaged (it could not be unpacked)."
		return out
	var data = bytes_to_var(raw)
	var why := _validate(data)
	if why == "" and int(data["schema"]) != schema:
		why = "The save file is damaged (its versions disagree)."
	if why != "":
		out["error"] = why
		return out
	var from := migrate(data)
	out["migrated_from"] = from if from < SCHEMA else 0
	out["data"] = data
	out["raw"] = raw
	out["ok"] = true
	return out


## "" if `data` has the shape the game needs, else a readable reason.
static func _validate(data) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "The save file is damaged (no game data)."
	if data.get("game_id") != GAME_ID:
		return "This is not a Sirens Went Quiet save file."
	if typeof(data.get("schema")) != TYPE_INT:
		return "The save file is damaged (no version)."
	if data["schema"] < MIN_SCHEMA or data["schema"] > SCHEMA:
		return "The save is from a %s version of the game." % ("newer" if data["schema"] > SCHEMA else "older")
	if typeof(data.get("state")) != TYPE_DICTIONARY:
		return "The save file is damaged (the survival state is missing)."
	for k in ["world", "game"]:
		if typeof(data.get(k)) != TYPE_DICTIONARY:
			return "The save file is damaged (the %s data is missing)." % k
	return ""


static func _first_error(p: String, main: Dictionary, bak: Dictionary) -> String:
	if not main.is_empty():
		return main["error"]
	if not bak.is_empty():
		return bak["error"]
	if DirAccess.dir_exists_absolute(_abs(p)):
		return "The save could not be opened (a folder is in its place)."
	return "No saved game."


static func _digest(a: PackedByteArray, b: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	if not a.is_empty():
		h.update(a)
	if not b.is_empty():
		h.update(b)
	return h.finish()


static func _fail(err: Error, text: String) -> Error:
	last_error = text
	return err


static func _remove(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(_abs(p))


## Test fault: flips one payload byte of a written file.
static func _corrupt(p: String) -> void:
	var f := FileAccess.open(p, FileAccess.READ_WRITE)
	if f == null:
		return
	var at := f.get_length() - 1
	f.seek(at)
	var b := f.get_8()
	f.seek(at)
	f.store_8(b ^ 0xFF)
	f.close()
