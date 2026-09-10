class_name Sm2EffectDefinition
extends RefCounted
var id: String = ""
var name: String = ""
var tags: Array[String] = []
var polarity: String = "harmful"
var dispellable: bool = true
var duration: int = 1
var operations: Array[Sm2EffectOperation] = []

func to_data() -> Dictionary:
	var ops: Array[Dictionary] = []
	for op: Sm2EffectOperation in operations: ops.append(op.to_data())
	return {"id":id,"name":name,"tags":tags.duplicate(),"polarity":polarity,"dispellable":dispellable,"duration":duration,"clock":"target_activation_end","stacking":"refresh","operations":ops}

static func from_data(data: Dictionary) -> Sm2EffectDefinition:
	var result: Sm2EffectDefinition = Sm2EffectDefinition.new()
	result.id = data.id
	result.name = data.name
	result.tags.assign(data.tags)
	result.polarity = data.polarity
	result.dispellable = data.dispellable
	result.duration = int(data.duration)
	for op: Dictionary in data.operations: result.operations.append(Sm2EffectOperation.from_data(op))
	return result
