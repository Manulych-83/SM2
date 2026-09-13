class_name Sm2BattleDevelopment
extends RefCounted
const AFTER_BATTLE: String="sm2.growth.after_battle.1"
var deferred_growth: bool=false
# Derived from accepted action counters, not a second serialized XP balance.
var pending: Dictionary[int,Dictionary]={}
var _profile: Sm2CombatGrowthProfile=null
var _upgrades: Dictionary[int,Sm2BodyUpgradeState]={}
var upgrades: Dictionary[int,Sm2BodyUpgradeState]:
	get:
		_materialize(); return _upgrades
	set(value):
		_materialize(); _upgrades=value
var _origin: Dictionary={}
var origin: Dictionary:
	get:
		_materialize(); return _origin
	set(value):
		_materialize(); _origin=value
var world_id: String = ""
var soul: Sm2SoulState = Sm2SoulState.new()
var incarnation: Sm2IncarnationRecord = Sm2IncarnationRecord.new()
var _bodies: Dictionary[int,Sm2ProgressBodyState]={}
var bodies: Dictionary[int,Sm2ProgressBodyState]:
	get:
		_materialize(); return _bodies
	set(value):
		_materialize(); _bodies=value
var counts: Dictionary[int,Dictionary] = {}
var sequence: int = 0
var catalog: Sm2DevelopmentCatalog
var progress: Sm2ProgressCatalog

func initialize(state: Sm2TacticalState, definitions: Sm2DevelopmentCatalog) -> String:
	if definitions == null or not definitions.ready(): return "development_catalog"
	catalog = definitions; progress = definitions._shared_progression(); world_id = state.battle_id
	var hero_actor: Sm2TacticalActor = state.actor(catalog.hero())
	var companion_actor: Sm2TacticalActor = state.actor(catalog.companion())
	if hero_actor == null or companion_actor == null: return "development_binding"
	if hero_actor.spatial.side != companion_actor.spatial.side or hero_actor.spatial.controller != "player" or companion_actor.spatial.controller != "player": return "development_control"
	soul.knowledge = progress.knowledge_ids()
	for actor_id: int in [catalog.hero(),catalog.companion()]:
		bodies[actor_id] = Sm2ProgressRules.empty_body(2 if actor_id == catalog.hero() else 4,progress)
		if progress.is_party() and actor_id==catalog.companion():
			bodies[actor_id]=Sm2CompanionProgress.new(); bodies[actor_id].id=4
		counts[actor_id] = {}
		for id: String in catalog.ability_ids(): counts[actor_id][id] = 0
	return ""

func _materialize() -> void:
	if _profile!=null:
		_profile.materialize_into(self); _profile=null

func has_actor(id: int) -> bool: return _profile.has_actor(id) if _profile!=null else _bodies.has(id)
func origin_version() -> String: return _profile.origin_version() if _profile!=null else str(_origin.get("version",""))
func origin_actors() -> Array: return _profile.actors() if _profile!=null else _origin.get("actors",[])
func body_id(id: int) -> int: return _profile.body_id(id) if _profile!=null else _bodies[id].id
func simple(id: int) -> bool: return _profile.simple(id) if _profile!=null else _bodies[id] is Sm2CompanionProgress
func earned(id: int,track: String) -> int:
	if _profile!=null: return _profile.earned(id,track)
	return (_bodies[id] as Sm2CompanionProgress).earned if simple(id) else _bodies[id].tracks[track].earned
func psionic_available(actor: int,id: String) -> bool:
	return _profile.available(actor,id) if _profile!=null else catalog.psionics().available(_bodies.get(actor),id)
func hybrid_available(actor: int,id: String) -> bool:
	return _profile.available(actor,id) if _profile!=null else catalog.hybrids().available(_bodies.get(actor),id)
func psionic_parameter(actor: int,id: String,shield: bool=false) -> Dictionary:
	if _profile!=null: return _profile.parameter(actor,id)
	return catalog.psionics().capacity(id,_bodies[actor],progress,track_modifiers(actor)) if shield else catalog.psionics().damage(id,_bodies[actor],progress,track_modifiers(actor))
func hybrid_parameter(actor: int,id: String) -> Dictionary:
	return _profile.parameter(actor,id) if _profile!=null else catalog.hybrids().damage(id,_bodies[actor],progress,track_modifiers(actor))
func concentration_cost(actor: int,base: int,id: String="") -> Dictionary:
	if _profile!=null and not id.is_empty(): return _profile.cost(actor,id)
	return Sm2PsionicCostQuery.resolve(base,catalog.upgrades(),upgrades.get(actor))

