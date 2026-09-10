class_name Sm2TurnProfileContent
extends Resource
@export var id: String = ""
@export var ap_max: int = 9
@export var fatigue_base: int = 100
@export var initiative_base: int = 0

func to_raw() -> Dictionary:
	return {"id": id, "ap_max": ap_max, "fatigue_base": fatigue_base, "initiative_base": initiative_base}
