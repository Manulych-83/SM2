class_name Sm2TurnLoadoutContent
extends Resource
@export var id: String = ""
@export var profile_id: String = ""
@export var equipment_ids: Array[String] = []

func to_raw() -> Dictionary:
	return {"id": id, "profile_id": profile_id, "equipment_ids": equipment_ids.duplicate()}
