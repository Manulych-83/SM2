class_name Sm2BodyUpgradeContentLoader
extends RefCounted
static func load_scenario() -> Dictionary:
	var base: Dictionary=Sm2PsionicShieldContentLoader.load_scenario()
	if not base.ok: return base
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p5/upgrades.json"))
	if not raw is Dictionary: return {"ok":false,"errors":PackedStringArray(["upgrades_file"])}
	var rules: Dictionary=base.development.to_data(); rules.version=Sm2DevelopmentCatalog.UPGRADE_VERSION; rules["body_upgrades"]=raw
	var dev: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new(); var errors: PackedStringArray=dev.build(rules,base.development.progression(),base.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	base.development=dev; base.journey_fingerprint=Sm2Canonical.hash([base.journey_fingerprint,dev.fingerprint()]); return base
