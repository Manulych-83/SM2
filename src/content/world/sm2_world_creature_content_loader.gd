class_name Sm2WorldCreatureContentLoader
extends RefCounted
## Explicit new campaign profile. The historical layered loader remains unchanged.
static func load_scenario(base: Dictionary={}, manifest: String="res://content/packages/world_creatures.json") -> Dictionary:
	var content: Dictionary = Sm2SurvivalContentLoader.load_scenario(true,true) if base.is_empty() else base.duplicate()
	if not content.ok: return content
	var packages: Dictionary = Sm2ContentPackages.load_groups(manifest,["world_creatures.core"])
	if not packages.ok: return packages
	if packages.groups.size()!=3 or not packages.groups.has_all(["profiles","templates","bindings"]): return _error("world_creatures_groups")
	var effects: Dictionary = Sm2EffectSequenceContentLoader.load_scenario()
	if not effects.ok: return effects
	var visual: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/creatures.json"))
	if not visual is Dictionary: return _error("world_creatures_visuals")
	var appearances: Array[String] = []; appearances.assign(visual.keys())
	var raw: Dictionary = packages.groups.duplicate(true); raw.erase("bindings"); raw.version=Sm2CreatureCatalog.TYPES_VERSION; raw.encounters=[]
	var templates: Sm2CreatureCatalog = Sm2CreatureCatalog.new()
	var errors: PackedStringArray = templates.build(raw,content.catalog,content.combat,effects.effects,{"ruins":content.setup.field},appearances)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var bindings: Sm2WorldCreatureCatalog = Sm2WorldCreatureCatalog.new()
	errors=bindings.build({"version":Sm2WorldCreatureCatalog.VERSION,"bindings":packages.groups.bindings},templates,content.world_definition,content.meetings,content.survival,content.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var definition: Dictionary = content.world_definition.to_data()
	for body: Dictionary in definition.bodies:
		var actor: Dictionary = bindings.actor(int(body.id))
		if not actor.is_empty(): body.name=actor.definition.name
	var world: Sm2LifeDefinition = Sm2LifeDefinition.new(); errors=world.build(definition)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	content.world_definition=world; content["world_creatures"]=bindings
	content.journey_fingerprint=Sm2Canonical.hash([content.journey_fingerprint,world.fingerprint(),bindings.fingerprint()])
	return content

static func _error(value: String) -> Dictionary: return {"ok":false,"errors":PackedStringArray([value])}
