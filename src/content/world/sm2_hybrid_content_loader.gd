class_name Sm2HybridContentLoader
extends RefCounted
static func load_scenario() -> Dictionary:
	var content: Dictionary=Sm2ImplantContentLoader.load_scenario()
	if not content.ok: return content
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p5/hybrid.json"))
	var node: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p5/hybrid_node.json"))
	if not raw is Dictionary or not node is Dictionary or not raw.get("abilities") is Array: return {"ok":false,"errors":PackedStringArray(["hybrid_file"])}
	var data: Dictionary=content.development.progression().to_data(); data.version=Sm2ProgressCatalog.CROSS_VERSION
	for existing: Dictionary in data.nodes: existing["extra_requirements"]=[]; existing["extra_costs"]=[]
	data.nodes.append(node)
	var progress: Sm2ProgressCatalog=Sm2ProgressCatalog.new(); var errors: PackedStringArray=progress.build(data)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var physical: Dictionary=content.combat.to_data()
	for entry: Variant in raw.abilities:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("base_attack") is String: return {"ok":false,"errors":PackedStringArray(["hybrid_base"])}
		var clone: Dictionary={}
		for ability: Dictionary in content.combat.to_data().abilities:
			if ability.id==entry.base_attack: clone=ability.duplicate(true)
		if clone.is_empty(): return {"ok":false,"errors":PackedStringArray(["hybrid_base_missing"])}
		clone.id=entry.id; physical.abilities.append(clone)
	var combat: Sm2CombatCatalog=Sm2CombatCatalog.new(); errors=combat.build(physical,content.catalog)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var rules: Dictionary=content.development.to_data(); rules.version=Sm2DevelopmentCatalog.HYBRID_VERSION; rules["hybrids"]=raw
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new(); errors=development.build(rules,progress,combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	content.combat=combat; content.development=development
	content.journey_fingerprint=Sm2Canonical.hash([content.journey_fingerprint,development.fingerprint(),combat.fingerprint()])
	return content
