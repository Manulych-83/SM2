class_name Sm2SurvivalBattle
extends RefCounted
const RULESET: String="sm2.survival_encounter.1"

static func body_id(state: Sm2TacticalState,actor_id: int) -> String:
	for row: Dictionary in state.development.origin_actors():
		if int(row.actor_id)==actor_id: return str(row.body_id)
	return ""

static func sync_actor(state: Sm2TacticalState,actor: Sm2TacticalActor) -> void:
	var body: Sm2Anatomy=state.survival.bodies[body_id(state,actor.spatial.actor_id)]
	actor.anatomy=body.copy()
	actor.combat.hp=body.summary(state.survival.catalog.to_data())
	for part: String in actor.body_functions.working: actor.body_functions.working[part]=body.working(part)
	if state.survival.catalog.has_devices(): Sm2SurvivalDevices.project_functions(state.survival,body_id(state,actor.spatial.actor_id),actor.body_functions)
	if not actor.body_functions.working.get("left_hand",true): actor.combat.clear_wall()

static func damage(state: Sm2TacticalState,target: Sm2TacticalActor,source: int,amount: int,part: String,cut: bool,events: Array[Dictionary],sever: bool=false) -> void:
	var body: Sm2Anatomy=state.survival.bodies[body_id(state,target.spatial.actor_id)]
	var location: String=part if not part.is_empty() else "torso"
	if state.survival.catalog.has_devices() and amount>0:
		var body_ref: String=body_id(state,target.spatial.actor_id)
		var device: String=Sm2SurvivalDevices.installed(state.survival,body_ref,location)
		if not device.is_empty():
			var item: Dictionary=state.survival.inventory.items[device]
			var loss: int=mini(amount,int(item.current)); item.current-=loss
			sync_actor(state,target)
			events.append({"type":"survival_device_damaged","target_actor_id":str(target.spatial.actor_id),"item_id":device,"name":state.survival.catalog.part_name(location),"loss":loss,"remaining":item.current})
			return
		if state.survival.missing[body_ref].has(location): return
		if sever:
			if not state.survival.catalog.devices().interfaces.has(location): state.survival_error="survival_sever_target"; return
			state.survival.missing[body_ref].append(location); state.survival.missing[body_ref].sort()
			amount=int(body.tissues[location]); cut=true
			events.append({"type":"survival_part_lost","target_actor_id":str(target.spatial.actor_id),"name":state.survival.catalog.part_name(location)})
	var available: int=int(body.tissues.get(location,0))
	var reason: String=body.injure(location,amount,cut,state.survival.catalog.to_data())
	if not reason.is_empty(): state.survival_error=reason; return
	if amount>available and location in ["head","torso"]:
		reason=body.injure("brain" if location=="head" else "heart",amount-available,cut,state.survival.catalog.to_data())
		if not reason.is_empty(): state.survival_error=reason; return
	sync_actor(state,target)
	events.append({"type":"anatomy_injured","target_actor_id":str(target.spatial.actor_id),"part":location,"damage":amount,"blood":body.blood,"bleeding":body.rate()})
	if not body.cause(state.survival.catalog.to_data()).is_empty(): Sm2HpApplication.kill(state,target,source,events)

static func close_round(state: Sm2TacticalState,events: Array[Dictionary]) -> void:
	if state.survival==null or state.round==0 or state.survival.last_round>=state.round: return
	var duration: int=int(state.survival.catalog.to_data().round_seconds)
	if state.survival.seconds>1000000000-duration: state.survival_error="survival_time_limit"; return
	# A combat interval always advances all projected bodies for the same duration.
	for id: String in state.survival.bodies: state.survival.bodies[id].advance(duration,state.survival.catalog.to_data())
	state.survival.seconds+=duration; state.survival.last_round=state.round
	for id: int in state.sorted_ids():
		var actor: Sm2TacticalActor=state.actor(id)
		var was_alive: bool=actor.spatial.alive
		sync_actor(state,actor)
		if not actor.anatomy.cause(state.survival.catalog.to_data()).is_empty(): Sm2HpApplication.kill(state,actor,0,events)
		if was_alive and not actor.spatial.alive and state.survival_context!=null:
			if not Sm2MoraleResolver.after_hit(state,state.survival_combat,actor,0,state.survival_context,events): state.survival_error="rng_counter_limit"
	events.append({"type":"physiology_advanced","seconds":duration,"world_seconds":state.survival.seconds})

