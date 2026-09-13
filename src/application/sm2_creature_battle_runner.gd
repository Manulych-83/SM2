class_name Sm2CreatureBattleRunner
extends Sm2BattleRunner
## Template identity is bound by the compiled catalog fingerprint; view data is derived.
var _source: Dictionary = {}
var _bindings: Dictionary = {}
var _visuals: Dictionary = {}

func _init(compiled: Dictionary, profile: Sm2AiProfile, store: Sm2SaveStore = null, self_play: bool = false, visuals: Dictionary = {}) -> void:
	super(compiled.catalog,compiled.combat,profile,store,self_play,compiled.effects)
	_bindings = compiled.bindings.duplicate(true); _visuals = visuals.duplicate(true)
	_source = {"catalog":_turns,"combat":_combat,"effects":_effects,"setup":compiled.setup.duplicate(true),"bindings":_bindings.duplicate(true),"encounter_name":compiled.encounter_name}

func new_battle(setup: Dictionary) -> Dictionary:
	if setup != _source.setup: return {"ok":false,"errors":PackedStringArray(["creature_setup_mismatch"])}
	return super.new_battle(setup)

func view() -> Dictionary:
	var data: Dictionary = super.view()
	if data.is_empty(): return data
	data["encounter_name"] = _source.encounter_name
	for actor: Dictionary in data.actors:
		var binding: Dictionary = _bindings.get(int(actor.actor_id),{})
		actor.merge(binding.duplicate(true),true)
		actor["appearance"] = _visuals.get(binding.get("appearance_id",""),{}).duplicate(true)
	return data

func restore(payload: Dictionary) -> Dictionary:
	var session: Variant = payload.get("session")
	if not session is Dictionary or not session.get("battle") is Dictionary: return {"ok":false,"errors":PackedStringArray(["creature_snapshot_shape"])}
	for key: String in ["battle_id","scenario_id"]:
		if session.battle.get(key) != _source.setup[key]: return {"ok":false,"errors":PackedStringArray(["creature_snapshot_encounter"])}
	if not Sm2Validate.integer(session.battle.get("round_limit"),1,1000) or int(session.battle.round_limit) != int(_source.setup.round_limit) or not session.battle.get("field") is Dictionary: return {"ok":false,"errors":PackedStringArray(["creature_snapshot_encounter"])}
	var field: Sm2Battlefield = Sm2Battlefield.new()
	if not field.build(session.battle.field).is_empty() or field.to_data() != _source.setup.field: return {"ok":false,"errors":PackedStringArray(["creature_snapshot_field"])}
	var actors: Variant = session.battle.get("actors")
	if not actors is Array or actors.size() != _source.setup.actors.size(): return {"ok":false,"errors":PackedStringArray(["creature_snapshot_members"])}
	for i: int in actors.size():
		if not actors[i] is Dictionary: return {"ok":false,"errors":PackedStringArray(["creature_snapshot_actor"])}
		var initial: Dictionary = _source.setup.actors[i]
		for key: String in ["actor_id","loadout_id","side","owner","controller","creator"]:
			if not actors[i].has(key) or str(actors[i][key]) != str(initial[key]): return {"ok":false,"errors":PackedStringArray(["creature_snapshot_binding"])}
	return super.restore(payload)

func copy() -> Sm2BattleRunner:
	var result: Sm2CreatureBattleRunner = Sm2CreatureBattleRunner.new(_source,_profile,_store,_self_play,_visuals)
	result._session = _session.copy(); result._key = _key; result._attempts = _attempts; result._error = _error
	return result
