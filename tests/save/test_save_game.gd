extends "res://tests/test_case.gd"
## SaveGame: round trip with world blobs, atomic write, .bak fallback, damaged
## and foreign files, schema mismatch, delete, info. Uses a private path;
## never touches the real save.

var dir := "user://test_save_s_%d" % OS.get_process_id()
var path := dir + "/slot.dat"


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:   # even if a test aborts
		SaveGame.path_override = ""
		SaveGame.fault_injection = ""


func _fresh() -> void:
	SaveGame.path_override = path
	SaveGame.fault_injection = ""
	SaveGame.delete_save()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _done() -> void:
	SaveGame.delete_save()
	SaveGame.path_override = ""
	SaveGame.fault_injection = ""


func _data(tag: String, blob_bytes := 4096) -> Dictionary:
	var s := GameState.new_run(5)
	s.inventory.add("scrap", 2)
	var blob := PackedByteArray()
	blob.resize(blob_bytes)
	for i in range(0, blob_bytes, 7):
		blob[i] = (i / 7) % 251
	var ints := PackedInt32Array()
	ints.resize(blob_bytes / 4)
	ints.fill(0x26221f)
	return {"summary": s.summary(), "state": s.to_dict(), "world": {"tag": tag, "mat": blob, "col": ints}, "game": {"player": Vector3(1, 0, 2)}}


