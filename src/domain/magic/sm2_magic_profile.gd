class_name Sm2MagicProfile
extends RefCounted
var id: String = ""
var mana_max: int = 0
var mana_per_round: int = 0
var arcane_resistance: int = 0
var spells: Array[String] = []

func to_data() -> Dictionary:
	return {"id":id,"mana_max":mana_max,"mana_per_round":mana_per_round,"arcane_resistance":arcane_resistance,"spells":Array(spells).duplicate()}

static func from_data(data: Dictionary) -> Sm2MagicProfile:
	var result: Sm2MagicProfile = Sm2MagicProfile.new()
	result.id = data.id
	result.mana_max = int(data.mana_max)
	result.mana_per_round = int(data.mana_per_round)
	result.arcane_resistance = int(data.arcane_resistance)
	result.spells.assign(data.spells)
	return result
