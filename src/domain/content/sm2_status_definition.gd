class_name Sm2StatusDefinition
extends RefCounted
var id: String = ""
var name: String = ""
var tick_damage: int = 0
var duration: int = 0

static func from_data(data: Dictionary) -> Sm2StatusDefinition:
	var result: Sm2StatusDefinition = Sm2StatusDefinition.new()
	result.id = data.id
	result.name = data.name
	result.tick_damage = int(data.tick_damage)
	result.duration = int(data.duration)
	return result

func to_data() -> Dictionary:
	return {"id": id, "name": name, "tick_damage": tick_damage, "duration": duration}
