class_name Sm2StatusContent
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var tick_damage: int = 0
@export var duration: int = 0


func to_raw() -> Dictionary:
	return {"id": id, "name": display_name, "tick_damage": tick_damage,
		"duration": duration}
