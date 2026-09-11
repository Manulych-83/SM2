class_name Sm2ExplorationContentLoader
extends RefCounted
static func load_scenario() -> Dictionary:
	var base: Dictionary=Sm2CareContentLoader.load_scenario()
	if not base.ok: return base
	var care_raw: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p4/exploration_care.json"))
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p4/exploration.json"))
	if not raw is Dictionary or not care_raw is Dictionary: return {"ok":false,"errors":PackedStringArray(["exploration_file"])}
	var care: Sm2CareCatalog=Sm2CareCatalog.new(); var errors: PackedStringArray=care.build(care_raw)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var exploration: Sm2ExplorationCatalog=Sm2ExplorationCatalog.new(); errors=exploration.build(raw,care,base.meetings.size())
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	base.care=care; base["exploration"]=exploration
	base.journey_fingerprint=Sm2Canonical.hash([base.journey_fingerprint,care.to_data(),exploration.to_data()]); return base
