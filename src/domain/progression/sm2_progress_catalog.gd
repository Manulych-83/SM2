class_name Sm2ProgressCatalog
extends RefCounted
const VERSION: String = "sm2.p1.content.1"
const ATTRIBUTE_VERSION: String = "sm2.p4.attributes.content.1"
const PARTY_VERSION: String = "sm2.p4.party.content.1"
const CROSS_VERSION: String="sm2.p5.cross_progression.1"
const UNLOCK_VERSION: String = "sm2.p4.party.content.2"
const XP_LIMIT: int = 1000000
var _raw: Dictionary = {}
var _tracks: Dictionary[String,Sm2ProgressTrackDefinition] = {}
var _nodes: Dictionary[String,Sm2ProgressNodeDefinition] = {}
var _activities: Dictionary[String,Sm2PracticeDefinition] = {}
var _knowledge: Dictionary[String,String] = {}
var _contributions: Array[Dictionary] = []
var _order: Array[String] = []

func build(raw: Dictionary) -> PackedStringArray:
	var candidate: Sm2ProgressCatalog = Sm2ProgressCatalog.new()
	var error: String = candidate._parse(raw)
	if not error.is_empty(): return PackedStringArray([error])
	if raw.get("version") in [PARTY_VERSION,UNLOCK_VERSION,CROSS_VERSION]:
		var growth_error: String=Sm2CompanionProgress.validate_definition(raw.companion_growth,candidate)
		if not growth_error.is_empty(): return PackedStringArray([growth_error])
	_raw=raw.duplicate(true); _tracks=candidate._tracks; _nodes=candidate._nodes
	_activities=candidate._activities; _knowledge=candidate._knowledge
	_contributions=candidate._contributions; _order=candidate._order
	return PackedStringArray()

