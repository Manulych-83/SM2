class_name Sm2ProgressSnapshot
extends RefCounted
static func decode(raw: Dictionary, catalog: Sm2ProgressCatalog) -> Dictionary:
	var invalid: Dictionary = {"ok":false,"errors":PackedStringArray(["progress_snapshot_invalid"])}
	if catalog == null or not catalog.is_ready(): return invalid
	if not Sm2Validate.fields(raw,["format","schema_version","ruleset","content_fingerprint","world_id","soul","body","incarnation","source_id","next_id","revision","practice_sequence","activity_counts"]): return invalid
	if raw.format != "sm2.progression_lab" or not Sm2Validate.integer(raw.schema_version,1,1) or raw.ruleset != "sm2.p1.practice.1" or raw.content_fingerprint != catalog.fingerprint(): return invalid
	if not Sm2Validate.text(raw.world_id) or raw.source_id != "4" or raw.next_id != "5": return invalid
	if not Sm2Validate.decimal(raw.revision,0,1001000) or not Sm2Validate.decimal(raw.practice_sequence,0,1000000): return invalid
	if not raw.soul is Dictionary or not Sm2Validate.fields(raw.soul,["id","incarnation_id","knowledge"]): return invalid
	if raw.soul.id != "1" or raw.soul.incarnation_id != "3" or not Sm2Validate.string_list(raw.soul.knowledge): return invalid
	if raw.soul.knowledge != catalog.knowledge_ids(): return invalid
	if not raw.incarnation is Dictionary or not Sm2Validate.fields(raw.incarnation,["id","soul_id","body_id"]): return invalid
	if raw.incarnation != {"id":"3","soul_id":"1","body_id":"2"}: return invalid
	if not raw.body is Dictionary or not Sm2Validate.fields(raw.body,["id","template_id","tracks"]): return invalid
	if raw.body.id != "2" or raw.body.template_id != "p1:body.human" or not raw.body.tracks is Array: return invalid
	if raw.body.tracks.size() != catalog.track_ids().size(): return invalid
	if not raw.activity_counts is Array or raw.activity_counts.size() != catalog.activity_ids().size(): return invalid
	var state: Sm2ProgressLabState = Sm2ProgressLabState.new()
	state.world_id=raw.world_id; state.soul.knowledge.assign(raw.soul.knowledge)
	state.revision=int(raw.revision); state.practice_sequence=int(raw.practice_sequence)
	var earned: Dictionary[String,int] = {}
	for id: String in catalog.track_ids(): earned[id]=0
	var sequence: int = 0
	for index: int in raw.activity_counts.size():
		var count: Variant = raw.activity_counts[index]
		if not count is Dictionary or not Sm2Validate.fields(count,["activity_id","count"]): return invalid
		if count.activity_id != catalog.activity_ids()[index] or not Sm2Validate.integer(count.count,0,1000000): return invalid
		var number: int = int(count.count)
		state.activity_counts[count.activity_id]=number; sequence+=number
		var activity: Sm2PracticeDefinition = catalog.activity(count.activity_id)
		for id: String in activity.awards: earned[id]+=number*activity.awards[id]
	if sequence != state.practice_sequence: return invalid
	var purchased: Array[String] = []
	for index: int in raw.body.tracks.size():
		var entry: Variant = raw.body.tracks[index]
		if not entry is Dictionary or not Sm2Validate.fields(entry,["track_id","earned_total","spent_total","owned_nodes"]): return invalid
		if entry.track_id != catalog.track_ids()[index] or not Sm2Validate.integer(entry.earned_total,0,Sm2ProgressCatalog.XP_LIMIT) or not Sm2Validate.integer(entry.spent_total,0,int(entry.earned_total)): return invalid
		if int(entry.earned_total) != earned[entry.track_id] or not Sm2Validate.string_list(entry.owned_nodes): return invalid
		var value: Sm2ProgressTrackState = Sm2ProgressTrackState.new()
		value.track_id=entry.track_id; value.earned=int(entry.earned_total); value.spent=int(entry.spent_total); value.nodes.assign(entry.owned_nodes)
		var sorted_nodes: Array[String] = value.nodes.duplicate(); sorted_nodes.sort()
		if sorted_nodes != value.nodes: return invalid
		var cost: int = 0
		for id: String in value.nodes:
			var node: Sm2ProgressNodeDefinition = catalog.node(id)
			if node == null or node.track_id != value.track_id or catalog.track(value.track_id).describe(value.earned).level < node.min_level: return invalid
			cost+=node.cost; purchased.append(id)
		if cost != value.spent: return invalid
		state.body.tracks[value.track_id]=value
	for id: String in purchased:
		for prerequisite: String in catalog.node(id).requires:
			if prerequisite not in purchased: return invalid
	if state.revision != sequence+purchased.size(): return invalid
	return {"ok":true,"errors":PackedStringArray(),"state":state}
