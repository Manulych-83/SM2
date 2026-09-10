class_name Sm2AiEffectAssessment
extends RefCounted
## A bounded utility estimate on a disposable query projection; no commands or dice.
static func assess(state: Sm2TacticalState, combat: Sm2CombatCatalog, command: Sm2Command, check: Dictionary, budget: Sm2AiWorkBudget, tuning: Dictionary) -> Dictionary:
	var target: Sm2TacticalActor = state.actor(command.target_actor_id)
	var candidate: Sm2TacticalState = state.copy()
	var definition: Sm2EffectDefinition = null
	var flat: bool = false
	if check.operation == "apply_effect":
		definition = state.effect_catalog.definition(state.effect_catalog.action(command.ability_id).effect_id)
		var previous: Sm2EffectInstance = Sm2EffectResolver.find(candidate,command.target_actor_id,definition.id)
		if previous == null:
			previous = Sm2EffectInstance.new()
			# Synthetic local identity; does not use or advance the battle allocator.
			previous.effect_id = -1
			previous.target_actor_id = command.target_actor_id
			previous.definition_id = definition.id
			candidate.effects[-1] = previous
		previous.remaining = definition.duration
		for op: Sm2EffectOperation in definition.operations: flat = flat or op.kind == "flat_stat_modifier"
	else:
		for id: int in check.remove_ids:
			var removed: Sm2EffectInstance = candidate.effects[id]
			for op: Sm2EffectOperation in state.effect_catalog.definition(removed.definition_id).operations: flat = flat or op.kind == "flat_stat_modifier"
			candidate.effects.erase(id)
	var allied: bool = target.spatial.side == state.actor(command.actor_id).spatial.side
	var before_poison: Dictionary = _periodic(state,target,tuning,budget)
	var after_poison: Dictionary = _periodic(candidate,candidate.actor(command.target_actor_id),tuning,budget)
	var poison_gain: int = int(before_poison.value)-int(after_poison.value) if allied else int(after_poison.value)-int(before_poison.value)
	var value: int = poison_gain*int(tuning.hp_weight)
	var urgent: bool = allied and check.operation == "dispel_effects" and int(before_poison.next) >= target.combat.hp and int(after_poison.next) < target.combat.hp
	if flat and not budget.exhausted:
		var baseline: Sm2TacticalState = state.copy()
		# Flat changes that expire at this very end of activation cannot protect later attacks.
		if command.target_actor_id == command.actor_id and int(check.ap_cost) >= state.actor(command.actor_id).spatial.ap:
			_age_flat(baseline,command.target_actor_id)
			_age_flat(candidate,command.target_actor_id)
		var weight: int = 100
		# Compare each horizon step, so refreshing buys only the extra lifetime.
		for tick: int in int(tuning.effect_horizon):
			var before: Dictionary = _pressure(baseline,combat,command.target_actor_id,budget)
			var after: Dictionary = _pressure(candidate,combat,command.target_actor_id,budget)
			if budget.exhausted: break
			var gain: int = int(after.outgoing)-int(before.outgoing)+int(before.incoming)-int(after.incoming)
			if not allied: gain = -gain
			@warning_ignore("integer_division")
			var flat_value: int = gain*int(tuning.hp_weight)*weight*int(tuning.defense_weight)/10000
			value += flat_value
			_age_flat(baseline,command.target_actor_id)
			_age_flat(candidate,command.target_actor_id)
			@warning_ignore("integer_division")
			var discounted: int = weight*int(tuning.future_tick_percent)/100
			weight = discounted
	return {"value":maxi(0,value),"urgent":urgent,"poison_gain_x100":poison_gain}

static func _periodic(state: Sm2TacticalState, target: Sm2TacticalActor, tuning: Dictionary, budget: Sm2AiWorkBudget) -> Dictionary:
	var value: int = 0
	var next: int = 0
	for effect: Dictionary in Sm2EffectResolver.describe_actor(state,target):
		for op: Dictionary in effect.operations:
			if not budget.spend(): return {"value":0,"next":0}
			if op.kind != "periodic_hp_damage": continue
			next += int(op.tick_loss)
			var weight: int = 100
			for tick: int in mini(int(effect.remaining),int(tuning.effect_horizon)):
				value += int(op.tick_loss)*weight
				@warning_ignore("integer_division")
				var discounted: int = weight*int(tuning.future_tick_percent)/100
				weight = discounted
	return {"value":mini(target.combat.hp*100,value),"next":next}

static func _age_flat(state: Sm2TacticalState, target_id: int) -> void:
	for id: int in state.sorted_effect_ids():
		var instance: Sm2EffectInstance = state.effects[id]
		if instance.target_actor_id == target_id:
			instance.remaining -= 1
			if instance.remaining <= 0: state.effects.erase(id)

static func _pressure(state: Sm2TacticalState, combat: Sm2CombatCatalog, target_id: int, budget: Sm2AiWorkBudget) -> Dictionary:
	var target: Sm2TacticalActor = state.actor(target_id)
	var outgoing: int = 0
	var incoming: int = 0
	for id: int in state.sorted_ids():
		var other: Sm2TacticalActor = state.actor(id)
		if not other.spatial.occupies() or other.spatial.side == target.spatial.side: continue
		outgoing = maxi(outgoing,_best_weapon(state,combat,target_id,id,budget))
		incoming += _best_weapon(state,combat,id,target_id,budget)
		if budget.exhausted: break
	return {"outgoing":outgoing,"incoming":incoming}

static func _best_weapon(state: Sm2TacticalState, combat: Sm2CombatCatalog, from_id: int, to_id: int, budget: Sm2AiWorkBudget) -> int:
	var source: Sm2TacticalActor = state.actor(from_id)
	var ap: int = source.spatial.ap
	var fatigue: int = source.spatial.fatigue
	source.spatial.ap = source.spatial.ap_max
	source.spatial.fatigue = 0
	var best: int = 0
	for id: String in Sm2AttackResolver.available_abilities(source,combat):
		if not budget.spend(): break
		if combat.ability(id).operation != "damage": continue
		var command: Sm2Command = Sm2Command.new()
		command.actor_id = from_id
		command.target_actor_id = to_id
		command.ability_id = id
		var check: Dictionary = Sm2AttackResolver.preview(state,combat,command)
		if check.allowed: best = maxi(best,int(check.expected_hp_loss_x100))
	source.spatial.ap = ap
	source.spatial.fatigue = fatigue
	return best
