class_name Sm2AbilityContent
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_enum("damage", "status", "summon") var operation: String = "damage"
@export var ap_cost: int = 0
@export var fatigue_cost: int = 0
@export var range: int = 0
@export var damage_bonus: int = 0
@export var status_id: String = ""
@export var summon_template_id: String = ""


func to_raw() -> Dictionary:
	return {"id": id, "name": display_name, "operation": operation,
		"ap_cost": ap_cost, "fatigue_cost": fatigue_cost, "range": range,
		"damage_bonus": damage_bonus, "status_id": status_id,
		"summon_template_id": summon_template_id}
