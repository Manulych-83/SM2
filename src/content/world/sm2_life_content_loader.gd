class_name Sm2LifeContentLoader
extends RefCounted
static func load_scenario() -> Dictionary:
	var content: Dictionary=Sm2DevelopmentContentLoader.load_scenario()
	if not content.ok: return content
	var manifest: Sm2LifeManifest=load("res://content/p3/world.tres") as Sm2LifeManifest
	if manifest==null: return {"ok":false,"errors":PackedStringArray(["world_manifest_missing"])}
	var definition: Sm2LifeDefinition=Sm2LifeDefinition.new()
	var errors: PackedStringArray=definition.build(manifest.specification)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	content.world_definition=definition
	return content
