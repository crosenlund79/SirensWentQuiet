extends Logger
## Collects push_warning() messages while installed (OS.add_logger).
## Used by the audio and resolver tests to check "warns, then falls back".

var _lock := Mutex.new()
var _lines := PackedStringArray()


func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array) -> void:
	if error_type != Logger.ERROR_TYPE_WARNING:
		return
	_lock.lock()
	_lines.append(rationale if rationale != "" else code)
	_lock.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


func lines() -> PackedStringArray:
	_lock.lock()
	var out := _lines.duplicate()
	_lock.unlock()
	return out


func count(fragment: String) -> int:
	var n := 0
	for l in lines():
		if l.contains(fragment):
			n += 1
	return n
