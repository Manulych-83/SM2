class_name Sm2CheckpointSession
extends Sm2JourneySession
const CHECKPOINT_FORMAT: String="sm2.checkpoint_journey.1"
var archive: Sm2CheckpointArchive=Sm2CheckpointArchive.new()
var repository: Sm2HistoryRepository
var facts: Dictionary=Sm2CheckpointFacts.empty()
var last: Dictionary={}
var battle_world: Dictionary={}
var _capacity_profile: Sm2CombatGrowthProfile=null
var _capacity_difference: int=0
var _observing: bool=false
var _copy_source: WeakRef
var _copy_revision: int=-1

func _init(content: Dictionary,profile: Sm2AiProfile,store: Sm2SaveStore=null,reader: Sm2HistoryRepository=null,shared_content: bool=false) -> void:
	super(content,profile,store,shared_content)
	repository=reader if reader!=null else Sm2HistoryRepository.new(store._base_directory) if store!=null else null
	var large: bool=world._progress.is_large()
	archive.large_profile=large
	if _store!=null: _store.large_profile=large
	if repository!=null: repository.store.large_profile=large

# Only newly started main-campaign encounters opt in. Restored battles carry
# their own explicit timing; legacy active encounters finish by their old rules.
func _prepare() -> Dictionary:
	var result: Dictionary=super._prepare()
	if result.ok: _encounter.setup["growth_timing"]=Sm2BattleDevelopment.AFTER_BATTLE
	return result

func format_id() -> String: return CHECKPOINT_FORMAT

func new_game() -> Dictionary:
	var candidate: Sm2CheckpointSession=_fresh()
	candidate.world.start("p4:"+Crypto.new().generate_random_bytes(16).hex_encode())
	candidate._bind_archive()
	return _publish(candidate)

func _fresh() -> Sm2CheckpointSession: return Sm2CheckpointSession.new(_content,_profile,_store,repository,true)
func _bind_archive() -> void:
	archive.world_id=world.world_id; archive.fingerprint=_content.journey_fingerprint

func capture(compact_battle: bool=false) -> Dictionary:
	return {"format":CHECKPOINT_FORMAT,"fingerprint":_content.journey_fingerprint,"brief_fingerprint":Sm2Canonical.hash(Sm2ExpeditionBrief.load_for(journey())),"world":world.capture(),"archive":archive.to_data(),"facts":facts.duplicate(true),"last":last.duplicate(true),"active":runner.capture(compact_battle) if world.busy() else {}}

func _copy() -> Sm2LifeSession:
	var candidate: Sm2CheckpointSession=_fresh()
	candidate._copy_source=weakref(self); candidate._copy_revision=world.revision
	candidate._capacity_profile=_capacity_profile; candidate._capacity_difference=_capacity_difference
	candidate.world=journey().copy_world(); candidate.archive=archive.copy(); candidate.facts=facts.duplicate(true)
	candidate.last=last.duplicate(true); candidate.battle_world=battle_world.duplicate(true); candidate.history.assign(history.duplicate(true))
	candidate._encounter=_encounter
	if runner!=null:
		candidate.runner=runner.copy()
	return candidate

func _publish(value: Sm2LifeSession) -> Dictionary:
	if not value is Sm2CheckpointSession: return _error("checkpoint_candidate_type")
	var bounded: Dictionary=_check_capacity(value as Sm2CheckpointSession)
	if not bounded.ok: return bounded
	var result: Dictionary=super._publish(value)
	if result.ok:
		archive=value.archive; facts=value.facts; last=value.last; battle_world=value.battle_world
	return result

