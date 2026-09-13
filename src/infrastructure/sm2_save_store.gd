class_name Sm2SaveStore
extends RefCounted

const FORMAT: String = "sm2.save"
const SCHEMA_VERSION: int = 2
const MAX_FILE_BYTES: int = 8 * 1024 * 1024
const MAX_DEPTH: int = 32
const MAX_NODES: int = 50000
const LARGE_MAX_NODES: int = 200000
## Selected by the trusted content/session, never by fields inside a save file.
var large_profile: bool=false
func node_budget() -> int: return LARGE_MAX_NODES if large_profile else MAX_NODES
const MAX_COLLECTION_SIZE: int = 10000
const MAX_STRING_LENGTH: int = 1024 * 1024
const MAX_SAFE_INTEGER: int = 9007199254740991

var _base_directory: String
var _base_error: String


func _init(base_directory: String = "user://saves") -> void:
	_base_error = _validate_directory(base_directory)
	_base_directory = ProjectSettings.globalize_path(base_directory.replace("\\", "/").trim_suffix("/"))


func has_slot(slot_name: String = "session") -> bool:
	return _location_error(slot_name).is_empty() and FileAccess.file_exists(_slot_path(slot_name))


func save_slot(payload: Dictionary, slot_name: String = "session") -> Dictionary:
	var problem: String = _location_error(slot_name)
	if not problem.is_empty():
		return _failure(problem)
	var budget: Array[int] = [node_budget()]
	problem = _validate_value(payload, 0, budget)
	if not problem.is_empty():
		return _failure("Некорректные данные сохранения: " + problem)
	# Work only with a detached, validated tree. Arbitrary Objects are never encoded.
	var detached: Dictionary = payload.duplicate(true)
	var envelope: Dictionary = {"format": FORMAT, "schema_version": SCHEMA_VERSION,
		"payload": detached, "checksum": Sm2Canonical.hash(detached)}
	var serialized: String = Sm2Canonical.stringify(envelope)
	if serialized.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return _failure("Размер сохранения превышает лимит 8 МиБ.")
	var directory_error: Error = _ensure_directory()
	if directory_error != OK:
		return _failure("Не удалось подготовить каталог сохранений: %s" % error_string(directory_error))
	var current_path: String = _slot_path(slot_name)
	var temporary_path: String = current_path + ".tmp"
	var backup_path: String = current_path + ".bak"
	var had_previous: bool = FileAccess.file_exists(current_path)
	if had_previous:
		var previous: Dictionary = _read_envelope(current_path,large_profile)
		if not previous["ok"]:
			return _failure("Предыдущий слот повреждён; он сохранён без изменений.")
	var temporary: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary == null:
		return _failure("Не удалось открыть временный файл: %s" % error_string(FileAccess.get_open_error()))
	temporary.store_string(serialized)
	temporary.flush()
	var write_error: Error = temporary.get_error()
	temporary.close()
	if write_error != OK:
		_remove_if_present(temporary_path)
		return _failure("Ошибка записи временного файла: %s" % error_string(write_error))
	var reloaded: Dictionary = _read_envelope(temporary_path,large_profile)
	if not reloaded["ok"] or Sm2Canonical.hash(reloaded["payload"]) != envelope["checksum"]:
		_remove_if_present(temporary_path)
		return _failure("Проверка временного сохранения не пройдена; слот не изменён.")
	if had_previous:
		if FileAccess.file_exists(backup_path):
			var cleanup_error: Error = DirAccess.remove_absolute(backup_path)
			if cleanup_error != OK:
				_remove_if_present(temporary_path)
				return _failure("Не удалось обновить резервную копию; слот не изменён.")
		var backup_error: Error = DirAccess.rename_absolute(current_path, backup_path)
		if backup_error != OK:
			_remove_if_present(temporary_path)
			return _failure("Не удалось создать резервную копию; слот не изменён.")
	var publish_error: Error = DirAccess.rename_absolute(temporary_path, current_path)
	if publish_error != OK:
		var rollback_error: Error = OK
		if had_previous:
			rollback_error = DirAccess.rename_absolute(backup_path, current_path)
		_remove_if_present(temporary_path)
		if rollback_error != OK:
			return _failure("Публикация не удалась. Предыдущие данные остались в .bak; автоматическое восстановление не удалось.")
		return _failure("Публикация не удалась; предыдущий слот восстановлен.")
	# Rename publication is guarded, but is not a hardware-level atomicity guarantee.
	return {"ok": true, "errors": PackedStringArray()}