static func bandage_preview(state: Sm2TacticalState,command: Sm2Command) -> Dictionary:
	var fail: Dictionary={"allowed":false,"reason":"Перевязка недоступна.","ap_cost":0,"fatigue_cost":0}
	if state.survival==null: return fail
	var actor: Sm2TacticalActor=state.actor(command.actor_id)
	var target: Sm2TacticalActor=state.actor(command.target_actor_id)
	if actor==null or target==null or not target.spatial.occupies() or actor.spatial.side!=target.spatial.side or actor.morale=="fleeing" or Sm2Hex.distance(actor.spatial.position,target.spatial.position)>1: return fail
	var body: String=body_id(state,command.actor_id)
	var target_body: Sm2Anatomy=state.survival.bodies[body_id(state,command.target_actor_id)]
	var wound: Dictionary=target_body.wound(command.ability_id)
	if wound.is_empty() or int(wound.rate)==0: fail.reason="Выберите кровоточащую рану."; return fail
	if not state.survival.has_hand(body): fail.reason="Нет действующей руки для перевязки."; return fail
	var item: String=state.survival.inventory.bandage_for(int(body),state.survival.catalog)
	if item.is_empty(): fail.reason="Нет перевязочного материала в быстром доступе."; return fail
	var cost: int=int(state.survival.catalog.to_data().bandage_ap)
	if actor.spatial.ap<cost: fail.reason="Недостаточно очков действия."; return fail
	return {"allowed":true,"reason":"","ap_cost":cost,"fatigue_cost":0,"item":item}

static func bandage(state: Sm2TacticalState,command: Sm2Command) -> Dictionary:
	var check: Dictionary=bandage_preview(state,command)
	if not check.allowed: return {"accepted":false,"code":check.reason,"events":[]}
	state.actor(command.actor_id).spatial.ap-=int(check.ap_cost)
	state.survival.inventory.items.erase(check.item)
	state.survival.bodies[body_id(state,command.target_actor_id)].bandage(command.ability_id)
	sync_actor(state,state.actor(command.target_actor_id))
	return {"accepted":true,"code":"accepted","events":[{"type":"wound_bandaged","actor_id":str(command.actor_id),"target_actor_id":str(command.target_actor_id),"wound_id":command.ability_id,"item_id":check.item}]}

