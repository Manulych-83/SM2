class_name Sm2TacticalSnapshot
extends RefCounted
## Rebuilds a detached candidate at a stable turn boundary. Never advances a turn.

const MAX_ACTOR_ID: int = 9223372036854775805
const MORALES: Array[String] = ["steady", "wavering", "breaking", "fleeing"]

static func decode(data: Dictionary, catalog: Sm2TurnCatalog, consequences: bool = false) -> Dictionary:
	if catalog == null:
		return _failure("turn snapshot: catalog is required")
	if not Sm2Validate.fields(data, ["format", "schema_version", "ruleset", "catalog_fingerprint", "battle_id", "scenario_id",
		"field", "field_fingerprint", "round_limit", "round", "revision", "next_actor_id", "actors", "sides",
		"main_queue", "deferred_queue", "phase", "active_actor_id", "finished", "finish_reason", "rng"]):
		return _failure("turn snapshot: missing or unexpected fields")
	if not data.format is String or data.format != "sm2.battle" \
		or not Sm2Validate.integer(data.schema_version, 2, 2) or not data.ruleset is String or data.ruleset != "sm2.m2.turns.1" \
		or not data.catalog_fingerprint is String or data.catalog_fingerprint != catalog.fingerprint():
		return _failure("turn snapshot: incompatible format, schema, ruleset or catalog")
	if not Sm2Validate.text(data.battle_id) or not Sm2Validate.text(data.scenario_id) \
		or not Sm2Validate.integer(data.round_limit, 1, 1000) or not Sm2Validate.decimal(data.round, 1, int(data.round_limit)) \
		or not Sm2Validate.decimal(data.revision) or not Sm2Validate.decimal(data.next_actor_id, 2) \
		or not Sm2Validate.decimal(data.active_actor_id, 0, MAX_ACTOR_ID):
		return _failure("turn snapshot: invalid identity, limits or decimal counters")
	if not data.actors is Array or data.actors.size() < 2 or data.actors.size() > 4096 \
		or not Sm2Validate.string_list(data.sides) or data.sides.size() != 2 or data.sides[0] >= data.sides[1] \
		or not data.main_queue is Array or data.main_queue.size() > data.actors.size() \
		or not data.deferred_queue is Array or data.deferred_queue.size() > data.actors.size() \
		or not data.phase is String or not data.phase in ["main", "deferred", "finished"] \
		or not data.finished is bool or not data.finish_reason is String or not data.finish_reason in (["", "round_limit", "opposition_removed", "mutual_removal"] if consequences else ["", "round_limit", "no_participants"]):
		return _failure("turn snapshot: invalid collections, phase or outcome")
	if not data.rng is Dictionary or not Sm2Validate.fields(data.rng, ["version", "state", "draws"]) \
		or not data.rng.version is String or data.rng.version != Sm2DeterministicRng.VERSION \
		or not Sm2Validate.decimal(data.rng.state, 1, Sm2DeterministicRng.SPAN) or not Sm2Validate.decimal(data.rng.draws):
		return _failure("turn snapshot: invalid RNG")
	if not data.field is Dictionary or not data.field_fingerprint is String:
		return _failure("turn snapshot: invalid field or fingerprint type")
	var field: Sm2Battlefield = Sm2Battlefield.new()
	var field_errors: PackedStringArray = field.build(data.field)
	if not field_errors.is_empty():
		return {"ok": false, "errors": field_errors, "state": null}
	if field.fingerprint() != data.field_fingerprint:
		return _failure("turn snapshot: field fingerprint mismatch")
	var candidate: Sm2TacticalState = Sm2TacticalState.new()
	candidate.consequences = consequences
	candidate.battle_id = data.battle_id
	candidate.scenario_id = data.scenario_id
	candidate.field = field
	candidate.round_limit = int(data.round_limit)
	candidate.round = data.round.to_int()
	candidate.revision = data.revision.to_int()
	candidate.next_actor_id = data.next_actor_id.to_int()
	candidate.sides.assign(data.sides)
	candidate.phase = data.phase
	candidate.finished = data.finished
	candidate.finish_reason = data.finish_reason
	candidate.rng = Sm2DeterministicRng.new()
	candidate.rng.state = data.rng.state.to_int()
	candidate.rng.draws = data.rng.draws.to_int()
	var positions: Dictionary[Vector2i, bool] = {}
	var represented_sides: Dictionary[String, bool] = {}
	var prior_id: int = 0
	for raw: Variant in data.actors:
		if not raw is Dictionary:
			return _failure("turn snapshot: actor must be a dictionary")
		var parsed: Dictionary = _parse_actor(raw, catalog, candidate)
		if not parsed.ok:
			return parsed
		var entry: Sm2TacticalActor = parsed.actor
		var actor_id: int = entry.spatial.actor_id
		if actor_id <= prior_id or actor_id >= candidate.next_actor_id:
			return _failure("turn snapshot: actor IDs must increase and precede next_actor_id")
		if entry.creator > 0 and (entry.creator >= actor_id or not candidate.actors.has(entry.creator)):
			return _failure("turn snapshot: creator must reference an earlier existing actor")
		prior_id = actor_id
		if entry.spatial.occupies():
			if positions.has(entry.spatial.position) or not field.cell(entry.spatial.position).passable:
				return _failure("turn snapshot: occupied positions must be unique and passable")
			positions[entry.spatial.position] = true
		represented_sides[entry.spatial.side] = true
		candidate.actors[actor_id] = entry
	if represented_sides.size() != 2:
		return _failure("turn snapshot: both original sides must be represented")
	var seen: Dictionary[int, bool] = {}
	var main: Dictionary = _parse_queue(data.main_queue, candidate, seen)
	if not main.ok:
		return main
	var deferred: Dictionary = _parse_queue(data.deferred_queue, candidate, seen)
	if not deferred.ok:
		return deferred
	candidate.main_queue.assign(main.queue)
	candidate.deferred_queue.assign(deferred.queue)
	var boundary_error: String = _validate_boundary(candidate, data.active_actor_id.to_int(), seen)
	if not boundary_error.is_empty():
		return _failure(boundary_error)
	return {"ok": true, "errors": PackedStringArray(), "state": candidate}

