class_name Sm2EncounterOrigin
extends RefCounted
const HYBRID_RULESET: String="sm2.p5.hybrid_encounter.1"
const IMPLANT_RULESET: String="sm2.p5.implant_encounter.1"
const UPGRADE_RULESET: String="sm2.p5.upgrade_encounter.1"
const PSIONIC_SHIELD_RULESET: String="sm2.p5.psionic_shield_encounter.1"
const PSIONIC_GROWTH_RULESET: String="sm2.p5.psionic_growth_encounter.1"
const PSIONIC_RULESET: String="sm2.p5.psionic_encounter.1"
## Immutable-by-copy input owned by the encounter coordinator, never by content.
const PROSTHESIS_RULESET: String="sm2.p4.prosthesis_encounter.1"
const BODY_RULESET: String="sm2.p4.body_encounter.1"
const PARTY_RULESET: String = "sm2.p4.party_encounter.1"
const RULESET: String = "sm2.p4.encounter.1"

static func initialize(state: Sm2TacticalState, definitions: Sm2DevelopmentCatalog, combat: Sm2CombatCatalog, raw: Dictionary, resources: bool, cache: Sm2ProgressDecodeCache=null,proof: Sm2CombatGrowthProfile=null) -> String:
	if not Sm2Validate.fields(raw,["version","world_id","battle_id","incarnation_id","members","actors"]): return "origin_fields"
	if raw.version != (HYBRID_RULESET if definitions.has_hybrids() else IMPLANT_RULESET if definitions.has_implants() else UPGRADE_RULESET if definitions.has_upgrades() else PSIONIC_SHIELD_RULESET if definitions.has_psionic_shields() else PSIONIC_GROWTH_RULESET if definitions.has_psionic_growth() else PSIONIC_RULESET if definitions.has_psionics() else PROSTHESIS_RULESET if definitions.has_prostheses() else BODY_RULESET if definitions.has_body_functions() else PARTY_RULESET if definitions.progression().is_party() else RULESET) or not Sm2Validate.text(raw.world_id) or raw.battle_id != state.battle_id or not Sm2Validate.decimal(raw.incarnation_id,1,1000000): return "origin_identity"
	if not raw.members is Array or raw.members.size()!=2 or not raw.actors is Array or raw.actors.size()!=state.actors.size(): return "origin_members"
	var value: Sm2BattleDevelopment = state.development
	var used_bodies: Array[int]=[]
	if proof==null:
		for index: int in 2:
			var member: Variant=raw.members[index]
			var actor_id: int=[definitions.hero(),definitions.companion()][index]
			if not member is Dictionary or not Sm2Validate.fields(member,["actor_id","body"]) or member.actor_id!=str(actor_id) or not member.body is Dictionary: return "origin_member"
			var checked: Dictionary=Sm2ProgressRules.decode_body(member.body,value.progress,cache)
			if not checked.ok or (checked.body is Sm2CompanionProgress)!=(value.progress.is_party() and index==1) or checked.body.id in used_bodies: return "origin_body"
			used_bodies.append(checked.body.id); value.bodies[actor_id]=checked.body
	else:
		for actor_id: int in [definitions.hero(),definitions.companion()]: used_bodies.append(proof.body_id(actor_id))
	value.soul.incarnation_id=int(raw.incarnation_id)
	value.incarnation.id=int(raw.incarnation_id); value.incarnation.body_id=used_bodies[0]
	var used_items: Array[String]=[]
	var actor_bodies: Array[String]=[]
	for index: int in raw.actors.size():
		var entry: Variant=raw.actors[index]
		var actor: Sm2TacticalActor=state.actor(state.sorted_ids()[index])
		var actor_fields: Array[String]=["actor_id","body_id","hp","items"]
		if definitions.has_upgrades(): actor_fields.append("upgrades")
		if definitions.has_body_functions(): actor_fields.append("body_functions")
		if not entry is Dictionary or not Sm2Validate.fields(entry,actor_fields) or entry.actor_id!=str(actor.spatial.actor_id) or not Sm2Validate.decimal(entry.body_id,1,1000000): return "origin_actor"
		if definitions.has_upgrades():
			var upgrade: Dictionary=Sm2BodyUpgradeState.decode(entry.upgrades,definitions.upgrades())
			if not upgrade.ok or (index!=0 and not upgrade.state.installed.is_empty()): return "origin_upgrades"
			if proof==null: value.upgrades[actor.spatial.actor_id]=upgrade.state
		if definitions.has_body_functions():
			var body: Dictionary=Sm2BodyFunctionState.decode(entry.body_functions,definitions.body_functions())
			if not body.ok: return "origin_functions"
			actor.body_functions=body.state; actor.body_catalog=definitions.body_functions()
		if entry.body_id in actor_bodies: return "origin_duplicate_body"
		actor_bodies.append(entry.body_id)
		if index<2 and int(entry.body_id)!=used_bodies[index]: return "origin_binding"
		if not Sm2Validate.integer(entry.hp,0,combat.profile(actor.loadout_id).hp_max) or not entry.items is Array or entry.items.size()!=actor.combat.items.size(): return "origin_resources"
		if resources:
			if state.survival==null and actor.spatial.alive!=(int(entry.hp)>0): return "origin_life"
			actor.combat.hp=int(entry.hp)
		elif actor.combat.hp>int(entry.hp): return "encounter_unearned_healing"
		var previous_slot: int=-1
		for item_index: int in entry.items.size():
			var item_raw: Variant=entry.items[item_index]
			if not item_raw is Dictionary or not Sm2Validate.fields(item_raw,["id","definition_id","slot","current","ammo"]) or not Sm2Validate.decimal(item_raw.id,1,1000000) or item_raw.id in used_items or not item_raw.slot is String: return "origin_item"
			var item: Sm2CombatItem=actor.combat.item(item_raw.slot)
			if item==null or item.definition_id!=item_raw.definition_id: return "origin_equipment"
			var slot_index: int=Sm2CombatCatalog.SLOTS.find(item_raw.slot)
			if slot_index<=previous_slot: return "origin_slot_order"
			previous_slot=slot_index
			var gear: Sm2CombatGear=combat.gear(item.definition_id)
			if not Sm2Validate.integer(item_raw.current,0,gear.capacity) or not Sm2Validate.integer(item_raw.ammo,0,gear.ammo): return "origin_condition"
			used_items.append(item_raw.id)
			if resources: item.current=int(item_raw.current); item.ammo=int(item_raw.ammo)
			elif item.current>int(item_raw.current) or item.ammo>int(item_raw.ammo): return "encounter_unearned_repair"
	if proof==null: value.origin=raw.duplicate(true)
	return ""

