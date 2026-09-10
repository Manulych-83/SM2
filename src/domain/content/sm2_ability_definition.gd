class_name Sm2AbilityDefinition
extends RefCounted
var id: String = ""
var name: String = ""
var operation: String = ""
var ap_cost: int = 0
var fatigue_cost: int = 0
var range: int = 0
var damage_bonus: int = 0
var status_id: String = ""
var summon_template_id: String = ""

static func from_data(data: Dictionary) -> Sm2AbilityDefinition:
	var result: Sm2AbilityDefinition = Sm2AbilityDefinition.new()
	result.id = data.id
	result.name = data.name
	result.operation = data.operation
	result.ap_cost = int(data.ap_cost)
	result.fatigue_cost = int(data.fatigue_cost)
	result.range = int(data.range)
	result.damage_bonus = int(data.damage_bonus)
	result.status_id = data.status_id
	result.summon_template_id = data.summon_template_id
	return result

func to_data() -> Dictionary:
	return {"id": id, "name": name, "operation": operation, "ap_cost": ap_cost,
		"fatigue_cost": fatigue_cost, "range": range, "damage_bonus": damage_bonus,
		"status_id": status_id, "summon_template_id": summon_template_id}
