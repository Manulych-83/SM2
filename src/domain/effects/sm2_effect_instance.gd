class_name Sm2EffectInstance
extends RefCounted
var effect_id: int = 0
var definition_id: String = ""
var source_actor_id: int = 0
var target_actor_id: int = 0
var remaining: int = 0
var applied_revision: int = 0

func to_data() -> Dictionary:
	return {"effect_id":str(effect_id),"definition_id":definition_id,"source_actor_id":str(source_actor_id),"target_actor_id":str(target_actor_id),"remaining":remaining,"applied_revision":str(applied_revision)}

func copy() -> Sm2EffectInstance:
	var result: Sm2EffectInstance = Sm2EffectInstance.new()
	result.effect_id = effect_id
	result.definition_id = definition_id
	result.source_actor_id = source_actor_id
	result.target_actor_id = target_actor_id
	result.remaining = remaining
	result.applied_revision = applied_revision
	return result
