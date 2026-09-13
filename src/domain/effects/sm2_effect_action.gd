class_name Sm2EffectAction
extends RefCounted
var id: String = ""
var name: String = ""
var operation: String = "apply_effect"
var effect_id: String = ""
var target_side: String = "enemy"
var ap_cost: int = 3
var fatigue_cost: int = 6
var range_min: int = 1
var range_max: int = 3
var steps: Array[Dictionary] = []

func to_data() -> Dictionary:
	var data: Dictionary = {"id":id,"name":name,"operation":operation,"effect_id":effect_id,"target_side":target_side,"ap_cost":ap_cost,"fatigue_cost":fatigue_cost,"range_min":range_min,"range_max":range_max}
	if operation == "effect_sequence": data["steps"] = steps.duplicate(true)
	return data

static func from_data(data: Dictionary) -> Sm2EffectAction:
	var result: Sm2EffectAction = Sm2EffectAction.new()
	result.id = data.id
	result.name = data.name
	result.operation = data.operation
	result.effect_id = data.effect_id
	result.target_side = data.target_side
	result.ap_cost = int(data.ap_cost)
	result.fatigue_cost = int(data.fatigue_cost)
	result.range_min = int(data.range_min)
	result.range_max = int(data.range_max)
	if data.has("steps"): result.steps.assign(data.steps.duplicate(true))
	return result

func applied_effects() -> Array[String]:
	var ids: Array[String] = []
	if operation == "apply_effect": ids.append(effect_id)
	for step: Dictionary in steps:
		if step.operation == "apply_effect" and not ids.has(step.effect_id): ids.append(step.effect_id)
	return ids
