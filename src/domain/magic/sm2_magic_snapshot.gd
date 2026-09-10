class_name Sm2MagicSnapshot
extends RefCounted
const RULESET: String = "sm2.m4.magic.1"
const AREA_RULESET: String = "sm2.m4.areas.1"

static func decode(data: Dictionary, turns: Sm2TurnCatalog, combat: Sm2CombatCatalog, effects: Sm2EffectCatalog, magic: Sm2MagicCatalog) -> Dictionary:
	if magic == null: return _failure("magic_snapshot_version")
	var schema: int = 7 if magic.supports_areas() else 6
	var ruleset: String = AREA_RULESET if magic.supports_areas() else RULESET
	if magic.fingerprint().is_empty() or data.get("ruleset") != ruleset or not Sm2Validate.integer(data.get("schema_version"),schema,schema) or data.get("magic_fingerprint") != magic.fingerprint() or not data.get("mana") is Array or data.mana.size() > 4096: return _failure("magic_snapshot_version")
	var projection: Dictionary = data.duplicate(true)
	projection.erase("magic_fingerprint")
	projection.erase("mana")
	projection.schema_version = 5
	projection.ruleset = Sm2EffectSnapshot.RULESET
	var decoded: Dictionary = Sm2EffectSnapshot.decode(projection,turns,combat,effects)
	if not decoded.ok: return decoded
	var state: Sm2TacticalState = decoded.state
	if data.mana.size() != state.actors.size(): return _failure("mana_coverage")
	var previous: int = 0
	for raw: Variant in data.mana:
		if not raw is Dictionary or not Sm2Validate.fields(raw,["actor_id","current"]) or not Sm2Validate.decimal(raw.actor_id,previous+1): return _failure("mana_fields")
		var id: int = raw.actor_id.to_int()
		var actor: Sm2TacticalActor = state.actor(id)
		if actor == null: return _failure("mana_actor_reference")
		var profile: Sm2MagicProfile = magic.profile(actor.loadout_id)
		if profile == null or not Sm2Validate.integer(raw.current,0,profile.mana_max): return _failure("mana_value")
		var pool: Sm2ManaPool = Sm2ManaPool.new()
		pool.current = int(raw.current)
		state.mana[id] = pool
		previous = id
	state.magic_catalog = magic
	return {"ok":true,"state":state,"errors":PackedStringArray()}

static func _failure(reason: String) -> Dictionary: return {"ok":false,"errors":PackedStringArray([reason])}
