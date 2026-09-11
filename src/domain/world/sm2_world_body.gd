class_name Sm2WorldBody
extends RefCounted
## Persistent identity. Tactical actor IDs belong to the participation binding.
var id: int = 0
var hp: int = 0
var alive: bool = false
var death_cause: String = ""
var drills: int = 0
var upgrades: Sm2BodyUpgradeState=null
var functions: Sm2BodyFunctionState=null
var progress: Sm2ProgressBodyState
func to_data() -> Dictionary:
	var data: Dictionary={"id":str(id),"hp":hp,"alive":alive,"death_cause":death_cause,"drills":drills,"progress":progress.to_data()}
	if upgrades!=null: data["upgrades"]=upgrades.to_data()
	if functions!=null: data["body_functions"]=functions.to_data()
	return data
