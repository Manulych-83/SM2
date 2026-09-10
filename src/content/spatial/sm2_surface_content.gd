class_name Sm2SurfaceContent
extends Resource
## Authoring data only. Passability and opacity belong to individual cells.

@export var id: String = ""
@export var ap_cost: int = 0
@export var fatigue_cost: int = 0


func to_raw() -> Dictionary:
	return {"id": id, "ap_cost": ap_cost, "fatigue_cost": fatigue_cost}
