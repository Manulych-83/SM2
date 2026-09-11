class_name Sm2ProgressLab
extends RefCounted
var _catalog: Sm2ProgressCatalog
var _state: Sm2ProgressLabState

func _init(catalog: Sm2ProgressCatalog) -> void:
	_catalog=Sm2ProgressCatalog.new()
	if catalog != null: _catalog.build(catalog.to_data())

func start(world_id: String) -> Dictionary:
	if not _catalog.is_ready(): return _error("catalog_invalid")
	if not Sm2Validate.text(world_id): return _error("world_id")
	var value: Sm2ProgressLabState = Sm2ProgressLabState.new()
	value.world_id=world_id; value.soul.knowledge=_catalog.knowledge_ids()
	for id: String in _catalog.track_ids():
		var track: Sm2ProgressTrackState = Sm2ProgressTrackState.new()
		track.track_id=id; value.body.tracks[id]=track
	for id: String in _catalog.activity_ids(): value.activity_counts[id]=0
	return restore(value.to_data(_catalog.fingerprint(),_catalog.snapshot_format(),_catalog.ruleset()))

func capture() -> Dictionary: return {} if _state == null else _state.to_data(_catalog.fingerprint(),_catalog.snapshot_format(),_catalog.ruleset())
func state_hash() -> String: return Sm2Canonical.hash(capture())
func restore(raw: Dictionary) -> Dictionary:
	var result: Dictionary = Sm2ProgressSnapshot.decode(raw,_catalog)
	if result.ok: _state=result.state
	return {"ok":result.ok,"errors":result.errors}

func preview(command: Sm2ProgressCommand) -> Dictionary:
	if _state == null: return _error("no_lab")
	if command == null: return _error("command_missing")
	if command.world_id != _state.world_id or command.body_id != _state.body.id or command.incarnation_id != _state.incarnation.id: return _error("wrong_incarnation")
	if command.expected_revision != _state.revision: return _error("stale_revision")
	if _state.revision >= 1001000: return _error("revision_limit")
	if command.kind == "practice":
		if command.practice_sequence != _state.practice_sequence+1: return _error("practice_sequence")
		var activity: Sm2PracticeDefinition = _catalog.activity(command.target_id)
		if activity == null: return _error("activity_missing")
		var capability: Dictionary = Sm2PracticeCapability.query(activity,_state.body,_catalog)
		if not capability.allowed:
			var refusal: Dictionary = _error("capability_required")
			refusal["capability"]=capability
			return refusal
		if _state.practice_sequence >= 1000000: return _error("practice_limit")
		for id: String in activity.awards:
			if _state.body.tracks[id].earned > Sm2ProgressCatalog.XP_LIMIT-activity.awards[id]: return _error("experience_limit")
		var awards: Array[Dictionary] = []
		var ids: Array[String] = []; ids.assign(activity.awards.keys()); ids.sort()
		for id: String in ids: awards.append({"track_id":id,"name":_catalog.track(id).title,"amount":activity.awards[id]})
		return {"ok":true,"errors":PackedStringArray(),"awards":awards,"seconds":activity.seconds,"capability":capability}
	if command.kind == "buy_node":
		if command.practice_sequence != 0: return _error("purchase_sequence")
		var node: Sm2ProgressNodeDefinition = _catalog.node(command.target_id)
		if node == null: return _error("node_missing")
		var purchase_error: String = Sm2ProgressRules.purchase_error(_state.body,_catalog,node.id)
		if not purchase_error.is_empty(): return _error(purchase_error)
		var result: Dictionary={"ok":true,"errors":PackedStringArray(),"cost":node.cost,"track_id":node.track_id}
		if not node.extra_costs.is_empty(): result["prices"]=node.prices()
		return result
	return _error("unknown_command")

