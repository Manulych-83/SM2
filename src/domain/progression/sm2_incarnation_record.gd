class_name Sm2IncarnationRecord
extends RefCounted
var id: int = 3
var soul_id: int = 1
var body_id: int = 2
func to_data() -> Dictionary:
	return {"id":str(id),"soul_id":str(soul_id),"body_id":str(body_id)}
