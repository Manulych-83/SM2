class_name Sm2PsionicContentLoader
extends RefCounted
static func load_scenario() -> Dictionary:
	var base: Dictionary=Sm2DiscoveryContentLoader.load_scenario()
	if not base.ok: return base
	var psi: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p5/psionics.json"))
	var additions: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p5/progression.json"))
	if not psi is Dictionary or not additions is Dictionary or not additions.has("node") or not additions.has("activity"): return {"ok":false,"errors":PackedStringArray(["psionic_content_file"])}
	var raw: Dictionary=base.development.progression().to_data()
	raw.nodes.append(additions.node); raw.activities.append(additions.activity)
	var progress: Sm2ProgressCatalog=Sm2ProgressCatalog.new(); var errors: PackedStringArray=progress.build(raw)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var rules: Dictionary=base.development.to_data(); rules.version=Sm2DevelopmentCatalog.PSIONIC_VERSION; rules.psionics=psi
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new(); errors=development.build(rules,progress,base.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var exploration: Sm2ExplorationCatalog=Sm2ExplorationCatalog.new(); errors=exploration.build(base.exploration.to_data(),base.care,base.meetings.size(),progress)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	base.development=development; base.exploration=exploration
	base.journey_fingerprint=Sm2Canonical.hash([base.journey_fingerprint,development.fingerprint(),exploration.to_data()]); return base
