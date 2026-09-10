class_name Sm2EffectOperation
extends RefCounted
var kind: String = ""
var stat: String = ""
var channel: String = ""
var amount: int = 0

func to_data() -> Dictionary:
	return {"kind":kind,"stat":stat,"channel":channel,"amount":amount}

static func from_data(data: Dictionary) -> Sm2EffectOperation:
	var result: Sm2EffectOperation = Sm2EffectOperation.new()
	result.kind = data.kind
	result.stat = data.stat
	result.channel = data.channel
	result.amount = int(data.amount)
	return result
