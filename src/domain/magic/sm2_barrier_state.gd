class_name Sm2BarrierState
extends RefCounted
## A body-owned, finite pool. Empty state has one canonical representation.
var ability_id: String=""
var capacity: int=0
var remaining: int=0
var expires_round: int=0

func to_data() -> Dictionary:
	return {} if remaining==0 else {"ability_id":ability_id,"capacity":capacity,"remaining":remaining,"expires_round":expires_round}
func copy() -> Sm2BarrierState:
	var result: Sm2BarrierState=Sm2BarrierState.new()
	result.ability_id=ability_id; result.capacity=capacity; result.remaining=remaining; result.expires_round=expires_round
	return result
func clear() -> void:
	ability_id=""; capacity=0; remaining=0; expires_round=0
