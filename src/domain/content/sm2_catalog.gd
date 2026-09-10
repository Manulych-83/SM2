class_name Sm2Catalog
extends RefCounted
## Only validated definitions are published. Accessors construct detached objects.
const GROUPS: Array[String] = ["actors", "weapons", "abilities", "statuses"]
var _data: Dictionary = {}
var _index: Dictionary = {}

func build(raw: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not Sm2Validate.fields(raw, ["version", "actors", "weapons", "abilities", "statuses"]) or not Sm2Validate.text(raw.get("version")):
		return PackedStringArray(["catalog: expected version and four definition arrays"])
	var candidate: Dictionary = {"version": raw.version}
	var index: Dictionary = {}
	var ids: Dictionary = {}
	for group: String in GROUPS:
		if not raw[group] is Array or raw[group].size() > 10000:
			errors.append(group + ": expected array with <=10000 definitions")
			continue
		candidate[group] = []
		index[group] = {}
		for entry: Variant in raw[group]:
			if not entry is Dictionary or not _valid_entry(group, entry):
				errors.append(group + ": invalid definition " + str(entry.get("id", "?")) if entry is Dictionary else group + ": expected dictionary")
				continue
			if ids.has(entry.id):
				errors.append("duplicate id: " + entry.id)
				continue
			ids[entry.id] = true
			var normalized: Dictionary = _normalize(group, entry)
			candidate[group].append(normalized)
			index[group][entry.id] = normalized
	if not errors.is_empty():
		return errors
	for entry: Dictionary in candidate.actors:
		if not index.weapons.has(entry.weapon_id):
			errors.append(entry.id + ": missing weapon " + entry.weapon_id)
		for ability_id: String in entry.abilities:
			if not index.abilities.has(ability_id):
				errors.append(entry.id + ": missing ability " + ability_id)
		for status_id: String in entry.immunities:
			if not index.statuses.has(status_id):
				errors.append(entry.id + ": missing immunity status " + status_id)
	for entry: Dictionary in candidate.abilities:
		if entry.operation == "status" and not index.statuses.has(entry.status_id):
			errors.append(entry.id + ": missing status " + entry.status_id)
		if entry.operation == "summon" and not index.actors.has(entry.summon_template_id):
			errors.append(entry.id + ": missing summon actor " + entry.summon_template_id)
	if not errors.is_empty():
		return errors
	for group: String in GROUPS:
		candidate[group].sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return left.id < right.id)
	_data = candidate
	_index = index
	return errors

func fingerprint() -> String:
	return Sm2Canonical.hash(_data)

func version() -> String:
	return _data.get("version", "")

func to_data() -> Dictionary:
	return _data.duplicate(true)

func actor(id: String) -> Sm2ActorDefinition:
	return Sm2ActorDefinition.from_data(_index.actors[id]) if has_actor(id) else null

func weapon(id: String) -> Sm2WeaponDefinition:
	return Sm2WeaponDefinition.from_data(_index.weapons[id]) if has_weapon(id) else null

func ability(id: String) -> Sm2AbilityDefinition:
	return Sm2AbilityDefinition.from_data(_index.abilities[id]) if has_ability(id) else null

func status(id: String) -> Sm2StatusDefinition:
	return Sm2StatusDefinition.from_data(_index.statuses[id]) if has_status(id) else null

func has_actor(id: String) -> bool:
	return _index.has("actors") and _index.actors.has(id)

func has_weapon(id: String) -> bool:
	return _index.has("weapons") and _index.weapons.has(id)

func has_ability(id: String) -> bool:
	return _index.has("abilities") and _index.abilities.has(id)

func has_status(id: String) -> bool:
	return _index.has("statuses") and _index.statuses.has(id)

static func _valid_entry(group: String, data: Dictionary) -> bool:
	if not Sm2Validate.text(data.get("id")) or not Sm2Validate.text(data.get("name")):
		return false
	match group:
		"actors":
			return Sm2Validate.fields(data, ["id", "name", "hp", "ap", "max_fatigue", "initiative", "weapon_id", "abilities", "immunities"]) \
				and Sm2Validate.integer(data.hp, 1, 1000000) and Sm2Validate.integer(data.ap, 1, 1000000) \
				and Sm2Validate.integer(data.max_fatigue, 0, 1000000) and Sm2Validate.integer(data.initiative, 0, 1000000) \
				and Sm2Validate.text(data.weapon_id) and Sm2Validate.string_list(data.abilities) and Sm2Validate.string_list(data.immunities)
		"weapons":
			return Sm2Validate.fields(data, ["id", "name", "damage_min", "damage_max", "durability"]) \
				and Sm2Validate.integer(data.damage_min, 0, 1000000) and Sm2Validate.integer(data.damage_max, int(data.damage_min), 1000000) \
				and Sm2Validate.integer(data.durability, 1, 1000000)
		"statuses":
			return Sm2Validate.fields(data, ["id", "name", "tick_damage", "duration"]) \
				and Sm2Validate.integer(data.tick_damage, 0, 1000000) and Sm2Validate.integer(data.duration, 1, 10000)
		"abilities":
			if not Sm2Validate.fields(data, ["id", "name", "operation", "ap_cost", "fatigue_cost", "range", "damage_bonus", "status_id", "summon_template_id"]):
				return false
			if not data.operation in ["damage", "status", "summon"] or not Sm2Validate.integer(data.ap_cost, 0, 1000000) \
				or not Sm2Validate.integer(data.fatigue_cost, 0, 1000000) or not Sm2Validate.integer(data.range, 0, 1000) \
				or not Sm2Validate.integer(data.damage_bonus, 0, 1000000) or not Sm2Validate.text(data.status_id, true) \
				or not Sm2Validate.text(data.summon_template_id, true):
				return false
			if data.operation == "damage":
				return data.status_id.is_empty() and data.summon_template_id.is_empty()
			if data.operation == "status":
				return not data.status_id.is_empty() and data.summon_template_id.is_empty() and int(data.damage_bonus) == 0
			return data.status_id.is_empty() and not data.summon_template_id.is_empty() and int(data.damage_bonus) == 0
	return false

static func _normalize(group: String, data: Dictionary) -> Dictionary:
	match group:
		"actors": return Sm2ActorDefinition.from_data(data).to_data()
		"weapons": return Sm2WeaponDefinition.from_data(data).to_data()
		"abilities": return Sm2AbilityDefinition.from_data(data).to_data()
		"statuses": return Sm2StatusDefinition.from_data(data).to_data()
	return {}
