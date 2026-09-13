class_name Sm2JourneySession
extends Sm2LifeSession
const REGION_SLOT: String="p6_region_journey"
const REGION_FORMAT: String="sm2.region_journey_session.1"
const HYBRID_SLOT: String="p5_hybrid_journey"
const HYBRID_FORMAT: String="sm2.hybrid_journey_session.1"
const IMPLANT_SLOT: String="p5_implant_journey"
const IMPLANT_FORMAT: String="sm2.implant_journey_session.1"
const UPGRADE_SLOT: String="p5_upgrade_journey"
const UPGRADE_FORMAT: String="sm2.upgrade_journey_session.1"
const PSIONIC_SHIELD_SLOT: String="p5_psionic_shield_journey"
const PSIONIC_SHIELD_FORMAT: String="sm2.psionic_shield_journey_session.1"
const PSIONIC_GROWTH_SLOT: String="p5_psionic_growth_journey"
const PSIONIC_GROWTH_FORMAT: String="sm2.psionic_growth_journey_session.1"
const PSIONIC_SLOT: String="p5_psionic_journey"
const PSIONIC_FORMAT: String="sm2.psionic_journey_session.1"
const JOURNEY_SLOT: String="p4_journey"
const DISCOVERY_SLOT: String="p4_discovery_journey"
const DISCOVERY_FORMAT: String="sm2.discovery_journey_session.1"
const SEARCH_SLOT: String="p4_search_journey"
const SEARCH_FORMAT: String="sm2.search_journey_session.1"
const EXPLORATION_SLOT: String="p4_exploration_journey"
const EXPLORATION_FORMAT: String="sm2.exploration_journey_session.1"
const CARE_SLOT: String="p4_care_journey"
const CARE_FORMAT: String="sm2.care_journey_session.1"
const JOURNEY_FORMAT: String="sm2.journey_session.1"
const PROSTHESIS_SLOT: String="p4_prosthesis_journey"
const PROSTHESIS_FORMAT: String="sm2.prosthesis_journey_session.1"
const BODY_SLOT: String="p4_body_journey"
const BODY_FORMAT: String="sm2.body_journey_session.1"
const PARTY_SLOT: String="p4_party_journey"
const PARTY_FORMAT: String="sm2.party_journey_session.1"
const HISTORY_LIMIT: int=4096
var history: Array[Dictionary]=[]
var _encounter: Dictionary={}

## Optional materialized read models; legacy profiles still derive these from replay.
func checkpoint_projection(_kind: String) -> Variant: return null

func _init(content: Dictionary, profile: Sm2AiProfile, store: Sm2SaveStore=null, shared_content: bool=false) -> void:
	super(content,profile,store,shared_content)
	_content["meetings"]=content.meetings if shared_content else content.meetings.duplicate(true)
	_content["journey_fingerprint"]=content.journey_fingerprint
	_content["initial_loadout"]=content.initial_loadout
	if content.has("care") and not shared_content:
		var care: Sm2CareCatalog=Sm2CareCatalog.new(); care.build(content.care.to_data()); _content["care"]=care
	if content.has("exploration") and not shared_content:
		var exploration: Sm2ExplorationCatalog=Sm2ExplorationCatalog.new(); exploration.build(content.exploration.to_data(),_content.care,_content.meetings.size(),_content.development.progression()); _content["exploration"]=exploration
	world=Sm2JourneyWorld.new(_content.development._shared_progression() if shared_content else _content.development.progression(),_content.world_definition,_content.combat,_content.meetings,_content.initial_loadout,_content.development.body_functions(),_content.get("care"),_content.get("exploration"),_content.development.psionics(),_content.development.upgrades(),_content.development.hybrids(),shared_content)
	if content.has("region"):
		_content["region"]=content.region if shared_content else content.region.copy()
		journey().region_catalog=_content.region
		journey().region=Sm2RegionState.new()
	if content.has("survival"):
		_content["survival"]=content.survival
		journey().survival=Sm2SurvivalState.new(); journey().survival.catalog=content.survival
	runner=null

func has_search_practice() -> bool: return _content.has("exploration") and _content.exploration.has_practice()
func has_discovery() -> bool: return _content.has("exploration") and _content.exploration.has_requirements()
func format_id() -> String:
	if _content.has("survival") and _content.survival.has_layers(): return "sm2.survival_journey_session.3"
	if _content.has("survival") and _content.survival.has_devices(): return "sm2.survival_journey_session.2"
	return "sm2.survival_journey_session.1" if _content.has("survival") else REGION_FORMAT if _content.has("region") else HYBRID_FORMAT if _content.development.has_hybrids() else IMPLANT_FORMAT if _content.development.has_implants() else UPGRADE_FORMAT if _content.development.has_upgrades() else PSIONIC_SHIELD_FORMAT if _content.development.has_psionic_shields() else PSIONIC_GROWTH_FORMAT if _content.development.has_psionic_growth() else PSIONIC_FORMAT if _content.development.has_psionics() else DISCOVERY_FORMAT if has_discovery() else SEARCH_FORMAT if has_search_practice() else EXPLORATION_FORMAT if _content.has("exploration") else CARE_FORMAT if _content.has("care") else PROSTHESIS_FORMAT if _content.development.has_prostheses() else BODY_FORMAT if _content.development.has_body_functions() else PARTY_FORMAT if _content.development.progression().is_party() else JOURNEY_FORMAT
