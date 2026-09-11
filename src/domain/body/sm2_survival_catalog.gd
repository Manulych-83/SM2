class_name Sm2SurvivalCatalog
extends RefCounted
var _raw: Dictionary = {}

func build(raw: Dictionary) -> PackedStringArray:
	if not Sm2Validate.fields(raw,["version","blood_max","blood_fatal","bleeding_per_damage","round_seconds","bandage_ap","bandage_seconds","parts","items"]) or raw.version!="sm2.survival.content.1": return PackedStringArray(["survival_catalog_fields"])
	for key: String in ["blood_max","blood_fatal","bleeding_per_damage","round_seconds","bandage_ap","bandage_seconds"]:
		if not Sm2Validate.integer(raw[key],1,10000): return PackedStringArray(["survival_catalog_number"])
	if int(raw.blood_fatal)>=int(raw.blood_max) or not raw.parts is Array or raw.parts.is_empty() or raw.parts.size()>64 or not raw.items is Array or raw.items.is_empty() or raw.items.size()>1000: return PackedStringArray(["survival_catalog_bounds"])
	var ids: Array[String] = []
	for part: Variant in raw.parts:
		if not part is Dictionary or not Sm2Validate.fields(part,["id","name","capacity","critical","parent"]) or not Sm2Validate.text(part.id) or part.id in ids or not Sm2Validate.text(part.name) or not part.critical is bool or not Sm2Validate.integer(part.capacity,1,10000) or not part.parent is String: return PackedStringArray(["survival_part"])
		if not part.parent.is_empty() and part.parent not in ids: return PackedStringArray(["survival_part_parent"])
		ids.append(part.id)
	for required: String in ["head","torso","right_hand","left_hand","right_leg","left_leg","brain","heart"]:
		if required not in ids: return PackedStringArray(["survival_human_parts"])
	ids.clear()
	for item: Variant in raw.items:
		if not item is Dictionary or not Sm2Validate.fields(item,["id","name","mass","volume","size","capacity","max_mass","max_size","quick","slot"]) or not Sm2Validate.text(item.id) or item.id in ids or not Sm2Validate.text(item.name) or not item.quick is bool or not item.slot is String: return PackedStringArray(["physical_item_definition"])
		for key: String in ["mass","volume","size","capacity","max_mass","max_size"]:
			if not Sm2Validate.integer(item[key],0,1000000): return PackedStringArray(["physical_item_number"])
		if int(item.size)<1 or int(item.volume)<1 or (int(item.capacity)>0 and (int(item.max_mass)<1 or int(item.max_size)<1)): return PackedStringArray(["physical_item_capacity"])
		ids.append(item.id)
	for required: String in ["bandage","pockets","belt","backpack","stash"]:
		if required not in ids: return PackedStringArray(["physical_fixture_items"])
	_raw = raw.duplicate(true)
	return PackedStringArray()

func to_data() -> Dictionary: return _raw.duplicate(true)
func fingerprint() -> String: return Sm2Canonical.hash(_raw)
func item(id: String) -> Dictionary:
	for entry: Dictionary in _raw.items:
		if entry.id == id: return entry.duplicate(true)
	return {}
func part_name(id: String) -> String:
	for part: Dictionary in _raw.parts:
		if part.id == id: return str(part.name)
	return id
