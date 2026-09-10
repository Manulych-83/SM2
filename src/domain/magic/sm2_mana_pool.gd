class_name Sm2ManaPool
extends RefCounted
## Current resource only; limits and recovery belong to the authored profile.
var current: int = 0

func copy() -> Sm2ManaPool:
	var result: Sm2ManaPool = Sm2ManaPool.new()
	result.current = current
	return result
