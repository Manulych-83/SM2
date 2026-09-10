class_name Sm2ActorContent
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var hp: int = 0
@export var ap: int = 0
@export var max_fatigue: int = 0
@export var initiative: int = 0
@export var weapon_id: String = ""
@export var abilities: Array[String] = []
@export var immunities: Array[String] = []


func to_raw() -> Dictionary:
	return {"id": id, "name": display_name, "hp": hp, "ap": ap,
		"max_fatigue": max_fatigue, "initiative": initiative,
		"weapon_id": weapon_id, "abilities": abilities.duplicate(),
		"immunities": immunities.duplicate()}