static func _parse_actor(data: Dictionary, catalog: Sm2TurnCatalog, state: Sm2TacticalState) -> Dictionary:
	if not Sm2Validate.fields(data, ["actor_id", "loadout_id", "side", "owner", "controller", "creator", "q", "r", "ap", "fatigue",
		"alive", "on_field", "morale", "round_fatigue", "round_morale", "initiative", "activation_started", "wait_used", "turn_done", "reactions_left"]):
		return _failure("turn actor: missing or unexpected fields")
	if not Sm2Validate.decimal(data.actor_id, 1, MAX_ACTOR_ID) or not Sm2Validate.decimal(data.creator, 0, MAX_ACTOR_ID) \
		or not Sm2Validate.text(data.loadout_id) or not catalog.has_loadout(data.loadout_id) \
		or not Sm2Validate.text(data.side) or not data.side in state.sides \
		or not Sm2Validate.text(data.owner) or not Sm2Validate.text(data.controller) \
		or not Sm2Validate.integer(data.q, 0, state.field.width() - 1) or not Sm2Validate.integer(data.r, 0, state.field.height() - 1):
		return _failure("turn actor: invalid identity, references, control or position")
	var definition: Sm2TurnDefinition = catalog.definition(data.loadout_id)
	if not Sm2Validate.integer(data.ap, 0, definition.ap_max) or not Sm2Validate.integer(data.fatigue, 0, definition.fatigue_max) \
		or not Sm2Validate.integer(data.round_fatigue, 0, definition.fatigue_max) or not Sm2Validate.integer(data.initiative, 0, 10000) \
		or not Sm2Validate.integer(data.reactions_left, 0, 1) or not data.morale is String or not data.morale in MORALES \
		or not data.round_morale is String or not data.round_morale in MORALES \
		or not data.alive is bool or not data.on_field is bool or not data.activation_started is bool \
		or not data.wait_used is bool or not data.turn_done is bool:
		return _failure("turn actor: invalid resources, round anchors or flags")
	if int(data.fatigue) < int(data.round_fatigue) or (MORALES.find(data.morale) < MORALES.find(data.round_morale) if state.consequences else data.morale != data.round_morale) \
		or int(data.initiative) != Sm2TurnScheduler.compute_initiative(definition, int(data.round_fatigue), data.round_morale):
		return _failure("turn actor: inconsistent round anchors or initiative")
	if (data.wait_used and (not data.activation_started or (data.round_morale == "fleeing" if state.consequences else data.morale == "fleeing"))) \
		or (data.turn_done and int(data.ap) != 0) or ((not data.alive or not data.on_field) and int(data.reactions_left) != 0):
		return _failure("turn actor: inconsistent wait, completion or reaction flags")
	var entry: Sm2TacticalActor = Sm2TacticalActor.new()
	entry.spatial = Sm2SpatialActor.new()
	entry.spatial.actor_id = data.actor_id.to_int()
	entry.spatial.side = data.side
	entry.spatial.owner = data.owner
	entry.spatial.controller = data.controller
	entry.spatial.position = Vector2i(int(data.q), int(data.r))
	entry.spatial.ap_max = definition.ap_max
	entry.spatial.ap = int(data.ap)
	entry.spatial.fatigue_max = definition.fatigue_max
	entry.spatial.fatigue = int(data.fatigue)
	entry.spatial.alive = data.alive
	entry.spatial.on_field = data.on_field
	entry.loadout_id = data.loadout_id
	entry.creator = data.creator.to_int()
	entry.morale = data.morale
	entry.round_fatigue = int(data.round_fatigue)
	entry.round_morale = data.round_morale
	entry.initiative = int(data.initiative)
	entry.activation_started = data.activation_started
	entry.wait_used = data.wait_used
	entry.turn_done = data.turn_done
	entry.reactions_left = int(data.reactions_left)
	return {"ok": true, "errors": PackedStringArray(), "actor": entry}

