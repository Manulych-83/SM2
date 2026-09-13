class_name Sm2ProgressPackageLoader
extends RefCounted
## Extensions augment the existing campaign. Compiler-only edge IDs are not gameplay data.
static func load_extensions(base: Dictionary,path: String="res://content/packages/progression.json") -> Dictionary:
	var packages: Dictionary=Sm2ContentPackages.load_groups(path,["progression.main"],40000)
	return merge(base,packages)

static func merge(base: Dictionary,packages: Dictionary) -> Dictionary:
	if not packages.ok: return packages
	var data: Dictionary=base.duplicate(true)
	for group: String in packages.groups:
		if group not in ["tracks","nodes","activities","contributions","knowledge","profile"]: return _error("progress_package_group:"+group)
		if group=="profile":
			var rows: Array=packages.groups[group]
			if rows.size()!=1 or not Sm2Validate.fields(rows[0],["id","version"]) or rows[0].id!="progression" or rows[0].version!=Sm2ProgressCatalog.LARGE_VERSION: return _error("progress_package_profile")
			data.version=Sm2ProgressCatalog.LARGE_VERSION
			continue
		for row: Dictionary in packages.groups[group]:
			var value: Dictionary=row.duplicate(true)
			if group=="contributions": value.erase("id")
			data[group].append(value)
	var catalog: Sm2ProgressCatalog=Sm2ProgressCatalog.new()
	var errors: PackedStringArray=catalog.build(data)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	return {"ok":true,"raw":data,"catalog":catalog,"origins":packages.origins}

static func _error(reason: String) -> Dictionary: return {"ok":false,"errors":PackedStringArray([reason])}
