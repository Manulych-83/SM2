class_name Sm2CombatItem
extends RefCounted
var item_id: int
var definition_id: String
var slot: String
var current: int
var ammo: int

func copy() -> Sm2CombatItem:
	var result: Sm2CombatItem = Sm2CombatItem.new()
	result.item_id = item_id
	result.definition_id = definition_id
	result.slot = slot
	result.current = current
	result.ammo = ammo
	return result

func to_data() -> Dictionary:
	return {"item_id": str(item_id), "definition_id": definition_id, "slot": slot, "current": current, "ammo": ammo}
