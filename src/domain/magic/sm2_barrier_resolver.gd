class_name Sm2BarrierResolver
extends RefCounted
## Runs inside the existing atomic battle candidate, including both practice awards.
static func preview(state: Sm2TacticalState, command: Sm2Command) -> Dictionary:
	var result: Dictionary={"kind":"barrier","allowed":false,"reason":"","ap_cost":0,"fatigue_cost":0,"mana_cost":0}
	var source: Sm2TacticalActor=state.actor(command.actor_id)
	var spell: Sm2SpellDefinition=state.magic_catalog.spell(command.ability_id)
	if source==null or spell==null or spell.operation!="self_barrier" or not source.spatial.occupies() or source.barrier==null or state.development==null or not state.development.catalog.has_psionic_shields(): return _deny(result,"ability_unavailable")
	if command.target_actor_id!=command.actor_id: return _deny(result,"self_target_required")
	if source.morale=="fleeing": return _deny(result,"fleeing_cannot_attack")
	var dev: Sm2BattleDevelopment=state.development
	if source.spatial.actor_id!=dev.catalog.hero() or not state.magic_catalog.profile(source.loadout_id).spells.has(spell.id) or not dev.catalog.psionics().available(dev.bodies[command.actor_id],spell.id): return _deny(result,"ability_unavailable")
	if source.spatial.ap<spell.ap_cost: return _deny(result,"insufficient_ap")
	var cost: Dictionary=Sm2ManaResolver.cost(state,command.actor_id,spell)
	if state.development!=null and state.development.catalog.has_implants(): result["cost_calculation"]=cost
	if state.mana[command.actor_id].current<int(cost.total): return _deny(result,"insufficient_concentration")
	var calculation: Dictionary=dev.catalog.psionics().capacity(spell.id,dev.bodies[command.actor_id],dev.progress,dev.track_modifiers(command.actor_id))
	result.merge({"allowed":true,"ap_cost":spell.ap_cost,"mana_cost":cost.total,"capacity":calculation.total,"capacity_calculation":calculation,"previous":source.barrier.remaining,"name":spell.name},true)
	return result

static func resolve(state: Sm2TacticalState, command: Sm2Command) -> Dictionary:
	var check: Dictionary=preview(state,command)
	if not check.allowed: return {"accepted":false,"code":check.reason,"events":[]}
	var source: Sm2TacticalActor=state.actor(command.actor_id)
	source.spatial.ap-=int(check.ap_cost)
	state.mana[command.actor_id].current-=int(check.mana_cost)
	source.barrier.ability_id=command.ability_id; source.barrier.capacity=int(check.capacity); source.barrier.remaining=int(check.capacity); source.barrier.expires_round=state.round+1
	var events: Array[Dictionary]=[
		{"type":"resources_spent","actor_id":str(command.actor_id),"ap":check.ap_cost,"fatigue":0},
		{"type":"concentration_spent","actor_id":str(command.actor_id),"amount":check.mana_cost,"current":state.mana[command.actor_id].current},
		{"type":"barrier_cast","actor_id":str(command.actor_id),"ability_id":command.ability_id,"capacity":check.capacity,"previous":check.previous,"capacity_calculation":check.capacity_calculation.duplicate(true)}]
	var reason: String=state.development.award(command.actor_id,command.ability_id,events)
	if not reason.is_empty(): return {"accepted":false,"code":reason,"events":[]}
	return {"accepted":true,"code":"accepted","events":events}

static func _deny(result: Dictionary, reason: String) -> Dictionary:
	result.reason=reason; return result
