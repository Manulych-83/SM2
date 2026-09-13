class_name Sm2CreatureContentLoader
extends RefCounted
static func load_catalog(manifest: String = "res://content/packages/creatures.json") -> Dictionary:
	var base: Dictionary = Sm2EffectSequenceContentLoader.load_scenario()
	if not base.ok: return base
	var groups: Dictionary = Sm2ContentPackages.load_groups(manifest,["creatures.core"])
	if not groups.ok: return groups
	if groups.groups.size() != 3 or not groups.groups.has_all(["profiles","templates","encounters"]): return _error("creature_package_groups")
	var visual: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/creatures.json"))
	if not visual is Dictionary or visual.is_empty(): return _error("creature_visuals")
	var appearances: Array[String] = []
	for id: Variant in visual:
		if not Sm2Validate.text(id) or not visual[id] is Dictionary or not Sm2Validate.fields(visual[id],["tunic_color"]) or not visual[id].tunic_color is String or not Color.html_is_valid(visual[id].tunic_color): return _error("creature_visual_fields")
		appearances.append(id)
	var raw: Dictionary = groups.groups.duplicate(true); raw.version = Sm2CreatureCatalog.VERSION
	var catalog: Sm2CreatureCatalog = Sm2CreatureCatalog.new()
	var errors: PackedStringArray = catalog.build(raw,base.catalog,base.combat,base.effects,{"ruins":base.setup.field},appearances)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var ai: Dictionary = Sm2AiContentLoader.load_profile(Sm2AiContentLoader.ABILITY_PATH)
	if not ai.ok: return ai
	return {"ok":true,"catalog":catalog,"visuals":visual,"profile":ai.profile}

static func _error(reason: String) -> Dictionary: return {"ok":false,"errors":PackedStringArray([reason])}
