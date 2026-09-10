class_name Sm2AreaSpellResolver
extends RefCounted

static func preview(state: Sm2TacticalState, command: Sm2Command) -> Dictionary:
	var result: Dictionary = {"kind":"area_spell","allowed":false,"reason":"","ap_cost":0,"fatigue_cost":0,"mana_cost":0,"cells":[],"targets":[],"hp_loss":0,"kills":0}
	var spell: Sm2SpellDefinition = state.magic_catalog.spell(command.ability_id)
	var source: Sm2TacticalActor = state.actor(command.actor_id)
	if spell == null or spell.operation != "area_hp_damage" or source == null or not source.spatial.occupies(): return _deny(result,"ability_unavailable")
	if not state.magic_catalog.profile(source.loadout_id).spells.has(spell.id): return _deny(result,"ability_unavailable")
	if command.target_actor_id != 0: return _deny(result,"area_cell_required")
	if source.morale == "fleeing": return _deny(result,"fleeing_cannot_attack")
	if not state.field.in_bounds(command.target): return _deny(result,"target_out_of_bounds")
	var tile: Dictionary = state.field.cell(command.target)
	if not tile.passable or tile.opaque: return _deny(result,"area_center_blocked")
	var distance: int = Sm2Hex.distance(source.spatial.position,command.target)
	if distance < spell.range_min or distance > spell.range_max: return _deny(result,"attack_range")
	if not Sm2SpatialQueries.los(state.field,source.spatial.position,command.target,state.occupancy()).visible: return _deny(result,"line_of_sight_blocked")
	result.merge({"ap_cost":spell.ap_cost,"fatigue_cost":spell.fatigue_cost,"mana_cost":spell.mana_cost,"name":spell.name,"channel":spell.channel,"radius":spell.radius},true)
	var cells: Array[Vector2i] = Sm2AreaGeometry.footprint(state.field,command.target,spell.radius)
	result.cells = cells
	for id: int in state.sorted_ids():
		var target: Sm2TacticalActor = state.actor(id)
		if not target.spatial.occupies() or target.spatial.side == source.spatial.side or not cells.has(target.spatial.position): continue
		var resistance: int = state.magic_catalog.profile(target.loadout_id).arcane_resistance
		@warning_ignore("integer_division")
		var damage: int = spell.damage*(100-resistance)/100
		var loss: int = mini(target.combat.hp,damage)
		var lethal: bool = loss == target.combat.hp
		result.targets.append({"actor_id":id,"q":target.spatial.position.x,"r":target.spatial.position.y,"resistance":resistance,"damage":damage,"hp_loss":loss,"lethal":lethal})
		result.hp_loss += loss
		result.kills += int(lethal)
	if result.targets.is_empty(): return _deny(result,"area_no_enemies")
	if source.spatial.ap < spell.ap_cost: return _deny(result,"insufficient_ap")
	if source.spatial.fatigue_max-source.spatial.fatigue < spell.fatigue_cost: return _deny(result,"fatigue_limit")
	if state.mana[command.actor_id].current < spell.mana_cost: return _deny(result,"insufficient_mana")
	result.allowed = true
	return result

static func resolve(state: Sm2TacticalState, combat: Sm2CombatCatalog, command: Sm2Command, context: Sm2ConsequenceContext) -> Dictionary:
	var check: Dictionary = preview(state,command)
	if not check.allowed: return {"accepted":false,"code":check.reason,"events":[]}
	var source: Sm2TacticalActor = state.actor(command.actor_id)
	source.spatial.ap -= int(check.ap_cost)
	source.spatial.fatigue += int(check.fatigue_cost)
	state.mana[command.actor_id].current -= int(check.mana_cost)
	var events: Array[Dictionary] = [
		{"type":"resources_spent","actor_id":str(command.actor_id),"ap":check.ap_cost,"fatigue":check.fatigue_cost},
		{"type":"mana_spent","actor_id":str(command.actor_id),"amount":check.mana_cost,"current":state.mana[command.actor_id].current},
		{"type":"area_spell_cast","actor_id":str(command.actor_id),"ability_id":command.ability_id,"name":check.name,"channel":check.channel,"q":command.target.x,"r":command.target.y,"radius":check.radius,"target_count":check.targets.size()}]
	# All HP/deaths first, then consequences, all inside the one candidate transaction.
	for hit: Dictionary in check.targets:
		events.append({"type":"spell_cast","actor_id":str(command.actor_id),"target_actor_id":str(hit.actor_id),"ability_id":command.ability_id,"name":check.name,"channel":check.channel,"resistance":hit.resistance,"loss":hit.hp_loss})
		Sm2HpApplication.apply(state,state.actor(int(hit.actor_id)),command.actor_id,int(hit.hp_loss),events)
	for hit: Dictionary in check.targets:
		if not Sm2MoraleResolver.after_hit(state,combat,state.actor(int(hit.actor_id)),int(hit.hp_loss),context,events): return {"accepted":false,"code":"rng_counter_limit","events":[]}
	return {"accepted":true,"code":"accepted","events":events}

static func _deny(result: Dictionary, reason: String) -> Dictionary:
	result.reason = reason
	return result