func load_slot(slot_name: String = "session") -> Dictionary:
	var problem: String = _location_error(slot_name)
	if not problem.is_empty():
		return _failure(problem)
	return _read_envelope(_slot_path(slot_name),large_profile)


func _slot_path(slot_name: String) -> String:
	return _base_directory.path_join(slot_name + ".json")


func _location_error(slot_name: String) -> String:
	if not _base_error.is_empty():
		return _base_error
	if slot_name.is_empty() or slot_name.length() > 64:
		return "Имя слота должно содержать от 1 до 64 символов."
	for index: int in slot_name.length():
		var code: int = slot_name.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90)
				or (code >= 97 and code <= 122) or code == 45 or code == 95):
			return "Имя слота допускает только латинские буквы, цифры, дефис и подчёркивание."
	var upper: String = slot_name.to_upper()
	if upper in ["CON", "PRN", "AUX", "NUL"]:
		return "Зарезервированное системой имя слота."
	if upper.length() == 4 and (upper.begins_with("COM") or upper.begins_with("LPT")):
		if upper.unicode_at(3) >= 49 and upper.unicode_at(3) <= 57:
			return "Зарезервированное системой имя слота."
	return ""


static func _validate_directory(directory: String) -> String:
	if directory.is_empty() or directory != directory.strip_edges():
		return "Некорректный каталог сохранений."
	for index: int in directory.length():
		if directory.unicode_at(index) < 32:
			return "Управляющие символы в пути сохранений запрещены."
	var normalized: String = directory.replace("\\", "/")
	if normalized.begins_with("res://"):
		return "Сохранения нельзя записывать в ресурсы проекта."
	if not normalized.begins_with("user://") and not normalized.is_absolute_path():
		return "Каталог сохранений должен быть user:// или абсолютным путём."
	var segments: PackedStringArray = normalized.split("/", false)
	for segment: String in segments:
		if segment == "." or segment == "..":
			return "Переходы между каталогами в пути сохранений запрещены."
	if normalized == "/" or normalized == "user://" or normalized.trim_suffix("/").ends_with(":"):
		return "Укажите отдельный каталог сохранений."
	return ""


func _ensure_directory() -> Error:
	# Recursive helper in Godot logs an engine error for a regular-file ancestor.
	# Inspect the whole ancestor chain before creating any missing components.
	var missing: Array[String] = []
	var cursor: String = _base_directory
	while not DirAccess.dir_exists_absolute(cursor):
		if FileAccess.file_exists(cursor):
			return ERR_ALREADY_EXISTS
		missing.append(cursor)
		var parent: String = cursor.get_base_dir()
		if parent.is_empty() or parent == cursor:
			return ERR_INVALID_PARAMETER
		cursor = parent
	missing.reverse()
	for path: String in missing:
		var result: Error = DirAccess.make_dir_absolute(path)
		if result != OK:
			return result
	return OK


