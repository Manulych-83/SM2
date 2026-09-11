class_name Sm2DevelopmentSnapshot
extends RefCounted
const RULESET: String = "sm2.p2.development.1"
static func decode(data: Dictionary, turns: Sm2TurnCatalog, combat: Sm2CombatCatalog, effects: Sm2EffectCatalog, magic: Sm2MagicCatalog, development: Sm2DevelopmentCatalog, origin: Dictionary = {}) -> Dictionary:
	if development == null or not development.ready() or data.get("ruleset") != (RULESET if origin.is_empty() else str(origin.get("version",""))) or not Sm2Validate.integer(data.get("schema_version"),Sm2EncounterOrigin.schema(development,origin),Sm2EncounterOrigin.schema(development,origin)) or not data.get("development") is Dictionary:
		return {"ok":false,"errors":PackedStringArray(["development_snapshot_version"])}
	if development.has_psionics() and (origin.is_empty() or magic==null or not magic.is_psionic()): return {"ok":false,"errors":PackedStringArray(["psionic_layers_required"])}
	if development.has_psionics() and development.has_psionic_shields()!=magic.supports_shields(): return {"ok":false,"errors":PackedStringArray(["shield_layers_required"])}
	var base: Dictionary = data.duplicate(true)
	base.erase("development")
	if development.has_psionic_shields():
		if magic==null or not magic.supports_shields() or not base.get("actors") is Array: return {"ok":false,"errors":PackedStringArray(["shield_layers_required"])}
		for actor: Variant in base.actors:
			if not actor is Dictionary or not actor.get("barrier") is Dictionary: return {"ok":false,"errors":PackedStringArray(["barrier_missing"])}
			actor.erase("barrier")
	if development.has_body_functions():
		if not data.get("body_changes") is Array or not data.get("actors") is Array: return {"ok":false,"errors":PackedStringArray(["body_snapshot_fields"])}
		base.erase("body_changes")
		for actor: Variant in base.actors:
			if not actor is Dictionary or not actor.has("body_functions"): return {"ok":false,"errors":PackedStringArray(["body_snapshot_actor"])}
			actor.erase("body_functions")
	base.schema_version = 7 if magic != null and magic.supports_areas() else 6 if magic != null else 5 if effects != null else 4
	base.ruleset = Sm2MagicSnapshot.AREA_RULESET if magic != null and magic.supports_areas() else Sm2MagicSnapshot.RULESET if magic != null else Sm2EffectSnapshot.RULESET if effects != null else Sm2CombatSnapshot.CONSEQUENCE_RULESET
	var decoded: Dictionary
	if magic != null: decoded = Sm2MagicSnapshot.decode(base,turns,combat,effects,magic)
	elif effects != null: decoded = Sm2EffectSnapshot.decode(base,turns,combat,effects)
	else: decoded = Sm2CombatSnapshot.decode(base,turns,combat,true)
	if not decoded.ok: return decoded
	var result: Dictionary = Sm2BattleDevelopment.decode(data.development,decoded.state,development) if origin.is_empty() else Sm2EncounterOrigin.decode(data.development,decoded.state,development,combat,origin)
	if not result.ok: return result
	decoded.state.development = result.development
	if development.has_body_functions():
		var reason: String=Sm2BodyFunctionRules.restore_changes(data.body_changes,decoded.state)
		if not reason.is_empty(): return {"ok":false,"errors":PackedStringArray([reason])}
		for raw: Dictionary in data.actors:
			var actor: Sm2TacticalActor=decoded.state.actor(int(raw.actor_id))
			if Sm2Canonical.hash(actor.body_functions.to_data())!=Sm2Canonical.hash(raw.body_functions) or Sm2Canonical.hash(actor.combat.to_data())!=Sm2Canonical.hash(raw.combat): return {"ok":false,"errors":PackedStringArray(["body_snapshot_history"])}
	if development.has_psionic_shields():
		for raw: Dictionary in data.actors:
			var reason: String=Sm2BarrierRules.restore(raw.barrier,decoded.state,decoded.state.actor(int(raw.actor_id)))
			if not reason.is_empty(): return {"ok":false,"errors":PackedStringArray([reason])}
	return decoded
