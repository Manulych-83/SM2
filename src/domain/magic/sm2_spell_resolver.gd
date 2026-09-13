class_name Sm2SpellResolver
extends RefCounted

static func preview(state: Sm2TacticalState, command: Sm2Command) -> Dictionary:
	var definition: Sm2SpellDefinition = state.magic_catalog.spell(command.ability_id)
	if definition != null and definition.operation == "self_barrier": return Sm2BarrierResolver.preview(state,command)
	if definition != null and definition.operation == "area_hp_damage": return Sm2AreaSpellResolver.preview(state,command)
	var result: Dictionary = {"kind":"spell","allowed":false,"reason":"","ap_cost":0,"fatigue_cost":0,"mana_cost":0}
	var spell: Sm2SpellDefinition = state.magic_catalog.spell(command.ability_id)
	var source: Sm2TacticalActor = state.actor(command.actor_id)
	var target: Sm2TacticalActor = state.actor(command.target_actor_id)
	if spell == null or source == null or not source.spatial.occupies(): return _deny(result,"ability_unavailable")
	if not state.magic_catalog.profile(source.loadout_id).spells.has(spell.id): return _deny(result,"ability_unavailable")
	if state.magic_catalog.is_psionic():
		if state.development==null or not state.development.catalog.has_psionics() or source.spatial.actor_id!=state.development.catalog.hero() or not state.development.psionic_available(command.actor_id,spell.id): return _deny(result,"ability_unavailable")
	if source.morale == "fleeing": return _deny(result,"fleeing_cannot_attack")
	if target == null or not target.spatial.occupies(): return _deny(result,"target_unavailable")
	if source.spatial.side == target.spatial.side: return _deny(result,"spell_enemy_required")
	var distance: int = Sm2Hex.distance(source.spatial.position,target.spatial.position)
	if distance < spell.range_min or distance > spell.range_max: return _deny(result,"attack_range")
	if not Sm2SpatialQueries.los(state.field,source.spatial.position,target.spatial.position,state.occupancy()).visible: return _deny(result,"line_of_sight_blocked")
	var requirements: Dictionary = Sm2ActionRequirements.resources(source,spell.ap_cost,spell.fatigue_cost)
	if not requirements.matches: return _deny(result,requirements.reason)
	var cost: Dictionary=Sm2ManaResolver.cost(state,command.actor_id,spell)
	if state.development!=null and state.development.catalog.has_implants(): result["cost_calculation"]=cost
	if state.mana[command.actor_id].current < int(cost.total): return _deny(result,"insufficient_concentration" if state.magic_catalog.is_psionic() else "insufficient_mana")
	var resistance: int = state.magic_catalog.profile(target.loadout_id).arcane_resistance
	var power: int=spell.damage
	if state.development!=null and state.development.catalog.has_psionic_growth() and spell.channel=="psionic":
		var calculation: Dictionary=state.development.psionic_parameter(command.actor_id,spell.id)
		power=int(calculation.total); result["damage_calculation"]=calculation
	@warning_ignore("integer_division")
	var damage: int = power*(100-resistance)/100
	result.merge({"allowed":true,"ap_cost":spell.ap_cost,"fatigue_cost":spell.fatigue_cost,"mana_cost":cost.total,"name":spell.name,"channel":spell.channel,"resistance":resistance,"base_damage":power,"damage":damage,"hp_loss":Sm2BarrierRules.loss(target,damage).hp_loss,"lethal":Sm2BarrierRules.loss(target,damage).hp_loss >= target.combat.hp},true)
	if state.survival!=null: result.lethal=Sm2SurvivalBattle.lethal_damage(target,int(result.hp_loss),state.survival.catalog.to_data())
	if target.barrier!=null: result["absorbed"]=Sm2BarrierRules.loss(target,damage).absorbed
	return result

static func resolve(state: Sm2TacticalState, combat: Sm2CombatCatalog, command: Sm2Command, context: Sm2ConsequenceContext) -> Dictionary:
	var definition: Sm2SpellDefinition = state.magic_catalog.spell(command.ability_id)
	if definition != null and definition.operation == "self_barrier": return Sm2BarrierResolver.resolve(state,command)
	if definition != null and definition.operation == "area_hp_damage": return Sm2AreaSpellResolver.resolve(state,combat,command,context)
	var check: Dictionary = preview(state,command)
	if not check.allowed: return {"accepted":false,"code":check.reason,"events":[]}
	var source: Sm2TacticalActor = state.actor(command.actor_id)
	var target: Sm2TacticalActor = state.actor(command.target_actor_id)
	source.spatial.ap -= int(check.ap_cost)
	source.spatial.fatigue += int(check.fatigue_cost)
	state.mana[command.actor_id].current -= int(check.mana_cost)
	var events: Array[Dictionary] = [
		{"type":"resources_spent","actor_id":str(command.actor_id),"ap":check.ap_cost,"fatigue":check.fatigue_cost},
		{"type":"mana_spent","actor_id":str(command.actor_id),"amount":check.mana_cost,"current":state.mana[command.actor_id].current},
		{"type":"spell_cast","actor_id":str(command.actor_id),"target_actor_id":str(command.target_actor_id),"ability_id":command.ability_id,"name":check.name,"channel":check.channel,"resistance":check.resistance,"loss":check.hp_loss}]
	if check.has("damage_calculation"): events[2]["damage_calculation"]=check.damage_calculation.duplicate(true)
	Sm2BarrierRules.absorb(target,int(check.damage),events)
	Sm2HpApplication.apply(state,target,command.actor_id,int(check.hp_loss),events)
	if not Sm2MoraleResolver.after_hit(state,combat,target,int(check.hp_loss),context,events): return {"accepted":false,"code":"rng_counter_limit","events":[]}
	if state.magic_catalog.is_psionic():
		events[1].type="concentration_spent"
		var reason: String=state.development.award(command.actor_id,command.ability_id,events)
		if not reason.is_empty(): return {"accepted":false,"code":reason,"events":[]}
	return {"accepted":true,"code":"accepted","events":events}

static func _deny(result: Dictionary, reason: String) -> Dictionary:
	result.reason = reason
	return result
