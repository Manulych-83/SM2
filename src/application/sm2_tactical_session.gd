class_name Sm2TacticalSession
extends RefCounted
## M2 has its own slot and payload; M1 history is never migrated implicitly.
const FORMAT: String = "sm2.session.m2.turns.1"
const SLOT: String = "m2_prototype"
const COMBAT_FORMAT: String = "sm2.session.m2.attacks.1"
var _catalog: Sm2TurnCatalog
var _store: Sm2SaveStore
var _battle: Sm2TacticalBattle = null
var _combat: Sm2CombatCatalog = null
const CONSEQUENCE_FORMAT: String = "sm2.session.m2.consequences.1"
var _consequences: bool = false
var _effects: Sm2EffectCatalog = null
var _magic: Sm2MagicCatalog = null
var _development: Sm2DevelopmentCatalog = null
var _origin: Dictionary = {}
const DEVELOPMENT_FORMAT: String = "sm2.session.p2.development.1"
const MAGIC_FORMAT: String = "sm2.session.m4.magic.1"
const AREA_FORMAT: String = "sm2.session.m4.areas.1"

func save_slot() -> String:
	if _development != null: return "p2_development_prototype"
	return "m4_area_prototype" if _magic != null and _magic.supports_areas() else "m4_magic_prototype" if _magic != null else "m4_effects_prototype" if _effects != null else SLOT

const EFFECT_FORMAT: String = "sm2.session.m4.effects.1"
var _result_recorded: bool = false

func _init(catalog: Sm2TurnCatalog, store: Sm2SaveStore, combat: Sm2CombatCatalog = null, consequences: bool = false, effects: Sm2EffectCatalog = null, magic: Sm2MagicCatalog = null, development: Sm2DevelopmentCatalog = null, origin: Dictionary = {}) -> void:
	_consequences = consequences
	_catalog = Sm2TurnCatalog.new()
	if catalog != null:
		_catalog.build(catalog.to_data())
	_store = store
	if combat != null:
		_combat = Sm2CombatCatalog.new()
		_combat.build(combat.to_data(), _catalog)
	if effects != null:
		_effects = Sm2EffectCatalog.new()
		_effects.build(effects.to_data(),_combat)

	if magic != null:
		_magic = Sm2MagicCatalog.new()
		_magic.build(magic.to_data(),_combat,_effects)
	_origin = origin.duplicate(true)
	if development != null:
		_development = Sm2DevelopmentCatalog.new()
		_development.build(development.to_data(),development.progression(),_combat)

func new_battle(setup: Dictionary) -> Dictionary:
	if _consequences and _battle != null and _battle.view().finished and not _result_recorded:
		return _failure("outcome_not_recorded")
	var candidate: Sm2TacticalBattle = Sm2TacticalBattle.new(_catalog, _combat, _consequences, _effects, _magic, _development, _origin)
	var result: Dictionary = candidate.start(setup)
	if result.ok:
		_battle = candidate
		_result_recorded = false
	return result

func has_active_game() -> bool:
	return _battle != null

func has_save() -> bool:
	return _store != null and _store.has_slot(save_slot())

func close_game() -> void:
	_battle = null

func capture() -> Dictionary:
	if _battle == null:
		return {}
	var data: Dictionary = {"format": COMBAT_FORMAT if _combat != null else FORMAT, "catalog": _catalog.fingerprint(), "battle": _battle.capture()}
	if _consequences:
		data.format = CONSEQUENCE_FORMAT
		data["result_recorded"] = _result_recorded
	if _effects != null: data.format = EFFECT_FORMAT
	if _magic != null: data.format = AREA_FORMAT if _magic.supports_areas() else MAGIC_FORMAT
	if _development != null: data.format = DEVELOPMENT_FORMAT if _origin.is_empty() else "sm2.session.p4.encounter.1"
	return data

func view() -> Dictionary:
	return _battle.view() if _battle != null else {}

func state_hash() -> String:
	return Sm2Canonical.hash(capture())

