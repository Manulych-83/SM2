class_name Sm2DevelopmentSnapshot
extends RefCounted
const RULESET: String = "sm2.p2.development.1"
static func decode(data: Dictionary, turns: Sm2TurnCatalog, combat: Sm2CombatCatalog, effects: Sm2EffectCatalog, magic: Sm2MagicCatalog, development: Sm2DevelopmentCatalog, origin: Dictionary = {}) -> Dictionary:
	if development == null or not development.ready() or data.get("ruleset") != (RULESET if origin.is_empty() else Sm2EncounterOrigin.RULESET) or not Sm2Validate.integer(data.get("schema_version"),8 if origin.is_empty() else 9,8 if origin.is_empty() else 9) or not data.get("development") is Dictionary:
		return {"ok":false,"errors":PackedStringArray(["development_snapshot_version"])}
	var base: Dictionary = data.duplicate(true)
	base.erase("development")
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
	return decoded
