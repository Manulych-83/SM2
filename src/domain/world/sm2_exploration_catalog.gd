class_name Sm2ExplorationCatalog
extends RefCounted
const TIME_LIMIT: int=1000000
var _raw: Dictionary={}
var _required: Dictionary[String,Sm2ProgressNodeDefinition]={}
func build(raw: Dictionary,care: Sm2CareCatalog,encounter_count: int,progress: Sm2ProgressCatalog=null) -> PackedStringArray:
	if care==null or not care.expandable() or not Sm2Validate.fields(raw,["version","sites"]) or raw.version not in ["sm2.exploration.content.1","sm2.exploration.content.2","sm2.exploration.content.3"] or not raw.sites is Array or raw.sites.is_empty() or raw.sites.size()>256: return PackedStringArray(["exploration_content"])
	var practice: bool=raw.version!="sm2.exploration.content.1"
	var gated: bool=raw.version=="sm2.exploration.content.3"
	if practice and (progress==null or not progress.is_party()): return PackedStringArray(["exploration_progress"])
	var required: Dictionary[String,Sm2ProgressNodeDefinition]={}
	var ids: Array[String]=[]
	for site: Variant in raw.sites:
		var fields: Array[String]=["id","name","description","minutes","after_encounters","rewards"]
		if practice: fields.append("practice")
		if gated: fields.append("required_nodes")
		if not site is Dictionary or not Sm2Validate.fields(site,fields) or not Sm2Validate.text(site.id) or site.id in ids or not Sm2Validate.text(site.name) or not Sm2Validate.text(site.description) or not Sm2Validate.integer(site.minutes,1,1440) or not Sm2Validate.integer(site.after_encounters,0,encounter_count) or not site.rewards is Dictionary or site.rewards.is_empty(): return PackedStringArray(["exploration_site"])
		if gated:
			if not Sm2Validate.string_list(site.required_nodes): return PackedStringArray(["exploration_required_nodes"])
			for node_id: String in site.required_nodes:
				var node: Sm2ProgressNodeDefinition=progress.node(node_id)
				if node==null: return PackedStringArray(["exploration_required_node_missing"])
				required[node_id]=node
		if practice:
			if not site.practice is Dictionary or site.practice.is_empty(): return PackedStringArray(["exploration_practice"])
			for track_id: Variant in site.practice:
				if not track_id is String or progress.track(track_id)==null or not Sm2Validate.integer(site.practice[track_id],1,Sm2ProgressCatalog.XP_LIMIT): return PackedStringArray(["exploration_practice_award"])
		for resource_id: Variant in site.rewards:
			if not resource_id is String or resource_id not in care.resource_ids() or not Sm2Validate.integer(site.rewards[resource_id],1,care.capacity(resource_id)): return PackedStringArray(["exploration_reward"])
		if not site.id.is_valid_identifier(): return PackedStringArray(["exploration_site_id"])
		ids.append(site.id)
	_raw=raw.duplicate(true); _required=required; return PackedStringArray()
func to_data() -> Dictionary: return _raw.duplicate(true)
func has_practice() -> bool: return _raw.get("version") in ["sm2.exploration.content.2","sm2.exploration.content.3"]
func has_requirements() -> bool: return _raw.get("version")=="sm2.exploration.content.3"
func required_node_ids() -> Array[String]:
	var result: Array[String]=[]; result.assign(_required.keys()); result.sort(); return result
func access_error(id: String,body: Sm2ProgressBodyState) -> String:
	for node_id: String in site(id).get("required_nodes",[]):
		var node: Sm2ProgressNodeDefinition=_required[node_id]
		if body==null or body is Sm2CompanionProgress or not body.tracks.has(node.track_id) or node_id not in body.tracks[node.track_id].nodes: return "Нужен изученный узел: "+node.title+"."
	return ""
func ids() -> Array[String]:
	var result: Array[String]=[]
	for site: Dictionary in _raw.sites: result.append(site.id)
	return result
func site(id: String) -> Dictionary:
	for row: Dictionary in _raw.sites:
		if row.id==id: return row.duplicate(true)
	return {}
