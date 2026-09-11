class_name Sm2PartyContentLoader
extends RefCounted
static func load_scenario() -> Dictionary:
	var base: Dictionary=Sm2JourneyContentLoader.load_scenario()
	if not base.ok: return base
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p4/party_progression.json"))
	if not raw is Dictionary: return {"ok":false,"errors":PackedStringArray(["party_content"])}
	var progress: Sm2ProgressCatalog=Sm2ProgressCatalog.new()
	var errors: PackedStringArray=progress.build(raw)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var rules: Dictionary=base.development.to_data()
	rules.version=Sm2DevelopmentCatalog.PARTY_VERSION
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	errors=development.build(rules,progress,base.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	base.development=development
	base.journey_fingerprint=Sm2Canonical.hash([base.journey_fingerprint,development.fingerprint()])
	return base
