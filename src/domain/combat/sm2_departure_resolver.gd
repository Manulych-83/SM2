class_name Sm2DepartureResolver
extends RefCounted

static func boundary(field: Sm2Battlefield, position: Vector2i) -> bool:
	return position.x == 0 or position.y == 0 or position.x == field.width() - 1 or position.y == field.height() - 1

static func preview(state: Sm2TacticalState, command: Sm2Command) -> Dictionary:
	var actor: Sm2TacticalActor = state.actor(command.actor_id)
	if command.kind == "move":
		return Sm2MovementResolver.preview(state.field, actor.spatial, state.occupancy(), command)
	var reason: String = ""
	if not boundary(state.field, actor.spatial.position):
		reason = "escape_boundary_required"
	elif actor.spatial.ap < 2:
		reason = "insufficient_ap"
	elif actor.spatial.fatigue_max - actor.spatial.fatigue < 4:
		reason = "fatigue_limit"
	return {"allowed": reason.is_empty(), "reason": reason, "ap_cost": 2, "fatigue_cost": 4}

static func resolve(state: Sm2TacticalState, catalog: Sm2CombatCatalog, command: Sm2Command,
	context: Sm2ConsequenceContext) -> Dictionary:
	var price: Dictionary = preview(state, command)
	if not price.allowed:
		return {"accepted": false, "code": price.reason, "events": []}
	var actor: Sm2TacticalActor = state.actor(command.actor_id)
	var origin: Vector2i = actor.spatial.position
	actor.spatial.ap -= int(price.ap_cost)
	actor.spatial.fatigue += int(price.fatigue_cost)
	var events: Array[Dictionary] = [{"type": "resources_spent", "actor_id": str(command.actor_id), "ap": price.ap_cost, "fatigue": price.fatigue_cost}]
	for id: int in Sm2AttackResolver.neighbors_threatening(state, actor, catalog, true):
		if not Sm2AttackResolver.neighbors_threatening(state, actor, catalog, true).has(id):
			continue
		var reaction: Sm2Command = Sm2Command.new()
		reaction.kind = "use_ability"
		reaction.actor_id = id
		reaction.target_actor_id = command.actor_id
		var abilities: Array[String] = Sm2AttackResolver.available_abilities(state.actor(id),catalog)
		abilities.sort()
		for ability_id: String in abilities:
			var ability: Sm2CombatAbility = catalog.ability(ability_id)
			if ability.operation == "damage" and ability.mode == "melee":
				reaction.ability_id = ability_id
				break
		var resolved: Dictionary = Sm2AttackResolver.resolve(state, catalog, reaction, true, context)
		if not resolved.accepted:
			return resolved
		events.append_array(resolved.events)
		for event: Dictionary in resolved.events:
			if event.type == "attack_hit":
				events.append({"type": "movement_interrupted", "actor_id": str(command.actor_id), "by_actor_id": str(id), "action": command.kind})
				return {"accepted": true, "code": "movement_interrupted", "events": events}
	if command.kind == "escape":
		actor.spatial.on_field = false
		actor.spatial.ap = 0
		actor.reactions_left = 0
		actor.turn_done = true
		actor.combat.clear_wall()
		state.main_queue.erase(command.actor_id)
		state.deferred_queue.erase(command.actor_id)
		events.append({"type": "actor_escaped", "actor_id": str(command.actor_id), "side": actor.spatial.side})
	else:
		actor.spatial.position = command.target
		events.append({"type": "moved", "actor_id": str(command.actor_id), "from_q": origin.x, "from_r": origin.y, "q": command.target.x, "r": command.target.y})
	return {"accepted": true, "code": "accepted", "events": events}
