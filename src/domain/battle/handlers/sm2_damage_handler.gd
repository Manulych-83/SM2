class_name Sm2DamageHandler
extends Sm2AbilityHandler

func validate(state: Sm2BattleState, _catalog: Sm2Catalog, source: Sm2ActorState,
	ability: Sm2AbilityDefinition, command: Sm2Command) -> String:
	if source.weapon.durability <= 0:
		return "broken_weapon"
	return enemy_target(state, source, ability, command)

func apply(state: Sm2BattleState, catalog: Sm2Catalog, source: Sm2ActorState,
	ability: Sm2AbilityDefinition, command: Sm2Command, events: Array[Dictionary]) -> void:
	var weapon: Sm2WeaponDefinition = catalog.weapon(source.weapon.definition_id)
	var amount: int = state.rng.range_inclusive(weapon.damage_min, weapon.damage_max) + ability.damage_bonus
	source.weapon.durability -= 1
	state.damage(state.actor(command.target_actor_id), amount, source.actor_id, ability.id, events)
	events.append({"type": "weapon_wear", "actor_id": str(source.actor_id), "durability": source.weapon.durability})