static func _parse_queue(raw: Array, state: Sm2TacticalState, seen: Dictionary[int, bool]) -> Dictionary:
	var queue: Array[int] = []
	var prior: Sm2TacticalActor = null
	for raw_id: Variant in raw:
		if not Sm2Validate.decimal(raw_id, 1, MAX_ACTOR_ID):
			return _failure("turn snapshot: queue IDs must be canonical decimal strings")
		var actor_id: int = raw_id.to_int()
		var entry: Sm2TacticalActor = state.actor(actor_id)
		if entry == null or seen.has(actor_id):
			return _failure("turn snapshot: missing, duplicate or intersecting queue actor")
		if not entry.spatial.occupies() or entry.spatial.ap <= 0:
			return _failure("turn snapshot: queued actor must be available with positive AP")
		if prior != null and not _earlier(prior, entry):
			return _failure("turn snapshot: queue is not ordered by saved initiative and numeric ID")
		seen[actor_id] = true
		queue.append(actor_id)
		prior = entry
	return {"ok": true, "errors": PackedStringArray(), "queue": queue}

static func _validate_boundary(state: Sm2TacticalState, active_actor_id: int, queued: Dictionary[int, bool]) -> String:
	var available_count: int = 0
	var main_ids: Dictionary[int, bool] = {}
	for actor_id: int in state.main_queue:
		main_ids[actor_id] = true
		var entry: Sm2TacticalActor = state.actor(actor_id)
		if entry.wait_used or entry.turn_done or entry.activation_started != (actor_id == active_actor_id):
			return "turn snapshot: inconsistent main activation flags"
	for actor_id: int in state.deferred_queue:
		var entry: Sm2TacticalActor = state.actor(actor_id)
		if not entry.wait_used or not entry.activation_started or entry.turn_done:
			return "turn snapshot: inconsistent deferred activation flags"
	for actor_id: int in state.actors:
		var entry: Sm2TacticalActor = state.actor(actor_id)
		if entry.spatial.occupies():
			available_count += 1
		if not queued.has(actor_id):
			if not entry.turn_done or entry.spatial.ap != 0 or (entry.spatial.occupies() and not entry.activation_started and not (state.consequences and state.finished)):
				return "turn snapshot: actor outside queues must have completed its turn"
	if state.finished:
		if state.phase != "finished" or active_actor_id != 0 or not queued.is_empty():
			return "turn snapshot: finished state still has an activation"
		if state.consequences and state.finish_reason in ["opposition_removed", "mutual_removal"]:
			return ""
		if state.finish_reason == "round_limit" and state.round == state.round_limit:
			return ""
		if state.finish_reason == "no_participants" and available_count == 0:
			return ""
		return "turn snapshot: inconsistent finish reason"
	if not state.finish_reason.is_empty() or available_count == 0:
		return "turn snapshot: unfinished state has an outcome or no participants"
	if state.phase == "main":
		if state.main_queue.is_empty() or active_actor_id != state.main_queue[0]:
			return "turn snapshot: main active actor must be its queue head"
		var active: Sm2TacticalActor = state.actor(active_actor_id)
		for actor_id: int in state.actors:
			var entry: Sm2TacticalActor = state.actor(actor_id)
			if entry.spatial.occupies() and entry.wait_used and entry.turn_done:
				return "turn snapshot: a waiter cannot complete before the deferred phase"
			if entry.spatial.occupies() and not main_ids.has(actor_id) and not _earlier(entry, active):
				return "turn snapshot: main queue must be the remaining suffix of round order"
	elif state.phase == "deferred":
		if not state.main_queue.is_empty() or state.deferred_queue.is_empty() or active_actor_id != state.deferred_queue[0]:
			return "turn snapshot: deferred active actor must be its queue head after main"
		var active: Sm2TacticalActor = state.actor(active_actor_id)
		for actor_id: int in state.actors:
			var entry: Sm2TacticalActor = state.actor(actor_id)
			if entry.spatial.occupies() and entry.wait_used and not queued.has(actor_id) and not _earlier(entry, active):
				return "turn snapshot: deferred queue must be the remaining suffix of waiter order"
	else:
		return "turn snapshot: unfinished state must be in main or deferred phase"
	return ""

static func _earlier(left: Sm2TacticalActor, right: Sm2TacticalActor) -> bool:
	if left.initiative != right.initiative:
		return left.initiative > right.initiative
	return left.spatial.actor_id < right.spatial.actor_id

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message]), "state": null}
