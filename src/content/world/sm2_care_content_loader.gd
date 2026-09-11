class_name Sm2CareContentLoader
extends RefCounted
static func load_scenario() -> Dictionary:
	var base: Dictionary=Sm2ProsthesisContentLoader.load_scenario()
	if not base.ok: return base
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p4/care.json"))
	if not raw is Dictionary: return {"ok":false,"errors":PackedStringArray(["care_content_file"])}
	var care: Sm2CareCatalog=Sm2CareCatalog.new()
	var errors: PackedStringArray=care.build(raw)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	base["care"]=care
	base.journey_fingerprint=Sm2Canonical.hash([base.journey_fingerprint,care.to_data()]); return base
