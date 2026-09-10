class_name Sm2EffectSnapshot
extends RefCounted
const RULESET: String = "sm2.m4.effects.1"
static func decode(data: Dictionary, turns: Sm2TurnCatalog, combat: Sm2CombatCatalog, effects: Sm2EffectCatalog) -> Dictionary:
	if effects == null or effects.fingerprint().is_empty() or data.get("ruleset") != RULESET or not Sm2Validate.integer(data.get("schema_version"),5,5) or data.get("effect_fingerprint") != effects.fingerprint() or not Sm2Validate.decimal(data.get("next_effect_id"),1,9223372036854775806) or not data.get("effects") is Array or data.effects.size() > Sm2EffectResolver.MAX_TOTAL: return _failure("effect_snapshot_version")
	var projection: Dictionary = data.duplicate(true)
	for key: String in ["effect_fingerprint","next_effect_id","effects"]: projection.erase(key)
	projection.schema_version = 4
	projection.ruleset = Sm2CombatSnapshot.CONSEQUENCE_RULESET
	var decoded: Dictionary = Sm2CombatSnapshot.decode(projection,turns,combat,true)
	if not decoded.ok: return decoded
	var state: Sm2TacticalState = decoded.state
	state.effect_catalog = effects
	state.next_effect_id = data.next_effect_id.to_int()
	var previous: int = 0
	var keys: Dictionary = {}
	var counts: Dictionary = {}
	for raw: Variant in data.effects:
		if not raw is Dictionary or not Sm2Validate.fields(raw,["effect_id","definition_id","source_actor_id","target_actor_id","remaining","applied_revision"]): return _failure("effect_snapshot_fields")
		if not Sm2Validate.decimal(raw.effect_id,previous+1,state.next_effect_id-1) or not raw.definition_id is String or not Sm2Validate.decimal(raw.source_actor_id,1) or not Sm2Validate.decimal(raw.target_actor_id,1) or not Sm2Validate.decimal(raw.applied_revision,1,state.revision): return _failure("effect_snapshot_identity")
		var definition: Sm2EffectDefinition = effects.definition(raw.definition_id)
		var source: Sm2TacticalActor = state.actor(raw.source_actor_id.to_int())
		var target: Sm2TacticalActor = state.actor(raw.target_actor_id.to_int())
		if definition == null or source == null or target == null or not target.spatial.occupies() or state.finished or not Sm2Validate.integer(raw.remaining,1,definition.duration) or effects.immune(target.loadout_id,definition.id): return _failure("effect_snapshot_reference")
		var key: String = raw.target_actor_id+":"+raw.definition_id
		if keys.has(key): return _failure("effect_snapshot_duplicate")
		keys[key] = true
		counts[raw.target_actor_id] = int(counts.get(raw.target_actor_id,0))+1
		if counts[raw.target_actor_id] > Sm2EffectResolver.MAX_PER_ACTOR: return _failure("effect_snapshot_limit")
		var instance: Sm2EffectInstance = Sm2EffectInstance.new()
		instance.effect_id = raw.effect_id.to_int()
		instance.definition_id = raw.definition_id
		instance.source_actor_id = raw.source_actor_id.to_int()
		instance.target_actor_id = raw.target_actor_id.to_int()
		instance.remaining = int(raw.remaining)
		instance.applied_revision = raw.applied_revision.to_int()
		state.effects[instance.effect_id] = instance
		previous = instance.effect_id
	return {"ok":true,"state":state,"errors":PackedStringArray()}
static func _failure(reason: String) -> Dictionary: return {"ok":false,"errors":PackedStringArray([reason])}
