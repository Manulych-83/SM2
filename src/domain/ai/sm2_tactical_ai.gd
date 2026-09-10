class_name Sm2TacticalAi
extends RefCounted

static func decide(view: Dictionary, queries: Sm2AiQueries, profile: Sm2AiProfile) -> Dictionary:
	if view.is_empty() or view.finished:
		return {"ok": false, "reason": "battle_unavailable"}
	var tuning: Dictionary = profile.to_data()
	if tuning.is_empty():
		return {"ok": false, "reason": "ai_profile_missing"}
	if tuning.policy in [Sm2AiProfile.ABILITY_POLICY,Sm2AiProfile.AREA_POLICY]:
		return Sm2AbilityAi.decide(view,queries,profile)
	var active: Dictionary = {}
	var enemies: Array[Dictionary] = []
	for actor: Dictionary in view.actors:
		if actor.actor_id == view.active_actor_id:
			active = actor
	if active.is_empty():
		return {"ok": false, "reason": "active_actor_missing"}
	for actor: Dictionary in view.actors:
		if actor.side != active.side and actor.alive and actor.on_field:
			enemies.append(actor)
	enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.actor_id) < int(b.actor_id))
	var damage_ids: Array[String] = []
	var empty_bow: bool = false
	for id: String in active.abilities:
		var ability: Sm2CombatAbility = queries.ability(id)
		if ability == null: continue
		if ability.operation == "damage":
			damage_ids.append(id)
			if ability.mode == "ranged" and ability.ammo_cost > 0:
				empty_bow = _item(active, "weapon").ammo < ability.ammo_cost
	if active.morale == "fleeing" or empty_bow:
		var retreat: Dictionary = Sm2RetreatPolicy.decide(view)
		retreat["choice"] = "retreat"
		return retreat
	damage_ids.sort()
	var position: Vector2i = Vector2i(int(active.q), int(active.r))
	var best_break: Dictionary = {}
	var best_attack: Dictionary = {}
	var positional_attack: bool = false
	var melee_position: bool = false
	var work: int = 0
	for target: Dictionary in enemies:
		for id: String in active.abilities:
			var ability: Sm2CombatAbility = queries.ability(id)
			if ability == null: continue
			if ability.operation not in ["damage", "shield_break"]:
				continue
			work += 2
			if work > int(tuning.query_limit):
				return {"ok": false, "reason": "ai_query_limit"}
			var command: Sm2Command = _command(view, "use_ability", id, int(target.actor_id))
			var check: Dictionary = queries.attack(command, position)
			if ability.operation == "shield_break":
				var shield: Dictionary = _item(target, "shield")
				if check.allowed and (int(shield.current) <= int(tuning.shield_threshold) or target.combat.shieldwall_source != "0"):
					if best_break.is_empty() or int(shield.current) < int(best_break.durability) or (int(shield.current) == int(best_break.durability) and _command_less(command, best_break.command)):
						best_break = {"command": command, "durability": shield.current}
			else:
				var available_position: bool = queries.attack(command, position, true).allowed
				positional_attack = positional_attack or available_position
				melee_position = melee_position or (available_position and ability.mode == "melee")
				if check.allowed:
					var score: int = int(tuning.hp_weight) * int(check.expected_hp_loss_x100) + int(tuning.armor_weight) * int(check.expected_armor_loss_x100)
					if best_attack.is_empty() or score > int(best_attack.score) or (score == int(best_attack.score) and _command_less(command, best_attack.command)):
						best_attack = {"command": command, "score": score}
	if not best_break.is_empty():
		return {"ok": true, "choice": "shield_break", "command": best_break.command}
	if not best_attack.is_empty():
		return {"ok": true, "choice": "attack", "score": best_attack.score, "command": best_attack.command}
	if melee_position:
		for id: String in active.abilities:
			if queries.ability(id) != null and queries.ability(id).operation == "shieldwall":
				var command: Sm2Command = _command(view, "use_ability", id, int(active.actor_id))
				if queries.attack(command, position).allowed:
					return {"ok": true, "choice": "shieldwall", "command": command}
	if positional_attack:
		return {"ok": true, "choice": "resources", "command": _command(view, "end_turn")}
	var routes: Dictionary = queries.routes(int(active.actor_id), int(tuning.query_limit) - work)
	if not routes.ok:
		return routes
	work += int(routes.work)
	var best: Dictionary = {}
	for cell: Dictionary in routes.cells:
		if cell.path.is_empty():
			continue
		for target: Dictionary in enemies:
			for id: String in damage_ids:
				work += 1
				if work > int(tuning.query_limit):
					return {"ok": false, "reason": "ai_query_limit"}
				var command: Sm2Command = _command(view, "use_ability", id, int(target.actor_id))
				if queries.attack(command, cell.position, true).allowed:
					var candidate: Dictionary = cell.duplicate(true)
					candidate["target_id"] = int(target.actor_id)
					candidate["ability_id"] = id
					if best.is_empty() or _route_less(candidate, best):
						best = candidate
	if best.is_empty():
		return {"ok": true, "choice": "no_route", "command": _command(view, "end_turn")}
	var price: Dictionary = queries.step(int(active.actor_id), best.path[0])
	if int(active.ap) < int(price.ap_cost) or int(active.fatigue_max) - int(active.fatigue) < int(price.fatigue_cost):
		return {"ok": true, "choice": "movement_resources", "command": _command(view, "end_turn")}
	var move: Sm2Command = _command(view, "move")
	move.target = best.path[0]
	return {"ok": true, "choice": "approach", "command": move, "route": best}

static func _command(view: Dictionary, kind: String, ability: String = "", target: int = 0) -> Sm2Command:
	var result: Sm2Command = Sm2Command.new()
	result.kind = kind
	result.actor_id = int(view.active_actor_id)
	result.expected_revision = int(view.revision)
	result.ability_id = ability
	result.target_actor_id = target
	return result

static func command_data(command: Sm2Command) -> Dictionary:
	var data: Dictionary = {"kind": command.kind, "actor_id": str(command.actor_id), "expected_revision": str(command.expected_revision),
		"ability_id": command.ability_id, "target_actor_id": str(command.target_actor_id), "q": command.target.x, "r": command.target.y}
	if not command.battle_id.is_empty(): data["battle_id"] = command.battle_id
	return data

static func _command_less(left: Sm2Command, right: Sm2Command) -> bool:
	return left.target_actor_id < right.target_actor_id if left.target_actor_id != right.target_actor_id else left.ability_id < right.ability_id

static func _route_less(left: Dictionary, right: Dictionary) -> bool:
	for key: String in ["risk", "ap_cost", "fatigue_cost", "target_id"]:
		if left[key] != right[key]:
			return int(left[key]) < int(right[key])
	if left.position != right.position:
		return Sm2Hex.numeric_less(left.position, right.position)
	if left.path != right.path:
		return Sm2Hex.path_less(left.path, right.path)
	return left.ability_id < right.ability_id

static func _item(actor: Dictionary, slot: String) -> Dictionary:
	for item: Dictionary in actor.combat.items:
		if item.slot == slot:
			return item
	return {}
