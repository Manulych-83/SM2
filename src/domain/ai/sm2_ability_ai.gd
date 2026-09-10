class_name Sm2AbilityAi
extends RefCounted
## Scores legal actions through shared queries; identity-independent support for known operations.
static func decide(view: Dictionary, queries: Sm2AiQueries, profile: Sm2AiProfile) -> Dictionary:
	var tuning: Dictionary = profile.to_data()
	var budget: Sm2AiWorkBudget = Sm2AiWorkBudget.new(int(tuning.query_limit))
	var active: Dictionary = {}
	var participants: Array[Dictionary] = []
	for actor: Dictionary in view.actors:
		if not budget.spend(): return _limit()
		if actor.actor_id == view.active_actor_id: active = actor
		if actor.alive and actor.on_field: participants.append(actor)
	if active.is_empty(): return {"ok":false,"reason":"active_actor_missing"}
	if active.morale == "fleeing": return _retreat(view)
	participants.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.actor_id) < int(b.actor_id))
	var infos: Array[Dictionary] = []
	var ids: Array[String] = []
	ids.assign(active.abilities)
	ids.sort()
	for id: String in ids:
		if not budget.spend(): return _limit()
		var info: Dictionary = queries.action_info(id)
		if not info.is_empty(): infos.append(info)
	var enemy_count: int = 0
	for target: Dictionary in participants:
		if target.side != active.side: enemy_count += 1
	var radius: int = 0
	if tuning.policy == Sm2AiProfile.AREA_POLICY:
		for info: Dictionary in infos:
			if info.operation == "area_hp_damage": radius = maxi(radius,int(info.radius))
	if radius > 0: participants.append_array(queries.area_centers(int(active.actor_id),radius,budget))
	if budget.exhausted: return _limit()
	var position: Vector2i = Vector2i(int(active.q),int(active.r))
	var best: Dictionary = {}
	var direct: Dictionary = {}
	var positional: bool = false
	for target: Dictionary in participants:
		for info: Dictionary in infos:
			if not budget.spend(): return _limit()
			if not _target(info,active,target): continue
			if not _spend_area(info,view,budget): return _limit()
			var command: Sm2Command = _target_command(view,info,target)
			var check: Dictionary = queries.action(command,position)
			if check.allowed:
				var evaluated: Dictionary = _score(active,target,info,check,command,queries,budget,tuning,enemy_count)
				if budget.exhausted: return _limit()
				if int(evaluated.score) > 0 and (best.is_empty() or _better(evaluated,best)): best = evaluated
				if info.operation in ["damage","direct_hp_damage","area_hp_damage"] and int(evaluated.score) > 0 and (direct.is_empty() or _better(evaluated,direct)): direct = evaluated
			if info.target_side == "enemy":
				if not budget.spend(): return _limit()
				if not _spend_area(info,view,budget): return _limit()
				var possible: Dictionary = queries.action(command,position,true)
				positional = positional or (possible.allowed and _offensive_value(info,possible))
	if not best.is_empty():
		# Non-urgent support must leave room for an available direct attack.
		if not direct.is_empty() and best.choice in ["effect","cleanse","shieldwall"] and int(best.priority) == 0 and int(active.ap)-int(best.ap) < int(direct.ap): best = direct
		return {"ok":true,"command":best.command,"choice":best.choice,"score":best.score,"priority":best.priority,"work":budget.used}
	if not queries.has_future_offense(int(active.actor_id),infos): return _retreat(view)
	if positional: return _end(view,"resources",budget)
	var routes: Dictionary = queries.routes(int(active.actor_id),budget.limit-budget.used)
	if not routes.ok: return routes
	if not budget.spend(int(routes.work)): return _limit()
	var destination: Dictionary = {}
	for cell: Dictionary in routes.cells:
		if cell.path.is_empty(): continue
		for target: Dictionary in participants:
			if target.side == active.side: continue
			for info: Dictionary in infos:
				if not budget.spend(): return _limit()
				if info.target_side != "enemy" or not _target(info,active,target): continue
				if not _spend_area(info,view,budget): return _limit()
				var command: Sm2Command = _target_command(view,info,target)
				var check: Dictionary = queries.action(command,cell.position,true)
				if not check.allowed or not _offensive_value(info,check): continue
				var candidate: Dictionary = cell.duplicate(true)
				candidate["target_id"] = int(target.actor_id)
				candidate["ability_id"] = info.id
				if destination.is_empty() or Sm2TacticalAi._route_less(candidate,destination): destination = candidate
	if destination.is_empty(): return _end(view,"no_route",budget)
	var price: Dictionary = queries.step(int(active.actor_id),destination.path[0])
	if int(active.ap) < int(price.ap_cost) or int(active.fatigue_max)-int(active.fatigue) < int(price.fatigue_cost): return _end(view,"movement_resources",budget)
	var move: Sm2Command = Sm2TacticalAi._command(view,"move")
	move.target = destination.path[0]
	return {"ok":true,"command":move,"choice":"approach","route":destination,"work":budget.used}

