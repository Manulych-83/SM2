class_name Sm2DiscoveryContentLoader
extends RefCounted
static func load_scenario() -> Dictionary:
	var base: Dictionary=Sm2SearchContentLoader.load_scenario()
	if not base.ok: return base
	var node: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p4/discovery_node.json"))
	var places: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p4/discovery_sites.json"))
	if not node is Dictionary or not places is Dictionary: return {"ok":false,"errors":PackedStringArray(["discovery_content_file"])}
	var raw: Dictionary=base.development.progression().to_data(); raw.version=Sm2ProgressCatalog.UNLOCK_VERSION; raw.nodes.append(node)
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