func copy(compact: bool=false) -> Sm2BattleDevelopment:
	if _profile!=null:
		var result: Sm2BattleDevelopment=_profile.instance()
		result.sequence=sequence; result.pending.assign(pending.duplicate(true)); result.counts.assign(counts.duplicate(true))
		if not compact: result._materialize()
		return result
	var value: Sm2BattleDevelopment = Sm2BattleDevelopment.new()
	value.deferred_growth=deferred_growth; value.pending.assign(pending.duplicate(true))
	value.catalog = catalog; value.progress = progress; value.world_id = world_id; value.sequence = sequence
	value.origin = origin.duplicate(true)
	for id: int in upgrades: value.upgrades[id]=upgrades[id].copy()
	value.soul.incarnation_id = soul.incarnation_id
	value.incarnation.id = incarnation.id; value.incarnation.body_id = incarnation.body_id
	value.soul.knowledge = soul.knowledge.duplicate()
	for actor_id: int in bodies:
		value.bodies[actor_id] = bodies[actor_id].copy()
		value.counts[actor_id] = counts[actor_id].duplicate(true)
	return value

func to_data(compact: bool=false) -> Dictionary:
	if _profile!=null: return _profile.snapshot(self,compact)
	var members: Array[Dictionary] = []
	for actor_id: int in [catalog.hero(),catalog.companion()]:
		var practice: Array[Dictionary] = []
		for id: String in catalog.ability_ids(): practice.append({"ability_id":id,"count":counts[actor_id][id]})
		members.append({"actor_id":str(actor_id),"body":bodies[actor_id].to_data(),"attacks":practice})
	var data: Dictionary = {"world_id":world_id,"fingerprint":catalog.fingerprint(),"soul":soul.to_data(),"incarnation":incarnation.to_data(),"source_id":"5","next_id":"6","sequence":str(sequence),"members":members}
	if deferred_growth: data["growth_timing"]=AFTER_BATTLE
	if not origin.is_empty(): data["origin"] = origin.duplicate(true)
	return data

func award(actor_id: int, ability_id: String, events: Array[Dictionary]) -> String:
	if not has_actor(actor_id): return ""
	var rewards: Dictionary = catalog.awards(ability_id)
	if rewards.is_empty(): return ""
	if sequence >= 1000000: return "practice_limit"
	if deferred_growth: return _accumulate(actor_id,ability_id,rewards,events)
	if bodies[actor_id] is Sm2CompanionProgress:
		var body: Sm2CompanionProgress=bodies[actor_id] as Sm2CompanionProgress
		var amount: int=int(progress.companion_growth().attack_xp)
		if body.earned>Sm2ProgressCatalog.XP_LIMIT-amount: return "experience_limit"
		var before: int=int(body.describe(progress).level)
		body.earned+=amount; sequence+=1; counts[actor_id][ability_id]+=1
		events.append({"type":"companion_experience_awarded","actor_id":str(actor_id),"body_id":str(body.id),"ability_id":ability_id,"amount":amount,"level_before":before,"level_after":body.describe(progress).level})
		return ""
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

## XP has no effect on any combat query until the whole encounter closes.
func _accumulate(actor_id: int,ability_id: String,rewards: Dictionary,events: Array[Dictionary]) -> String:
	var simple: bool=simple(actor_id)
	var awards: Dictionary={"general":int(progress.companion_growth().attack_xp)} if simple else rewards
	var accumulated: Dictionary=pending.get(actor_id,{})
	for id: String in awards:
		var baseline: int=earned(actor_id,id)
		if baseline>Sm2ProgressCatalog.XP_LIMIT-int(accumulated.get(id,0))-int(awards[id]): return "experience_limit"
	sequence+=1; counts[actor_id][ability_id]+=1
	for id: String in awards:
		accumulated[id]=int(accumulated.get(id,0))+int(awards[id])
		events.append({"type":"battle_practice_accumulated","actor_id":str(actor_id),"body_id":str(body_id(actor_id)),"ability_id":ability_id,"track_id":id,"name":"Общий опыт" if simple else progress.track(id).title,"amount":int(awards[id])})
	pending[actor_id]=accumulated
	return ""

## Called once on the closing command's candidate, before snapshot validation.
func settle_practice(events: Array[Dictionary]) -> void:
	if not deferred_growth or pending.is_empty(): return
	_materialize()
	for actor_id: int in [catalog.hero(),catalog.companion()]:
		var awards: Dictionary=pending.get(actor_id,{})
		for id: String in awards:
			if bodies[actor_id] is Sm2CompanionProgress:
				var body: Sm2CompanionProgress=bodies[actor_id] as Sm2CompanionProgress
				var before: int=int(body.describe(progress).level)
				body.earned+=int(awards[id])
				events.append({"type":"battle_growth_applied","actor_id":str(actor_id),"name":"Общий опыт","amount":int(awards[id]),"level_before":before,"level_after":int(body.describe(progress).level)})
			else:
				var track: Sm2ProgressTrackState=bodies[actor_id].tracks[id]
				var before: int=int(progress.track(id).describe(track.earned).level)
				track.earned+=int(awards[id])
				events.append({"type":"battle_growth_applied","actor_id":str(actor_id),"name":progress.track(id).title,"amount":int(awards[id]),"level_before":before,"level_after":int(progress.track(id).describe(track.earned).level)})
	pending.clear()

