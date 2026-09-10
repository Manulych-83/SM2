class_name Sm2MagicCatalog
extends RefCounted
const AREA_VERSION: String = "sm2.m4.areas.content.1"
var _raw: Dictionary = {}
var _hash: String = ""
var _spells: Dictionary[String, Sm2SpellDefinition] = {}
var _profiles: Dictionary[String, Sm2MagicProfile] = {}

func build(raw: Dictionary, combat: Sm2CombatCatalog, effects: Sm2EffectCatalog) -> PackedStringArray:
	if combat == null or effects == null or not Sm2Validate.fields(raw,["version","spells","profiles"]) or not Sm2Validate.text(raw.version): return _error("magic_catalog_shape")
	if combat.fingerprint().is_empty() or effects.fingerprint().is_empty(): return _error("magic_dependencies")
	var normalized: Dictionary = {"version":raw.version}
	for group: String in ["spells","profiles"]:
		if not raw[group] is Array or raw[group].is_empty() or raw[group].size() > 10000: return _error("magic_group")
		var entries: Array[Dictionary] = []
		var ids: Dictionary = {}
		for entry: Variant in raw[group]:
			if not entry is Dictionary or not Sm2Validate.text(entry.get("id")) or ids.has(entry.id): return _error("magic_id")
			ids[entry.id] = true
			entries.append(entry.duplicate(true))
		entries.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.id < b.id)
		normalized[group] = entries
	var spells: Dictionary[String, Sm2SpellDefinition] = {}
	var profiles: Dictionary[String, Sm2MagicProfile] = {}
	for data: Dictionary in normalized.spells:
		var fields: Array[String] = ["id","name","operation","target_side","ap_cost","fatigue_cost","mana_cost","range_min","range_max","damage","channel"]
		var area: bool = data.get("operation") == "area_hp_damage"
		if area: fields.append("radius")
		if not Sm2Validate.fields(data,fields) or not Sm2Validate.text(data.name): return _error("spell_fields")
		if combat.ability(data.id) != null or effects.action(data.id) != null: return _error("spell_id_collision")
		if data.operation not in ["direct_hp_damage","area_hp_damage"] or data.target_side != "enemy" or data.channel != "arcane": return _error("spell_operation")
		if area:
			if raw.version != AREA_VERSION or not Sm2Validate.integer(data.radius,1,3): return _error("spell_area")
			data.radius = int(data.radius)
		for key: String in ["ap_cost","fatigue_cost","mana_cost","range_min","range_max","damage"]:
			var upper: int = 64 if key.begins_with("range") else 10000
			if not Sm2Validate.integer(data[key],0 if key == "fatigue_cost" else 1,upper): return _error("spell_range")
			data[key] = int(data[key])
		if data.range_min > data.range_max: return _error("spell_range")
		spells[data.id] = Sm2SpellDefinition.from_data(data)
	for data: Dictionary in normalized.profiles:
		if not Sm2Validate.fields(data,["id","mana_max","mana_per_round","arcane_resistance","spells"]) or combat.profile(data.id) == null: return _error("magic_profile_fields")
		if not Sm2Validate.integer(data.mana_max,0,10000) or not Sm2Validate.integer(data.mana_per_round,0,10000) or not Sm2Validate.integer(data.arcane_resistance,0,100) or not Sm2Validate.string_list(data.spells): return _error("magic_profile_values")
		for id: String in data.spells:
			if not spells.has(id): return _error("magic_spell_reference")
		for key: String in ["mana_max","mana_per_round","arcane_resistance"]: data[key] = int(data[key])
		data.spells.sort()
		profiles[data.id] = Sm2MagicProfile.from_data(data)
	_raw = normalized
	_hash = Sm2Canonical.hash(normalized)
	_spells = spells
	_profiles = profiles
	return PackedStringArray()

func fingerprint() -> String: return _hash
func supports_areas() -> bool: return _raw.get("version") == AREA_VERSION
func to_data() -> Dictionary: return _raw.duplicate(true)
func spell(id: String) -> Sm2SpellDefinition:
	return Sm2SpellDefinition.from_data(_spells[id].to_data()) if _spells.has(id) else null
func profile(id: String) -> Sm2MagicProfile:
	return Sm2MagicProfile.from_data(_profiles[id].to_data()) if _profiles.has(id) else null
static func _error(reason: String) -> PackedStringArray: return PackedStringArray([reason])
