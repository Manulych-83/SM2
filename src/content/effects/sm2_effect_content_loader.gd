class_name Sm2EffectContentLoader
extends RefCounted
static func load_scenario(path: String = "res://content/m4/effects.tres") -> Dictionary:
	var content: Dictionary = Sm2CombatContentLoader.load_scenario()
	if not content.ok: return content
	var manifest: Sm2EffectManifest = load(path) as Sm2EffectManifest
	if manifest == null: return {"ok":false,"errors":PackedStringArray(["effect_manifest_missing"])}
	var effects: Sm2EffectCatalog = Sm2EffectCatalog.new()
	var errors: PackedStringArray = effects.build({"version":manifest.version,"effects":manifest.effects,"actions":manifest.actions,"profiles":manifest.profiles},content.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var placements: Dictionary = {}
	for raw: Dictionary in manifest.placements:
		if not Sm2Validate.fields(raw,["actor_id","q","r"]) or not Sm2Validate.integer(raw.actor_id,1,4096) or not Sm2Validate.integer(raw.q,0,63) or not Sm2Validate.integer(raw.r,0,63) or placements.has(int(raw.actor_id)): return {"ok":false,"errors":PackedStringArray(["effect_placement"])}
		placements[int(raw.actor_id)] = raw
	if placements.size() != content.setup.actors.size(): return {"ok":false,"errors":PackedStringArray(["effect_placement_coverage"])}
	for actor: Dictionary in content.setup.actors:
		if not placements.has(int(actor.actor_id)): return {"ok":false,"errors":PackedStringArray(["effect_placement_reference"])}
		actor.q = int(placements[int(actor.actor_id)].q)
		actor.r = int(placements[int(actor.actor_id)].r)
	content.setup.battle_id = "m4_effects_demo"
	content.setup.scenario_id = "m4:scenario.effects"
	content["effects"] = effects
	return content
