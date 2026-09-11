class_name Sm2RegionContentLoader
extends RefCounted
static func load_scenario() -> Dictionary:
	var content: Dictionary=Sm2HybridContentLoader.load_scenario()
	if not content.ok: return content
	var carriers: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p6/carriers.json"))
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p6/region.json"))
	if not carriers is Array or not raw is Dictionary: return {"ok":false,"errors":PackedStringArray(["region_files"])}
	var definition: Dictionary=content.world_definition.to_data(); definition.bodies.append_array(carriers)
	var world: Sm2LifeDefinition=Sm2LifeDefinition.new(); var errors: PackedStringArray=world.build(definition)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	content.world_definition=world
	var region: Sm2RegionCatalog=Sm2RegionCatalog.new(); errors=region.build(raw,content)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	content["region"]=region
	content.journey_fingerprint=Sm2Canonical.hash([content.journey_fingerprint,world.fingerprint(),region.to_data()])
	return content
