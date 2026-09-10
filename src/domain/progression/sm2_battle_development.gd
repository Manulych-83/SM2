class_name Sm2BattleDevelopment
extends RefCounted
var origin: Dictionary = {}
var world_id: String = ""
var soul: Sm2SoulState = Sm2SoulState.new()
var incarnation: Sm2IncarnationRecord = Sm2IncarnationRecord.new()
var bodies: Dictionary[int,Sm2ProgressBodyState] = {}
var counts: Dictionary[int,Dictionary] = {}
var sequence: int = 0
var catalog: Sm2DevelopmentCatalog
var progress: Sm2ProgressCatalog

func initialize(state: Sm2TacticalState, definitions: Sm2DevelopmentCatalog) -> String:
	if definitions == null or not definitions.ready(): return "development_catalog"
	catalog = definitions; progress = definitions.progression(); world_id = state.battle_id
	var hero_actor: Sm2TacticalActor = state.actor(catalog.hero())
	var companion_actor: Sm2TacticalActor = state.actor(catalog.companion())
	if hero_actor == null or companion_actor == null: return "development_binding"
	if hero_actor.spatial.side != companion_actor.spatial.side or hero_actor.spatial.controller != "player" or companion_actor.spatial.controller != "player": return "development_control"
	soul.knowledge = progress.knowledge_ids()
	for actor_id: int in [catalog.hero(),catalog.companion()]:
		bodies[actor_id] = Sm2ProgressRules.empty_body(2 if actor_id == catalog.hero() else 4,progress)
		counts[actor_id] = {}
		for id: String in catalog.ability_ids(): counts[actor_id][id] = 0
	return ""

func copy() -> Sm2BattleDevelopment:
	var value: Sm2BattleDevelopment = Sm2BattleDevelopment.new()
	value.catalog = catalog; value.progress = progress; value.world_id = world_id; value.sequence = sequence
	value.origin = origin.duplicate(true)
	value.soul.incarnation_id = soul.incarnation_id
	value.incarnation.id = incarnation.id; value.incarnation.body_id = incarnation.body_id
	value.soul.knowledge = soul.knowledge.duplicate()
	for actor_id: int in bodies:
		value.bodies[actor_id] = Sm2ProgressRules.decode_body(bodies[actor_id].to_data(),progress).body
		value.counts[actor_id] = counts[actor_id].duplicate(true)
	return value

func to_data() -> Dictionary:
	var members: Array[Dictionary] = []
	for actor_id: int in [catalog.hero(),catalog.companion()]:
		var practice: Array[Dictionary] = []
		for id: String in catalog.ability_ids(): practice.append({"ability_id":id,"count":counts[actor_id][id]})
		members.append({"actor_id":str(actor_id),"body":bodies[actor_id].to_data(),"attacks":practice})
	var data: Dictionary = {"world_id":world_id,"fingerprint":catalog.fingerprint(),"soul":soul.to_data(),"incarnation":incarnation.to_data(),"source_id":"5","next_id":"6","sequence":str(sequence),"members":members}
	if not origin.is_empty(): data["origin"] = origin.duplicate(true)
	return data

func award(actor_id: int, ability_id: String, events: Array[Dictionary]) -> String:
	if not bodies.has(actor_id): return ""
	var rewards: Dictionary = catalog.awards(ability_id)
	if rewards.is_empty(): return ""
	if sequence >= 1000000: return "practice_limit"
	for id: String in rewards:
		if bodies[actor_id].tracks[id].earned > Sm2ProgressCatalog.XP_LIMIT-int(rewards[id]): return "experience_limit"
	sequence += 1
	counts[actor_id][ability_id] += 1
	for id: String in progress.track_ids():
		if not rewards.has(id): continue
		var track: Sm2ProgressTrackState = bodies[actor_id].tracks[id]
		var before: int = progress.track(id).describe(track.earned).level
		track.earned += int(rewards[id])
		events.append({"type":"battle_practice_awarded","actor_id":str(actor_id),"body_id":str(bodies[actor_id].id),"world_id":world_id,"source_id":"5","practice_sequence":str(sequence),"ability_id":ability_id,"track_id":id,"name":progress.track(id).title,"amount":int(rewards[id]),"level_before":before,"level_after":progress.track(id).describe(track.earned).level})
	return ""

func purchase_error(state: Sm2TacticalState, command: Sm2Command) -> String:
	if not origin.is_empty(): return "nodes_in_camp"
	if not state.finished: return "nodes_after_battle"
	if not bodies.has(command.actor_id) or command.target_actor_id != command.actor_id: return "development_owner"
	var actor: Sm2TacticalActor = state.actor(command.actor_id)
	if not actor.spatial.alive or actor.spatial.controller != "player": return "development_owner"
	return Sm2ProgressRules.purchase_error(bodies[command.actor_id],progress,command.ability_id)