static func _target(info: Dictionary, active: Dictionary, target: Dictionary) -> bool:
	if info.operation == "area_hp_damage": return target.has("area_center")
	if target.has("area_center"): return false
	if info.target_side == "self": return target.actor_id == active.actor_id
	return (target.side == active.side) == (info.target_side == "ally")

static func _score(active: Dictionary, target: Dictionary, info: Dictionary, check: Dictionary, command: Sm2Command, queries: Sm2AiQueries, budget: Sm2AiWorkBudget, tuning: Dictionary, enemy_count: int) -> Dictionary:
	var value: int = 0
	var priority: int = 0
	var choice: String = "attack"
	var mana: int = 0
	if info.kind == "spell":
		choice = "spell"
		mana = int(check.mana_cost)
		var penalty: int = int(tuning.mana_weight)
		if int(active.mana)-mana < int(tuning.mana_reserve): penalty += int(tuning.low_mana_weight)
		value = int(check.hp_loss)*100*int(tuning.hp_weight)-mana*penalty
		var kills: int = int(check.get("kills",int(check.get("lethal",false))))
		if kills > 0:
			priority = 1100 if kills == enemy_count else 900
			value = maxi(int(check.ap_cost),value)
	elif info.kind == "effect":
		var assessment: Dictionary = queries.effect_assessment(command,check,budget,tuning)
		value = int(assessment.value)
		priority = 1000 if assessment.urgent else 0
		if assessment.urgent: value = maxi(int(check.ap_cost),value)
		choice = "cleanse" if info.operation == "dispel_effects" else "effect"
	elif info.operation == "damage":
		value = int(check.expected_hp_loss_x100)*int(tuning.hp_weight)+int(check.expected_armor_loss_x100)*int(tuning.armor_weight)
	elif info.operation == "shield_break":
		choice = "shield_break"
		var shield: Dictionary = Sm2TacticalAi._item(target,"shield")
		if int(shield.current) <= int(tuning.shield_threshold) or target.combat.shieldwall_source != "0": value = int(check.shield_loss)*100*int(tuning.armor_weight)
	elif info.operation == "shieldwall":
		# Keep the ordinary stance only as a fallback when an adjacent enemy can threaten.
		choice = "shieldwall"
		if budget.spend() and queries.threatened(int(active.actor_id)): value = int(check.ap_cost)
	@warning_ignore("integer_division")
	var score: int = maxi(0,value)/maxi(1,int(check.ap_cost))
	return {"command":command,"choice":choice,"score":score,"priority":priority,"mana":mana,"fatigue":int(check.fatigue_cost),"ap":int(check.ap_cost)}

static func _offensive_value(info: Dictionary, check: Dictionary) -> bool:
	if info.kind == "weapon": return info.operation == "damage"
	if info.kind == "spell": return int(check.hp_loss) > 0
	if info.operation == "apply_effect":
		for effect: Dictionary in check.effects:
			for op: Dictionary in effect.operations:
				if op.kind == "periodic_hp_damage" and int(op.tick_loss) > 0: return true
	return false

static func _better(a: Dictionary,b: Dictionary) -> bool:
	for key: String in ["priority","score"]:
		if a[key] != b[key]: return int(a[key]) > int(b[key])
	for key: String in ["mana","fatigue","ap"]:
		if a[key] != b[key]: return int(a[key]) < int(b[key])
	if a.command.target_actor_id == b.command.target_actor_id and a.command.ability_id == b.command.ability_id: return Sm2Hex.numeric_less(a.command.target,b.command.target)
	return Sm2TacticalAi._command_less(a.command,b.command)

static func _target_command(view: Dictionary, info: Dictionary, target: Dictionary) -> Sm2Command:
	var command: Sm2Command = Sm2TacticalAi._command(view,"use_ability",info.id,int(target.actor_id))
	if target.has("area_center"): command.target = Vector2i(int(target.q),int(target.r))
	return command

static func _spend_area(info: Dictionary, view: Dictionary, budget: Sm2AiWorkBudget) -> bool:
	if info.operation != "area_hp_damage": return true
	return budget.spend(view.actors.size()+(2*int(info.radius)+1)*(2*int(info.radius)+1))

static func _end(view: Dictionary, choice: String, budget: Sm2AiWorkBudget) -> Dictionary:
	return {"ok":true,"choice":choice,"command":Sm2TacticalAi._command(view,"end_turn"),"work":budget.used}
static func _retreat(view: Dictionary) -> Dictionary:
	var result: Dictionary = Sm2RetreatPolicy.decide(view)
	result["choice"] = "retreat"
	return result
static func _limit() -> Dictionary: return {"ok":false,"reason":"ai_query_limit"}
