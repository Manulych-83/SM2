class_name Sm2WeaponContent
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var damage_min: int = 0
@export var damage_max: int = 0
@export var durability: int = 0


func to_raw() -> Dictionary:
	return {"id": id, "name": display_name, "damage_min": damage_min,
		"damage_max": damage_max, "durability": durability}
