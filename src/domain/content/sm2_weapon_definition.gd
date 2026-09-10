class_name Sm2WeaponDefinition
extends RefCounted
var id: String = ""
var name: String = ""
var damage_min: int = 0
var damage_max: int = 0
var durability: int = 0

static func from_data(data: Dictionary) -> Sm2WeaponDefinition:
	var result: Sm2WeaponDefinition = Sm2WeaponDefinition.new()
	result.id = data.id
	result.name = data.name
	result.damage_min = int(data.damage_min)
	result.damage_max = int(data.damage_max)
	result.durability = int(data.durability)
	return result

func to_data() -> Dictionary:
	return {"id": id, "name": name, "damage_min": damage_min, "damage_max": damage_max, "durability": durability}
