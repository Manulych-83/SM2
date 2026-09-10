class_name Sm2EffectResolver
extends RefCounted
const MAX_PER_ACTOR: int = 64
const MAX_TOTAL: int = 4096

static func find(state: Sm2TacticalState, target_id: int, definition_id: String) -> Sm2EffectInstance:
	for id: int in state.sorted_effect_ids():
		var effect: Sm2EffectInstance = state.effects[id]
		if effect.target_actor_id == target_id and effect.definition_id == definition_id: return effect
	return null

static func dispellable(state: Sm2TacticalState, target_id: int) -> Array[int]:
	var result: Array[int] = []
	for id: int in state.sorted_effect_ids():
		var effect: Sm2EffectInstance = state.effects[id]
		var definition: Sm2EffectDefinition = state.effect_catalog.definition(effect.definition_id)
		if effect.target_actor_id == target_id and definition.polarity == "harmful" and definition.dispellable: result.append(id)
	return result

static func preview(state: Sm2TacticalState, command: Sm2Command) -> Dictionary:
	var result: Dictionary = {"allowed":false,"reason":"","ap_cost":0,"fatigue_cost":0,"kind":"effect","effects":[]}
	var catalog: Sm2EffectCatalog = state.effect_catalog
	var action: Sm2EffectAction = catalog.action(command.ability_id)
	var source: Sm2TacticalActor = state.actor(command.actor_id)
	var target: Sm2TacticalActor = state.actor(command.target_actor_id)
	if action == null or source == null or not source.spatial.occupies() or not catalog.grants(source.loadout_id).has(command.ability_id): return _deny(result,"ability_unavailable")
	if source.morale == "fleeing": return _deny(result,"fleeing_cannot_attack")
	if target == null or not target.spatial.occupies(): return _deny(result,"target_unavailable")
	var allied: bool = source.spatial.side == target.spatial.side
	if allied != (action.target_side == "ally"): return _deny(result,"effect_target_side")
	var distance: int = Sm2Hex.distance(source.spatial.position,target.spatial.position)
	if distance < action.range_min or distance > action.range_max: return _deny(result,"attack_range")
	if distance > 0 and not Sm2SpatialQueries.los(state.field,source.spatial.position,target.spatial.position,state.occupancy()).visible: return _deny(result,"line_of_sight_blocked")
	if source.spatial.ap < action.ap_cost: return _deny(result,"insufficient_ap")
	if source.spatial.fatigue_max-source.spatial.fatigue < action.fatigue_cost: return _deny(result,"fatigue_limit")
	if action.operation == "apply_effect":
		var definition: Sm2EffectDefinition = catalog.definition(action.effect_id)
		if catalog.immune(target.loadout_id,definition.id): return _deny(result,"effect_immune")
		var previous: Sm2EffectInstance = find(state,command.target_actor_id,definition.id)
		if previous != null and previous.remaining >= definition.duration: return _deny(result,"effect_already_full")
		if previous == null:
			var count: int = 0
			for instance: Sm2EffectInstance in state.effects.values():
				if instance.target_actor_id == command.target_actor_id: count += 1
			if count >= MAX_PER_ACTOR or state.effects.size() >= MAX_TOTAL: return _deny(result,"effect_limit")
			if state.next_effect_id >= 9223372036854775806: return _deny(result,"effect_id_limit")
		result.effects = [_describe(state,definition,target,definition.duration)]
		result["refresh"] = previous != null
	else:
		var ids: Array[int] = dispellable(state,command.target_actor_id)
		if ids.is_empty(): return _deny(result,"no_dispellable_effects")
		result["remove_ids"] = ids
		for id: int in ids: result.effects.append({"name":catalog.definition(state.effects[id].definition_id).name,"effect_id":str(id)})
	result.allowed = true
	result.ap_cost = action.ap_cost
	result.fatigue_cost = action.fatigue_cost
	result["operation"] = action.operation
	return result

static func resolve(state: Sm2TacticalState, command: Sm2Command) -> Dictionary:
	var check: Dictionary = preview(state,command)
	if not check.allowed: return {"accepted":false,"code":check.reason,"events":[]}
	var events: Array[Dictionary] = []
	var source: Sm2TacticalActor = state.actor(command.actor_id)
	source.spatial.ap -= int(check.ap_cost)
	source.spatial.fatigue += int(check.fatigue_cost)
	events.append({"type":"resources_spent","actor_id":str(command.actor_id),"ap":check.ap_cost,"fatigue":check.fatigue_cost})
	var action: Sm2EffectAction = state.effect_catalog.action(command.ability_id)
	if action.operation == "dispel_effects":
		for id: int in check.remove_ids: remove(state,id,"dispelled",events)
	else:
		var instance: Sm2EffectInstance = find(state,command.target_actor_id,action.effect_id)
		var refreshed: bool = instance != null
		if instance == null:
			instance = Sm2EffectInstance.new()
			instance.effect_id = state.next_effect_id
			state.next_effect_id += 1
			instance.definition_id = action.effect_id
			instance.target_actor_id = command.target_actor_id
			state.effects[instance.effect_id] = instance
		instance.remaining = state.effect_catalog.definition(action.effect_id).duration
		instance.source_actor_id = command.actor_id
		instance.applied_revision = state.revision+1
		events.append({"type":"effect_refreshed" if refreshed else "effect_applied","effect_id":str(instance.effect_id),"definition_id":action.effect_id,"name":state.effect_catalog.definition(action.effect_id).name,"actor_id":str(command.actor_id),"target_actor_id":str(command.target_actor_id),"remaining":instance.remaining})
	return {"accepted":true,"code":"accepted","events":events}

