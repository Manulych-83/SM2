class_name Sm2FieldSession
extends RefCounted
## M2.1 spatial rehearsal: a fixed active actor, no invented turn or combat rules.
## The movement resolver and queries are reusable by the subsequent battle coordinator.
const FORMAT: String = "sm2.field_probe"
const RULESET: String = "sm2.m2.spatial.1"
var _field: Sm2Battlefield = null
var _actors: Dictionary[int, Sm2SpatialActor] = {}
var _active_id: int = 0
var _revision: int = 0
var _rng: Sm2DeterministicRng = Sm2DeterministicRng.new()

func start(field: Sm2Battlefield, actors: Array[Dictionary], active_id: int, seed_value: int = 1) -> Dictionary:
	if field == null or field.to_data().is_empty():
		return _failure("invalid_field")
	var candidate_field: Sm2Battlefield = Sm2Battlefield.new()
	var errors: PackedStringArray = candidate_field.build(field.to_data())
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	if actors.is_empty() or actors.size() > 4096:
		return _failure("actor_count")
	var candidate_actors: Dictionary[int, Sm2SpatialActor] = {}
	var occupied: Dictionary[Vector2i, bool] = {}
	for raw: Dictionary in actors:
		var decoded: Dictionary = Sm2SpatialActor.decode(raw)
		if not decoded.ok:
			return _failure(decoded.reason)
		var actor: Sm2SpatialActor = decoded.actor
		if candidate_actors.has(actor.actor_id):
			return _failure("duplicate_actor_id")
		if not candidate_field.in_bounds(actor.position):
			return _failure("actor_out_of_bounds")
		if actor.occupies():
			if not candidate_field.cell(actor.position).passable:
				return _failure("actor_impassable")
			if occupied.has(actor.position):
				return _failure("duplicate_occupied_position")
			occupied[actor.position] = true
		candidate_actors[actor.actor_id] = actor
	if not candidate_actors.has(active_id) or not candidate_actors[active_id].occupies():
		return _failure("invalid_active_actor")
	_field = candidate_field
	_actors = candidate_actors
	_active_id = active_id
	_revision = 0
	_rng = Sm2DeterministicRng.new(seed_value)
	return {"ok": true, "errors": PackedStringArray()}

func preview(command: Sm2Command) -> Dictionary:
	var reason: String = _validate_command(command)
	if not reason.is_empty():
		return {"allowed": false, "reason": reason, "ap_cost": 0, "fatigue_cost": 0}
	return Sm2MovementResolver.preview(_field, _actors[_active_id], _occupancy(), command)

func execute(command: Sm2Command) -> Sm2CommandResult:
	var result: Sm2CommandResult = Sm2CommandResult.new()
	result.revision = _revision
	var check: Dictionary = preview(command)
	if not check.allowed:
		result.code = check.reason
		return result
	var resolved: Dictionary = Sm2MovementResolver.resolve(_field, _actors[_active_id], _occupancy(), command)
	if not resolved.accepted:
		result.code = resolved.code
		return result
	# Publish once. Neither the returned actor nor events are live session references.
	_actors[_active_id] = resolved.actor
	_revision += 1
	result.accepted = true
	result.code = resolved.code
	result.revision = _revision
	result.events.assign(resolved.events.duplicate(true))
	for index: int in result.events.size():
		result.events[index]["revision"] = str(_revision)
		result.events[index]["sequence"] = index
	return result

func reachable(actor_id: int) -> Dictionary:
	if not _available(actor_id):
		return {"ok": false, "reason": "actor_unavailable", "cells": []}
	var actor: Sm2SpatialActor = _actors[actor_id]
	return Sm2SpatialQueries.reachable(_field, actor.position, _occupancy(), actor.ap, actor.fatigue_max - actor.fatigue)

func route(actor_id: int, target: Vector2i) -> Dictionary:
	if not _available(actor_id):
		return {"ok": false, "reason": "actor_unavailable", "path": [], "ap_cost": 0, "fatigue_cost": 0}
	var actor: Sm2SpatialActor = _actors[actor_id]
	return Sm2SpatialQueries.route(_field, actor.position, target, _occupancy(), actor.ap_max, actor.fatigue_max)

func line_of_sight(from_actor_id: int, to_actor_id: int) -> Dictionary:
	if not _available(from_actor_id) or not _available(to_actor_id):
		return {"ok": false, "reason": "actor_unavailable", "visible": false, "cells": [], "blockers": []}
	return Sm2SpatialQueries.los(_field, _actors[from_actor_id].position, _actors[to_actor_id].position, _occupancy())

func view() -> Dictionary:
	if _field == null:
		return {}
	var actors: Array[Dictionary] = []
	for actor_id: int in _sorted_ids():
		actors.append(_actors[actor_id].view())
	return {"ruleset": RULESET, "revision": _revision, "active_actor_id": _active_id,
		"field": _field.to_data(), "actors": actors}

func capture() -> Dictionary:
	if _field == null:
		return {}
	var actors: Array[Dictionary] = []
	for actor_id: int in _sorted_ids():
		actors.append(_actors[actor_id].to_data())
	return {"format": FORMAT, "schema_version": 1, "ruleset": RULESET,
		"revision": str(_revision), "active_actor_id": str(_active_id),
		"field": _field.to_data(), "field_fingerprint": _field.fingerprint(), "actors": actors,
		"rng": {"version": Sm2DeterministicRng.VERSION, "state": str(_rng.state), "draws": str(_rng.draws)}}

func state_hash() -> String:
	return Sm2Canonical.hash(capture())

func _validate_command(command: Sm2Command) -> String:
	if _field == null:
		return "not_started"
	if command == null:
		return "invalid_command"
	if command.expected_revision != _revision:
		return "stale_revision"
	if _revision >= 9223372036854775806:
		return "counter_limit"
	if command.actor_id != _active_id:
		return "not_active_actor"
	return ""

func _available(actor_id: int) -> bool:
	return _field != null and _actors.has(actor_id) and _actors[actor_id].occupies()

func _occupancy() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for actor_id: int in _sorted_ids():
		if _actors[actor_id].occupies():
			result.append(_actors[actor_id].position)
	return result

func _sorted_ids() -> Array[int]:
	var result: Array[int] = []
	result.assign(_actors.keys())
	result.sort()
	return result

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([reason])}
