class_name Sm2AbilityHandler
extends RefCounted
## Registry boundary: validate is pure, apply runs only after global validation.

func validate(_state: Sm2BattleState, _catalog: Sm2Catalog, _source: Sm2ActorState,
	_ability: Sm2AbilityDefinition, _command: Sm2Command) -> String:
	return "unsupported_operation"

func apply(_state: Sm2BattleState, _catalog: Sm2Catalog, _source: Sm2ActorState,
	_ability: Sm2AbilityDefinition, _command: Sm2Command, _events: Array[Dictionary]) -> void:
	pass

func enemy_target(state: Sm2BattleState, source: Sm2ActorState, ability: Sm2AbilityDefinition,
	command: Sm2Command) -> String:
	var target: Sm2ActorState = state.actor(command.target_actor_id)
	if target == null or not target.alive():
		return "invalid_target"
	if target.side == source.side:
		return "friendly_target"
	if Sm2BattleState.distance(source.position, target.position) > ability.range:
		return "out_of_range"
	return ""
