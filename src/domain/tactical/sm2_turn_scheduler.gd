class_name Sm2TurnScheduler
extends RefCounted
## Deterministic transitions on a caller-owned, validated candidate.
## The battle coordinator owns revision, transactions and RNG; this class does not.

static func compute_initiative(definition: Sm2TurnDefinition, fatigue: int, morale: String) -> int:
	if definition == null:
		return 0
	var percentage: int = 100
	match morale:
		"wavering": percentage = 90
		"breaking": percentage = 80
	var unloaded: int = definition.initiative_base - definition.load_penalty
	if fatigue < 0 or fatigue >= unloaded:
		return 0
	var available: int = unloaded - fatigue
	@warning_ignore("integer_division")
	var initiative: int = available * percentage / 100
	return initiative

static func start_round(state: Sm2TacticalState, catalog: Sm2TurnCatalog, events: Array[Dictionary]) -> void:
	if state == null or catalog == null or state.finished:
		return
	if not _has_participants(state):
		_finish(state, "no_participants", events)
		return
	if state.round >= state.round_limit:
		_finish(state, "round_limit", events)
		return
	state.round += 1
	state.phase = "main"
	state.main_queue.clear()
	state.deferred_queue.clear()
	events.append({"type": "round_started", "round": str(state.round)})
	for id: int in state.sorted_ids():
		var entry: Sm2TacticalActor = state.actor(id)
		var definition: Sm2TurnDefinition = catalog.definition(entry.loadout_id)
		entry.wait_used = false
		entry.activation_started = false
		if entry.combat != null:
			entry.combat.shieldwall_used = false
		entry.turn_done = not entry.spatial.occupies()
		if entry.spatial.occupies():
			var previous_fatigue: int = entry.spatial.fatigue
			entry.spatial.ap = entry.spatial.ap_max
			entry.spatial.fatigue = maxi(0, previous_fatigue - 15)
			entry.reactions_left = 1
			Sm2ManaResolver.recover_round(state,id,events)
			state.main_queue.append(id)
			events.append({"type": "round_resources", "actor_id": str(id), "ap": entry.spatial.ap,
				"fatigue": entry.spatial.fatigue, "restored_fatigue": previous_fatigue - entry.spatial.fatigue})
		else:
			entry.spatial.ap = 0
			entry.reactions_left = 0
		entry.round_fatigue = entry.spatial.fatigue
		entry.round_morale = entry.morale
		entry.initiative = compute_initiative(definition, entry.round_fatigue, entry.round_morale)
	_sort_queue(state.main_queue, state)
	_activate_head(state, events)

static func advance(state: Sm2TacticalState, catalog: Sm2TurnCatalog, events: Array[Dictionary]) -> void:
	if state == null or catalog == null or state.finished:
		return
	for id: int in state.sorted_ids():
		var entry: Sm2TacticalActor = state.actor(id)
		if not entry.spatial.occupies():
			entry.spatial.ap = 0
			entry.turn_done = true
			entry.reactions_left = 0
	_prune_unavailable(state.main_queue, state)
	_prune_unavailable(state.deferred_queue, state)
	if not _has_participants(state):
		_finish(state, "no_participants", events)
		return
	while true:
		if state.phase == "main" and not state.main_queue.is_empty():
			pass
		elif not state.deferred_queue.is_empty():
			state.phase = "deferred"
		else:
			start_round(state, catalog, events)
			return
		var active: Sm2TacticalActor = state.actor(state.active_id())
		_activate_head(state, events)
		if active.spatial.ap > 0:
			return
		# Defensive completion if an earlier effect exhausted a pending actor.
		_end_head(state, active, events, true)

static func wait_active(state: Sm2TacticalState, catalog: Sm2TurnCatalog, events: Array[Dictionary]) -> void:
	if state == null or catalog == null or state.finished or state.phase != "main":
		return
	var active: Sm2TacticalActor = state.actor(state.active_id())
	if active == null or not active.spatial.occupies() or active.morale == "fleeing" \
		or active.spatial.ap <= 0 or active.wait_used or not active.activation_started:
		return
	var id: int = active.spatial.actor_id
	state.main_queue.erase(id)
	active.wait_used = true
	state.deferred_queue.append(id)
	_sort_queue(state.deferred_queue, state)
	events.append({"type": "actor_waited", "actor_id": str(id)})
	advance(state, catalog, events)

