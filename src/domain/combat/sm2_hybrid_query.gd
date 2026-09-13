class_name Sm2HybridQuery
extends RefCounted
## Shared detached values for attack resolution, forecast and AI metadata.
static func definition(state: Sm2TacticalState,id: String) -> Dictionary:
	if state.development==null or not state.development.catalog.has_hybrids(): return {}
	return state.development.catalog.hybrids().ability(id)

static func details(state: Sm2TacticalState,actor_id: int,id: String) -> Dictionary:
	var entry: Dictionary=definition(state,id)
	if entry.is_empty(): return {}
	var dev: Sm2BattleDevelopment=state.development
	if actor_id!=dev.catalog.hero() or not dev.has_actor(actor_id): return {}
	var cost: Dictionary=dev.concentration_cost(actor_id,int(entry.concentration_cost),id)
	var damage: Dictionary=dev.hybrid_parameter(actor_id,id)
	return {"name":entry.name,"mana_cost":cost.total,"cost_calculation":cost,"psionic_damage":damage.total,"damage_calculation":damage,"base_attack":entry.base_attack,"awards":entry.awards}
