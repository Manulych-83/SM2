class_name Sm2ProgressContentLoader
extends RefCounted
static func load_catalog(path: String = "res://content/p1/progression.tres") -> Dictionary:
	var manifest: Sm2ProgressManifest = load(path) as Sm2ProgressManifest
	if manifest == null: return {"ok":false,"errors":PackedStringArray(["progress_manifest_missing"])}
	var catalog: Sm2ProgressCatalog = Sm2ProgressCatalog.new()
	var errors: PackedStringArray = catalog.build({"version":manifest.version,"tracks":manifest.tracks,"nodes":manifest.nodes,"activities":manifest.activities,"contributions":manifest.contributions,"knowledge":manifest.knowledge})
	return {"ok":errors.is_empty(),"errors":errors,"catalog":catalog if errors.is_empty() else null}
