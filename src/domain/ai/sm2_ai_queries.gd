class_name Sm2AiQueries
extends RefCounted
## Detached query projection. Actual RNG, allocator and mutable battle are never retained.
var _state: Sm2TacticalState
var _catalog: Sm2CombatCatalog

func _init(state: Sm2TacticalState, catalog: Sm2CombatCatalog) -> void:
	_state = Sm2TacticalState.new()
	_state.round = state.round
	_state.effect_catalog = state.effect_catalog
	_state.magic_catalog = state.magic_catalog
	if state.development != null: _state.development = state.development.copy()
	for id: int in state.mana: _state.mana[id] = state.mana[id].copy()
	# Retain only availability, never the real allocator value or RNG.
	if state.next_effect_id >= 9223372036854775806: _state.next_effect_id = 9223372036854775806
	for id: int in state.sorted_effect_ids(): _state.effects[id] = state.effects[id].copy()
	_state.field = Sm2Battlefield.new()
	_state.field.build(state.field.to_data())
	for id: int in state.sorted_ids():
		_state.actors[id] = state.actor(id).copy()
	_catalog = catalog

func ability(id: String) -> Sm2CombatAbility:
	return _catalog.ability(id)

func action_info(id: String) -> Dictionary:
	var weapon: Sm2CombatAbility = _catalog.ability(id)
	if weapon != null:
		var data: Dictionary = {"id":weapon.id,"operation":weapon.operation,"ap_cost":weapon.ap_cost,"fatigue_cost":weapon.fatigue_cost,"ammo_cost":weapon.ammo_cost}
		data["kind"] = "weapon"
		data["target_side"] = "self" if weapon.mode == "self" else "enemy"
		return data
	if _state.magic_catalog != null:
		var spell: Sm2SpellDefinition = _state.magic_catalog.spell(id)
		if spell != null:
			var data: Dictionary = spell.to_data()
			data["kind"] = "spell"
			return data
	if _state.effect_catalog != null:
		var effect: Sm2EffectAction = _state.effect_catalog.action(id)
		if effect != null:
			var data: Dictionary = effect.to_data()
			data["kind"] = "effect"
			return data
	return {}

func action(command: Sm2Command, position: Vector2i, positional: bool = false) -> Dictionary:
	var info: Dictionary = action_info(command.ability_id)
	if info.is_empty(): return {"allowed":false,"reason":"ability_unavailable"}
	if info.kind == "weapon":
		if int(info.ammo_cost) > 0 and _state.actor(command.actor_id).combat.item("weapon").ammo < int(info.ammo_cost): return {"allowed":false,"reason":"no_ammunition"}
		return attack(command,position,positional)
	var source: Sm2SpatialActor = _state.actor(command.actor_id).spatial
	var origin: Vector2i = source.position
	var ap: int = source.ap
	var fatigue: int = source.fatigue
	source.position = position
	if positional:
		source.ap = source.ap_max
		source.fatigue = 0
	var result: Dictionary = Sm2SpellResolver.preview(_state,command) if info.kind == "spell" else Sm2EffectResolver.preview(_state,command)
	source.position = origin
	source.ap = ap
	source.fatigue = fatigue
	return result

func effect_assessment(command: Sm2Command, check: Dictionary, budget: Sm2AiWorkBudget, tuning: Dictionary) -> Dictionary:
	return Sm2AiEffectAssessment.assess(_state,_catalog,command,check,budget,tuning)

func threatened(id: int) -> bool:
	return not Sm2AttackResolver.neighbors_threatening(_state,_state.actor(id),_catalog,true).is_empty()

func area_centers(actor_id: int, radius: int, budget: Sm2AiWorkBudget) -> Array[Dictionary]:
	var found: Dictionary = {}
	for id: int in _state.sorted_ids():
		if not budget.spend(): return []
		var target: Sm2TacticalActor = _state.actor(id)
		if not target.spatial.occupies() or target.spatial.side == _state.actor(actor_id).spatial.side: continue
		for cell: Vector2i in Sm2AreaGeometry.disc(_state.field,target.spatial.position,radius):
			if not budget.spend(): return []
			found[cell] = true
	var cells: Array[Vector2i] = []
	cells.assign(found.keys())
	cells.sort_custom(Sm2Hex.numeric_less)
	var result: Array[Dictionary] = []
	for cell: Vector2i in cells: result.append({"area_center":true,"actor_id":0,"side":"area_candidate","q":cell.x,"r":cell.y})
	return result

func has_future_offense(id: int, infos: Array[Dictionary]) -> bool:
	var source: Sm2TacticalActor = _state.actor(id)
	for info: Dictionary in infos:
		if info.target_side != "enemy" or int(info.ap_cost) > source.spatial.ap_max or int(info.fatigue_cost) > source.spatial.fatigue_max: continue
		if info.kind == "spell":
			var profile: Sm2MagicProfile = _state.magic_catalog.profile(source.loadout_id)
			if profile.mana_max >= int(info.mana_cost) and (_state.mana[id].current >= int(info.mana_cost) or profile.mana_per_round > 0): return true
		elif info.kind == "weapon" and info.operation == "damage":
			if int(info.ammo_cost) == 0 or source.combat.item("weapon").ammo >= int(info.ammo_cost): return true
		elif info.kind == "effect" and info.operation == "apply_effect":
			for op: Sm2EffectOperation in _state.effect_catalog.definition(info.effect_id).operations:
				if op.kind == "periodic_hp_damage": return true
	return false

func attack(command: Sm2Command, position: Vector2i, positional: bool = false) -> Dictionary:
	# Only the query projection moves; occupancy contains the attacker exactly once.
	var actor: Sm2TacticalActor = _state.actor(command.actor_id)
	var origin: Vector2i = actor.spatial.position
	actor.spatial.position = position
	var result: Dictionary = Sm2AttackResolver.preview(_state, _catalog, command, false, positional)
	actor.spatial.position = origin
	return result

func routes(actor_id: int, work_limit: int) -> Dictionary:
	var actor: Sm2TacticalActor = _state.actor(actor_id)
	var origin: Vector2i = actor.spatial.position
	var risks: Dictionary = {}
	var work: int = 0
	for q: int in _state.field.width():
		for r: int in _state.field.height():
			work += _state.actors.size()
			if work > work_limit:
				actor.spatial.position = origin
				return {"ok": false, "reason": "ai_query_limit", "cells": []}
			actor.spatial.position = Vector2i(q, r)
			if not Sm2AttackResolver.neighbors_threatening(_state, actor, _catalog, true).is_empty():
				risks[actor.spatial.position] = 1
	actor.spatial.position = origin
	var result: Dictionary = Sm2SpatialQueries.strategic_cells(_state.field, origin, _state.occupancy(), actor.spatial.ap_max, actor.spatial.fatigue_max, risks)
	result["work"] = work
	return result

func step(actor_id: int, target: Vector2i) -> Dictionary:
	return Sm2SpatialQueries.step(_state.field, _state.actor(actor_id).spatial.position, target, _state.occupancy())
