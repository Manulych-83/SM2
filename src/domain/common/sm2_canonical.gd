class_name Sm2Canonical
extends RefCounted
## Stable JSON encoding. Integer-valued JSON floats equal their original ints.

static func stringify(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var keys: Array = value.keys()
			keys.sort()
			var parts: PackedStringArray = []
			for key: String in keys:
				parts.append(JSON.stringify(key) + ":" + stringify(value[key]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var parts: PackedStringArray = []
			for entry: Variant in value:
				parts.append(stringify(entry))
			return "[" + ",".join(parts) + "]"
		TYPE_FLOAT:
			if is_finite(value) and value == floor(value) and absf(value) <= 9007199254740991.0:
				return str(int(value))
			return JSON.stringify(value, "", true, true)
		_:
			return JSON.stringify(value)

static func hash(value: Variant) -> String:
	return stringify(value).sha256_text()

static func is_json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			return value >= -9007199254740991 and value <= 9007199254740991
		TYPE_FLOAT:
			return is_finite(value) and absf(value) <= 9007199254740991.0
		TYPE_ARRAY:
			for entry: Variant in value:
				if not is_json_safe(entry, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not is_json_safe(value[key], depth + 1):
					return false
			return true
	return false