func slot_name() -> String:
	if _content.has("survival") and _content.survival.has_layers(): return "survival_tissues"
	if _content.has("survival") and _content.survival.has_devices(): return "survival_devices"
	return "survival_journey" if _content.has("survival") else REGION_SLOT if _content.has("region") else HYBRID_SLOT if _content.development.has_hybrids() else IMPLANT_SLOT if _content.development.has_implants() else UPGRADE_SLOT if _content.development.has_upgrades() else PSIONIC_SHIELD_SLOT if _content.development.has_psionic_shields() else PSIONIC_GROWTH_SLOT if _content.development.has_psionic_growth() else PSIONIC_SLOT if _content.development.has_psionics() else DISCOVERY_SLOT if has_discovery() else SEARCH_SLOT if has_search_practice() else EXPLORATION_SLOT if _content.has("exploration") else CARE_SLOT if _content.has("care") else PROSTHESIS_SLOT if _content.development.has_prostheses() else BODY_SLOT if _content.development.has_body_functions() else PARTY_SLOT if _content.development.progression().is_party() else JOURNEY_SLOT

func journey() -> Sm2JourneyWorld: return world as Sm2JourneyWorld

func new_game() -> Dictionary:
	var bytes: PackedByteArray=Crypto.new().generate_random_bytes(16)
	if bytes.size()!=16: return _error("world_identity_failed")
	var candidate: Sm2JourneySession=Sm2JourneySession.new(_content,_profile,_store)
	candidate.world.start("p4:"+bytes.hex_encode())
	return _publish(candidate)

func capture() -> Dictionary:
	return {"format":format_id(),"fingerprint":_content.journey_fingerprint,"world":world.capture(),"history":history.duplicate(true),"active":runner.capture() if world.busy() else {}}

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
	if journey().survival!=null: _encounter["survival"]=journey().survival.copy()
	runner=Sm2BattleRunner.new(_encounter.catalog,_encounter.combat,_profile,null,false,_encounter.get("effects"),_encounter.get("magic"),_encounter.development,_encounter.origin,_encounter.get("survival"),true)
	return {"ok":true}

func attack(value: Sm2Command) -> Sm2CommandResult:
	var denied: Sm2CommandResult=Sm2CommandResult.new()
	denied.revision=int(runner.status().revision) if runner!=null else 0
	if not world.busy() or value==null or value.kind=="buy_node": denied.code="world_battle_locked"; return denied
	if world.revision>=1000000 or history.size()>=HISTORY_LIMIT: denied.code="world_limit"; return denied
	var candidate: Sm2JourneySession=_copy() as Sm2JourneySession
	if candidate==null: denied.code="world_copy_failed"; return denied
	var result: Sm2CommandResult=candidate.runner.execute_player(value)
	if not result.accepted: return result
	candidate.world.revision+=1
	var finished: Dictionary=candidate._finish()
	var published: Dictionary=_commit_battle_action(candidate) if finished.ok else finished
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
	var published: Dictionary=_commit_battle_action(candidate) if finished.ok else finished
	return result if published.ok else {"ok":false,"reason":str(published.errors[0])}

func _finish() -> Dictionary:
	if not runner.status().finished: return {"ok":true}
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
	# restore() has already checked this exact payload through the battle decoder.
	# Retain encounter-specific checks below on an isolated copy of that result.
	var state: Sm2TacticalState=runner.state_copy()
	if state==null: return _error("encounter_state_missing")
	if state.scenario_id!=_encounter.setup.scenario_id or state.field.to_data()!=_encounter.setup.field or state.round_limit!=int(_encounter.setup.round_limit) or state.actors.size()!=4: return _error("encounter_definition")
	for entry: Dictionary in _encounter.setup.actors:
		var actor: Sm2TacticalActor=state.actor(int(entry.actor_id))
		if actor==null or actor.loadout_id!=entry.loadout_id or actor.spatial.side!=entry.side or actor.spatial.controller!=entry.controller or actor.spatial.owner!=entry.owner: return _error("encounter_binding")
	if state.finished and not raw.session.result_recorded: return _error("encounter_receipt_missing")
	return {"ok":true,"state":state,"errors":PackedStringArray()}

func restore(raw: Dictionary) -> Dictionary:
	if not Sm2Validate.fields(raw,["format","fingerprint","world","history","active"]) or raw.format!=format_id() or raw.fingerprint!=_content.journey_fingerprint or not raw.world is Dictionary or not raw.history is Array or raw.history.size()>HISTORY_LIMIT or not raw.active is Dictionary: return _error("journey_save_version")
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
		candidate.runner=Sm2BattleRunner.new(_encounter.catalog,_encounter.combat,_profile,null,false,_encounter.get("effects"),_encounter.get("magic"),_encounter.development,_encounter.origin,_encounter.get("survival"))
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

## Called only after an accepted command on an isolated internal candidate.
func _commit_battle_action(value: Sm2JourneySession) -> Dictionary:
	return _publish(value)

func save_game() -> Dictionary:
	if _store==null: return _error("no_store")
	var checked: Sm2JourneySession=Sm2JourneySession.new(_content,_profile,_store)
	if not checked.restore(capture()).ok: return _error("world_save_invalid")
	return _store.save_slot(capture(),slot_name())

func load_game() -> Dictionary:
	if _store==null: return _error("no_store")
	var loaded: Dictionary=_store.load_slot(slot_name())
	return restore(loaded.payload) if loaded.ok else loaded

static func _command_data(value: Sm2WorldCommand) -> Dictionary:
	return {"kind":value.kind,"world_id":value.world_id,"revision":value.expected_revision,"incarnation_id":value.incarnation_id,"body_id":value.body_id,"target_id":value.target_id,"content_id":value.content_id}
