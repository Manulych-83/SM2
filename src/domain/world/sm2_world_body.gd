class_name Sm2WorldBody
extends RefCounted
## Persistent identity. Tactical actor IDs belong to the participation binding.
var id: int = 0
var hp: int = 0
var alive: bool = false
var death_cause: String = ""
var drills: int = 0
var progress: Sm2ProgressBodyState
func to_data() -> Dictionary:
	return {"id":str(id),"hp":hp,"alive":alive,"death_cause":death_cause,"drills":drills,"progress":progress.to_data()}
