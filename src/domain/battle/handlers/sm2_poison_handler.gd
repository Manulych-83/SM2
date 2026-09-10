class_name Sm2PoisonHandler
extends Sm2AbilityHandler
## M1 status operation: refresh one instance; ticks at activation, never at preview.

func validate(state: Sm2BattleState, catalog: Sm2Catalog, source: Sm2ActorState,
	ability: Sm2AbilityDefinition, command: Sm2Command) -> String:
	var reason: String = enemy_target(state, source, ability, command)
	if not reason.is_empty():
		return reason
	if ability.status_id in catalog.actor(state.actor(command.target_actor_id).template_id).immunities:
		return "immune_target"
	return ""

func apply(state: Sm2BattleState, catalog: Sm2Catalog, source: Sm2ActorState,
	ability: Sm2AbilityDefinition, command: Sm2Command, events: Array[Dictionary]) -> void:
	var target: Sm2ActorState = state.actor(command.target_actor_id)
	var selected: Sm2EffectState = null
	for effect: Sm2EffectState in target.effects:
		if effect.status_id == ability.status_id:
			selected = effect
			break
	if selected == null:
		selected = Sm2EffectState.new()
		selected.status_id = ability.status_id
		target.effects.append(selected)
	selected.source_actor_id = source.actor_id
	selected.remaining = catalog.status(ability.status_id).duration
	events.append({"type": "status_applied", "actor_id": str(target.actor_id), "status_id": ability.status_id, "remaining": selected.remaining})

func tick(state: Sm2BattleState, catalog: Sm2Catalog, target: Sm2ActorState, events: Array[Dictionary]) -> void:
	var survivors: Array[Sm2EffectState] = []
	for effect: Sm2EffectState in target.effects:
		if target.alive():
			state.damage(target, catalog.status(effect.status_id).tick_damage, effect.source_actor_id, effect.status_id, events)
			effect.remaining -= 1
			if effect.remaining > 0:
				survivors.append(effect)
			else:
				events.append({"type": "status_expired", "actor_id": str(target.actor_id), "status_id": effect.status_id})
		else:
			survivors.append(effect)
	target.effects = survivors
