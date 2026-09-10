class_name Sm2DevelopmentContentLoader
extends RefCounted
static func load_scenario(path: String = "res://content/p2/development.tres") -> Dictionary:
	var base: Dictionary = Sm2CombatContentLoader.load_scenario()
	var progression: Dictionary = Sm2ProgressContentLoader.load_catalog()
	if not base.ok: return base
	if not progression.ok: return progression
	if not ResourceLoader.exists(path): return {"ok":false,"errors":PackedStringArray(["development_missing"])}
	var manifest: Sm2DevelopmentManifest = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as Sm2DevelopmentManifest
	if manifest == null: return {"ok":false,"errors":PackedStringArray(["development_type"])}
	var development: Sm2DevelopmentCatalog = Sm2DevelopmentCatalog.new()
	var errors: PackedStringArray = development.build(manifest.rules,progression.catalog,base.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var probe: Sm2TacticalBattle = Sm2TacticalBattle.new(base.catalog,base.combat,true,null,null,development)
	var checked: Dictionary = probe.start(manifest.setup)
	if not checked.ok: return checked
	return {"ok":true,"errors":PackedStringArray(),"catalog":base.catalog,"combat":base.combat,"development":development,"setup":manifest.setup.duplicate(true)}
