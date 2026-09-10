class_name Sm2LifeSession
extends RefCounted
const FORMAT: String="sm2.life_session.1"
const SLOT: String="p3_world"
var world: Sm2LifeWorld
var runner: Sm2BattleRunner
var _content: Dictionary
var _profile: Sm2AiProfile
var _store: Sm2SaveStore

func _init(content: Dictionary, profile: Sm2AiProfile, store: Sm2SaveStore=null) -> void:
	_content={"setup":content.setup.duplicate(true)}; _store=store
	_content.catalog=Sm2TurnCatalog.new(); _content.catalog.build(content.catalog.to_data())
	_content.combat=Sm2CombatCatalog.new(); _content.combat.build(content.combat.to_data(),_content.catalog)
	_content.development=Sm2DevelopmentCatalog.new(); _content.development.build(content.development.to_data(),content.development.progression(),_content.combat)
	_content.world_definition=Sm2LifeDefinition.new(); _content.world_definition.build(content.world_definition.to_data())
	_profile=Sm2AiProfile.new(); _profile.build(profile.to_data())
	world=Sm2LifeWorld.new(_content.development.progression(),_content.world_definition)
	runner=_new_runner()

func _new_runner() -> Sm2BattleRunner:
	return Sm2BattleRunner.new(_content.catalog,_content.combat,_profile,null,false,null,null,_content.development)

func new_game() -> Dictionary:
	var bytes: PackedByteArray=Crypto.new().generate_random_bytes(16)
	if bytes.size()!=16: return _error("world_identity_failed")
	var candidate: Sm2LifeSession=Sm2LifeSession.new(_content,_profile,_store)
	candidate.world.start("p3:"+bytes.hex_encode())
	var setup: Dictionary=_content.setup.duplicate(true); setup.battle_id=candidate.world.world_id+":12"
	var started: Dictionary=candidate.runner.new_battle(setup)
	return _publish(candidate) if started.ok else started

func capture() -> Dictionary: return {"format":FORMAT,"world":world.capture(),"battle":runner.capture()}
func view() -> Dictionary: return world.view()
func state_hash() -> String: return Sm2Canonical.hash(capture())

func command(kind: String, target_id: int=0, content_id: String="") -> Sm2WorldCommand:
	var value: Sm2WorldCommand=Sm2WorldCommand.new()
	value.kind=kind; value.target_id=target_id; value.content_id=content_id
	value.world_id=world.world_id; value.expected_revision=world.revision
	value.body_id=world.hero_id(); value.incarnation_id=world.soul.incarnation_id
	return value

func act(value: Sm2WorldCommand) -> Dictionary:
	var reason: String=world.check(value)
	if not reason.is_empty(): return _error(reason)
	var candidate: Sm2LifeSession=_copy()
	if candidate==null: return _error("world_copy_failed")
	candidate.world.apply(value)
	return _publish(candidate)

func attack(value: Sm2Command) -> Sm2CommandResult:
	var denied: Sm2CommandResult=Sm2CommandResult.new()
	denied.revision=int(runner.view().revision)
	if not world.busy() or value==null or value.kind=="buy_node": denied.code="world_battle_locked"; return denied
	if world.revision>=1000000: denied.code="world_limit"; return denied
	var candidate: Sm2LifeSession=_copy()
	if candidate==null: denied.code="world_copy_failed"; return denied
	var result: Sm2CommandResult=candidate.runner.execute_player(value)
	if not result.accepted: return result
	candidate.world.revision+=1
	var finished: Dictionary=candidate._finish()
	var published: Dictionary=_publish(candidate) if finished.ok else finished
	if not published.ok: denied.code=str(published.errors[0]); return denied
	return result

func step() -> Dictionary:
	if not world.busy(): return {"ok":true,"status":"finished" if runner.view().finished else "player_turn"}
	if world.revision>=1000000: return {"ok":false,"reason":"world_limit"}
	var candidate: Sm2LifeSession=_copy()
	if candidate==null: return {"ok":false,"reason":"world_copy_failed"}
	var result: Dictionary=candidate.runner.step()
	if not result.ok: return result
	if not result.has("command"): return result
	candidate.world.revision+=1
	var finished: Dictionary=candidate._finish()
	var published: Dictionary=_publish(candidate) if finished.ok else finished
	return result if published.ok else {"ok":false,"reason":str(published.errors[0])}

func _finish() -> Dictionary:
	if not runner.view().finished: return {"ok":true}
	runner.record_outcome()
	var raw: Dictionary=runner.capture().session.battle
	var decoded: Dictionary=Sm2DevelopmentSnapshot.decode(raw,_content.catalog,_content.combat,null,null,_content.development)
	if not decoded.ok: return decoded
	var reason: String=world.apply_battle(decoded.state,Sm2Canonical.hash(raw))
	return {"ok":true} if reason.is_empty() else _error(reason)

func restore(raw: Dictionary) -> Dictionary:
	if not Sm2Validate.fields(raw,["format","world","battle"]) or raw.format!=FORMAT or not raw.world is Dictionary or not raw.battle is Dictionary: return _error("world_save_version")
	var candidate_runner: Sm2BattleRunner=_new_runner()
	var loaded: Dictionary=candidate_runner.restore(raw.battle)
	if not loaded.ok: return loaded
	var snapshot: Dictionary=candidate_runner.capture().session.battle
	var decoded: Dictionary=Sm2DevelopmentSnapshot.decode(snapshot,_content.catalog,_content.combat,null,null,_content.development)
	if not decoded.ok: return decoded
	var state: Sm2TacticalState=decoded.state
	if state.scenario_id!=_content.setup.scenario_id or state.round_limit!=int(_content.setup.round_limit) or state.actors.size()!=4 or state.field.to_data()!=_content.setup.field: return _error("world_encounter_definition")
	for entry: Dictionary in _content.setup.actors:
		var actor: Sm2TacticalActor=state.actor(int(entry.actor_id))
		if actor==null or actor.loadout_id!=entry.loadout_id or actor.spatial.side!=entry.side or actor.spatial.controller!=entry.controller: return _error("world_encounter_binding")
	for body: Sm2ProgressBodyState in state.development.bodies.values():
		for track: Sm2ProgressTrackState in body.tracks.values():
			if not track.nodes.is_empty(): return _error("world_nodes_belong_to_camp")
	if state.finished and not raw.battle.session.result_recorded: return _error("world_outcome_receipt_missing")
	var checked: Dictionary=Sm2LifeWorld.decode(raw.world,_content.development.progression(),_content.world_definition,state,Sm2Canonical.hash(snapshot))
	if not checked.ok: return checked
	world=checked.world; runner=candidate_runner
	return {"ok":true,"errors":PackedStringArray()}

func _copy() -> Sm2LifeSession:
	var candidate: Sm2LifeSession=Sm2LifeSession.new(_content,_profile,_store)
	return candidate if candidate.restore(capture()).ok else null

func _publish(candidate: Sm2LifeSession) -> Dictionary:
	return restore(candidate.capture())

func save_game() -> Dictionary:
	if _store==null: return _error("no_store")
	if _copy()==null: return _error("world_save_invalid")
	return _store.save_slot(capture(),SLOT)

func load_game() -> Dictionary:
	if _store==null: return _error("no_store")
	var loaded: Dictionary=_store.load_slot(SLOT)
	return restore(loaded.payload) if loaded.ok else loaded

static func _error(reason: String) -> Dictionary: return {"ok":false,"errors":PackedStringArray([reason])}