func _parse(raw: Dictionary) -> String:
	var fields: Array[String]=["version","tracks","nodes","activities","contributions","knowledge"]
	if raw.get("version") in [PARTY_VERSION,UNLOCK_VERSION,CROSS_VERSION]: fields.append("companion_growth")
	if not Sm2Validate.fields(raw,fields) or raw.version not in [VERSION,ATTRIBUTE_VERSION,PARTY_VERSION,UNLOCK_VERSION,CROSS_VERSION]: return "progress_content_version"
	var attributes: bool = raw.version in [ATTRIBUTE_VERSION,PARTY_VERSION,UNLOCK_VERSION,CROSS_VERSION]
	for group: String in ["tracks","nodes","activities","contributions","knowledge"]:
		if not raw[group] is Array or raw[group].size() > 1000: return "progress_content_group"
		for row: Variant in raw[group]:
			if not row is Dictionary: return "progress_content_entry"
	if raw.tracks.is_empty() or raw.activities.is_empty(): return "progress_content_empty"
	var all_ids: Dictionary = {}
	for row: Dictionary in raw.tracks:
		if not Sm2Validate.fields(row,["id","name","kind","base_level","step","growth"]) or not _identity(row,all_ids): return "progress_track_fields"
		if row.kind not in ["attribute","skill"]: return "progress_track_kind"
		if not Sm2Validate.integer(row.base_level,0,10000) or not Sm2Validate.integer(row.step,1,10000) or not Sm2Validate.integer(row.growth,0,10000): return "progress_track_curve"
		var track_value: Sm2ProgressTrackDefinition = Sm2ProgressTrackDefinition.new()
		track_value.id=row.id; track_value.title=row.name; track_value.kind=row.kind
		track_value.base_level=int(row.base_level); track_value.step=int(row.step); track_value.growth=int(row.growth)
		_tracks[track_value.id]=track_value
	for row: Dictionary in raw.nodes:
		var node_fields: Array[String]=["id","name","track_id","min_level","cost","bonus","requires"]
		if raw.version==CROSS_VERSION: node_fields.append_array(["extra_requirements","extra_costs"])
		if not Sm2Validate.fields(row,node_fields) or not _identity(row,all_ids): return "progress_node_fields"
		if not row.track_id is String or not _tracks.has(row.track_id) or not Sm2Validate.string_list(row.requires): return "progress_node_reference"
		if not Sm2Validate.integer(row.min_level,0,1010000) or not Sm2Validate.integer(row.cost,1,XP_LIMIT) or not Sm2Validate.integer(row.bonus,0 if raw.version in [UNLOCK_VERSION,CROSS_VERSION] else 1,10000): return "progress_node_numbers"
		var node: Sm2ProgressNodeDefinition = Sm2ProgressNodeDefinition.new()
		node.id=row.id; node.title=row.name; node.track_id=row.track_id
		node.min_level=int(row.min_level); node.cost=int(row.cost); node.bonus=int(row.bonus); node.requires.assign(row.requires)
		if raw.version==CROSS_VERSION:
			for field: String in ["extra_requirements","extra_costs"]:
				if not row[field] is Array or row[field].size()>64: return "cross_node_shape"
				var used: Array[String]=[node.track_id]
				for entry: Variant in row[field]:
					var key: String="min_level" if field=="extra_requirements" else "amount"
					if not entry is Dictionary or not Sm2Validate.fields(entry,["track_id",key]): return "cross_node_fields"
					if not entry.track_id is String or not _tracks.has(entry.track_id) or entry.track_id in used: return "cross_node_track"
					if not Sm2Validate.integer(entry[key],1,1010000 if key=="min_level" else XP_LIMIT): return "cross_node_number"
					used.append(entry.track_id)
			node.extra_requirements.assign(row.extra_requirements.duplicate(true))
			node.extra_costs.assign(row.extra_costs.duplicate(true))
			for entry: Dictionary in node.extra_requirements: entry.min_level=int(entry.min_level)
			for entry: Dictionary in node.extra_costs: entry.amount=int(entry.amount)
		_nodes[node.id]=node
	var prerequisites: Dictionary = {}
	for id: String in _nodes:
		prerequisites[id]=_nodes[id].requires.duplicate()
		for needed: String in _nodes[id].requires:
			if not _nodes.has(needed): return "progress_node_missing_requirement"
	if _topology(node_ids(),prerequisites).size() != _nodes.size(): return "progress_node_cycle"
	for row: Dictionary in raw.activities:
		var activity_fields: Array[String] = ["id","name","operation","seconds","awards"]
		if attributes: activity_fields.append("capability")
		if not Sm2Validate.fields(row,activity_fields) or not _identity(row,all_ids): return "practice_fields"
		var operations: Array[String] = []
		operations.assign(["attribute_exercise","capacity_trial"] if attributes else ["sword_exercise"])
		if row.operation not in operations or not Sm2Validate.integer(row.seconds,1,10000): return "practice_operation"
		if not row.awards is Array or row.awards.is_empty() or row.awards.size() > _tracks.size(): return "practice_awards"
		var activity_value: Sm2PracticeDefinition = Sm2PracticeDefinition.new()
		activity_value.id=row.id; activity_value.title=row.name; activity_value.seconds=int(row.seconds)
		if attributes:
			if not row.capability is Dictionary: return "practice_capability_fields"
			var capability: Dictionary = row.capability
			if row.operation == "attribute_exercise":
				if not capability.is_empty(): return "practice_capability_fields"
			else:
				if not Sm2Validate.fields(capability,["track_id","minimum","bonus","source"]): return "practice_capability_fields"
				if not capability.track_id is String or not _tracks.has(capability.track_id): return "practice_capability_track"
				if not Sm2Validate.integer(capability.minimum,1,10000) or not Sm2Validate.integer(capability.bonus,0,10000): return "practice_capability_numbers"
				if not capability.source is String or (capability.bonus > 0 and not Sm2Validate.text(capability.source)) or (capability.bonus == 0 and capability.source != ""): return "practice_capability_source"
				activity_value.required_track=capability.track_id; activity_value.required_value=int(capability.minimum)
				activity_value.assistance=int(capability.bonus); activity_value.assistance_name=capability.source
		for award: Variant in row.awards:
			if not award is Dictionary or not Sm2Validate.fields(award,["track_id","amount"]): return "practice_award_fields"
			if not award.track_id is String or not _tracks.has(award.track_id) or activity_value.awards.has(award.track_id): return "practice_award_reference"
			if not Sm2Validate.integer(award.amount,1,XP_LIMIT): return "practice_award_amount"
			activity_value.awards[award.track_id]=int(award.amount)
		_activities[activity_value.id]=activity_value
	var dependencies: Dictionary = {}
	for id: String in _tracks: dependencies[id]=[]
	for row: Dictionary in raw.contributions:
		if not Sm2Validate.fields(row,["source","target","numerator","denominator"]): return "progress_contribution_fields"
		if not row.source is String or not row.target is String or not _tracks.has(row.source) or not _tracks.has(row.target): return "progress_contribution_reference"
		if not Sm2Validate.integer(row.numerator,1,10) or not Sm2Validate.integer(row.denominator,1,10000): return "progress_contribution_ratio"
		# P1 contributions use the source's own level + own nodes, never recursively amplified values.
		if dependencies[row.target].has(row.source): return "progress_contribution_duplicate"
		dependencies[row.target].append(row.source)
		_contributions.append({"source":row.source,"target":row.target,"numerator":int(row.numerator),"denominator":int(row.denominator)})
	_order=_topology(track_ids(),dependencies)
	if _order.size() != _tracks.size(): return "progress_contribution_cycle"
	for row: Dictionary in raw.knowledge:
		if not Sm2Validate.fields(row,["id","name"]) or not _identity(row,all_ids): return "progress_knowledge_fields"
		_knowledge[row.id]=row.name
	return ""

