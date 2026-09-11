class_name Sm2ProgressNodeDefinition
extends RefCounted
var id: String
var title: String
var track_id: String
var min_level: int
var cost: int
var bonus: int
var requires: Array[String] = []
var extra_requirements: Array[Dictionary]=[]
var extra_costs: Array[Dictionary]=[]

func copy() -> Sm2ProgressNodeDefinition:
	var value: Sm2ProgressNodeDefinition = Sm2ProgressNodeDefinition.new()
	value.id=id; value.title=title; value.track_id=track_id
	value.min_level=min_level; value.cost=cost; value.bonus=bonus
	value.requires=requires.duplicate()
	value.extra_requirements.assign(extra_requirements.duplicate(true)); value.extra_costs.assign(extra_costs.duplicate(true))
	return value

func prices() -> Dictionary[String,int]:
	var result: Dictionary[String,int]={track_id:cost}
	for entry: Dictionary in extra_costs: result[entry.track_id]=int(entry.amount)
	return result
func own_levels() -> Dictionary[String,int]:
	var result: Dictionary[String,int]={track_id:min_level}
	for entry: Dictionary in extra_requirements: result[entry.track_id]=int(entry.min_level)
	return result
