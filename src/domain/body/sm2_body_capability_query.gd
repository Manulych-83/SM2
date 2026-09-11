class_name Sm2BodyCapabilityQuery
extends RefCounted

static func requirements(state: Sm2BodyFunctionState, ids: Array[String]) -> bool:
	if state==null: return true
	for id: String in ids:
		if not state.working.get(id,false): return false
	return true

static func item_allowed(actor: Sm2TacticalActor, gear: Sm2CombatGear) -> bool:
	return actor.body_catalog==null or requirements(actor.body_functions,actor.body_catalog.required("two_handed" if gear.two_handed else gear.slot))

static func shield(actor: Sm2TacticalActor, combat: Sm2CombatCatalog) -> bool:
	return actor.combat.shield_intact() and item_allowed(actor,combat.gear(actor.combat.item("shield").definition_id))

static func unarmed(actor: Sm2TacticalActor, combat: Sm2CombatCatalog) -> bool:
	if actor.body_catalog==null: return actor.combat.item("weapon")==null
	var occupied: Array[String]=[]
	for slot: String in ["weapon","shield"]:
		var item: Sm2CombatItem=actor.combat.item(slot)
		if item!=null:
			var gear: Sm2CombatGear=combat.gear(item.definition_id)
			occupied.append_array(actor.body_catalog.required("two_handed" if gear.two_handed else slot))
	for id: String in actor.body_catalog.required("two_handed"):
		if actor.body_functions.working[id] and id not in occupied: return true
	return false
