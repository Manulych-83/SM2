class_name Sm2ProgressNodeDefinition
extends RefCounted
var id: String
var title: String
var track_id: String
var min_level: int
var cost: int
var bonus: int
var requires: Array[String] = []

func copy() -> Sm2ProgressNodeDefinition:
	var value: Sm2ProgressNodeDefinition = Sm2ProgressNodeDefinition.new()
	value.id=id; value.title=title; value.track_id=track_id
	value.min_level=min_level; value.cost=cost; value.bonus=bonus
	value.requires=requires.duplicate()
	return value
