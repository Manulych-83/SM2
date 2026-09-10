class_name Sm2TurnEquipmentContent
extends Resource
@export var id: String = ""
@export var load_penalty: int = 0

func to_raw() -> Dictionary:
	return {"id": id, "load_penalty": load_penalty}
