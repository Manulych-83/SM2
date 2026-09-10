class_name Sm2Validate
extends RefCounted

static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= minimum and value <= maximum
	if typeof(value) == TYPE_FLOAT:
		return is_finite(value) and value == floor(value) and value >= minimum and value <= maximum
	return false

static func decimal(value: Variant, minimum: int = 0, maximum: int = 9223372036854775806) -> bool:
	if not value is String or value.is_empty():
		return false
	if value.length() > 1 and value.begins_with("0"):
		return false
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if code < 48 or code > 57:
			return false
	var ceiling: String = str(maximum)
	if value.length() > ceiling.length() or (value.length() == ceiling.length() and value > ceiling):
		return false
	return value.to_int() >= minimum

static func fields(data: Dictionary, required: Array[String]) -> bool:
	if data.size() != required.size():
		return false
	for field: String in required:
		if not data.has(field):
			return false
	return true

static func text(value: Variant, allow_empty: bool = false) -> bool:
	return value is String and value.length() <= 256 and (allow_empty or not value.strip_edges().is_empty())

static func string_list(value: Variant) -> bool:
	if not value is Array or value.size() > 1000:
		return false
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not text(entry) or seen.has(entry):
			return false
		seen[entry] = true
	return true