func pending_view(actor_id: int) -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	for id: String in pending.get(actor_id,{}):
		rows.append({"title":"Общий опыт" if id=="general" else progress.track(id).title,"xp":int(pending[actor_id][id])})
	return rows

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

func track_modifiers(actor_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if catalog.has_upgrades(): result=catalog.upgrades().track_modifiers(upgrades.get(actor_id))
	return result
func extra_attack_fatigue(actor_id: int) -> int:
	if _profile!=null: return _profile.fatigue(actor_id)
	return catalog.upgrades().attack_fatigue(upgrades.get(actor_id)) if catalog.has_upgrades() else 0

func stat_bonus(actor_id: int, stat: String) -> int:
	if _profile!=null: return _profile.stat(actor_id,stat)
	if not bodies.has(actor_id): return 0
	if bodies[actor_id] is Sm2CompanionProgress:
		return (int((bodies[actor_id] as Sm2CompanionProgress).describe(progress).level)-1)*int(progress.companion_growth().melee_per_level) if stat=="melee_skill" else 0
	var result: int = 0
	for mapping: Dictionary in catalog.mappings():
		if mapping.stat != stat: continue
		var row: Dictionary=Sm2ProgressRules.track(bodies[actor_id],progress,mapping.track_id,track_modifiers(actor_id))
		result += (int(row.effective)-int(mapping.baseline))*int(mapping.scale)
	return result

func view(state: Sm2TacticalState, actor_id: int) -> Dictionary:
	if _profile!=null: return _profile.view(self,actor_id)
	if not bodies.has(actor_id): return {}
	if bodies[actor_id] is Sm2CompanionProgress:
		return {"world_id":world_id,"body_id":bodies[actor_id].id,"role":"companion","pending_practice":pending_view(actor_id),"growth_deferred":deferred_growth and not state.finished,"growth":(bodies[actor_id] as Sm2CompanionProgress).describe(progress),"knowledge":[],"tracks":Sm2ProgressRules.tracks(bodies[actor_id],progress,track_modifiers(actor_id)),"nodes":[],"attacks":counts[actor_id].duplicate(true),"melee_bonus":stat_bonus(actor_id,"melee_skill")}
	var knowledge: Array[String] = []
	if actor_id == catalog.hero():
		for id: String in soul.knowledge: knowledge.append(progress.knowledge_name(id))
	var nodes: Array[Dictionary] = []
	# The large campaign edits its tree in camp. A combat HUD query must not
	# materialize thousands of disabled purchase cards on every action.
	var node_ids: Array[String]=[]
	if not progress.is_large(): node_ids=progress.node_ids()
	for id: String in node_ids:
		var node: Sm2ProgressNodeDefinition = progress.node(id)
		var command: Sm2Command = Sm2Command.new()
		command.kind = "buy_node"; command.actor_id = actor_id; command.target_actor_id = actor_id; command.ability_id = id
		var reason: String = purchase_error(state,command)
		nodes.append({"id":id,"name":node.title,"cost":node.cost,"track_name":progress.track(node.track_id).title,"bonus":node.bonus,"min_level":node.min_level,"owned":id in bodies[actor_id].tracks[node.track_id].nodes,"allowed":reason.is_empty(),"reason":reason})
	var result: Dictionary={"world_id":world_id,"body_id":bodies[actor_id].id,"role":"hero" if actor_id == catalog.hero() else "companion","pending_practice":pending_view(actor_id),"growth_deferred":deferred_growth and not state.finished,"knowledge":knowledge,"tracks":Sm2ProgressRules.tracks(bodies[actor_id],progress,track_modifiers(actor_id)),"nodes":nodes,"attacks":counts[actor_id].duplicate(true),"melee_bonus":stat_bonus(actor_id,"melee_skill")}

	if progress.is_large(): result["nodes_in_camp"] = true
	return result

static func decode(raw: Dictionary, state: Sm2TacticalState, definitions: Sm2DevelopmentCatalog, cache: Sm2ProgressDecodeCache=null) -> Dictionary:
	var invalid: Dictionary = {"ok":false,"errors":PackedStringArray(["development_snapshot_invalid"])}
	if definitions.progression().is_party(): return invalid
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
		var decoded: Dictionary = Sm2ProgressRules.decode_body(member.body,value.progress,cache)
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
