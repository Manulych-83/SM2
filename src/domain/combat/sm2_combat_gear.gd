class_name Sm2CombatGear
extends RefCounted
var id: String
var slot: String
var capacity: int
var ammo: int
var melee_defense: int
var ranged_defense: int
var two_handed: bool
var abilities: Array[String] = []

func copy() -> Sm2CombatGear:
	var result: Sm2CombatGear = Sm2CombatGear.new()
	for key: String in ["id", "slot", "capacity", "ammo", "melee_defense", "ranged_defense", "two_handed"]:
		result.set(key, get(key))
	result.abilities.assign(abilities)
	return result