func _check_capacity(value: Sm2CheckpointSession) -> Dictionary:
	var maximum: int=Sm2SaveStore.LARGE_MAX_NODES if world._progress.is_large() else Sm2SaveStore.MAX_NODES
	var profile: Sm2CombatGrowthProfile=value.runner.growth_profile() if value.world.busy() and value.runner!=null else null
	var difference: int=0
	if profile!=null:
		if _capacity_profile!=profile:
			# Only this immutable subtree is substituted, at its real depth:
			# checkpoint -> active -> session -> battle -> development.
			var full: Array[int]=[maximum]; var small: Array[int]=[maximum]
			var validator: Sm2SaveStore=Sm2SaveStore.new("user://unused")
			if not validator._validate_value(profile._raw,4,full).is_empty(): return _error("checkpoint_state_capacity")
			if not validator._validate_value(profile.snapshot(profile._base,true),4,small).is_empty(): return _error("checkpoint_state_capacity")
			_capacity_profile=profile; _capacity_difference=small[0]-full[0]
			difference=_capacity_difference
		else: difference=_capacity_difference
	var budget: Array[int]=[maximum-difference]
	var shape_error: String=Sm2SaveStore.new("user://unused")._validate_value(value.capture(profile!=null),0,budget)
	if not shape_error.is_empty():
		value.archive.seal(); budget=[maximum-difference]
		shape_error=Sm2SaveStore.new("user://unused")._validate_value(value.capture(profile!=null),0,budget)
		if not shape_error.is_empty(): return _error("checkpoint_state_capacity")
	return {"ok":true}

func _commit_battle_action(value: Sm2JourneySession) -> Dictionary:
	var candidate: Sm2CheckpointSession=value as Sm2CheckpointSession
	if candidate==null or candidate._copy_source==null or candidate._copy_source.get_ref()!=self or candidate._copy_revision!=world.revision or candidate.world.revision!=world.revision+1: return _error("checkpoint_candidate_origin")
	# Settlement changes the world; the general validator remains mandatory there.
	if not candidate.world.busy(): return _publish(candidate)
	# During combat the coordinator only advances the world's revision. The kernel
	# has already validated the accepted action; the copied camp world stays frozen.
	if not world.busy() or candidate.runner==null or candidate._encounter!=_encounter: return _error("checkpoint_candidate_binding")
	var bounded: Dictionary=_check_capacity(candidate)
	if not bounded.ok: return bounded
	world=candidate.world; runner=candidate.runner; history=candidate.history; _encounter=candidate._encounter
	archive=candidate.archive; facts=candidate.facts; last=candidate.last; battle_world=candidate.battle_world
	return {"ok":true,"errors":PackedStringArray()}

func _before(entry: Dictionary) -> Dictionary:
	var w: Sm2JourneyWorld=journey()
	Sm2ExpeditionView.observe(self,entry,archive.count,false,Sm2ExpeditionBrief.load_for(w),facts)
	return {"hero":w.hero_id(),"items":w.survival.inventory.ids(),"location":w.region.location_id,"subject":Sm2JournalView.subject(self,entry.command) if entry.kind=="camp" else ""}

func _record(entry: Dictionary,before: Dictionary) -> Dictionary:
	var w: Sm2JourneyWorld=journey()
	_observing=true
	Sm2ExpeditionView.observe(self,entry,archive.count,true,Sm2ExpeditionBrief.load_for(w),facts)
	var outcome: String=""
	if entry.kind=="outcome": outcome=Sm2BattleResultsView.title_for(runner.outcome())
	_observing=false
	var added: int=0
	for id: String in w.survival.inventory.ids():
		if id not in before.items: added+=1
	var kind: String=entry.command.kind if entry.kind=="camp" else "outcome"
	var ended: bool=int(before.hero)!=0 and w.hero_id()==0
	var row: Dictionary={"number":archive.count+1,"kind":kind,"subject":before.subject,"outcome":outcome,"interrupted":ended and kind not in ["end_life","outcome"],"seconds":w.region.seconds,"from":w.region_catalog.location(before.location).name,"location":w.region_catalog.location(w.region.location_id).name,"life_ended":ended,"new_items":added}
	if not archive.append(entry,row,w.revision): return _error("checkpoint_archive_limit")
	if entry.kind=="outcome": archive.seal()
	# Legacy history is only a bounded bridge for the current transition/battle presenter.
	if history.size()>64: history=history.slice(-1)
	return {"ok":true}

