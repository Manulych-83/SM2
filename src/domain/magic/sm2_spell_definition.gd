class_name Sm2SpellDefinition
extends RefCounted
var id: String = ""
var name: String = ""
var ap_cost: int = 0
var fatigue_cost: int = 0
var mana_cost: int = 0
var range_min: int = 1
var range_max: int = 1
var damage: int = 0
var channel: String = "arcane"
var operation: String = "direct_hp_damage"
var radius: int = 0

func to_data() -> Dictionary:
	var data: Dictionary = {"id":id,"name":name,"operation":operation,"target_side":"enemy","ap_cost":ap_cost,"fatigue_cost":fatigue_cost,"mana_cost":mana_cost,"range_min":range_min,"range_max":range_max,"damage":damage,"channel":channel}
	if operation == "area_hp_damage": data["radius"] = radius
	return data

static func from_data(data: Dictionary) -> Sm2SpellDefinition:
	var result: Sm2SpellDefinition = Sm2SpellDefinition.new()
	result.id = data.id
	result.name = data.name
	result.channel = data.channel
	result.operation = data.operation
	result.radius = int(data.get("radius",0))
	for key: String in ["ap_cost","fatigue_cost","mana_cost","range_min","range_max","damage"]: result.set(key,int(data[key]))
	return result
