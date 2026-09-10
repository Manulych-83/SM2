class_name Sm2ItemState
extends RefCounted
## Item IDs have their own namespace; one weapon per actor in M1.
var instance_id: int = 0
var definition_id: String = ""
var durability: int = 0

func to_data() -> Dictionary:
	return {"instance_id": str(instance_id), "definition_id": definition_id, "durability": durability}
