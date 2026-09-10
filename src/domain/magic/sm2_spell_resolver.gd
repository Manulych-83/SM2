class_name Sm2SpellResolver
extends RefCounted

static func preview(state: Sm2TacticalState, command: Sm2Command) -> Dictionary:
	var definition: Sm2SpellDefinition = state.magic_catalog.spell(command.ability_id)
	if definition != null and definition.operation == "area_hp_damage": return Sm2AreaSpellResolver.preview(state,command)
	var result: Dictionary = {"kind":"spell","allowed":false,"reason":"","ap_cost":0,"fatigue_cost":0,"mana_cost":0}
	var spell: Sm2SpellDefinition = state.magic_catalog.spell(command.ability_id)
	var source: Sm2TacticalActor = state.actor(command.actor_id)
	var target: Sm2TacticalActor = state.actor(command.target_actor_id)
	if spell == null or source == null or not source.spatial.occupies(): return _deny(result,"ability_unavailable")
	if not state.magic_catalog.profile(source.loadout_id).spells.has(spell.id): return _deny(result,"ability_unavailable")
	if source.morale == "fleeing": return _deny(result,"fleeing_cannot_attack")
	if target == null or not target.spatial.occupies(): return _deny(result,"target_unavailable")
	if source.spatial.side == target.spatial.side: return _deny(result,"spell_enemy_required")
	var distance: int = Sm2Hex.distance(source.spatial.position,target.spatial.position)
	if distance < spell.range_min or distance > spell.range_max: return _deny(result,"attack_range")
	if not Sm2SpatialQueries.los(state.field,source.spatial.position,target.spatial.position,state.occupancy()).visible: return _deny(result,"line_of_sight_blocked")
	if source.spatial.ap < spell.ap_cost: return _deny(result,"insufficient_ap")
	if source.spatial.fatigue_max-source.spatial.fatigue < spell.fatigue_cost: return _deny(result,"fatigue_limit")
	if state.mana[command.actor_id].current < spell.mana_cost: return _deny(result,"insufficient_mana")
	var resistance: int = state.magic_catalog.profile(target.loadout_id).arcane_resistance
	@warning_ignore("integer_division")
	var damage: int = spell.damage*(100-resistance)/100
	result.merge({"allowed":true,"ap_cost":spell.ap_cost,"fatigue_cost":spell.fatigue_cost,"mana_cost":spell.mana_cost,"name":spell.name,"channel":spell.channel,"resistance":resistance,"base_damage":spell.damage,"damage":damage,"hp_loss":mini(target.combat.hp,damage),"lethal":damage >= target.combat.hp},true)
	return result

static func resolve(state: Sm2TacticalState, combat: Sm2CombatCatalog, command: Sm2Command, context: Sm2ConsequenceContext) -> Dictionary:
	var definition: Sm2SpellDefinition = state.magic_catalog.spell(command.ability_id)
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
	Sm2HpApplication.apply(state,target,command.actor_id,int(check.hp_loss),events)
	if not Sm2MoraleResolver.after_hit(state,combat,target,int(check.hp_loss),context,events): return {"accepted":false,"code":"rng_counter_limit","events":[]}
	return {"accepted":true,"code":"accepted","events":events}

static func _deny(result: Dictionary, reason: String) -> Dictionary:
	result.reason = reason
	return result
