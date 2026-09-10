class_name Sm2AiWorkBudget
extends RefCounted
var limit: int = 0
var used: int = 0
var exhausted: bool = false

func _init(maximum: int) -> void:
	limit = maximum

func spend(amount: int = 1) -> bool:
	if amount < 0 or amount > limit-used:
		exhausted = true
		return false
	used += amount
	return true