func _camp(raw: Dictionary,restoring: bool=false) -> Dictionary:
	if archive.count>=Sm2CheckpointArchive.MAX_RECORDS-1: return _error("checkpoint_archive_limit")
	# The parent performs authoritative shape/context checks before mutation.
	if not Sm2Validate.fields(raw,["kind","world_id","revision","incarnation_id","body_id","target_id","content_id"]): return _error("camp_command_fields")
	for key: String in ["kind","world_id","content_id"]:
		if not raw[key] is String: return _error("camp_command_types")
	for key: String in ["revision","incarnation_id","body_id","target_id"]:
		if not Sm2Validate.integer(raw[key],0,1000000): return _error("camp_command_number")
	var command_value: Sm2WorldCommand=command(raw.kind,int(raw.target_id),raw.content_id)
	command_value.world_id=raw.world_id; command_value.expected_revision=int(raw.revision); command_value.incarnation_id=int(raw.incarnation_id); command_value.body_id=int(raw.body_id)
	var reason: String=world.check(command_value)
	if not reason.is_empty(): return _error(reason)
	var entry: Dictionary={"kind":"camp","command":raw.duplicate(true)}
	var before: Dictionary=_before(entry)
	var result: Dictionary=super._camp(raw,restoring)
	if not result.ok: return result
	if raw.kind=="start_battle": battle_world=world.capture()
	return _record(entry,before)

func _finish() -> Dictionary:
	if not runner.status().finished: return {"ok":true}
	var entry: Dictionary={"kind":"outcome","battle":{}}
	var before: Dictionary=_before(entry)
	var result: Dictionary=super._finish()
	if not result.ok: return result
	entry.battle=runner.capture()
	last={"world":battle_world.duplicate(true),"battle":entry.battle.duplicate(true)}
	return _record(entry,before)

func checkpoint_projection(kind: String) -> Variant:
	if _observing: return null
	if kind=="expedition":
		var brief: Dictionary=Sm2ExpeditionBrief.load_for(journey())
		return Sm2ExpeditionView.from_state(self,facts,brief) if not brief.is_empty() else {"ok":false}
	if kind=="journal": return {"ok":true,"rows":archive.rows(),"busy":world.busy()}
	if kind=="battle": return Sm2BattleResultsView.from_entry(self,last.get("battle",{}),_encounter)
	return null

func save_game() -> Dictionary:
	if _store==null or repository==null: return _error("no_store")
	var saved_blocks: Dictionary=repository.publish(archive.blocks)
	if not saved_blocks.ok: return saved_blocks
	archive.repository=repository
	archive.blocks.clear() # Published immutable files can be read through the repository.
	var raw: Dictionary=capture()
	# CampaignStore owns the mandatory semantic validator and checks before publishing.
	if _store is Sm2CampaignStore: return _store.save_slot(raw,slot_name())
	var check: Sm2CheckpointSession=_fresh()
	var result: Dictionary=check.restore(raw)
	if not result.ok: return result
	return _store.save_slot(raw,slot_name())

func load_game() -> Dictionary:
	if _store==null: return _error("no_store")
	var loaded: Dictionary=_store.load_slot(slot_name())
	if not loaded.ok: return loaded
	if loaded.get("validated_session") is Sm2CheckpointSession:
		return _publish(loaded.validated_session)
	return restore(loaded.payload)

func restore(raw: Dictionary) -> Dictionary:
	var candidate: Sm2CheckpointSession=_fresh()
	var checkpoint: bool=raw.get("format")==CHECKPOINT_FORMAT
	var result: Dictionary=candidate._restore_checkpoint(raw) if checkpoint else candidate._import_legacy(raw)
	if not result.ok: return result
	if not checkpoint: return _publish(candidate)
	# This local candidate just passed full world/archive/battle decoding. Retain
	# the publication binding and capacity checks without decoding it again.
	if candidate.world.busy() and (candidate.runner==null or Sm2Canonical.hash(candidate.journey().origin())!=Sm2Canonical.hash(candidate._encounter.origin)): return _error("journey_candidate_binding")
	var bounded: Dictionary=_check_capacity(candidate)
	if not bounded.ok: return bounded
	world=candidate.world; runner=candidate.runner; history=candidate.history; _encounter=candidate._encounter
	archive=candidate.archive; facts=candidate.facts; last=candidate.last; battle_world=candidate.battle_world
	return {"ok":true,"errors":PackedStringArray()}