static func _read_envelope(path: String,large: bool=false) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("Сохранение не найдено.")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Не удалось прочитать сохранение: %s" % error_string(FileAccess.get_open_error()))
	var byte_count: int = file.get_length()
	if byte_count < 2 or byte_count > MAX_FILE_BYTES:
		file.close()
		return _failure("Недопустимый размер файла сохранения.")
	var buffer: PackedByteArray = file.get_buffer(byte_count)
	file.close()
	if buffer.size() != byte_count:
		return _failure("Файл сохранения прочитан не полностью.")
	var source: String = buffer.get_string_from_utf8()
	if not _json_depth_allowed(source):
		return _failure("Превышена допустимая вложенность файла сохранения.")
	var json: JSON = JSON.new()
	if json.parse(source) != OK:
		return _failure("Файл сохранения содержит повреждённый JSON.")
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failure("Корень сохранения должен быть объектом.")
	var envelope: Dictionary = json.data
	if typeof(envelope.get("format")) != TYPE_STRING or envelope.get("format") != FORMAT:
		return _failure("Неизвестный формат сохранения.")
	var version: Variant = envelope.get("schema_version")
	if typeof(version) != TYPE_FLOAT and typeof(version) != TYPE_INT:
		return _failure("Версия схемы должна быть целым числом.")
	if not is_finite(float(version)) or float(version) != floor(float(version)):
		return _failure("Некорректная версия схемы.")
	if version != 1 and version != SCHEMA_VERSION:
		return _failure("Версия сохранения не поддерживается: %s." % str(version))
	var payload_key: String = "payload" if version == SCHEMA_VERSION else "state"
	if envelope.size() != 4 or not envelope.has(payload_key) or not envelope.has("checksum"):
		return _failure("Неправильный набор полей сохранения.")
	if typeof(envelope[payload_key]) != TYPE_DICTIONARY:
		return _failure("Данные сессии должны быть объектом.")
	if typeof(envelope["checksum"]) != TYPE_STRING or not _valid_checksum(envelope["checksum"]):
		return _failure("Некорректный формат контрольной суммы.")
	var payload: Dictionary = envelope[payload_key]
	var budget: Array[int] = [LARGE_MAX_NODES if large else MAX_NODES]
	var problem: String = _validate_value(payload, 0, budget)
	if not problem.is_empty():
		return _failure("Некорректные данные сохранения: " + problem)
	if Sm2Canonical.hash(payload) != envelope["checksum"]:
		return _failure("Контрольная сумма сохранения не совпадает.")
	# Schema 1 is an artificial migration fixture: verify it before renaming state.
	# Migration is in memory only; reading never rewrites the user's file.
	return {"ok": true, "payload": payload.duplicate(true), "errors": PackedStringArray()}


static func _validate_value(value: Variant, depth: int, budget: Array[int]) -> String:
	if depth > MAX_DEPTH:
		return "слишком глубокая вложенность."
	budget[0] -= 1
	if budget[0] < 0:
		return "слишком много элементов."
	match typeof(value):
		TYPE_NIL, TYPE_BOOL:
			return ""
		TYPE_INT:
			return "" if value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER else "большие целые числа должны быть строками."
		TYPE_FLOAT:
			return "" if is_finite(value) and absf(value) <= MAX_SAFE_INTEGER else "недопустимое число."
		TYPE_STRING:
			return "" if value.length() <= MAX_STRING_LENGTH else "слишком длинная строка."
		TYPE_ARRAY:
			if value.size() > MAX_COLLECTION_SIZE:
				return "слишком большой массив."
			for element: Variant in value:
				var problem: String = _validate_value(element, depth + 1, budget)
				if not problem.is_empty():
					return problem
		TYPE_DICTIONARY:
			if value.size() > MAX_COLLECTION_SIZE:
				return "слишком большой объект."
			for key: Variant in value:
				if typeof(key) != TYPE_STRING or key.length() > 256:
					return "ключи должны быть строками длиной до 256 символов."
				var problem: String = _validate_value(value[key], depth + 1, budget)
				if not problem.is_empty():
					return problem
		_:
			return "разрешены только явные JSON-значения."
	return ""


static func _valid_checksum(checksum: String) -> bool:
	if checksum.length() != 64:
		return false
	for index: int in checksum.length():
		var code: int = checksum.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _json_depth_allowed(source: String) -> bool:
	var depth: int = 0
	var in_string: bool = false
	var escaped: bool = false
	for index: int in source.length():
		var code: int = source.unicode_at(index)
		if in_string:
			if escaped:
				escaped = false
			elif code == 92:
				escaped = true
			elif code == 34:
				in_string = false
		elif code == 34:
			in_string = true
		elif code == 123 or code == 91:
			depth += 1
			if depth > MAX_DEPTH + 2:
				return false
		elif code == 125 or code == 93:
			depth -= 1
	return true


static func _remove_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "payload": {}, "errors": PackedStringArray([message])}
