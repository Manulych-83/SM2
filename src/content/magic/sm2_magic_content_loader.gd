class_name Sm2MagicContentLoader
extends RefCounted
static func load_scenario(path: String = "res://content/m4/magic.tres") -> Dictionary:
	var content: Dictionary = Sm2EffectContentLoader.load_scenario()
	if not content.ok: return content
	var manifest: Sm2MagicManifest = load(path) as Sm2MagicManifest
	if manifest == null: return {"ok":false,"errors":PackedStringArray(["magic_manifest_missing"])}
	var magic: Sm2MagicCatalog = Sm2MagicCatalog.new()
	var errors: PackedStringArray = magic.build({"version":manifest.version,"spells":manifest.spells,"profiles":manifest.profiles},content.combat,content.effects)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	content["magic"] = magic
	content.setup.battle_id = "m4_magic_demo"
	content.setup.scenario_id = "m4:scenario.magic"
	return content