func _restore_checkpoint(raw: Dictionary) -> Dictionary:
	if not Sm2Validate.fields(raw,["format","fingerprint","brief_fingerprint","world","archive","facts","last","active"]) or raw.fingerprint!=_content.journey_fingerprint or not raw.active is Dictionary or not raw.last is Dictionary: return _error("checkpoint_format")
	var decoded: Dictionary=Sm2CheckpointWorld.decode(raw.world,journey())
	if not decoded.ok: return decoded
	world=decoded.world; _bind_archive()
	if world.busy() and not world.receipt.is_empty(): return _error("checkpoint_busy_receipt")
	if journey().completed==0 and (not raw.last.is_empty() or not world.receipt.is_empty()): return _error("checkpoint_unearned_receipt")
	if raw.brief_fingerprint!=Sm2Canonical.hash(Sm2ExpeditionBrief.load_for(journey())): return _error("checkpoint_brief")
	if not archive.restore(raw.archive,repository) or archive.revision>world.revision or (not world.busy() and archive.revision!=world.revision): return _error("checkpoint_archive")
	if not Sm2CheckpointFacts.valid(raw.facts,journey(),archive.count): return _error("checkpoint_facts")
	facts=Sm2CheckpointFacts.detached_numbers(raw.facts); last=raw.last.duplicate(true)
	if not last.is_empty():
		if not Sm2Validate.fields(last,["world","battle"]) or not last.battle is Dictionary: return _error("checkpoint_last_battle")
		var previous: Sm2CheckpointSession=_fresh()
		decoded=Sm2CheckpointWorld.decode(last.world,previous.journey())
		if not decoded.ok: return decoded
		previous.world=decoded.world
		if previous.world.world_id!=world.world_id or previous.journey().completed!=journey().completed-1 or not previous.world.busy(): return _error("checkpoint_last_context")
		if not previous._prepare().ok: return _error("checkpoint_last_prepare")
		var checked: Dictionary=previous._check_battle(last.battle)
		if not checked.ok or not checked.state.finished: return _error("checkpoint_last_result")
		runner=previous.runner; _encounter=previous._encounter
		history=[{"kind":"outcome","battle":last.battle.duplicate(true)}]
	if journey().completed>0 and last.is_empty(): return _error("checkpoint_last_missing")
	if world.busy():
		battle_world=world.capture()
		if not _prepare().ok: return _error("checkpoint_prepare")
		var checked: Dictionary=_check_battle(raw.active)
		if not checked.ok or checked.state.finished or world.revision!=archive.revision+checked.state.revision: return _error("checkpoint_active")
		battle_world.revision=str(archive.revision)
	elif not raw.active.is_empty() or (not last.is_empty() and world.receipt!=Sm2Canonical.hash(last.battle)): return _error("checkpoint_receipt")
	return {"ok":true}

func _import_legacy(raw: Dictionary) -> Dictionary:
	if not Sm2Validate.fields(raw,["format","fingerprint","world","history","active"]) or raw.format!="sm2.survival_journey_session.3" or raw.fingerprint!=_content.journey_fingerprint or not raw.world is Dictionary or not raw.history is Array or raw.history.size()>HISTORY_LIMIT or not raw.active is Dictionary: return _error("journey_save_version")
	if not Sm2Validate.text(raw.world.get("world_id")) or str(raw.world.world_id).length()>100: return _error("journey_world_id")
	world.start(raw.world.world_id); _bind_archive()
	for entry: Variant in raw.history:
		if not entry is Dictionary: return _error("journey_history_entry")
		if entry.get("kind")=="camp":
			if not Sm2Validate.fields(entry,["kind","command"]) or not entry.command is Dictionary: return _error("journey_camp_entry")
			var applied: Dictionary=_camp(entry.command,true)
			if not applied.ok: return applied
		elif entry.get("kind")=="outcome":
			if not Sm2Validate.fields(entry,["kind","battle"]) or not entry.battle is Dictionary or not world.busy(): return _error("journey_outcome_entry")
			var checked: Dictionary=_check_battle(entry.battle)
			if not checked.ok or not checked.state.finished: return _error("journey_outcome_unfinished")
			world.revision+=checked.state.revision
			var finished: Dictionary=_finish()
			if not finished.ok: return finished
		else: return _error("journey_history_kind")
	if world.busy():
		var checked: Dictionary=_check_battle(raw.active)
		if not checked.ok or checked.state.finished: return _error("journey_active")
		world.revision+=checked.state.revision
	elif not raw.active.is_empty(): return _error("journey_unexpected_battle")
	if Sm2Canonical.hash(world.capture())!=Sm2Canonical.hash(raw.world): return _error("journey_world_history_mismatch")
	return {"ok":true}
