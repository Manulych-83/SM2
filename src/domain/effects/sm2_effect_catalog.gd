class_name Sm2EffectCatalog
extends RefCounted
const STATS: Array[String] = ["melee_skill","ranged_skill","melee_defense","ranged_defense"]
var _raw: Dictionary = {}
var _hash: String = ""
var _effects: Dictionary[String, Sm2EffectDefinition] = {}
var _actions: Dictionary[String, Sm2EffectAction] = {}
var _profiles: Dictionary[String, Dictionary] = {}

func build(raw: Dictionary, combat: Sm2CombatCatalog) -> PackedStringArray:
	if combat == null or not Sm2Validate.fields(raw,["version","effects","actions","profiles"]) or not Sm2Validate.text(raw.version): return _error("effect_catalog_shape")
	var normalized: Dictionary = {"version":raw.version}
	for group: String in ["effects","actions","profiles"]:
		if not raw[group] is Array or raw[group].is_empty() or raw[group].size() > 10000: return _error("effect_catalog_group")
		var entries: Array[Dictionary] = []
		var ids: Dictionary = {}
		for entry: Variant in raw[group]:
			if not entry is Dictionary or not Sm2Validate.text(entry.get("id")) or ids.has(entry.id): return _error("effect_definition_id")
			ids[entry.id] = true
			entries.append(entry.duplicate(true))
		entries.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.id < b.id)
		normalized[group] = entries
	var effects: Dictionary[String, Sm2EffectDefinition] = {}
	var actions: Dictionary[String, Sm2EffectAction] = {}
	var profiles: Dictionary[String, Dictionary] = {}
	for data: Dictionary in normalized.effects:
		if not Sm2Validate.fields(data,["id","name","tags","polarity","dispellable","duration","clock","stacking","operations"]) or not Sm2Validate.text(data.name) or not _strings(data.tags) or data.polarity not in ["harmful","helpful"] or not data.dispellable is bool or not Sm2Validate.integer(data.duration,1,1000) or data.clock != "target_activation_end" or data.stacking != "refresh": return _error("effect_definition_fields")
		if not data.operations is Array or data.operations.is_empty() or data.operations.size() > 16: return _error("effect_operations")
		for op: Variant in data.operations:
			if not op is Dictionary or not Sm2Validate.fields(op,["kind","stat","channel","amount"]): return _error("effect_operation_shape")
			if op.kind == "flat_stat_modifier":
				if op.stat not in STATS or op.channel != "" or not Sm2Validate.integer(op.amount,-10000,10000): return _error("effect_stat_modifier")
			elif op.kind == "periodic_hp_damage":
				if op.stat != "" or op.channel != "poison" or not Sm2Validate.integer(op.amount,1,10000): return _error("effect_damage_operation")
			else: return _error("effect_operation_unknown")
			data.duration = int(data.duration)
			op.amount = int(op.amount)
		data.tags.sort()
		effects[data.id] = Sm2EffectDefinition.from_data(data)
	for data: Dictionary in normalized.actions:
		if not Sm2Validate.fields(data,["id","name","operation","effect_id","target_side","ap_cost","fatigue_cost","range_min","range_max"]) or not Sm2Validate.text(data.name) or combat.ability(data.id) != null: return _error("effect_action_fields")
		if data.operation not in ["apply_effect","dispel_effects"] or data.target_side not in ["enemy","ally"] or not data.effect_id is String: return _error("effect_action_operation")
		if (data.operation == "apply_effect" and not effects.has(data.effect_id)) or (data.operation == "dispel_effects" and data.effect_id != ""): return _error("effect_action_reference")
		for key: String in ["ap_cost","fatigue_cost","range_min","range_max"]:
			if not Sm2Validate.integer(data[key],1 if key == "ap_cost" else 0,64 if key.begins_with("range") else 1000): return _error("effect_action_range")
			data[key] = int(data[key])
		if data.range_min > data.range_max: return _error("effect_action_range")
		actions[data.id] = Sm2EffectAction.from_data(data)
	for data: Dictionary in normalized.profiles:
		if not Sm2Validate.fields(data,["id","actions","immunities","resistances"]) or combat.profile(data.id) == null or not _strings(data.actions) or not _strings(data.immunities) or not data.resistances is Dictionary: return _error("effect_profile_fields")
		for id: String in data.actions:
			if not actions.has(id): return _error("effect_profile_action")
		for channel: Variant in data.resistances:
			if channel != "poison" or not Sm2Validate.integer(data.resistances[channel],0,100): return _error("effect_resistance")
			data.resistances[channel] = int(data.resistances[channel])
		data.actions.sort()
		data.immunities.sort()
		profiles[data.id] = data.duplicate(true)
	_raw = normalized
	_hash = Sm2Canonical.hash(normalized)
	_effects = effects
	_actions = actions
	_profiles = profiles
	return PackedStringArray()

func fingerprint() -> String: return _hash
func to_data() -> Dictionary: return _raw.duplicate(true)
func definition(id: String) -> Sm2EffectDefinition:
	return Sm2EffectDefinition.from_data(_effects[id].to_data()) if _effects.has(id) else null
func action(id: String) -> Sm2EffectAction:
	return Sm2EffectAction.from_data(_actions[id].to_data()) if _actions.has(id) else null
func profile(id: String) -> Dictionary:
	return _profiles.get(id,{}).duplicate(true)
func grants(id: String) -> Array[String]:
	var result: Array[String] = []
	result.assign(profile(id).get("actions",[]))
	return result
func immune(loadout: String, definition_id: String) -> bool:
	var immunities: Array = profile(loadout).get("immunities",[])
	for tag: String in _effects[definition_id].tags:
		if immunities.has(tag): return true
	return false
func resistance(loadout: String, channel: String) -> int:
	return int(profile(loadout).get("resistances",{}).get(channel,0))
static func _strings(value: Variant) -> bool:
	if not value is Array or value.size() > 1000: return false
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not Sm2Validate.text(entry) or seen.has(entry): return false
		seen[entry] = true
	return true
static func _error(reason: String) -> PackedStringArray: return PackedStringArray([reason])
