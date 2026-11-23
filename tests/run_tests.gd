extends SceneTree
## Minimal headless test runner for Experiment 001 (no external framework).
##
##   godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd
##   godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=voxel
##
## Runs every method named test_* in every res://tests/**/test_*.gd script.
## Test scripts extend res://tests/test_case.gd. Methods may await.
## Exit code 0 = all passed, 1 = failures.
## A GDScript runtime error during a test (which aborts the test function
## silently) is caught by a Logger and fails that test.

var _filter := ""
var _failures := PackedStringArray()
var _passed := 0
var _skipped := PackedStringArray()
var _errors := ErrorCatcher.new()


class ErrorCatcher extends Logger:
	var _lock := Mutex.new()
	var _seen := PackedStringArray()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array) -> void:
		if error_type != Logger.ERROR_TYPE_SCRIPT:
			return
		_lock.lock()
		_seen.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> PackedStringArray:
		_lock.lock()
		var out := _seen.duplicate()
		_seen.clear()
		_lock.unlock()
		return out


func _initialize() -> void:
	OS.add_logger(_errors)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			_filter = a.trim_prefix("--filter=")
	_run()


func _run() -> void:
	var files := _find("res://tests")
	files.sort()
	for f in files:
		var script: GDScript = load(f)
		if script == null:
			_failures.append("%s: failed to load" % f)
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var id := "%s::%s" % [f.get_file().get_basename(), name]
			if _filter != "" and not id.contains(_filter):
				continue
			var t = script.new()
			t.tree = self
			t.test_id = id
			var t0 := Time.get_ticks_msec()
			_errors.take()
			await t.call(name)
			await t.cleanup()
			for e in _errors.take():
				t.failures.append("%s: script error: %s" % [id, e])
			var ms := Time.get_ticks_msec() - t0
			if t.skipped != "":
				_skipped.append("%s (%s)" % [id, t.skipped])
				print("SKIP  %s  - %s" % [id, t.skipped])
			elif t.failures.is_empty():
				_passed += 1
				print("PASS  %s  (%d ms)" % [id, ms])
			else:
				for msg in t.failures:
					_failures.append(msg)
					print("FAIL  %s" % msg)
	print("\n%d passed, %d failed, %d skipped" % [_passed, _failures.size(), _skipped.size()])
	quit(1 if not _failures.is_empty() else 0)


func _find(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		out.append_array(_find(dir.path_join(sub)))
	for file in d.get_files():
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			out.append(dir.path_join(file))
	return out