func _bytes(p: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(p)


func _put(p: String, b: PackedByteArray) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()


func _tag(r: Dictionary) -> String:
	return str(r["data"]["world"]["tag"]) if r["ok"] else ""


func test_round_trip_with_world_blobs() -> void:
	_fresh()
	var d := _data("A", 4 * 1024 * 1024)
	var t0 := Time.get_ticks_msec()
	check_eq(SaveGame.write(d), OK, "written")
	var t1 := Time.get_ticks_msec()
	var r := SaveGame.read()
	var t2 := Time.get_ticks_msec()
	var info := SaveGame.info()
	var t3 := Time.get_ticks_msec()
	print("      4 MB world: write %d ms, read %d ms, info %d ms, file %d bytes" % [t1 - t0, t2 - t1, t3 - t2, _bytes(path).size()])
	check(r["ok"] and not r["restored_from_backup"], "read back: %s" % r["error"])
	check_eq(r["data"]["world"]["mat"], d["world"]["mat"], "byte blob intact")
	check_eq(r["data"]["world"]["col"], d["world"]["col"], "int blob intact")
	check_eq(r["data"]["game"]["player"], Vector3(1, 0, 2), "game data intact")
	check_eq(r["data"]["schema"], SaveGame.SCHEMA, "schema added")
	check_eq(r["data"]["game_id"], SaveGame.GAME_ID, "game id added")
	check(absi(int(r["data"]["saved_at"]) - int(Time.get_unix_time_from_system())) < 60, "saved_at added")
	var s := GameState.from_dict(r["data"]["state"])
	check(s != null and s.inventory.count("scrap") == 2, "state restores")
	check(info["exists"] and info["valid"], "info: valid")
	check_eq(info["summary"], d["summary"], "info: summary")
	check_eq(info["schema"], SaveGame.SCHEMA, "info: schema")
	check(info["saved_at"] > 0, "info: saved_at")
	check(_bytes(path).size() < 1024 * 1024, "compressed well")
	check(not FileAccess.file_exists(path + ".tmp"), "no temp file left")
	_done()


func test_write_validates_its_input() -> void:
	_fresh()
	check_eq(SaveGame.write({"summary": {}}), ERR_INVALID_PARAMETER, "no state")
	check(SaveGame.last_error != "", "readable reason")
	check_eq(SaveGame.write({"state": {}, "world": [1]}), ERR_INVALID_PARAMETER, "world must be a dictionary")
	check(not FileAccess.file_exists(path), "nothing written")
	check_eq(SaveGame.write({"state": {"x": 1}}), OK, "world and game default to {}")
	var r := SaveGame.read()
	check(r["ok"] and r["data"]["world"] == {} and r["data"]["game"] == {}, "defaults stored")
	_done()


func test_second_write_rotates_to_bak() -> void:
	_fresh()
	SaveGame.write(_data("A"))
	SaveGame.write(_data("B"))
	check_eq(_tag(SaveGame.read()), "B", "main is the newest")
	SaveGame.path_override = path + ".bak"
	check_eq(_tag(SaveGame.read()), "A", "the previous save is the .bak")
	SaveGame.path_override = path
	_done()


func test_failed_verification_keeps_the_old_save() -> void:
	_fresh()
	SaveGame.write(_data("A"))
	var before := _bytes(path)
	SaveGame.fault_injection = "corrupt_tmp"
	check_eq(SaveGame.write(_data("B")), ERR_FILE_CORRUPT, "verification failed")
	SaveGame.fault_injection = ""
	check(SaveGame.last_error.contains("previous save was kept"), "says so: %s" % SaveGame.last_error)
	check_eq(_bytes(path), before, "old file byte-for-byte intact")
	check(not FileAccess.file_exists(path + ".tmp"), "temp removed")
	check(not FileAccess.file_exists(path + ".bak"), "no rotation happened")
	check_eq(_tag(SaveGame.read()), "A", "still loads A")
	_done()


func test_failed_final_rename_falls_back_to_bak() -> void:
	_fresh()
	SaveGame.write(_data("A"))
	SaveGame.fault_injection = "fail_rename"   # as if the game crashed after the rotation
	check(SaveGame.write(_data("B")) != OK, "write reports the failure")
	SaveGame.fault_injection = ""
	var r := SaveGame.read()
	check(r["ok"] and r["restored_from_backup"], "restored from the backup")
	check_eq(_tag(r), "A", "the last good save")
	check(r.get("backup_reason", "") != "", "says why")
	check(SaveGame.info()["valid"], "info: Continue still works")
	check_eq(SaveGame.write(_data("C")), OK, "the next save works")
	check_eq(_tag(SaveGame.read()), "C", "and is read normally")
	_done()


func test_damaged_main_uses_bak() -> void:
	_fresh()
	SaveGame.write(_data("A"))
	SaveGame.write(_data("B"))
	var b := _bytes(path)
	b[b.size() / 2] ^= 0x5A
	_put(path, b)
	var r := SaveGame.read()
	check(r["ok"] and r["restored_from_backup"] and _tag(r) == "A", "bit flip detected, backup loaded")
	check(r["backup_reason"].contains("damaged"), "reason: %s" % r["backup_reason"])
	var info := SaveGame.info()
	check(info["valid"] and info["restored_from_backup"], "info agrees")
	check_eq(SaveGame.write(_data("C")), OK, "saving over a damaged main works")
	SaveGame.path_override = path + ".bak"
	check_eq(_tag(SaveGame.read()), "A", "the damaged file did not replace the good backup")
	SaveGame.path_override = path
	_done()


func test_damaged_files_without_backup() -> void:
	_fresh()
	SaveGame.write(_data("A"))
	var good := _bytes(path)
	var cases := {
		"empty": PackedByteArray(),
		"truncated": good.slice(0, good.size() / 2),
		"header only": good.slice(0, 30),
		"extended": good + PackedByteArray([1, 2, 3]),
		"garbage": PackedByteArray([7, 1, 255, 0, 3, 9, 9, 9, 9, 9, 9, 9]),
		"text": "hello, this is not a save at all".to_utf8_buffer(),
	}
	for name in cases:
		_put(path, cases[name])
		var r := SaveGame.read()
		check(not r["ok"] and r["error"] != "", "%s: refused (%s)" % [name, r["error"]])
		check_eq(r["data"], {}, "%s: no data" % name)
		var info := SaveGame.info()
		check(info["exists"] and not info["valid"] and info["error"] != "", "%s: info says invalid" % name)
	_put(path, PackedByteArray())
	check(SaveGame.read()["error"].contains("empty"), "empty file message")
	_put(path, good.slice(0, good.size() - 10))
	check(SaveGame.read()["error"].contains("cut off"), "truncated file message")
	_done()


func test_huge_header_values() -> void:
	_fresh()
	SaveGame.write(_data("A"))
	var good := _bytes(path)
	for at in [24, 28, 32]:
		var b := good.duplicate()
		b.encode_u32(at, 0xFFFFFFF0)
		_put(path, b)
		var r := SaveGame.read()
		check(not r["ok"], "huge value at %d refused: %s" % [at, r["error"]])
	_done()


func test_schema_and_foreign_files() -> void:
	_fresh()
	SaveGame.write(_data("A"))
	var good := _bytes(path)
	var older := good.duplicate()
	older.encode_u32(8, 0)
	_put(path, older)
	check(SaveGame.read()["error"].contains("older version"), "older schema")
	check_eq(SaveGame.info()["schema"], 0, "info reports the file's schema")
	var newer := good.duplicate()
	newer.encode_u32(8, SaveGame.SCHEMA + 1)
	_put(path, newer)
	check(SaveGame.read()["error"].contains("newer version"), "newer schema")
	var f := FileAccess.open(path, FileAccess.WRITE)   # the foundation's plain layout
	f.store_var({"game": SaveGame.GAME_ID, "schema": 1, "state": {}}, false)
	f.close()
	check(SaveGame.read()["error"].contains("older version"), "foundation-format file")
	_put(path, var_to_bytes({"state": {}}))
	check(SaveGame.read()["error"].contains("not a Sirens Went Quiet save"), "some other file")
	_done()


func test_info_does_not_unpack_the_payload() -> void:
	_fresh()
	# a well-formed header and checksum around a payload that is not zstd
	var summary := var_to_bytes({"day": 9})
	var payload := "not compressed data".to_utf8_buffer()
	var h := PackedByteArray()
	h.resize(SaveGame.HEADER_SIZE)
	h.fill(0)
	for i in 4:
		h[i] = SaveGame.MAGIC.unicode_at(i)
	h.encode_u32(4, SaveGame.FORMAT)
	h.encode_u32(8, SaveGame.SCHEMA)
	h.encode_u64(12, 1234)
	h.encode_u32(20, SaveGame.CODEC_ZSTD)
	h.encode_u32(24, 1000)
	h.encode_u32(28, summary.size())
	h.encode_u32(32, payload.size())
	var digest := SaveGame._digest(summary, payload)
	for i in 16:
		h[36 + i] = digest[i]
	_put(path, h + summary + payload)
	var info := SaveGame.info()
	check(info["valid"] and info["summary"] == {"day": 9} and info["saved_at"] == 1234, "info reads only header, summary and checksum")
	var r := SaveGame.read()
	check(not r["ok"] and r["error"].contains("unpacked"), "read() does unpack and refuses: %s" % r["error"])
	_done()


func test_directory_in_place_of_the_file() -> void:
	_fresh()
	SaveGame.write(_data("A"))
	SaveGame.write(_data("B"))   # main B, bak A
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path))
	var r := SaveGame.read()
	check(r["ok"] and _tag(r) == "A", "falls back to the backup")
	check(SaveGame.write(_data("C")) != OK, "can't write over a folder, no crash")
	check(SaveGame.last_error != "", "reason given")
	check_eq(_tag(SaveGame.read()), "A", "backup still intact")
	SaveGame.delete_save()
	check(SaveGame.read()["error"].contains("folder"), "explains the folder: %s" % SaveGame.read()["error"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_done()


func test_delete_and_missing() -> void:
	_fresh()
	var r := SaveGame.read()
	check(not r["ok"] and r["error"] == "No saved game.", "no save yet")
	var info := SaveGame.info()
	check(not info["exists"] and not info["valid"], "info: none")
	SaveGame.write(_data("A"))
	SaveGame.write(_data("B"))
	_put(path + ".tmp", PackedByteArray([1, 2, 3]))
	SaveGame.delete_save()
	for p in [path, path + ".bak", path + ".tmp"]:
		check(not FileAccess.file_exists(p), "%s removed" % p.get_file())
	check(not SaveGame.info()["exists"], "a dead run can't be continued")
	SaveGame.delete_save()   # twice is fine
	_done()


func test_stale_tmp_does_not_block_saving() -> void:
	_fresh()
	SaveGame.write(_data("A"))
	_put(path + ".tmp", PackedByteArray([9, 9, 9]))   # left by a crash mid-write
	check_eq(_tag(SaveGame.read()), "A", "ignored by read")
	check_eq(SaveGame.write(_data("B")), OK, "overwritten by the next save")
	check_eq(_tag(SaveGame.read()), "B", "new save")
	_done()