static func end_activation(state: Sm2TacticalState, target_id: int, combat: Sm2CombatCatalog, context: Sm2ConsequenceContext, events: Array[Dictionary]) -> String:
	var target: Sm2TacticalActor = state.actor(target_id)
	for id: int in state.sorted_effect_ids():
		if state.finished or not target.spatial.occupies(): break
		if not state.effects.has(id) or state.effects[id].target_actor_id != target_id: continue
		var effect: Sm2EffectInstance = state.effects[id]
		var definition: Sm2EffectDefinition = state.effect_catalog.definition(effect.definition_id)
		for op: Sm2EffectOperation in definition.operations:
			if op.kind != "periodic_hp_damage": continue
			var resistance: int = state.effect_catalog.resistance(target.loadout_id,op.channel)
			@warning_ignore("integer_division")
			var loss: int = mini(target.combat.hp,op.amount*(100-resistance)/100)
			events.append({"type":"effect_ticked","effect_id":str(id),"definition_id":effect.definition_id,"name":definition.name,"actor_id":str(effect.source_actor_id),"target_actor_id":str(target_id),"channel":op.channel,"resistance":resistance,"loss":loss})
			Sm2HpApplication.apply(state,target,effect.source_actor_id,loss,events)
			if not target.spatial.alive and not Sm2MoraleResolver.after_hit(state,combat,target,0,context,events): return "rng_counter_limit"
			Sm2BattleOutcome.evaluate(state,events)
			if state.finished or not target.spatial.occupies(): break
		if state.effects.has(id):
			effect.remaining -= 1
			if effect.remaining == 0: remove(state,id,"expired",events)
	return ""

static func remove(state: Sm2TacticalState, id: int, reason: String, events: Array[Dictionary]) -> void:
	var effect: Sm2EffectInstance = state.effects[id]
	events.append({"type":"effect_removed","effect_id":str(id),"definition_id":effect.definition_id,"name":state.effect_catalog.definition(effect.definition_id).name,"target_actor_id":str(effect.target_actor_id),"reason":reason})
	state.effects.erase(id)

static func clear_target(state: Sm2TacticalState, target_id: int, reason: String, events: Array[Dictionary]) -> void:
	for id: int in state.sorted_effect_ids():
		if state.effects[id].target_actor_id == target_id: remove(state,id,reason,events)

static func cleanup(state: Sm2TacticalState, events: Array[Dictionary]) -> void:
	for id: int in state.sorted_effect_ids():
		var target: Sm2TacticalActor = state.actor(state.effects[id].target_actor_id)
		if state.finished or not target.spatial.occupies(): remove(state,id,"battle_finished" if state.finished else ("death" if not target.spatial.alive else "escaped"),events)

static func describe_actor(state: Sm2TacticalState, target: Sm2TacticalActor) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: int in state.sorted_effect_ids():
		var effect: Sm2EffectInstance = state.effects[id]
		if effect.target_actor_id != target.spatial.actor_id: continue
		var data: Dictionary = _describe(state,state.effect_catalog.definition(effect.definition_id),target,effect.remaining)
		data["effect_id"] = str(id)
		data["source_actor_id"] = str(effect.source_actor_id)
		result.append(data)
	return result

static func _describe(state: Sm2TacticalState, definition: Sm2EffectDefinition, target: Sm2TacticalActor, duration: int) -> Dictionary:
	var operations: Array[Dictionary] = []
	for op: Sm2EffectOperation in definition.operations:
		var data: Dictionary = op.to_data()
		if op.kind == "periodic_hp_damage":
			data["resistance"] = state.effect_catalog.resistance(target.loadout_id,op.channel)
			@warning_ignore("integer_division")
			var loss: int = op.amount*(100-int(data.resistance))/100
			data["tick_loss"] = loss
		operations.append(data)
	return {"definition_id":definition.id,"name":definition.name,"remaining":duration,"polarity":definition.polarity,"operations":operations}

static func _deny(result: Dictionary, reason: String) -> Dictionary:
	result.reason = reason
	return result
