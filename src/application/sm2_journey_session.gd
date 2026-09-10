class_name Sm2JourneySession
extends Sm2LifeSession
const JOURNEY_SLOT: String="p4_journey"
const JOURNEY_FORMAT: String="sm2.journey_session.1"
const HISTORY_LIMIT: int=4096
var history: Array[Dictionary]=[]
var _encounter: Dictionary={}

func _init(content: Dictionary, profile: Sm2AiProfile, store: Sm2SaveStore=null) -> void:
	super(content,profile,store)
	_content["meetings"]=content.meetings.duplicate(true)
	_content["journey_fingerprint"]=content.journey_fingerprint
	_content["initial_loadout"]=content.initial_loadout
	world=Sm2JourneyWorld.new(_content.development.progression(),_content.world_definition,_content.combat,_content.meetings,_content.initial_loadout)
	runner=null

func journey() -> Sm2JourneyWorld: return world as Sm2JourneyWorld

func new_game() -> Dictionary:
	var bytes: PackedByteArray=Crypto.new().generate_random_bytes(16)
	if bytes.size()!=16: return _error("world_identity_failed")
	var candidate: Sm2JourneySession=Sm2JourneySession.new(_content,_profile,_store)
	candidate.world.start("p4:"+bytes.hex_encode())
	return _publish(candidate)

func capture() -> Dictionary:
	return {"format":JOURNEY_FORMAT,"fingerprint":_content.journey_fingerprint,"world":world.capture(),"history":history.duplicate(true),"active":runner.capture() if world.busy() else {}}

func act(value: Sm2WorldCommand) -> Dictionary:
	var reason: String=world.check(value)
	if not reason.is_empty(): return _error(reason)
	if history.size()>=HISTORY_LIMIT: return _error("journey_history_limit")
	if value.kind=="start_battle" and history.size()>=HISTORY_LIMIT-1: return _error("journey_history_limit")
	var candidate: Sm2JourneySession=_copy() as Sm2JourneySession
	if candidate==null: return _error("world_copy_failed")
	var applied: Dictionary=candidate._camp(_command_data(value))
	return _publish(candidate) if applied.ok else applied

func _camp(raw: Dictionary, restoring: bool=false) -> Dictionary:
	if not Sm2Validate.fields(raw,["kind","world_id","revision","incarnation_id","body_id","target_id","content_id"]): return _error("camp_command_fields")
	if not raw.kind is String or not raw.world_id is String or not raw.content_id is String: return _error("camp_command_types")
	for key: String in ["revision","incarnation_id","body_id","target_id"]:
		if not Sm2Validate.integer(raw[key],0,1000000): return _error("camp_command_number")
	var value: Sm2WorldCommand=command(raw.kind,int(raw.target_id),raw.content_id)
	value.world_id=raw.world_id; value.expected_revision=int(raw.revision); value.incarnation_id=int(raw.incarnation_id); value.body_id=int(raw.body_id)
	var reason: String=world.check(value)
	if not reason.is_empty(): return _error(reason)
	world.apply(value)
	if value.kind=="start_battle":
		var created: Dictionary=_prepare()
		if not created.ok: return created
		if not restoring:
			var started: Dictionary=runner.new_battle(_encounter.setup)
			if not started.ok: return started
	history.append({"kind":"camp","command":raw.duplicate(true)})
	return {"ok":true}

func _prepare() -> Dictionary:
	_encounter=Sm2EncounterFactory.build(_content,journey())
	if not _encounter.ok: return _encounter
	runner=Sm2BattleRunner.new(_encounter.catalog,_encounter.combat,_profile,null,false,null,null,_encounter.development,_encounter.origin)
	return {"ok":true}

func attack(value: Sm2Command) -> Sm2CommandResult:
	var denied: Sm2CommandResult=Sm2CommandResult.new()
	denied.revision=int(runner.view().revision) if runner!=null else 0
	if not world.busy() or value==null or value.kind=="buy_node": denied.code="world_battle_locked"; return denied
	if world.revision>=1000000 or history.size()>=HISTORY_LIMIT: denied.code="world_limit"; return denied
	var candidate: Sm2JourneySession=_copy() as Sm2JourneySession
	if candidate==null: denied.code="world_copy_failed"; return denied
	var result: Sm2CommandResult=candidate.runner.execute_player(value)
	if not result.accepted: return result
	candidate.world.revision+=1
	var finished: Dictionary=candidate._finish()
	var published: Dictionary=_publish(candidate) if finished.ok else finished
	if not published.ok: denied.code=str(published.errors[0]); return denied
	return result

func step() -> Dictionary:
	if not world.busy(): return {"ok":true,"status":"finished"}
	if world.revision>=1000000 or history.size()>=HISTORY_LIMIT: return {"ok":false,"reason":"world_limit"}
	var candidate: Sm2JourneySession=_copy() as Sm2JourneySession
	if candidate==null: return {"ok":false,"reason":"world_copy_failed"}
	var result: Dictionary=candidate.runner.step()
	if not result.ok or not result.has("command"): return result
	candidate.world.revision+=1
	var finished: Dictionary=candidate._finish()
	var published: Dictionary=_publish(candidate) if finished.ok else finished
	return result if published.ok else {"ok":false,"reason":str(published.errors[0])}

func _finish() -> Dictionary:
	if not runner.view().finished: return {"ok":true}
	runner.record_outcome()
	var checked: Dictionary=_check_battle(runner.capture())
	if not checked.ok: return checked
	var reason: String=journey().settle(checked.state,Sm2Canonical.hash(runner.capture()))
	if not reason.is_empty(): return _error(reason)
	history.append({"kind":"outcome","battle":runner.capture()})
	return {"ok":true}