static func decode(data: Dictionary,turns: Sm2TurnCatalog,combat: Sm2CombatCatalog,effects: Sm2EffectCatalog,magic: Sm2MagicCatalog,development: Sm2DevelopmentCatalog,origin: Dictionary,initial: Sm2SurvivalState, cache: Sm2ProgressDecodeCache=null,proof: Sm2CombatGrowthProfile=null) -> Dictionary:
	var fail: Dictionary={"ok":false,"errors":PackedStringArray(["survival_battle_snapshot"])}
	if data.get("schema_version")!=initial.catalog.battle_schema() or data.get("ruleset")!=initial.catalog.battle_ruleset() or data.get("survival_initial")!=Sm2Canonical.hash(initial.to_data()): return fail
	var decoded: Dictionary=Sm2SurvivalState.decode(data.get("survival"),initial)
	if not decoded.ok: return decoded
	var base: Dictionary=data.duplicate(true); base.erase("survival"); base.erase("survival_initial")
	base.schema_version=Sm2EncounterOrigin.schema(development,origin); base.ruleset=origin.version
	var result: Dictionary=Sm2DevelopmentSnapshot.decode(base,turns,combat,effects,magic,development,origin,true,cache,proof)
	if not result.ok: return result
	var state: Sm2TacticalState=result.state
	state.survival=decoded.state; state.survival_initial=Sm2Canonical.hash(initial.to_data())
	var expected_round: int=state.round if state.finished else state.round-1
	if state.survival.last_round!=expected_round or state.survival.seconds!=initial.seconds+expected_round*int(initial.catalog.to_data().round_seconds): return fail
	for id: int in state.sorted_ids():
		var actor: Sm2TacticalActor=state.actor(id)
		var body: Sm2Anatomy=state.survival.bodies[body_id(state,id)]
		if actor.combat.hp!=body.summary(initial.catalog.to_data()) or actor.spatial.alive!=body.cause(initial.catalog.to_data()).is_empty(): return fail
		var raw: Dictionary=data.actors[state.sorted_ids().find(id)]
		sync_actor(state,actor)
		if Sm2Canonical.hash(actor.body_functions.to_data())!=Sm2Canonical.hash(raw.body_functions): return fail
	var participants: Array[String]=[]
	for row: Dictionary in origin.actors: participants.append(str(row.body_id))
	if initial.catalog.has_devices():
		for id: String in initial.bodies:
			for part: String in initial.missing[id]:
				if not state.survival.missing[id].has(part): return fail
			if id not in participants and Sm2Canonical.hash(initial.missing[id])!=Sm2Canonical.hash(state.survival.missing[id]): return fail
	var treated: int=0
	for id: String in initial.bodies:
		var old: Sm2Anatomy=initial.bodies[id]
		var current: Sm2Anatomy=state.survival.bodies[id]
		if current.blood>old.blood or current.wounds.size()<old.wounds.size(): return fail
		if current.death=="prepared_carrier" and old.death!="prepared_carrier": return fail
		for index: int in old.wounds.size():
			var before: Dictionary=old.wounds[index]; var after: Dictionary=current.wounds[index]
			if initial.catalog.has_layers():
				if before.cut!=after.cut or Sm2Canonical.hash(before.layer_losses)!=Sm2Canonical.hash(after.layer_losses): return fail
			for key: String in ["id","part","loss","initial_rate"]:
				if before[key]!=after[key]: return fail
			if int(after.rate)>int(before.rate): return fail
		for wound: Dictionary in current.wounds:
			var previous: Dictionary=old.wound(wound.id)
			if int(wound.initial_rate)>0 and int(wound.rate)==0 and (previous.is_empty() or int(previous.rate)>0): treated+=1
	# No item creation or movement inside combat; only physical bandages can disappear.
	var consumed: int=0
	for id: String in initial.inventory.items:
		if not state.survival.inventory.items.has(id):
			if initial.inventory.items[id].definition_id!="bandage": return fail
			var owner: int=initial.inventory.owner(id)
			var item: Dictionary=initial.inventory.items[id]
			if owner==0 or item.place!="container" or not bool(initial.catalog.item(initial.inventory.items[item.holder].definition_id).quick): return fail
			var present: bool=false
			for row: Dictionary in origin.actors:
				if int(row.body_id)==owner: present=true
			if not present: return fail
			consumed+=1
		elif initial.catalog.has_devices():
			if not Sm2SurvivalDevices.battle_item_valid(initial.inventory.items[id],state.survival.inventory.items[id],initial.catalog,participants): return fail
		elif Sm2Canonical.hash(state.survival.inventory.items[id])!=Sm2Canonical.hash(initial.inventory.items[id]): return fail
	for id: String in state.survival.inventory.items:
		if not initial.inventory.items.has(id): return fail
	if consumed!=treated: return fail
	return result

static func lethal_damage(target: Sm2TacticalActor,amount: int,rules: Dictionary) -> bool:
	var forecast: Sm2Anatomy=target.anatomy.copy()
	var available: int=int(forecast.tissues.torso)
	forecast.injure("torso",amount,false,rules)
	if amount>available: forecast.injure("heart",amount-available,false,rules)
	return not forecast.cause(rules).is_empty()