static func finish_active(state: Sm2TacticalState, events: Array[Dictionary], automatic: bool) -> void:
	# Exposes the existing end boundary without starting the next activation.
	_end_head(state, state.actor(state.active_id()), events, automatic)

static func end_active(state: Sm2TacticalState, catalog: Sm2TurnCatalog, events: Array[Dictionary], automatic: bool = false) -> void:
	if state == null or catalog == null or state.finished:
		return
	var active: Sm2TacticalActor = state.actor(state.active_id())
	if active == null:
		return
	_end_head(state, active, events, automatic)
	advance(state, catalog, events)

static func after_action(state: Sm2TacticalState, catalog: Sm2TurnCatalog, events: Array[Dictionary]) -> void:
	if state == null or catalog == null or state.finished:
		return
	var active: Sm2TacticalActor = state.actor(state.active_id())
	if active == null or not active.spatial.occupies():
		advance(state, catalog, events)
	elif active.spatial.ap <= 0:
		end_active(state, catalog, events, true)
	# AP>0 preserves the current activation and emits no duplicate continuation.

static func _activate_head(state: Sm2TacticalState, events: Array[Dictionary]) -> void:
	var active: Sm2TacticalActor = state.actor(state.active_id())
	if active == null:
		return
	if state.phase == "deferred":
		events.append({"type": "activation_resumed", "actor_id": str(active.spatial.actor_id)})
	elif not active.activation_started:
		active.activation_started = true
		Sm2BarrierRules.expire(active,state.round,events)
		if active.combat != null and active.combat.shieldwall_source != 0 and active.combat.shieldwall_until_round <= state.round:
			var source_id: int = active.combat.shieldwall_source
			active.combat.clear_wall()
			events.append({"type": "shieldwall_expired", "actor_id": str(active.spatial.actor_id), "item_id": str(source_id)})
		events.append({"type": "activation_started", "actor_id": str(active.spatial.actor_id)})

static func _end_head(state: Sm2TacticalState, active: Sm2TacticalActor, events: Array[Dictionary], automatic: bool) -> void:
	var id: int = active.spatial.actor_id
	active.spatial.ap = 0
	active.turn_done = true
	if state.phase == "main":
		state.main_queue.erase(id)
	else:
		state.deferred_queue.erase(id)
	events.append({"type": "turn_ended", "actor_id": str(id), "automatic": automatic})

static func _prune_unavailable(queue: Array[int], state: Sm2TacticalState) -> void:
	var retained: Array[int] = []
	for id: int in queue:
		var entry: Sm2TacticalActor = state.actor(id)
		if entry != null and entry.spatial.occupies():
			retained.append(id)
		elif entry != null:
			entry.spatial.ap = 0
			entry.turn_done = true
			entry.reactions_left = 0
	queue.assign(retained)

static func _sort_queue(queue: Array[int], state: Sm2TacticalState) -> void:
	queue.sort_custom(func(left: int, right: int) -> bool:
		var left_i: int = state.actor(left).initiative
		var right_i: int = state.actor(right).initiative
		return left_i > right_i if left_i != right_i else left < right)

static func _has_participants(state: Sm2TacticalState) -> bool:
	for id: int in state.sorted_ids():
		if state.actor(id).spatial.occupies():
			return true
	return false

static func _finish(state: Sm2TacticalState, reason: String, events: Array[Dictionary]) -> void:
	state.finished = true
	state.phase = "finished"
	state.finish_reason = reason
	state.main_queue.clear()
	state.deferred_queue.clear()
	for id: int in state.sorted_ids():
		var entry: Sm2TacticalActor = state.actor(id)
		entry.spatial.ap = 0
		entry.turn_done = true
		if not entry.spatial.occupies():
			entry.reactions_left = 0
	events.append({"type": "round_limit_reached" if reason == "round_limit" else "no_participants", "round": str(state.round)})
