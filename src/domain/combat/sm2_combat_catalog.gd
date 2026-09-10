class_name Sm2CombatCatalog
extends RefCounted
const SLOTS: Array[String] = ["weapon", "shield", "body", "head"]
var _raw: Dictionary = {}
var _fingerprint: String = ""
var _turn_fingerprint: String = ""
var _profiles: Dictionary[String, Sm2CombatProfile] = {}
var _gear: Dictionary[String, Sm2CombatGear] = {}
var _abilities: Dictionary[String, Sm2CombatAbility] = {}
var _bodies: Dictionary[String, Array] = {}
var _loadouts: Dictionary[String, Dictionary] = {}

func build(raw: Dictionary, turns: Sm2TurnCatalog) -> PackedStringArray:
	var fields: Array[String] = ["version", "profiles", "bodies", "equipment", "abilities"]
	if raw.get("version") == "sm2.p4.combat.1": fields.append("unarmed_ability")
	if turns == null or not Sm2Validate.fields(raw, fields) or not Sm2Validate.text(raw.version):
		return _error("catalog_shape")
	var normalized: Dictionary = {"version": raw.version}
	for group: String in ["profiles", "bodies", "equipment", "abilities"]:
		if not raw[group] is Array or raw[group].is_empty() or raw[group].size() > 10000:
			return _error("catalog_group")
		var entries: Array[Dictionary] = []
		var seen: Dictionary = {}
		for entry: Variant in raw[group]:
			if not entry is Dictionary or not Sm2Validate.text(entry.get("id")) or seen.has(entry.id):
				return _error("definition_identity")
			seen[entry.id] = true
			entries.append(entry.duplicate(true))
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
		normalized[group] = entries
	var profiles: Dictionary[String, Sm2CombatProfile] = {}
	var gear: Dictionary[String, Sm2CombatGear] = {}
	var abilities: Dictionary[String, Sm2CombatAbility] = {}
	var bodies: Dictionary[String, Array] = {}
	var loadouts: Dictionary[String, Dictionary] = {}
	for body: Dictionary in normalized.bodies:
		if not Sm2Validate.fields(body, ["id", "zones"]) or not body.zones is Array or body.zones.size() != 2:
			return _error("body_shape")
		var total: int = 0
		var zones: Dictionary = {}
		for zone: Variant in body.zones:
			if not zone is Dictionary or not Sm2Validate.fields(zone, ["id", "weight", "hp_percent"]) or zone.id not in ["body", "head"] or zones.has(zone.id):
				return _error("body_zone")
			if not Sm2Validate.integer(zone.weight, 1, 99) or not Sm2Validate.integer(zone.hp_percent, 1, 1000):
				return _error("body_weights")
			zone.weight = int(zone.weight)
			zone.hp_percent = int(zone.hp_percent)
			zones[zone.id] = true
			total += zone.weight
		if total != 100:
			return _error("body_total")
		# Authored order defines the deterministic zone roll intervals.
		bodies[body.id] = body.zones.duplicate(true)
	for entry: Dictionary in normalized.profiles:
		if not Sm2Validate.fields(entry, ["id", "body_id", "hp_max", "melee_skill", "ranged_skill", "melee_defense", "ranged_defense", "resolve", "morale_immune"]):
			return _error("profile_fields")
		if not entry.body_id is String or not bodies.has(entry.body_id) or not entry.morale_immune is bool:
			return _error("profile_body")
		var definition: Sm2CombatProfile = Sm2CombatProfile.new()
		for key: String in ["hp_max", "melee_skill", "ranged_skill", "melee_defense", "ranged_defense", "resolve"]:
			if not Sm2Validate.integer(entry[key], 1 if key == "hp_max" else 0, 10000):
				return _error("profile_stat")
			entry[key] = int(entry[key])
		for key: String in entry:
			definition.set(key, entry[key])
		profiles[entry.id] = definition
	for entry: Dictionary in normalized.abilities:
		if not Sm2Validate.fields(entry, ["id", "operation", "mode", "ap_cost", "fatigue_cost", "range_min", "range_max", "damage_min", "damage_max", "hit_bonus", "armor_percent", "penetration_percent", "ammo_cost", "shield_damage", "melee_bonus", "ranged_bonus"]):
			return _error("ability_fields")
		if entry.operation not in ["damage", "shield_break", "shieldwall"] or entry.mode not in ["melee", "ranged", "self"]:
			return _error("unsupported_operation")
		var definition: Sm2CombatAbility = Sm2CombatAbility.new()
		for key: String in entry:
			if key in ["id", "operation", "mode"]:
				continue
			if not Sm2Validate.integer(entry[key], -100 if key == "hit_bonus" else 0, 1000):
				return _error("ability_stat")
			entry[key] = int(entry[key])
		if entry.ap_cost < 1 or entry.penetration_percent > 100 or entry.range_max > 64 or entry.range_min > entry.range_max or entry.damage_min > entry.damage_max:
			return _error("ability_bounds")
		if entry.operation == "damage":
			if entry.mode == "self" or entry.damage_min < 1 or entry.shield_damage != 0 or entry.melee_bonus != 0 or entry.ranged_bonus != 0:
				return _error("damage_contract")
			if (entry.mode == "melee" and (entry.range_min != 1 or entry.range_max != 1 or entry.ammo_cost != 0)) or (entry.mode == "ranged" and (entry.range_min < 2 or entry.ammo_cost < 1)):
				return _error("attack_range")
		elif entry.damage_min != 0 or entry.damage_max != 0 or entry.hit_bonus != 0 or entry.armor_percent != 0 or entry.penetration_percent != 0 or entry.ammo_cost != 0:
			return _error("non_damage_contract")
		elif entry.operation == "shield_break":
			if entry.mode != "melee" or entry.range_min != 1 or entry.range_max != 1 or entry.shield_damage < 1 or entry.melee_bonus != 0 or entry.ranged_bonus != 0:
				return _error("shield_break_contract")
		elif entry.mode != "self" or entry.range_min != 0 or entry.range_max != 0 or entry.shield_damage != 0:
			return _error("shieldwall_contract")
		for key: String in entry:
			definition.set(key, entry[key])
		abilities[entry.id] = definition
	if fields.has("unarmed_ability"):
		if not raw.unarmed_ability is String or not abilities.has(raw.unarmed_ability): return _error("unarmed_reference")
		var unarmed: Sm2CombatAbility = abilities[raw.unarmed_ability]
		if unarmed.operation != "damage" or unarmed.mode != "melee": return _error("unarmed_contract")
		normalized["unarmed_ability"] = raw.unarmed_ability
	for entry: Dictionary in normalized.equipment:
		if not Sm2Validate.fields(entry, ["id", "slot", "capacity", "ammo", "melee_defense", "ranged_defense", "two_handed", "abilities"]) or entry.slot not in SLOTS or not entry.two_handed is bool or not Sm2Validate.string_list(entry.abilities) or entry.abilities.size() > 32:
			return _error("gear_fields")
		for key: String in ["capacity", "ammo", "melee_defense", "ranged_defense"]:
			if not Sm2Validate.integer(entry[key], 0, 10000):
				return _error("gear_stat")
			entry[key] = int(entry[key])
		if (entry.slot == "weapon" and entry.capacity != 0) or (entry.slot != "weapon" and (entry.two_handed or entry.ammo != 0)) or (entry.slot in ["head", "body", "shield"] and entry.capacity < 1) or (entry.slot != "shield" and (entry.melee_defense != 0 or entry.ranged_defense != 0)):
			return _error("gear_slot_values")
		var ranged: bool = false
		var melee: bool = false
		var walls: int = 0
		for id: String in entry.abilities:
			if not abilities.has(id):
				return _error("ability_reference")
			var ability: Sm2CombatAbility = abilities[id]
			if (entry.slot == "shield" and ability.operation != "shieldwall") or (entry.slot == "weapon" and ability.operation == "shieldwall") or entry.slot in ["body", "head"]:
				return _error("ability_slot")
			ranged = ranged or ability.mode == "ranged"
			melee = melee or (ability.mode == "melee" and ability.operation == "damage")
			walls += 1 if ability.operation == "shieldwall" else 0
		if walls > 1 or (ranged and (not entry.two_handed or melee or entry.ammo == 0)) or (not ranged and entry.ammo != 0):
			return _error("gear_attack_modes")
		var definition: Sm2CombatGear = Sm2CombatGear.new()
		entry.abilities.sort()
		for key: String in entry:
			if key != "abilities":
				definition.set(key, entry[key])
		definition.abilities.assign(entry.abilities)
		gear[entry.id] = definition
	var turn_data: Dictionary = turns.to_data()
	if not turn_data.has("profiles") or profiles.size() != turn_data.profiles.size() or gear.size() != turn_data.equipment.size():
		return _error("turn_coverage")
	for entry: Dictionary in turn_data.profiles:
		if not profiles.has(entry.id):
			return _error("turn_profile_reference")
	for entry: Dictionary in turn_data.equipment:
		if not gear.has(entry.id):
			return _error("turn_equipment_reference")
	for entry: Dictionary in turn_data.loadouts:
		var slots: Dictionary = {}
		for id: String in entry.equipment_ids:
			var slot: String = gear[id].slot
			if slots.has(slot):
				return _error("duplicate_slot")
			slots[slot] = id
		if (not slots.has("weapon") and not normalized.has("unarmed_ability")) or (slots.has("weapon") and gear[slots.weapon].two_handed and slots.has("shield")):
			return _error("incompatible_loadout")
		loadouts[entry.id] = {"profile_id": entry.profile_id, "slots": slots}
	var fingerprint_value: String = Sm2Canonical.hash({"turns": turns.fingerprint(), "combat": normalized})
	_raw = normalized
	_profiles = profiles
	_gear = gear
	_abilities = abilities
	_bodies = bodies
	_loadouts = loadouts
	_turn_fingerprint = turns.fingerprint()
	_fingerprint = fingerprint_value
	return PackedStringArray()

func to_data() -> Dictionary:
	return _raw.duplicate(true)
func unarmed_ability() -> String:
	return _raw.get("unarmed_ability", "")
func fingerprint() -> String:
	return _fingerprint
func matches(turns: Sm2TurnCatalog) -> bool:
	return not _fingerprint.is_empty() and turns != null and turns.fingerprint() == _turn_fingerprint
func profile(loadout_id: String) -> Sm2CombatProfile:
	return _profiles[_loadouts[loadout_id].profile_id].copy() if _loadouts.has(loadout_id) else null
func slots(loadout_id: String) -> Dictionary:
	return _loadouts[loadout_id].slots.duplicate(true) if _loadouts.has(loadout_id) else {}
func gear(id: String) -> Sm2CombatGear:
	return _gear[id].copy() if _gear.has(id) else null
func ability(id: String) -> Sm2CombatAbility:
	return _abilities[id].copy() if _abilities.has(id) else null
func zones(loadout_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var definition: Sm2CombatProfile = profile(loadout_id)
	if definition != null:
		result.assign(_bodies[definition.body_id].duplicate(true))
	return result
static func _error(reason: String) -> PackedStringArray:
	return PackedStringArray(["combat_catalog: " + reason])
