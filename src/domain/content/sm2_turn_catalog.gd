class_name Sm2TurnCatalog
extends RefCounted
## Atomic, normalized authoring catalog for round resources and initiative.
const GROUPS: Array[String] = ["profiles", "equipment", "loadouts"]
var _data: Dictionary = {}
var _definitions: Dictionary[String, Sm2TurnDefinition] = {}
var _fingerprint: String = Sm2Canonical.hash({})

func build(raw: Dictionary) -> PackedStringArray:
	if not Sm2Validate.fields(raw, ["version", "profiles", "equipment", "loadouts"]) \
		or not Sm2Validate.text(raw.get("version")):
		return _error("expected version, profiles, equipment and loadouts")
	var candidate: Dictionary = {"version": raw.version}
	var indices: Dictionary = {}
	for group: String in GROUPS:
		if not raw[group] is Array or raw[group].size() > 10000:
			return _error(group + ": expected at most 10000 definitions")
		candidate[group] = []
		indices[group] = {}
		for entry: Variant in raw[group]:
			if not entry is Dictionary or not _valid_entry(group, entry):
				return _error(group + ": invalid definition")
			if indices[group].has(entry.id):
				return _error(group + ": duplicate ID " + entry.id)
			var normalized: Dictionary = _normalize(group, entry)
			candidate[group].append(normalized)
			indices[group][entry.id] = normalized
		candidate[group].sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return left.id < right.id)
	var definitions: Dictionary[String, Sm2TurnDefinition] = {}
	for loadout: Dictionary in candidate.loadouts:
		if not indices.profiles.has(loadout.profile_id):
			return _error(loadout.id + ": missing profile " + loadout.profile_id)
		var profile: Dictionary = indices.profiles[loadout.profile_id]
		var load: int = 0
		for equipment_id: String in loadout.equipment_ids:
			if not indices.equipment.has(equipment_id):
				return _error(loadout.id + ": missing equipment " + equipment_id)
			load += int(indices.equipment[equipment_id].load_penalty)
		if load > int(profile.fatigue_base) - 15:
			return _error(loadout.id + ": equipment leaves less than 15 fatigue capacity")
		var resolved: Sm2TurnDefinition = Sm2TurnDefinition.new()
		resolved.id = loadout.id
		resolved.ap_max = int(profile.ap_max)
		resolved.fatigue_base = int(profile.fatigue_base)
		resolved.initiative_base = int(profile.initiative_base)
		resolved.load_penalty = load
		resolved.fatigue_max = resolved.fatigue_base - load
		definitions[resolved.id] = resolved
	var candidate_fingerprint: String = Sm2Canonical.hash(candidate)
	_data = candidate
	_definitions = definitions
	_fingerprint = candidate_fingerprint
	return PackedStringArray()

func to_data() -> Dictionary:
	return _data.duplicate(true)

func fingerprint() -> String:
	return _fingerprint

func version() -> String:
	return _data.get("version", "")

func has_loadout(id: String) -> bool:
	return _definitions.has(id)

func definition(loadout_id: String) -> Sm2TurnDefinition:
	return _definitions[loadout_id].copy() if has_loadout(loadout_id) else null

static func _valid_entry(group: String, entry: Dictionary) -> bool:
	if not Sm2Validate.text(entry.get("id")):
		return false
	match group:
		"profiles":
			return Sm2Validate.fields(entry, ["id", "ap_max", "fatigue_base", "initiative_base"]) \
				and Sm2Validate.integer(entry.ap_max, 1, 1000) \
				and Sm2Validate.integer(entry.fatigue_base, 15, 10000) \
				and Sm2Validate.integer(entry.initiative_base, 0, 10000)
		"equipment":
			return Sm2Validate.fields(entry, ["id", "load_penalty"]) \
				and Sm2Validate.integer(entry.load_penalty, 0, 10000)
		"loadouts":
			return Sm2Validate.fields(entry, ["id", "profile_id", "equipment_ids"]) \
				and Sm2Validate.text(entry.profile_id) and Sm2Validate.string_list(entry.equipment_ids) \
				and entry.equipment_ids.size() <= 64
	return false

static func _normalize(group: String, entry: Dictionary) -> Dictionary:
	match group:
		"profiles":
			return {"id": entry.id, "ap_max": int(entry.ap_max), "fatigue_base": int(entry.fatigue_base),
				"initiative_base": int(entry.initiative_base)}
		"equipment":
			return {"id": entry.id, "load_penalty": int(entry.load_penalty)}
		"loadouts":
			var ids: Array[String] = []
			ids.assign(entry.equipment_ids)
			ids.sort()
			return {"id": entry.id, "profile_id": entry.profile_id, "equipment_ids": ids}
	return {}

static func _error(message: String) -> PackedStringArray:
	return PackedStringArray(["turn catalog: " + message])