func execute(command: Sm2ProgressCommand) -> Dictionary:
	var checked: Dictionary = preview(command)
	if not checked.ok: return checked
	var decoded: Dictionary = Sm2ProgressSnapshot.decode(capture(),_catalog)
	if not decoded.ok: return decoded
	var candidate: Sm2ProgressLabState = decoded.state
	var events: Array[Dictionary] = []
	if command.kind == "practice":
		var activity: Sm2PracticeDefinition = _catalog.activity(command.target_id)
		candidate.activity_counts[activity.id]+=1
		candidate.practice_sequence+=1
		events.append({"kind":"exercise_completed","activity_id":activity.id,"source_id":"4","sequence":str(candidate.practice_sequence),"seconds":activity.seconds})
		for award: Dictionary in checked.awards:
			var track: Sm2ProgressTrackState = candidate.body.tracks[award.track_id]
			var previous: int = _catalog.track(track.track_id).describe(track.earned).level
			track.earned+=int(award.amount)
			events.append({"kind":"practice_awarded","track_id":track.track_id,"amount":award.amount,"level_before":previous,"level_after":_catalog.track(track.track_id).describe(track.earned).level})
	else:
		var node: Sm2ProgressNodeDefinition = _catalog.node(command.target_id)
		Sm2ProgressRules.purchase(candidate.body,node)
		var event: Dictionary={"kind":"node_purchased","node_id":node.id,"cost":node.cost,"track_id":node.track_id}
		if not node.extra_costs.is_empty(): event["prices"]=node.prices()
		events.append(event)
	candidate.revision+=1
	var verified: Dictionary = Sm2ProgressSnapshot.decode(candidate.to_data(_catalog.fingerprint(),_catalog.snapshot_format(),_catalog.ruleset()),_catalog)
	if not verified.ok: return verified
	_state=verified.state
	for event: Dictionary in events:
		event["world_id"]=_state.world_id; event["body_id"]=str(_state.body.id); event["incarnation_id"]=str(_state.incarnation.id); event["revision"]=str(_state.revision)
	return {"ok":true,"errors":PackedStringArray(),"events":events,"revision":_state.revision}

func view() -> Dictionary:
	if _state == null: return {}
	var tracks: Array[Dictionary] = Sm2ProgressRules.tracks(_state.body,_catalog)
	var nodes: Array[Dictionary] = []
	for id: String in _catalog.node_ids():
		var node: Sm2ProgressNodeDefinition = _catalog.node(id)
		var command: Sm2ProgressCommand = _command("buy_node",id)
		var available: Dictionary = preview(command)
		nodes.append({"id":id,"name":node.title,"track_id":node.track_id,"track_name":_catalog.track(node.track_id).title,"cost":node.cost,"min_level":node.min_level,"bonus":node.bonus,"owned":id in _state.body.tracks[node.track_id].nodes,"allowed":available.ok,"reason":"" if available.ok else available.errors[0],"requires":node.requires.duplicate()})
	var activities: Array[Dictionary] = []
	var elapsed: int = 0
	for id: String in _catalog.activity_ids():
		var activity: Sm2PracticeDefinition = _catalog.activity(id)
		elapsed+=_state.activity_counts[id]*activity.seconds
		var award_rows: Array[Dictionary] = []
		for track_id: String in _catalog.track_ids():
			if activity.awards.has(track_id): award_rows.append({"track_id":track_id,"name":_catalog.track(track_id).title,"amount":activity.awards[track_id]})
		activities.append({"id":id,"name":activity.title,"awards":award_rows,"seconds":activity.seconds,"preview":preview(_command("practice",id))})
	var knowledge: Array[Dictionary] = []
	for id: String in _state.soul.knowledge: knowledge.append({"id":id,"name":_catalog.knowledge_name(id)})
	return {"world_id":_state.world_id,"body_id":_state.body.id,"incarnation_id":_state.incarnation.id,"revision":_state.revision,"practice_sequence":_state.practice_sequence,"elapsed":elapsed,"tracks":tracks,"nodes":nodes,"activities":activities,"knowledge":knowledge}

func _command(kind: String, target_id: String) -> Sm2ProgressCommand:
	var value: Sm2ProgressCommand = Sm2ProgressCommand.new()
	value.kind=kind; value.target_id=target_id; value.world_id=_state.world_id
	value.expected_revision=_state.revision
	value.practice_sequence=_state.practice_sequence+1 if kind == "practice" else 0
	return value

static func _error(code: String) -> Dictionary:
	return {"ok":false,"errors":PackedStringArray([code])}
