class_name Sm2ContentPackages
extends RefCounted
## Authoring packages compile to existing catalog data. No overrides or executable content.
const VERSION: String="sm2.content_packages.1"
const MAX_PACKAGES: int=1000
const MAX_ROWS: int=10000
const MAX_BYTES: int=8*1024*1024

static func resolve(raw: Variant, roots: Array[String]) -> Dictionary:
	if not raw is Dictionary or not Sm2Validate.fields(raw,["format","packages"]) or raw.format!=VERSION or not raw.packages is Array or raw.packages.is_empty() or raw.packages.size()>MAX_PACKAGES: return _error("package_manifest")
	var ids: Array[String]=[]; var by_id: Dictionary={}; var dependencies: Dictionary={}
	for p: Variant in raw.packages:
		if not p is Dictionary or not Sm2Validate.fields(p,["id","requires","sources"]) or not Sm2Validate.text(p.id) or by_id.has(p.id): return _error("package_identity")
		if not Sm2Validate.string_list(p.requires) or p.requires.size()>MAX_PACKAGES or not p.sources is Array or p.sources.size()>1000: return _error("package_fields",p.id)
		for source: Variant in p.sources:
			if not source is Dictionary: return _error("package_source",p.id)
			var fields: Array[String]=["group","path","field"]
			if source.has("integer_fields"): fields.append("integer_fields")
			if not Sm2Validate.fields(source,fields) or not Sm2Validate.text(source.group) or not source.field is String or not _path(source.path) or not Sm2Validate.string_list(source.get("integer_fields",[])): return _error("package_source",p.id)
		ids.append(p.id); by_id[p.id]=p; dependencies[p.id]=p.requires
	var graph: Dictionary=Sm2DependencyGraph.inspect(ids,dependencies)
	if not graph.ok: return {"ok":false,"errors":graph.errors}
	if roots.is_empty(): return _error("package_roots")
	var selected: Dictionary={}; var pending: Array[String]=roots.duplicate()
	while not pending.is_empty():
		var id: String=pending.pop_back()
		if not by_id.has(id): return _error("package_root_missing",id)
		if selected.has(id): continue
		selected[id]=true
		for needed: String in dependencies[id]: pending.append(needed)
	var ordered: Array[Dictionary]=[]
	for id: String in graph.order:
		if selected.has(id): ordered.append(by_id[id].duplicate(true))
	return {"ok":true,"packages":ordered,"errors":[]}

static func load_groups(path: String, roots: Array[String],max_rows: int=MAX_ROWS) -> Dictionary:
	var file: Dictionary=_read(path)
	if not file.ok: return file
	var resolved: Dictionary=resolve(file.value,roots)
	if not resolved.ok: return resolved
	var documents: Dictionary={}
	for p: Dictionary in resolved.packages:
		for source: Dictionary in p.sources:
			if documents.has(source.path): continue
			var loaded: Dictionary=_read(source.path)
			if not loaded.ok: return loaded
			documents[source.path]=loaded.value
	return compile(file.value,roots,documents,max_rows)

static func compile(manifest: Variant, roots: Array[String], documents: Dictionary,max_rows: int=MAX_ROWS) -> Dictionary:
	if max_rows<1 or max_rows>40000: return _error("package_policy")
	var resolved: Dictionary=resolve(manifest,roots)
	if not resolved.ok: return resolved
	var groups: Dictionary={}; var origins: Dictionary={}; var packages: Array[String]=[]
	var count: int=0
	for p: Dictionary in resolved.packages:
		packages.append(p.id)
		for source: Dictionary in p.sources:
			if not documents.has(source.path): return _error("package_document_missing",p.id,source.path)
			var rows: Variant=documents[source.path]
			if not source.field.is_empty():
				if not rows is Dictionary or not rows.has(source.field): return _error("package_field_missing",p.id,source.path)
				rows=rows[source.field]
			if not rows is Array: return _error("package_rows",p.id,source.path)
			if not groups.has(source.group): groups[source.group]=[]; origins[source.group]={}
			for index: int in rows.size():
				var row: Variant=rows[index]
				if not row is Dictionary or not Sm2Validate.text(row.get("id")): return _error("package_row_identity",p.id,source.path,str(index))
				if origins[source.group].has(row.id):
					var failure: Dictionary=_error("package_duplicate_id",p.id,source.path,row.id)
					failure.errors[0]["previous"]=origins[source.group][row.id].duplicate(true)
					return failure
				count+=1
				if count>max_rows: return _error("package_row_limit",p.id,source.path,row.id)
				var value: Dictionary=row.duplicate(true)
				for field: String in source.get("integer_fields",[]):
					if not Sm2Validate.integer(value.get(field),-9007199254740991,9007199254740991): return _error("package_integer",p.id,source.path,row.id+":"+field)
					value[field]=int(value[field])
				groups[source.group].append(value)
				origins[source.group][row.id]={"package":p.id,"path":source.path,"field":source.field,"index":index}
	return {"ok":true,"groups":groups,"origins":origins,"packages":packages,"errors":[]}

static func _path(value: Variant) -> bool:
	if not value is String or not value.begins_with("res://content/") or not value.ends_with(".json") or "\\" in value: return false
	for part: String in value.substr(6).split("/"):
		if part in ["",".",".."] or ":" in part: return false
	return true

static func _read(path: String) -> Dictionary:
	if not _path(path): return _error("package_path","",path)
	var file: FileAccess=FileAccess.open(path,FileAccess.READ)
	if file==null: return _error("package_file_missing","",path)
	if file.get_length()>MAX_BYTES: return _error("package_file_size","",path)
	var parser: JSON=JSON.new()
	if parser.parse(file.get_as_text())!=OK: return _error("package_json","",path,str(parser.get_error_line())+": "+parser.get_error_message())
	return {"ok":true,"value":parser.data}

static func _error(code: String, package: String="", path: String="", id: String="") -> Dictionary:
	return {"ok":false,"errors":[{"code":code,"package":package,"path":path,"id":id}]}
