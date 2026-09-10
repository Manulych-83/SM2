class_name Sm2SpawnMarkerContent
extends Resource
## Spatial start marker; combat statistics and equipment are defined elsewhere.

@export var id: int = 0
@export var side: String = ""
@export var owner: String = ""
@export var controller: String = ""
@export var q: int = 0
@export var r: int = 0


func to_raw() -> Dictionary:
	return {"actor_id": id, "side": side, "owner": owner,
		"controller": controller, "q": q, "r": r}
