class_name Sm2AiProfile
extends RefCounted
const POLICY: String = "sm2.ai.greedy.1"
const ABILITY_POLICY: String = "sm2.ai.abilities.1"
const AREA_POLICY: String = "sm2.ai.areas.1"
var _data: Dictionary = {}

func build(raw: Dictionary) -> PackedStringArray:
	var fields: Array[String] = ["policy", "hp_weight", "armor_weight", "shield_threshold", "attempt_limit", "query_limit"]
	if raw.get("policy") in [ABILITY_POLICY,AREA_POLICY]:
		fields.append_array(["mana_weight","low_mana_weight","mana_reserve","defense_weight","effect_horizon","future_tick_percent"])
	if not Sm2Validate.fields(raw, fields) or raw.policy not in [POLICY,ABILITY_POLICY,AREA_POLICY]:
		return PackedStringArray(["ai_profile_fields"])
	for key: String in ["hp_weight", "armor_weight", "shield_threshold"]:
		if not Sm2Validate.integer(raw[key], 0, 1000):
			return PackedStringArray(["ai_profile_weights"])
	if int(raw.hp_weight) + int(raw.armor_weight) == 0 or not Sm2Validate.integer(raw.attempt_limit, 1, 100) or not Sm2Validate.integer(raw.query_limit, 1, 200000):
		return PackedStringArray(["ai_profile_limits"])
	if raw.policy in [ABILITY_POLICY,AREA_POLICY]:
		for key: String in ["mana_weight","low_mana_weight","mana_reserve","defense_weight"]:
			if not Sm2Validate.integer(raw[key],0,10000): return PackedStringArray(["ai_ability_weights"])
		if not Sm2Validate.integer(raw.effect_horizon,1,3) or not Sm2Validate.integer(raw.future_tick_percent,0,100): return PackedStringArray(["ai_ability_horizon"])
	_data = raw.duplicate(true)
	return PackedStringArray()

func to_data() -> Dictionary:
	return _data.duplicate(true)

func fingerprint() -> String:
	return Sm2Canonical.hash(_data)