static func decode(raw: Dictionary, state: Sm2TacticalState, definitions: Sm2DevelopmentCatalog, combat: Sm2CombatCatalog, origin: Dictionary, cache: Sm2ProgressDecodeCache=null) -> Dictionary:
	var failure: Dictionary={"ok":false,"errors":PackedStringArray(["encounter_development_invalid"])}
	var value: Sm2BattleDevelopment=Sm2BattleDevelopment.new()
	if not value.initialize(state,definitions).is_empty(): return failure
	state.development=value
	var origin_error: String=initialize(state,definitions,combat,origin,false,cache)
	if not origin_error.is_empty(): return {"ok":false,"errors":PackedStringArray([origin_error])}
	if raw.has("growth_timing"):
		if not raw.growth_timing is String or raw.growth_timing!=Sm2BattleDevelopment.AFTER_BATTLE: return failure
		value.deferred_growth=true
	var expected: Dictionary=value.to_data()
	var fields: Array[String]=[]; fields.assign(expected.keys())
	if not Sm2Validate.fields(raw,fields): return failure
	for key: String in ["world_id","fingerprint","soul","incarnation","source_id","next_id","origin"]:
		if Sm2Canonical.stringify(raw[key])!=Sm2Canonical.stringify(expected[key]): return {"ok":false,"errors":PackedStringArray(["encounter_metadata_"+key])}
	if not raw.members is Array or raw.members.size()!=2 or not Sm2Validate.decimal(raw.sequence,0,1000000): return failure
	var total: int=0
	for index: int in 2:
		var actor_id: int=[definitions.hero(),definitions.companion()][index]
		var member: Variant=raw.members[index]
		if not member is Dictionary or not Sm2Validate.fields(member,["actor_id","body","attacks"]) or member.actor_id!=str(actor_id) or not member.body is Dictionary or not member.attacks is Array or member.attacks.size()!=definitions.ability_ids().size(): return failure
		var decoded: Dictionary=Sm2ProgressRules.decode_body(member.body,value.progress,cache)
		if not decoded.ok or (decoded.body is Sm2CompanionProgress)!=(value.progress.is_party() and index==1) or decoded.body.id!=value.bodies[actor_id].id: return failure
		var earned: Dictionary[String,int]={}
		var simple: bool=value.bodies[actor_id] is Sm2CompanionProgress
		var general: int=(value.bodies[actor_id] as Sm2CompanionProgress).earned if simple else 0
		if not simple:
			for id: String in value.progress.track_ids(): earned[id]=value.bodies[actor_id].tracks[id].earned
		var count_sum: int=0
		for rule_index: int in member.attacks.size():
			var rule: Variant=member.attacks[rule_index]
			if not rule is Dictionary or not Sm2Validate.fields(rule,["ability_id","count"]) or rule.ability_id!=definitions.ability_ids()[rule_index] or not Sm2Validate.integer(rule.count,0,state.revision): return failure
			var count: int=int(rule.count); count_sum+=count
			if count>0 and definitions.has_psionics() and not definitions.psionics().ability(rule.ability_id).is_empty():
				if actor_id!=definitions.hero() or not definitions.psionics().available(value.bodies[actor_id],rule.ability_id): return failure
			if count>0 and definitions.has_hybrids() and not definitions.hybrids().ability(rule.ability_id).is_empty():
				if actor_id!=definitions.hero() or not definitions.hybrids().available(value.bodies[actor_id],rule.ability_id): return failure
				if not Sm2AttackResolver.available_abilities(state.actor(actor_id),combat).has(definitions.hybrids().ability(rule.ability_id).base_attack): return failure
			value.counts[actor_id][rule.ability_id]=count
			if simple: general+=count*int(value.progress.companion_growth().attack_xp)
			else:
				for id: String in definitions.awards(rule.ability_id): earned[id]+=count*int(definitions.awards(rule.ability_id)[id])
		if count_sum>state.revision or (int(origin.actors[index].hp)==0 and count_sum!=0): return failure
		total+=count_sum
		var waiting: bool=value.deferred_growth and not state.finished
		var accumulated: Dictionary={}
		if simple:
			var baseline: int=(value.bodies[actor_id] as Sm2CompanionProgress).earned
			if general>Sm2ProgressCatalog.XP_LIMIT or (decoded.body as Sm2CompanionProgress).earned!=(baseline if waiting else general): return failure
			if waiting and general>baseline: accumulated["general"]=general-baseline
		for id: String in earned:
			var track: Sm2ProgressTrackState=decoded.body.tracks[id]
			var baseline: Sm2ProgressTrackState=value.bodies[actor_id].tracks[id]
			if earned[id]>Sm2ProgressCatalog.XP_LIMIT or track.earned!=(baseline.earned if waiting else earned[id]) or track.spent!=baseline.spent or track.nodes!=baseline.nodes: return failure
			if waiting and earned[id]>baseline.earned: accumulated[id]=earned[id]-baseline.earned
		if not accumulated.is_empty(): value.pending[actor_id]=accumulated
		value.bodies[actor_id]=decoded.body
	if total!=int(raw.sequence): return failure
	value.sequence=total
	return {"ok":true,"development":value,"errors":PackedStringArray()}

