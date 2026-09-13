class_name Sm2SurvivalCatalog
extends RefCounted
const MAX_ITEMS: int=10000
var _raw: Dictionary = {}
var _items: Dictionary={}
var _parts: Dictionary={}
var _devices: Dictionary={}
var _fingerprint: String=""

func build(raw: Dictionary) -> PackedStringArray:
	var layered: bool=raw.get("version")=="sm2.survival.content.3"
	var enhanced: bool=layered or raw.get("version")=="sm2.survival.content.2"
	var fields: Array[String]=["version","blood_max","blood_fatal","bleeding_per_damage","round_seconds","bandage_ap","bandage_seconds","parts","items"]
	if enhanced: fields.append("devices")
	if layered: fields.append_array(["tissue_layers","supplies"])
	if not Sm2Validate.fields(raw,fields) or raw.version not in ["sm2.survival.content.1","sm2.survival.content.2","sm2.survival.content.3"]: return PackedStringArray(["survival_catalog_fields"])
	for key: String in ["blood_max","blood_fatal","bleeding_per_damage","round_seconds","bandage_ap","bandage_seconds"]:
		if not Sm2Validate.integer(raw[key],1,10000): return PackedStringArray(["survival_catalog_number"])
	if int(raw.blood_fatal)>=int(raw.blood_max) or not raw.parts is Array or raw.parts.is_empty() or raw.parts.size()>64 or not raw.items is Array or raw.items.is_empty() or raw.items.size()>MAX_ITEMS: return PackedStringArray(["survival_catalog_bounds"])
	var ids: Array[String] = []
	for part: Variant in raw.parts:
		if not part is Dictionary or not Sm2Validate.fields(part,["id","name","capacity","critical","parent"]) or not Sm2Validate.text(part.id) or part.id in ids or not Sm2Validate.text(part.name) or not part.critical is bool or not Sm2Validate.integer(part.capacity,1,10000) or not part.parent is String: return PackedStringArray(["survival_part"])
		if not part.parent.is_empty() and part.parent not in ids: return PackedStringArray(["survival_part_parent"])
		ids.append(part.id)
	for required: String in ["head","torso","right_hand","left_hand","right_leg","left_leg","brain","heart"]:
		if required not in ids: return PackedStringArray(["survival_human_parts"])
	var part_ids: Array[String]=ids.duplicate()
	ids.clear()
	var item_ids: Dictionary={}
	for item: Variant in raw.items:
		if not item is Dictionary or not Sm2Validate.fields(item,["id","name","mass","volume","size","capacity","max_mass","max_size","quick","slot"]) or not Sm2Validate.text(item.id) or item_ids.has(item.id) or not Sm2Validate.text(item.name) or not item.quick is bool or not item.slot is String: return PackedStringArray(["physical_item_definition"])
		for key: String in ["mass","volume","size","capacity","max_mass","max_size"]:
			if not Sm2Validate.integer(item[key],0,1000000): return PackedStringArray(["physical_item_number"])
		if int(item.size)<1 or int(item.volume)<1 or (int(item.capacity)>0 and (int(item.max_mass)<1 or int(item.max_size)<1)): return PackedStringArray(["physical_item_capacity"])
		ids.append(item.id)
		item_ids[item.id]=true
	for required: String in ["bandage","pockets","belt","backpack","stash"]:
		if required not in ids: return PackedStringArray(["physical_fixture_items"])
	if enhanced:
		var reason: String=Sm2SurvivalDevices.validate_catalog(raw.devices,raw.items,part_ids)
		if not reason.is_empty(): return PackedStringArray([reason])
		if "repair_parts" not in ids: return PackedStringArray(["survival_repair_parts_missing"])
	if layered:
		var error: String=Sm2TissueLayers.validate(raw.tissue_layers,raw.parts)
		if not error.is_empty(): return PackedStringArray([error])
		if not raw.supplies is Dictionary or not Sm2Validate.fields(raw.supplies,["care","upgrades"]): return PackedStringArray(["physical_supply_binding"])
		var mapped: Array[String]=[]
		for group: String in ["care","upgrades"]:
			if not raw.supplies[group] is Dictionary or raw.supplies[group].is_empty(): return PackedStringArray(["physical_supply_binding"])
			for id: Variant in raw.supplies[group]:
				var definition: Variant=raw.supplies[group][id]
				if not Sm2Validate.text(id) or not definition is String or not item_ids.has(definition) or definition in mapped: return PackedStringArray(["physical_supply_definition"])
				mapped.append(definition)
	_raw = raw.duplicate(true)
	_items={}; _parts={}; _devices={}; _fingerprint=""
	for item: Dictionary in _raw.items: _items[item.id]=item
	for part: Dictionary in _raw.parts: _parts[part.id]=part
	for device: Dictionary in _raw.get("devices",{}).get("definitions",[]): _devices[device.id]=device
	return PackedStringArray()

func to_data() -> Dictionary: return _raw.duplicate(true)
func fingerprint() -> String:
	if _fingerprint.is_empty(): _fingerprint=Sm2Canonical.hash(_raw)
	return _fingerprint
func item(id: String) -> Dictionary:
	return _items.get(id,{}).duplicate(true)
func part_name(id: String) -> String:
	return str(_parts[id].name) if _parts.has(id) else id

func has_layers() -> bool: return _raw.get("version")=="sm2.survival.content.3"
func has_devices() -> bool: return has_layers() or _raw.get("version")=="sm2.survival.content.2"
func devices() -> Dictionary: return _raw.get("devices",{}).duplicate(true)
func device(id: String) -> Dictionary:
	return _devices.get(id,{}).duplicate(true)
func state_format() -> String: return "sm2.survival_state.3" if has_layers() else "sm2.survival_state.2" if has_devices() else "sm2.survival_state.1"
func battle_schema() -> int: return 21 if has_layers() else 20 if has_devices() else 19
func battle_ruleset() -> String: return "sm2.survival_encounter.3" if has_layers() else "sm2.survival_encounter.2" if has_devices() else "sm2.survival_encounter.1"
