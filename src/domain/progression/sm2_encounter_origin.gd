class_name Sm2EncounterOrigin
extends RefCounted
## Immutable-by-copy input owned by the encounter coordinator, never by content.
const RULESET: String = "sm2.p4.encounter.1"

static func initialize(state: Sm2TacticalState, definitions: Sm2DevelopmentCatalog, combat: Sm2CombatCatalog, raw: Dictionary, resources: bool) -> String:
	if not Sm2Validate.fields(raw,["version","world_id","battle_id","incarnation_id","members","actors"]): return "origin_fields"
	if raw.version != RULESET or not Sm2Validate.text(raw.world_id) or raw.battle_id != state.battle_id or not Sm2Validate.decimal(raw.incarnation_id,1,1000000): return "origin_identity"
	if not raw.members is Array or raw.members.size()!=2 or not raw.actors is Array or raw.actors.size()!=state.actors.size(): return "origin_members"
	var value: Sm2BattleDevelopment = state.development
	var used_bodies: Array[int]=[]
	for index: int in 2:
		var member: Variant=raw.members[index]
		var actor_id: int=[definitions.hero(),definitions.companion()][index]
		if not member is Dictionary or not Sm2Validate.fields(member,["actor_id","body"]) or member.actor_id!=str(actor_id) or not member.body is Dictionary: return "origin_member"
		var checked: Dictionary=Sm2ProgressRules.decode_body(member.body,value.progress)
		if not checked.ok or checked.body.id in used_bodies: return "origin_body"
		used_bodies.append(checked.body.id); value.bodies[actor_id]=checked.body
	value.soul.incarnation_id=int(raw.incarnation_id)
	value.incarnation.id=int(raw.incarnation_id); value.incarnation.body_id=used_bodies[0]
	var used_items: Array[String]=[]
	var actor_bodies: Array[String]=[]
	for index: int in raw.actors.size():
		var entry: Variant=raw.actors[index]
		var actor: Sm2TacticalActor=state.actor(state.sorted_ids()[index])
		if not entry is Dictionary or not Sm2Validate.fields(entry,["actor_id","body_id","hp","items"]) or entry.actor_id!=str(actor.spatial.actor_id) or not Sm2Validate.decimal(entry.body_id,1,1000000): return "origin_actor"
		if entry.body_id in actor_bodies: return "origin_duplicate_body"
		actor_bodies.append(entry.body_id)
		if index<2 and int(entry.body_id)!=used_bodies[index]: return "origin_binding"
		if not Sm2Validate.integer(entry.hp,0,combat.profile(actor.loadout_id).hp_max) or not entry.items is Array or entry.items.size()!=actor.combat.items.size(): return "origin_resources"
		if resources:
			if actor.spatial.alive!=(int(entry.hp)>0): return "origin_life"
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
	value.origin=raw.duplicate(true)
	return ""

static func decode(raw: Dictionary, state: Sm2TacticalState, definitions: Sm2DevelopmentCatalog, combat: Sm2CombatCatalog, origin: Dictionary) -> Dictionary:
	var failure: Dictionary={"ok":false,"errors":PackedStringArray(["encounter_development_invalid"])}
	var value: Sm2BattleDevelopment=Sm2BattleDevelopment.new()
	if not value.initialize(state,definitions).is_empty(): return failure
	state.development=value
	var origin_error: String=initialize(state,definitions,combat,origin,false)
	if not origin_error.is_empty(): return {"ok":false,"errors":PackedStringArray([origin_error])}
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
		var decoded: Dictionary=Sm2ProgressRules.decode_body(member.body,value.progress)
		if not decoded.ok or decoded.body.id!=value.bodies[actor_id].id: return failure
		var earned: Dictionary[String,int]={}
		for id: String in value.progress.track_ids(): earned[id]=value.bodies[actor_id].tracks[id].earned
		var count_sum: int=0
		for rule_index: int in member.attacks.size():
			var rule: Variant=member.attacks[rule_index]
			if not rule is Dictionary or not Sm2Validate.fields(rule,["ability_id","count"]) or rule.ability_id!=definitions.ability_ids()[rule_index] or not Sm2Validate.integer(rule.count,0,state.revision): return failure
			var count: int=int(rule.count); count_sum+=count
			value.counts[actor_id][rule.ability_id]=count
			for id: String in definitions.awards(rule.ability_id): earned[id]+=count*int(definitions.awards(rule.ability_id)[id])
		if count_sum>state.revision or (int(origin.actors[index].hp)==0 and count_sum!=0): return failure
		total+=count_sum
		for id: String in earned:
			var track: Sm2ProgressTrackState=decoded.body.tracks[id]
			var baseline: Sm2ProgressTrackState=value.bodies[actor_id].tracks[id]
			if track.earned!=earned[id] or track.spent!=baseline.spent or track.nodes!=baseline.nodes: return failure
		value.bodies[actor_id]=decoded.body
	if total!=int(raw.sequence): return failure
	value.sequence=total
	return {"ok":true,"development":value,"errors":PackedStringArray()}
