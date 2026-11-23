extends SceneTree
## Minimal headless test runner for Experiment 001 (no external framework).
##
##   godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd
##   godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=voxel
##
## Runs every method named test_* in every res://tests/**/test_*.gd script.
## Test scripts extend res://tests/test_case.gd. Methods may await.
## Exit code 0 = all passed, 1 = failures.

var _filter := ""
var _failures := PackedStringArray()
var _passed := 0
var _skipped := PackedStringArray()


func _initialize() -> void:
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
			await t.call(name)
			await t.cleanup()
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