static func schema(definitions: Sm2DevelopmentCatalog, origin: Dictionary) -> int:
	return 8 if origin.is_empty() else 18 if definitions.has_hybrids() else 17 if definitions.has_implants() else 16 if definitions.has_upgrades() else 15 if definitions.has_psionic_shields() else 14 if definitions.has_psionic_growth() else 13 if definitions.has_psionics() else 12 if definitions.has_prostheses() else 11 if definitions.has_body_functions() else 10 if definitions.progression().is_party() else 9

## Internal live candidate only. Public/file decode never supplies this proof.
static func decode_compact(raw: Dictionary,state: Sm2TacticalState,definitions: Sm2DevelopmentCatalog,combat: Sm2CombatCatalog,origin: Dictionary,proof: Sm2CombatGrowthProfile) -> Dictionary:
	var fail: Dictionary={"ok":false,"errors":PackedStringArray(["compact_development_invalid"])}
	if proof==null or proof._base.catalog!=definitions or state.finished or not Sm2Validate.fields(raw,["format","profile","sequence","members"]): return fail
	if not raw.format is String or not raw.profile is String or raw.format!=Sm2CombatGrowthProfile.LIVE_FORMAT or raw.profile!=proof._key or not Sm2Validate.decimal(raw.sequence,0,1000000): return fail
	if not raw.members is Array or raw.members.size()!=2: return fail
	var dev: Sm2BattleDevelopment=proof.instance(); state.development=dev
	var problem: String=initialize(state,definitions,combat,origin,false,null,proof)
	if not problem.is_empty(): return {"ok":false,"errors":PackedStringArray([problem])}
	var ids: Array[String]=definitions.ability_ids()
	var total: int=0
	for index: int in 2:
		var actor: int=[definitions.hero(),definitions.companion()][index]
		var member: Variant=raw.members[index]
		if not member is Dictionary or not Sm2Validate.fields(member,["actor_id","attacks"]) or not member.actor_id is String or member.actor_id!=str(actor) or not member.attacks is Array or member.attacks.size()!=ids.size(): return fail
		var count_sum: int=0; var pending: Dictionary={}
		for i: int in ids.size():
			var row: Variant=member.attacks[i]; var id: String=ids[i]
			if not row is Dictionary or not Sm2Validate.fields(row,["ability_id","count"]) or not row.ability_id is String or row.ability_id!=id or not Sm2Validate.integer(row.count,0,state.revision): return fail
			var count: int=int(row.count); count_sum+=count; dev.counts[actor][id]=count
			if count==0: continue
			if definitions.has_psionics() and not definitions.psionics().ability(id).is_empty():
				if actor!=definitions.hero() or not proof.available(actor,id): return fail
			if definitions.has_hybrids() and not definitions.hybrids().ability(id).is_empty():
				if actor!=definitions.hero() or not proof.available(actor,id) or not Sm2AttackResolver.available_abilities(state.actor(actor),combat).has(definitions.hybrids().ability(id).base_attack): return fail
			var awards: Dictionary={"general":int(dev.progress.companion_growth().attack_xp)} if proof.simple(actor) else definitions.awards(id)
			for track: String in awards: pending[track]=int(pending.get(track,0))+count*int(awards[track])
		if count_sum>state.revision or (int(origin.actors[index].hp)==0 and count_sum!=0): return fail
		for track: String in pending:
			if proof.earned(actor,track)>Sm2ProgressCatalog.XP_LIMIT-int(pending[track]): return fail
		# Match full decoder's canonical track order, including closing event order.
		var ordered: Dictionary={}
		if proof.simple(actor): ordered=pending
		else:
			for track: String in dev.progress.track_ids():
				if pending.has(track): ordered[track]=pending[track]
		if not ordered.is_empty(): dev.pending[actor]=ordered
		total+=count_sum
	if total!=int(raw.sequence): return fail
	dev.sequence=total
	return {"ok":true,"development":dev,"errors":PackedStringArray()}