func preview(command: Sm2Command) -> Dictionary:
	if _battle == null:
		return {"allowed": false, "reason": "no_session", "ap_cost": 0, "fatigue_cost": 0}
	return _battle.preview(command)

func reachable(actor_id: int) -> Dictionary:
	return _battle.reachable(actor_id) if _battle != null else {"ok": false, "reason": "no_session", "cells": []}

func execute(command: Sm2Command) -> Sm2CommandResult:
	if _battle != null:
		return _battle.execute(command)
	var result: Sm2CommandResult = Sm2CommandResult.new()
	result.code = "no_session"
	return result

func ai_decision(profile: Sm2AiProfile) -> Dictionary:
	return _battle.ai_decision(profile) if _battle != null else {"ok": false, "reason": "no_session"}

func outcome() -> Dictionary:
	return _battle.outcome() if _battle != null else {}

func record_outcome() -> Dictionary:
	if not _consequences or _battle == null or not _battle.view().finished:
		return _failure("outcome_unavailable")
	if _result_recorded:
		return {"ok": true, "code": "already_recorded", "outcome": {}}
	_result_recorded = true
	return {"ok": true, "code": "recorded", "outcome": _battle.outcome()}

func advance_retreat() -> Sm2CommandResult:
	var result: Sm2CommandResult = Sm2CommandResult.new()
	if not _consequences or _battle == null:
		result.code = "no_consequence_session"
		return result
	var data: Dictionary = _battle.view()
	result.revision = data.revision
	var fleeing: bool = false
	for actor: Dictionary in data.actors:
		if actor.actor_id == data.active_actor_id:
			fleeing = actor.morale == "fleeing"
	if not fleeing:
		result.code = "active_actor_not_fleeing"
		return result
	var decision: Dictionary = _battle.retreat_decision()
	if not decision.ok:
		result.code = decision.reason
		return result
	return execute(decision.command)

func restore_payload(payload: Dictionary) -> Dictionary:
	var checked: Dictionary = _decode(payload)
	if not checked.ok:
		return checked
	_battle = checked.battle
	_result_recorded = payload.result_recorded if _consequences else false
	return {"ok": true, "errors": PackedStringArray()}

func save_game() -> Dictionary:
	if _battle == null or _store == null:
		return _failure("no_session_or_store")
	var payload: Dictionary = capture()
	var checked: Dictionary = _decode(payload)
	if not checked.ok:
		return checked
	return _store.save_slot(payload, save_slot())

func load_game() -> Dictionary:
	if _store == null:
		return _failure("no_store")
	var loaded: Dictionary = _store.load_slot(save_slot())
	if not loaded.ok:
		return loaded
	return restore_payload(loaded.payload)

func _decode(payload: Dictionary) -> Dictionary:
	var expected_format: String = AREA_FORMAT if _magic != null and _magic.supports_areas() else MAGIC_FORMAT if _magic != null else EFFECT_FORMAT if _effects != null else CONSEQUENCE_FORMAT if _consequences else (COMBAT_FORMAT if _combat != null else FORMAT)
	if _development != null: expected_format = DEVELOPMENT_FORMAT if _origin.is_empty() else "sm2.session.p4.encounter.1"
	var fields: Array[String] = ["format", "catalog", "battle"]
	if _consequences:
		fields.append("result_recorded")
	if not Sm2Validate.fields(payload, fields) or payload.get("format") != expected_format or payload.get("catalog") != _catalog.fingerprint():
		return _failure("incompatible_session")
	if not payload.battle is Dictionary:
		return _failure("battle_shape")
	var candidate: Sm2TacticalBattle = Sm2TacticalBattle.new(_catalog, _combat, _consequences, _effects, _magic, _development, _origin)
	var restored: Dictionary = candidate.restore(payload.battle)
	if not restored.ok:
		return restored
	if _consequences and (not payload.result_recorded is bool or (payload.result_recorded and not candidate.view().finished)):
		return _failure("invalid_outcome_record")
	return {"ok": true, "battle": candidate, "errors": PackedStringArray()}

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([reason])}
