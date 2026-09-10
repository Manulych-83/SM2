class_name Sm2CellOverrideContent
extends Resource

@export var q: int = 0
@export var r: int = 0
@export var surface_id: String = ""
@export var elevation: int = 0
@export var passable: bool = true
@export var opaque: bool = false


func to_raw() -> Dictionary:
	return {"q": q, "r": r, "surface_id": surface_id, "elevation": elevation,
		"passable": passable, "opaque": opaque}
