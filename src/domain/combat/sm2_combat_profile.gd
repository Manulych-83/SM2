class_name Sm2CombatProfile
extends RefCounted
var id: String
var body_id: String
var hp_max: int
var melee_skill: int
var ranged_skill: int
var melee_defense: int
var ranged_defense: int
var resolve: int
var morale_immune: bool

func copy() -> Sm2CombatProfile:
	var result: Sm2CombatProfile = Sm2CombatProfile.new()
	for key: String in ["id", "body_id", "hp_max", "melee_skill", "ranged_skill", "melee_defense", "ranged_defense", "resolve", "morale_immune"]:
		result.set(key, get(key))
	return result
