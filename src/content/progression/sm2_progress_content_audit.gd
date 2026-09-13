class_name Sm2ProgressContentAudit
extends RefCounted
## Author-facing diagnostics supplement, but never replace, the authoritative catalog.
static func inspect(raw: Dictionary) -> Dictionary:
	var catalog: Sm2ProgressCatalog=Sm2ProgressCatalog.new()
	var validation: PackedStringArray=catalog.build(raw)
	var diagnostics: Array[Dictionary]=[]; var seen: Dictionary={}
	for group: String in ["tracks","nodes","activities","knowledge"]:
		if not raw.get(group) is Array: continue
		for index: int in raw[group].size():
			var row: Variant=raw[group][index]
			if not row is Dictionary or not row.get("id") is String: continue
			var path: String="%s[%s].id" % [group,index]
			if seen.has(row.id): diagnostics.append({"code":"duplicate_id","path":path,"id":row.id,"first":seen[row.id]})
			else: seen[row.id]=path
	var ids: Array[String]=[]; var dependencies: Dictionary={}; var paths: Dictionary={}
	if raw.get("nodes") is Array:
		for index: int in raw.nodes.size():
			var row: Variant=raw.nodes[index]
			if not row is Dictionary or not row.get("id") is String or not Sm2Validate.string_list(row.get("requires")): continue
			if dependencies.has(row.id): continue
			ids.append(row.id); dependencies[row.id]=row.requires; paths[row.id]="nodes[%s].requires" % index
	var graph: Dictionary=Sm2DependencyGraph.inspect(ids,dependencies)
	for error: Dictionary in graph.errors:
		var entry: Dictionary=error.duplicate(true)
		if entry.has("id"): entry.path=paths.get(entry.id,"")
		diagnostics.append(entry)
	var skills: int=0; var attributes: int=0
	if validation.is_empty():
		for row: Dictionary in catalog.track_summaries():
			if row.kind=="skill": skills+=1
			else: attributes+=1
	return {"ok":validation.is_empty(),"validation":Array(validation),"diagnostics":diagnostics,"nodes":ids.size(),"skills":skills,"attributes":attributes,"activities":catalog.activity_ids().size() if validation.is_empty() else 0,"fingerprint":catalog.fingerprint() if validation.is_empty() else ""}