func purchase(command: Sm2Command, events: Array[Dictionary]) -> void:
	var node: Sm2ProgressNodeDefinition = progress.node(command.ability_id)
	Sm2ProgressRules.purchase(bodies[command.actor_id],node)
	events.append({"type":"battle_node_purchased","actor_id":str(command.actor_id),"body_id":str(bodies[command.actor_id].id),"node_id":node.id,"name":node.title,"cost":node.cost,"track_id":node.track_id})

func stat_bonus(actor_id: int, stat: String) -> int:
	if not bodies.has(actor_id): return 0
	var result: int = 0
	for mapping: Dictionary in catalog.mappings():
		if mapping.stat != stat: continue
		for row: Dictionary in Sm2ProgressRules.tracks(bodies[actor_id],progress):
			if row.id == mapping.track_id: result += (int(row.effective)-int(mapping.baseline))*int(mapping.scale)
	return result

func view(state: Sm2TacticalState, actor_id: int) -> Dictionary:
	if not bodies.has(actor_id): return {}
	var knowledge: Array[String] = []
	if actor_id == catalog.hero():
		for id: String in soul.knowledge: knowledge.append(progress.knowledge_name(id))
	var nodes: Array[Dictionary] = []
	for id: String in progress.node_ids():
		var node: Sm2ProgressNodeDefinition = progress.node(id)
		var command: Sm2Command = Sm2Command.new()
		command.kind = "buy_node"; command.actor_id = actor_id; command.target_actor_id = actor_id; command.ability_id = id
		var reason: String = purchase_error(state,command)
		nodes.append({"id":id,"name":node.title,"cost":node.cost,"track_name":progress.track(node.track_id).title,"bonus":node.bonus,"min_level":node.min_level,"owned":id in bodies[actor_id].tracks[node.track_id].nodes,"allowed":reason.is_empty(),"reason":reason})
	return {"world_id":world_id,"body_id":bodies[actor_id].id,"role":"hero" if actor_id == catalog.hero() else "companion","knowledge":knowledge,"tracks":Sm2ProgressRules.tracks(bodies[actor_id],progress),"nodes":nodes,"attacks":counts[actor_id].duplicate(true),"melee_bonus":stat_bonus(actor_id,"melee_skill")}

static func decode(raw: Dictionary, state: Sm2TacticalState, definitions: Sm2DevelopmentCatalog) -> Dictionary:
	var invalid: Dictionary = {"ok":false,"errors":PackedStringArray(["development_snapshot_invalid"])}
	if not Sm2Validate.fields(raw,["world_id","fingerprint","soul","incarnation","source_id","next_id","sequence","members"]): return invalid
	if raw.world_id != state.battle_id or raw.fingerprint != definitions.fingerprint() or raw.source_id != "5" or raw.next_id != "6" or not Sm2Validate.decimal(raw.sequence,0,1000000): return invalid
	var value: Sm2BattleDevelopment = Sm2BattleDevelopment.new()
	if not value.initialize(state,definitions).is_empty(): return invalid
	if not raw.soul is Dictionary or not raw.incarnation is Dictionary or raw.soul != value.soul.to_data() or raw.incarnation != value.incarnation.to_data(): return invalid
	if not raw.members is Array or raw.members.size() != 2: return invalid
	var total: int = 0
	var purchases: int = 0
	for index: int in 2:
		var actor_id: int = [definitions.hero(),definitions.companion()][index]
		var member: Variant = raw.members[index]
		if not member is Dictionary or not Sm2Validate.fields(member,["actor_id","body","attacks"]) or member.actor_id != str(actor_id) or not member.body is Dictionary: return invalid
		var decoded: Dictionary = Sm2ProgressRules.decode_body(member.body,value.progress)
		if not decoded.ok or decoded.body.id != value.bodies[actor_id].id: return invalid
		value.bodies[actor_id] = decoded.body
		if not member.attacks is Array or member.attacks.size() != definitions.ability_ids().size(): return invalid
		var earned: Dictionary[String,int] = {}
		for id: String in value.progress.track_ids(): earned[id] = 0
		var member_total: int = 0
		for rule_index: int in member.attacks.size():
			var rule: Variant = member.attacks[rule_index]
			if not rule is Dictionary or not Sm2Validate.fields(rule,["ability_id","count"]) or rule.ability_id != definitions.ability_ids()[rule_index] or not Sm2Validate.integer(rule.count,0,1000000): return invalid
			var count: int = int(rule.count)
			value.counts[actor_id][rule.ability_id] = count; member_total += count
			var awards: Dictionary = definitions.awards(rule.ability_id)
			for id: String in awards: earned[id] += count*int(awards[id])
		if member_total > state.revision: return invalid
		total += member_total
		for id: String in earned:
			var track: Sm2ProgressTrackState = value.bodies[actor_id].tracks[id]
			if track.earned != earned[id]: return invalid
			if not track.nodes.is_empty() and (not state.finished or not state.actor(actor_id).spatial.alive): return invalid
			purchases += track.nodes.size()
	if purchases > state.revision or total != int(raw.sequence): return invalid
	value.sequence = total
	return {"ok":true,"development":value,"errors":PackedStringArray()}
