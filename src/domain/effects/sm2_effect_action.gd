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

func to_data() -> Dictionary:
	return {"id":id,"name":name,"operation":operation,"effect_id":effect_id,"target_side":target_side,"ap_cost":ap_cost,"fatigue_cost":fatigue_cost,"range_min":range_min,"range_max":range_max}

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
	return result
