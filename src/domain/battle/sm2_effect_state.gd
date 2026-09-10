class_name Sm2EffectState
extends RefCounted
var status_id: String = ""
var source_actor_id: int = 0
var remaining: int = 0

func to_data() -> Dictionary:
	return {"status_id": status_id, "source_actor_id": str(source_actor_id), "remaining": remaining}
