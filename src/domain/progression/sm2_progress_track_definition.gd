class_name Sm2ProgressTrackDefinition
extends RefCounted
var id: String
var title: String
var kind: String
var base_level: int
var step: int
var growth: int

func threshold(steps: int) -> int:
	@warning_ignore("integer_division")
	return step * steps + growth * steps * (steps - 1) / 2

func describe(earned: int) -> Dictionary:
	var low: int = 0
	var high: int = earned + 1
	while low + 1 < high:
		@warning_ignore("integer_division")
		var middle: int = (low + high) / 2
		if threshold(middle) <= earned: low = middle
		else: high = middle
	return {"level":base_level+low,"progress":earned-threshold(low),"needed":threshold(low+1)-threshold(low)}

func copy() -> Sm2ProgressTrackDefinition:
	var value: Sm2ProgressTrackDefinition = Sm2ProgressTrackDefinition.new()
	value.id=id; value.title=title; value.kind=kind
	value.base_level=base_level; value.step=step; value.growth=growth
	return value
