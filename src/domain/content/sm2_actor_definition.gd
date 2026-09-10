class_name Sm2ActorDefinition
extends RefCounted
var id: String = ""
var name: String = ""
var hp: int = 0
var ap: int = 0
var max_fatigue: int = 0
var initiative: int = 0
var weapon_id: String = ""
var abilities: Array[String] = []
var immunities: Array[String] = []

static func from_data(data: Dictionary) -> Sm2ActorDefinition:
	var result: Sm2ActorDefinition = Sm2ActorDefinition.new()
	result.id = data.id
	result.name = data.name
	result.hp = int(data.hp)
	result.ap = int(data.ap)
	result.max_fatigue = int(data.max_fatigue)
	result.initiative = int(data.initiative)
	result.weapon_id = data.weapon_id
	result.abilities.assign(data.abilities)
	result.immunities.assign(data.immunities)
	return result

func to_data() -> Dictionary:
	return {"id": id, "name": name, "hp": hp, "ap": ap, "max_fatigue": max_fatigue,
		"initiative": initiative, "weapon_id": weapon_id, "abilities": Array(abilities).duplicate(), "immunities": Array(immunities).duplicate()}