func _check_battle(raw: Dictionary) -> Dictionary:
	var loaded: Dictionary=runner.restore(raw)
	if not loaded.ok: return loaded
	var decoded: Dictionary=Sm2DevelopmentSnapshot.decode(runner.capture().session.battle,_encounter.catalog,_encounter.combat,null,null,_encounter.development,_encounter.origin)
	if not decoded.ok: return decoded
	var state: Sm2TacticalState=decoded.state
	if state.scenario_id!=_encounter.setup.scenario_id or state.field.to_data()!=_encounter.setup.field or state.round_limit!=int(_encounter.setup.round_limit) or state.actors.size()!=4: return _error("encounter_definition")
	for entry: Dictionary in _encounter.setup.actors:
		var actor: Sm2TacticalActor=state.actor(int(entry.actor_id))
		if actor==null or actor.loadout_id!=entry.loadout_id or actor.spatial.side!=entry.side or actor.spatial.controller!=entry.controller or actor.spatial.owner!=entry.owner: return _error("encounter_binding")
	if state.finished and not raw.session.result_recorded: return _error("encounter_receipt_missing")
	return decoded

func restore(raw: Dictionary) -> Dictionary:
	if not Sm2Validate.fields(raw,["format","fingerprint","world","history","active"]) or raw.format!=JOURNEY_FORMAT or raw.fingerprint!=_content.journey_fingerprint or not raw.world is Dictionary or not raw.history is Array or raw.history.size()>HISTORY_LIMIT or not raw.active is Dictionary: return _error("journey_save_version")
	if not Sm2Validate.text(raw.world.get("world_id")) or str(raw.world.world_id).length()>100: return _error("journey_world_id")
	var candidate: Sm2JourneySession=Sm2JourneySession.new(_content,_profile,_store)
	candidate.world.start(raw.world.world_id)
	for entry: Variant in raw.history:
		if not entry is Dictionary: return _error("journey_history_entry")
		if entry.get("kind")=="camp":
			if not Sm2Validate.fields(entry,["kind","command"]) or not entry.command is Dictionary: return _error("journey_camp_entry")
			var applied: Dictionary=candidate._camp(entry.command,true)
			if not applied.ok: return applied
		elif entry.get("kind")=="outcome":
			if not Sm2Validate.fields(entry,["kind","battle"]) or not entry.battle is Dictionary or not candidate.world.busy(): return _error("journey_outcome_entry")
			var checked: Dictionary=candidate._check_battle(entry.battle)
			if not checked.ok: return checked
			if not checked.state.finished: return _error("journey_outcome_unfinished")
			candidate.world.revision+=checked.state.revision
			var reason: String=candidate.journey().settle(checked.state,Sm2Canonical.hash(candidate.runner.capture()))
			if not reason.is_empty(): return _error(reason)
			candidate.history.append(entry.duplicate(true))
		else: return _error("journey_history_kind")
	if candidate.world.busy():
		var checked: Dictionary=candidate._check_battle(raw.active)
		if not checked.ok: return checked
		if checked.state.finished: return _error("journey_unsettled_outcome")
		candidate.world.revision+=checked.state.revision
	elif not raw.active.is_empty(): return _error("journey_unexpected_battle")
	if Sm2Canonical.stringify(candidate.world.capture())!=Sm2Canonical.stringify(raw.world): return _error("journey_world_history_mismatch")
	world=candidate.world; runner=candidate.runner; history=candidate.history; _encounter=candidate._encounter
	return {"ok":true,"errors":PackedStringArray()}

func _copy() -> Sm2LifeSession:
	var candidate: Sm2JourneySession=Sm2JourneySession.new(_content,_profile,_store)
	candidate.world=journey().copy_world()
	# Closed history entries are append-only and never mutated by a command.
	candidate.history.assign(history)
	candidate._encounter=_encounter
	if runner!=null:
		candidate.runner=Sm2BattleRunner.new(_encounter.catalog,_encounter.combat,_profile,null,false,null,null,_encounter.development,_encounter.origin)
		if not candidate.runner.restore(runner.capture()).ok: return null
	return candidate

func _publish(value: Sm2LifeSession) -> Dictionary:
	var candidate: Sm2JourneySession=value as Sm2JourneySession
	if candidate==null: return _error("journey_candidate_type")
	var reason: String=candidate.journey().validate()
	if not reason.is_empty(): return _error(reason)
	if candidate.world.busy():
		if candidate.runner==null or Sm2Canonical.hash(candidate.journey().origin())!=Sm2Canonical.hash(candidate._encounter.origin): return _error("journey_candidate_binding")
		var checked: Dictionary=candidate._check_battle(candidate.runner.capture())
		if not checked.ok: return checked
	world=candidate.world; runner=candidate.runner; history=candidate.history; _encounter=candidate._encounter
	return {"ok":true,"errors":PackedStringArray()}

func save_game() -> Dictionary:
	if _store==null: return _error("no_store")
	var checked: Sm2JourneySession=Sm2JourneySession.new(_content,_profile,_store)
	if not checked.restore(capture()).ok: return _error("world_save_invalid")
	return _store.save_slot(capture(),JOURNEY_SLOT)

func load_game() -> Dictionary:
	if _store==null: return _error("no_store")
	var loaded: Dictionary=_store.load_slot(JOURNEY_SLOT)
	return restore(loaded.payload) if loaded.ok else loaded

static func _command_data(value: Sm2WorldCommand) -> Dictionary:
	return {"kind":value.kind,"world_id":value.world_id,"revision":value.expected_revision,"incarnation_id":value.incarnation_id,"body_id":value.body_id,"target_id":value.target_id,"content_id":value.content_id}