static func _identity(row: Dictionary, seen: Dictionary) -> bool:
	if not Sm2Validate.text(row.id) or not Sm2Validate.text(row.name) or seen.has(row.id): return false
	seen[row.id]=true
	return true

static func _topology(ids: Array[String], dependencies: Dictionary) -> Array[String]:
	var order: Array[String] = []
	var remaining: Array[String] = ids.duplicate()
	while not remaining.is_empty():
		var progressed: bool = false
		for id: String in remaining.duplicate():
			var ready: bool = true
			for needed: String in dependencies.get(id,[]):
				if needed not in order: ready=false; break
			if ready:
				order.append(id); remaining.erase(id); progressed=true
		if not progressed: break
	return order

func fingerprint() -> String: return Sm2Canonical.hash(_raw)
func snapshot_format() -> String: return "sm2.attributes_lab" if _raw.get("version","") == ATTRIBUTE_VERSION else "sm2.progression_lab"
func ruleset() -> String: return "sm2.p4.attributes.1" if _raw.get("version","") == ATTRIBUTE_VERSION else "sm2.p1.practice.1"
func is_ready() -> bool: return not _raw.is_empty()
func to_data() -> Dictionary: return _raw.duplicate(true)
func track_ids() -> Array[String]:
	var result: Array[String] = []; result.assign(_tracks.keys()); result.sort(); return result
func node_ids() -> Array[String]:
	var result: Array[String] = []; result.assign(_nodes.keys()); result.sort(); return result
func activity_ids() -> Array[String]:
	var result: Array[String] = []; result.assign(_activities.keys()); result.sort(); return result
func knowledge_ids() -> Array[String]:
	var result: Array[String] = []; result.assign(_knowledge.keys()); result.sort(); return result
func track(id: String) -> Sm2ProgressTrackDefinition: return _tracks[id].copy() if _tracks.has(id) else null
func node(id: String) -> Sm2ProgressNodeDefinition: return _nodes[id].copy() if _nodes.has(id) else null
func activity(id: String) -> Sm2PracticeDefinition: return _activities[id].copy() if _activities.has(id) else null
func knowledge_name(id: String) -> String: return _knowledge.get(id,"")
func contributions() -> Array[Dictionary]: return _contributions.duplicate(true)

func is_party() -> bool: return _raw.get("version") in [PARTY_VERSION,UNLOCK_VERSION,CROSS_VERSION]
func companion_growth() -> Dictionary: return _raw.get("companion_growth",{}).duplicate(true)
