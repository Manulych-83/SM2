class_name Sm2SummonHandler
extends Sm2AbilityHandler

func validate(state: Sm2BattleState, _catalog: Sm2Catalog, source: Sm2ActorState,
	ability: Sm2AbilityDefinition, command: Sm2Command) -> String:
	if command.target_actor_id != 0:
		return "unexpected_actor_target"
	if not state.in_bounds(command.target):
		return "out_of_bounds"
	if state.occupied(command.target):
		return "occupied"
	if Sm2BattleState.distance(source.position, command.target) > ability.range:
		return "out_of_range"
	if state.actors.size() >= 10000 or state.next_id >= 9223372036854775806:
		return "entity_limit"
	return ""

func apply(state: Sm2BattleState, catalog: Sm2Catalog, source: Sm2ActorState,
	ability: Sm2AbilityDefinition, command: Sm2Command, events: Array[Dictionary]) -> void:
	var summoned: Sm2ActorState = state.spawn(catalog.actor(ability.summon_template_id), catalog,
		source.side, source.owner, source.controller, command.target, source.actor_id, state.round + 1)
	events.append({"type": "summoned", "actor_id": str(summoned.actor_id), "creator": str(source.actor_id), "eligible_round": str(summoned.eligible_round)})
