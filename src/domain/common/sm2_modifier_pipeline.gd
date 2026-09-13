class_name Sm2ModifierPipeline
extends RefCounted
## Order is explicit in the supplied sequence. Never sort by display name or dictionary order.
const MAX_STEPS: int = 2048
# Wide progression can exceed 10^12 through direct contributions and its combat mapping.
# At most 8*10^12 times 10^6 still fits signed 64-bit arithmetic.
const MAX_VALUE: int = 8000000000000

static func evaluate(base: int, modifiers: Array, facts: Dictionary = {}) -> Dictionary:
	if base < -MAX_VALUE or base > MAX_VALUE or modifiers.size() > MAX_STEPS: return _error("modifier_budget")
	var value: int = base
	var steps: Array[Dictionary] = []
	for entry: Variant in modifiers:
		if not entry is Dictionary: return _error("modifier_shape")
		var fields: Array[String] = ["source","operation","amount"]
		if entry.has("when"): fields.append("when")
		if not Sm2Validate.fields(entry,fields) or not Sm2Validate.text(entry.source): return _error("modifier_fields")
		if entry.operation not in ["add","scale_percent","minimum","maximum","set"]: return _error("modifier_operation")
		if not Sm2Validate.integer(entry.amount,-MAX_VALUE,MAX_VALUE): return _error("modifier_amount")
		var amount: int = int(entry.amount)
		# The product remains within signed 64-bit range before integer division.
		if entry.operation == "scale_percent" and (amount < 0 or amount > 1000000): return _error("modifier_percent")
		var condition: Dictionary = {"valid":true,"matches":true,"reason":""}
		if entry.has("when"): condition = Sm2RuleCondition.evaluate(entry.when,facts)
		if not condition.valid: return _error(condition.reason)
		var before: int = value
		if condition.matches:
			match entry.operation:
				"add": value += amount
				"scale_percent": value = _floor_percent(value,amount)
				"minimum": value = maxi(value,amount)
				"maximum": value = mini(value,amount)
				"set": value = amount
		if value < -MAX_VALUE or value > MAX_VALUE: return _error("modifier_value_range")
		steps.append({"source":entry.source,"operation":entry.operation,"amount":amount,"before":before,"after":value,"applied":condition.matches,"reason":condition.reason})
	return {"valid":true,"value":value,"steps":steps,"reason":""}

static func _floor_percent(value: int, percent: int) -> int:
	var product: int = value*percent
	@warning_ignore("integer_division")
	var quotient: int = product/100
	return quotient-1 if product < 0 and product % 100 != 0 else quotient

static func _error(reason: String) -> Dictionary:
	return {"valid":false,"value":0,"steps":[],"reason":reason}
