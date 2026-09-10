class_name Sm2CombatAbility
extends RefCounted
var id: String
var operation: String
var mode: String
var ap_cost: int
var fatigue_cost: int
var range_min: int
var range_max: int
var damage_min: int
var damage_max: int
var hit_bonus: int
var armor_percent: int
var penetration_percent: int
var ammo_cost: int
var shield_damage: int
var melee_bonus: int
var ranged_bonus: int

func copy() -> Sm2CombatAbility:
	var result: Sm2CombatAbility = Sm2CombatAbility.new()
	for key: String in ["id", "operation", "mode", "ap_cost", "fatigue_cost", "range_min", "range_max", "damage_min", "damage_max", "hit_bonus", "armor_percent", "penetration_percent", "ammo_cost", "shield_damage", "melee_bonus", "ranged_bonus"]:
		result.set(key, get(key))
	return result
