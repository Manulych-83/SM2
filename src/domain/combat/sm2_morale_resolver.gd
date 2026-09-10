class_name Sm2MoraleResolver
extends RefCounted
const LEVELS: Array[String] = ["steady", "wavering", "breaking", "fleeing"]

static func after_hit(state: Sm2TacticalState, catalog: Sm2CombatCatalog, target: Sm2TacticalActor,
	hp_loss: int, context: Sm2ConsequenceContext, events: Array[Dictionary]) -> bool:
	if not target.spatial.alive:
		context.facts.append(_fact(target, 20, "ally_died"))
	elif hp_loss * 5 >= catalog.profile(target.loadout_id).hp_max:
		if not _check(state, catalog, target, 10, "large_hit", context, events):
			return false
	var cursor: int = 0
	while cursor < context.facts.size():
		var fact: Dictionary = context.facts[cursor]
		cursor += 1
		for id: int in state.sorted_ids():
			var actor: Sm2TacticalActor = state.actor(id)
			if actor.spatial.side == fact.side and Sm2Hex.distance(actor.spatial.position, fact.position) <= 4:
				if not _check(state, catalog, actor, fact.penalty, fact.cause, context, events):
					return false
	context.facts.clear()
	return true

static func _check(state: Sm2TacticalState, catalog: Sm2CombatCatalog, actor: Sm2TacticalActor,
	penalty: int, cause: String, context: Sm2ConsequenceContext, events: Array[Dictionary]) -> bool:
	var id: int = actor.spatial.actor_id
	var profile: Sm2CombatProfile = catalog.profile(actor.loadout_id)
	if context.checked.has(id) or not actor.spatial.occupies() or actor.morale == "fleeing" or profile.morale_immune:
		return true
	context.checked[id] = true
	var enemies: int = Sm2AttackResolver.neighbors_threatening(state, actor, catalog, false).size()
	var threshold: int = clampi(profile.resolve - penalty - 5 * maxi(enemies - 1, 0), 5, 95)
	var rolled: int = Sm2BattleDice.roll(state.rng, 1, 100)
	if rolled == 0:
		return false
	events.append({"type": "morale_checked", "actor_id": str(id), "cause": cause, "penalty": penalty,
		"enemies": enemies, "threshold": threshold, "roll": rolled})
	if rolled > threshold:
		var previous: String = actor.morale
		actor.morale = LEVELS[LEVELS.find(previous) + 1]
		events.append({"type": "morale_changed", "actor_id": str(id), "from": previous, "to": actor.morale})
		if actor.morale == "fleeing":
			actor.combat.clear_wall()
			context.facts.append(_fact(actor, 10, "ally_fled"))
	return true

static func _fact(actor: Sm2TacticalActor, penalty: int, cause: String) -> Dictionary:
	return {"side": actor.spatial.side, "position": actor.spatial.position, "penalty": penalty, "cause": cause}
