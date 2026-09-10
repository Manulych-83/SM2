class_name Sm2Combatant
extends RefCounted
var hp: int
var items: Dictionary[String, Sm2CombatItem] = {}
var shieldwall_used: bool = false
var shieldwall_source: int = 0
var shieldwall_until_round: int = 0

func item(slot: String) -> Sm2CombatItem:
	return items.get(slot, null) as Sm2CombatItem

func shield_intact() -> bool:
	return items.has("shield") and items.shield.current > 0

func clear_wall() -> void:
	shieldwall_source = 0
	shieldwall_until_round = 0

func copy() -> Sm2Combatant:
	var result: Sm2Combatant = Sm2Combatant.new()
	result.hp = hp
	result.shieldwall_used = shieldwall_used
	result.shieldwall_source = shieldwall_source
	result.shieldwall_until_round = shieldwall_until_round
	for slot: String in items:
		result.items[slot] = items[slot].copy()
	return result

func to_data() -> Dictionary:
	var encoded: Array[Dictionary] = []
	for slot: String in Sm2CombatCatalog.SLOTS:
		if items.has(slot):
			encoded.append(items[slot].to_data())
	return {"hp": hp, "items": encoded, "shieldwall_used": shieldwall_used,
		"shieldwall_source": str(shieldwall_source), "shieldwall_until_round": str(shieldwall_until_round)}
