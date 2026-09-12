class_name Sm2CombatHudView
extends RefCounted
## Detached read models; no scene references, texture paths or simulated commands.

static func command(state: Dictionary, kind: String, ability: String = "", target: int = 0) -> Sm2Command:
	var value: Sm2Command = Sm2Command.new()
	value.battle_id = state.battle_id; value.expected_revision = int(state.revision)
	value.actor_id = int(state.active_actor_id); value.kind = kind
	value.ability_id = ability; value.target_actor_id = target
	return value

static func actor(state: Dictionary, id: int) -> Dictionary:
	for entry: Dictionary in state.get("actors",[]):
		if int(entry.actor_id) == id: return entry.duplicate(true)
	return {}

static func card(value: Dictionary) -> Dictionary:
	if value.is_empty(): return {}
	var rate: int = 0
	for wound: Dictionary in value.get("anatomy",{}).get("wounds",[]): rate += int(wound.rate)
	return {"id":int(value.actor_id),"name":value.get("display_name","Боец"),"side":value.side,"alive":value.alive,"on_field":value.on_field,"morale":value.morale,
		"ap":[value.ap,value.ap_max],"fatigue":[value.fatigue,value.fatigue_max],"condition":[value.combat.hp,value.hp_max],
		"focus":[value.get("mana",0),value.get("magic_profile",{}).get("mana_max",0)],"blood":value.get("anatomy",{}).get("blood",-1),"bleeding":rate,"barrier":value.get("barrier",{}).get("remaining",0)}

static func queue(state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for group: String in ["main_queue","deferred_queue"]:
		for id: Variant in state.get(group,[]):
			var value: Dictionary = actor(state,int(id))
			if value.is_empty(): continue
			result.append({"id":int(id),"name":value.get("display_name","Боец"),"side":value.side,"current":int(id)==int(state.active_actor_id),"deferred":group=="deferred_queue"})
	return result

static func actions(runner: Sm2BattleRunner, state: Dictionary, player: bool) -> Array[Dictionary]:
	var active: Dictionary = actor(state,int(state.active_actor_id))
	if active.is_empty(): return []
	var rows: Array[Dictionary] = []
	for id: String in active.abilities:
		var self_target: bool = id.ends_with("shieldwall")
		for spell: Dictionary in active.get("spells",[]):
			if spell.id == id and spell.operation == "self_barrier": self_target = true
		var cost: Dictionary = runner.ability_cost(int(active.actor_id),id)
		var check: Dictionary = {"allowed":false,"reason":"target_unavailable"}
		var chosen: int = int(active.actor_id)
		for target: Dictionary in state.actors:
			if self_target and target.actor_id != active.actor_id: continue
			if not self_target and (target.side == active.side or not target.alive or not target.on_field): continue
			var probe: Dictionary = runner.preview(command(state,"use_ability",id,int(target.actor_id)))
			if check.reason == "target_unavailable" or probe.allowed or (check.reason in ["attack_range","line_of_sight_blocked"] and probe.reason not in ["attack_range","line_of_sight_blocked"]):
				check = probe; chosen = int(target.actor_id)
			if probe.allowed: break
		rows.append({"id":id,"button":"Ability_"+id.get_slice(".",1),"kind":"use_ability","target":chosen,"self":self_target,
			"cost":cost,"allowed":player and check.allowed,"reason":check.reason if player else "not_player_turn","check":check.duplicate(true),"revision":int(state.revision)})
	for target: Dictionary in state.actors:
		if target.side != active.side or not target.alive: continue
		for wound: Dictionary in target.get("anatomy",{}).get("wounds",[]):
			if int(wound.rate) <= 0: continue
			var check: Dictionary = runner.preview(command(state,"bandage",wound.id,int(target.actor_id)))
			rows.append({"id":str(wound.id),"button":"Bandage_%s_%s" % [target.actor_id,wound.id],"kind":"bandage","target":int(target.actor_id),"self":true,
				"label":"Повязка №%s · %s" % [target.actor_id,wound.name],"cost":{"ap_cost":active.bandage_ap},"allowed":player and check.allowed,"reason":check.reason if player else "not_player_turn","check":check.duplicate(true),"revision":int(state.revision)})
	for row: Dictionary in rows:
		row["battle_id"] = str(state.battle_id); row["actor_id"] = int(active.actor_id)
	return rows
