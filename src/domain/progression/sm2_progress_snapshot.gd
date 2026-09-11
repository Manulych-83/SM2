class_name Sm2ProgressSnapshot
extends RefCounted
static func decode(raw: Dictionary, catalog: Sm2ProgressCatalog) -> Dictionary:
	var invalid: Dictionary = {"ok":false,"errors":PackedStringArray(["progress_snapshot_invalid"])}
	if catalog == null or not catalog.is_ready(): return invalid
	if not Sm2Validate.fields(raw,["format","schema_version","ruleset","content_fingerprint","world_id","soul","body","incarnation","source_id","next_id","revision","practice_sequence","activity_counts"]): return invalid
	if raw.format != catalog.snapshot_format() or not Sm2Validate.integer(raw.schema_version,1,1) or raw.ruleset != catalog.ruleset() or raw.content_fingerprint != catalog.fingerprint(): return invalid
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
	var decoded: Dictionary=Sm2ProgressRules.decode_body(raw.body,catalog)
	if not decoded.ok: return invalid
	state.body=decoded.body
	var purchased: Array[String]=[]
	for id: String in catalog.track_ids():
		if state.body.tracks[id].earned!=earned[id]: return invalid
		purchased.append_array(state.body.tracks[id].nodes)
	if state.revision != sequence+purchased.size(): return invalid
	for id: String in catalog.activity_ids():
		if state.activity_counts[id] > 0 and not Sm2PracticeCapability.query(catalog.activity(id),state.body,catalog).allowed: return invalid
	return {"ok":true,"errors":PackedStringArray(),"state":state}
