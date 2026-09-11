class_name Sm2SearchContentLoader
extends RefCounted
static func load_scenario() -> Dictionary:
	var base: Dictionary=Sm2ExplorationContentLoader.load_scenario()
	if not base.ok: return base
	var track: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p4/search_track.json"))
	var places: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p4/search_sites.json"))
	if not track is Dictionary or not places is Dictionary: return {"ok":false,"errors":PackedStringArray(["search_content_file"])}
	var raw: Dictionary=base.development.progression().to_data(); raw.tracks.append(track)
	var progress: Sm2ProgressCatalog=Sm2ProgressCatalog.new(); var errors: PackedStringArray=progress.build(raw)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	errors=development.build(base.development.to_data(),progress,base.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var exploration: Sm2ExplorationCatalog=Sm2ExplorationCatalog.new()
	errors=exploration.build(places,base.care,base.meetings.size(),progress)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	base.development=development; base.exploration=exploration
	base.journey_fingerprint=Sm2Canonical.hash([base.journey_fingerprint,development.fingerprint(),exploration.to_data()]); return base
