class_name Sm2ErrorCapture
extends Logger
## Captures engine/script/shader errors, including faults inside called helpers.
## Never log from a Logger callback: doing so would recurse into the logger.

var _mutex: Mutex = Mutex.new()
var _messages: Array[String] = []


func _log_error(function: String, file: String, line: int, code: String,
		rationale: String, _editor_notify: bool, error_type: int,
		_script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type not in [Logger.ERROR_TYPE_ERROR, Logger.ERROR_TYPE_SCRIPT, Logger.ERROR_TYPE_SHADER]:
		return
	var detail: String = code if rationale.is_empty() else code + " | " + rationale
	var message: String = "%s:%s %s: %s" % [file, line, function, detail]
	_mutex.lock()
	_messages.append(message)
	_mutex.unlock()


func messages() -> Array[String]:
	_mutex.lock()
	var detached: Array[String] = _messages.duplicate()
	_mutex.unlock()
	return detached
