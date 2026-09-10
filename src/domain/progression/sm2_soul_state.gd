class_name Sm2SoulState
extends RefCounted
var id: int = 1
var incarnation_id: int = 3
var knowledge: Array[String] = []
func to_data() -> Dictionary:
	return {"id":str(id),"incarnation_id":str(incarnation_id),"knowledge":knowledge.duplicate()}
