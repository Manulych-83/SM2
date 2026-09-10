class_name Sm2TestTurnScheduler
extends RefCounted

static func run(t: Sm2TestHarness) -> void:
	_actor_model(t)
	_initial_round(t)
	_wait_and_resources(t)
	_all_wait_and_last_wait(t)
	_initiative_and_next_round(t)
	_automatic_and_unavailable(t)
	_finish(t)
	_copies_and_snapshot(t)
	t.complete_suite("turn_scheduler")

static func _actor_model(t: Sm2TestHarness) -> void:
	var catalog: Sm2TurnCatalog = _catalog(t)
	var raw: Dictionary = _spawn(1, "spear", Vector2i(1, 1), "company")
	raw.fatigue = 16
	var parsed: Dictionary = Sm2TacticalActor.from_setup(raw, catalog)
	t.expect(parsed.ok, "actor: valid setup")
	var actor: Sm2TacticalActor = parsed.actor
	t.equal(actor.spatial.ap_max, 9, "actor: AP maximum from profile")
	t.equal(actor.spatial.fatigue_max, 65, "actor: equipment load determines fatigue maximum")
	t.equal(actor.spatial.ap, 0, "actor: no AP issuance before round starts")
	t.equal(actor.spatial.fatigue, 16, "actor: setup fatigue is pre-recovery")
	t.equal(actor.round_fatigue, 16, "actor: unpublished initial anchor")
	var before: String = Sm2Canonical.hash(actor.to_data())
	raw.q = 3
	var view: Dictionary = actor.view()
	view.fatigue = 0
	view.actor_id = 999
	var data: Dictionary = actor.to_data()
	data.side = "changed"
	t.equal(Sm2Canonical.hash(actor.to_data()), before, "actor: setup/view/data detached")
	t.expect(not actor.to_data().has("ap_max") and not actor.to_data().has("fatigue_max"), "actor: snapshot derives limits from catalog")
	t.expect(actor.to_data().actor_id is String and actor.view().actor_id is int, "actor: snapshot IDs exact strings and view IDs int")
	var malformed: Array[Dictionary] = []
	var bad: Dictionary = _spawn(1, "spear", Vector2i(1, 1), "company")
	bad.fatigue = 66
	malformed.append(bad)
	bad = _spawn(1, "spear", Vector2i(1, 1), "company")
	bad.fatigue = 1.5
	malformed.append(bad)
	bad = _spawn(1, "absent", Vector2i(1, 1), "company")
	malformed.append(bad)
	bad = _spawn(1, "spear", Vector2i(1, 1), "company")
	bad.creator = 1
	malformed.append(bad)
	bad = _spawn(1, "spear", Vector2i(1, 1), "company")
	bad.morale = "happy"
	malformed.append(bad)
	bad = _spawn(1, "spear", Vector2i(1, 1), "company")
	bad.alive = 1
	malformed.append(bad)
	bad = _spawn(1, "spear", Vector2i(1, 1), "company")
	bad.actor_id = "1"
	malformed.append(bad)
	bad = _spawn(1, "spear", Vector2i(1, 1), "company")
	bad.q = -1
	malformed.append(bad)
	bad = _spawn(1, "spear", Vector2i(1, 1), "company")
	bad.erase("owner")
	malformed.append(bad)
	for index: int in malformed.size():
		t.expect(not Sm2TacticalActor.from_setup(malformed[index], catalog).ok, "actor: rejects malformed setup %d" % index)
	t.expect(not Sm2TacticalActor.from_setup(_spawn(1, "spear", Vector2i.ONE, "company"), null).ok, "actor: rejects missing catalog")

static func _initial_round(t: Sm2TestHarness) -> void:
	var catalog: Sm2TurnCatalog = _catalog(t)
	var state: Sm2TacticalState = _state(t, catalog)
	var events: Array[Dictionary] = []
	var rng: Dictionary = state.to_data(catalog.fingerprint()).rng
	Sm2TurnScheduler.start_round(state, catalog, events)
	t.equal(state.round, 1, "round: starts at one")
	t.equal(state.main_queue, [3, 6, 2, 4, 1, 5], "round: six-person initiative oracle")
	t.equal(state.deferred_queue, [], "round: no initial deferred participants")
	t.equal(state.phase, "main", "round: published phase is main")
	t.equal(state.active_id(), 3, "round: first archer active")
	var initiatives: Array[int] = [75, 88, 104, 79, 75, 104]
	var fatigue_maxima: Array[int] = [65, 73, 74, 64, 65, 74]
	for id: int in state.sorted_ids():
		var actor: Sm2TacticalActor = state.actor(id)
		t.equal(actor.initiative, initiatives[id - 1], "round: per-actor initiative %d" % id)
		t.equal(actor.spatial.fatigue_max, fatigue_maxima[id - 1], "round: independent loadout limit %d" % id)
		t.equal(actor.spatial.ap, 9, "round: resources issued to all, including not yet active %d" % id)
		t.equal(actor.reactions_left, 1, "round: one reaction credit stored without simulating reactions %d" % id)
		t.equal(actor.activation_started, id == 3, "round: only first activation started %d" % id)
		t.expect(not actor.wait_used and not actor.turn_done, "round: flags reset %d" % id)
	t.equal(_types(events), ["round_started", "round_resources", "round_resources", "round_resources", "round_resources", "round_resources", "round_resources", "activation_started"], "round: resources precede first activation")
	for index: int in 6:
		t.equal(events[index + 1].actor_id, str(index + 1), "round: resource event IDs numeric-ordered")
	t.equal(state.to_data(catalog.fingerprint()).rng, rng, "round: scheduler never consumes RNG")
	t.equal(state.revision, 0, "round: coordinator owns revision")
	t.equal(state.next_actor_id, 7, "round: scheduler allocates no actors")

static func _wait_and_resources(t: Sm2TestHarness) -> void:
	var catalog: Sm2TurnCatalog = _catalog(t)
	var state: Sm2TacticalState = _state(t, catalog)
	var events: Array[Dictionary] = []
	Sm2TurnScheduler.start_round(state, catalog, events)
	state.actor(3).spatial.ap = 5
	state.actor(3).spatial.fatigue = 20
	events.clear()
	Sm2TurnScheduler.after_action(state, catalog, events)
	t.equal(events, [], "wait: ordinary action with AP remaining emits no scheduler events")
	Sm2TurnScheduler.wait_active(state, catalog, events)
	t.equal(state.main_queue, [6, 2, 4, 1, 5], "wait: active removed from main")
	t.equal(state.deferred_queue, [3], "wait: active moved to deferred")
	t.equal(state.active_id(), 6, "wait: next main participant receives control")
	t.equal(state.actor(3).spatial.ap, 5, "wait: AP preserved")
	t.equal(state.actor(3).spatial.fatigue, 20, "wait: fatigue preserved")
	t.expect(state.actor(3).activation_started and state.actor(3).wait_used and not state.actor(3).turn_done, "wait: continuation flags persisted")
	t.equal(_types(events), ["actor_waited", "activation_started"], "wait: transition events")
	for index: int in 5:
		Sm2TurnScheduler.end_active(state, catalog, events)
	t.equal(state.phase, "deferred", "wait: switches after main exhaustion")
	t.equal(state.active_id(), 3, "wait: original active resumes")
	t.equal(state.actor(3).spatial.ap, 5, "wait: continuation never reissues AP")
	t.equal(state.actor(3).spatial.fatigue, 20, "wait: continuation never recovers fatigue")
	t.equal(_count(events, "activation_resumed"), 1, "wait: one explicit continuation")
	events.clear()
	state.actor(3).spatial.ap = 3
	state.actor(3).spatial.fatigue = 24
	Sm2TurnScheduler.after_action(state, catalog, events)
	t.equal(events, [], "wait: movement in deferred does not emit repeated resume")
	var before: String = _hash(state, catalog)
	Sm2TurnScheduler.wait_active(state, catalog, events)
	t.equal(_hash(state, catalog), before, "wait: second Wait is inert")
	t.equal(events, [], "wait: invalid repeated Wait emits nothing")
	Sm2TurnScheduler.end_active(state, catalog, events)
	t.equal(state.round, 2, "wait: completing last deferred starts next round")
	t.equal(state.actor(3).spatial.ap, 9, "wait: new round grants AP exactly once")
	t.equal(state.actor(3).spatial.fatigue, 9, "wait: 24 fatigue minus 15 at new round")
	t.expect(not state.actor(3).wait_used, "wait: permission resets only in new round")
	t.equal(_count(events, "round_started"), 1, "wait: a single new-round event")

static func _all_wait_and_last_wait(t: Sm2TestHarness) -> void:
	var catalog: Sm2TurnCatalog = _catalog(t)
	var state: Sm2TacticalState = _state(t, catalog)
	var events: Array[Dictionary] = []
	Sm2TurnScheduler.start_round(state, catalog, events)
	events.clear()
	var expected: Array[int] = [3, 6, 2, 4, 1, 5]
	for id: int in expected:
		t.equal(state.active_id(), id, "all Wait: stable main order")
		Sm2TurnScheduler.wait_active(state, catalog, events)
	t.equal(state.main_queue, [], "all Wait: main drained")
	t.equal(state.deferred_queue, expected, "all Wait: deferred sorted by frozen I then ID")
	t.equal(state.phase, "deferred", "all Wait: no empty intermediate phase published")
	t.equal(state.active_id(), 3, "all Wait: first deferred resumed")
	t.equal(_count(events, "actor_waited"), 6, "all Wait: once per actor")
	t.equal(_count(events, "round_resources"), 0, "all Wait: no additional recovery")
	t.equal(_count(events, "activation_resumed"), 1, "all Wait: only current deferred resumed")
	for id: int in expected:
		t.equal(state.active_id(), id, "all Wait: stable deferred order")
		Sm2TurnScheduler.end_active(state, catalog, events)
	t.equal(state.round, 2, "all Wait: exactly one round completed")
	t.equal(_count(events, "activation_resumed"), 6, "all Wait: one continuation per waited actor")
	state = _state(t, catalog)
	events.clear()
	Sm2TurnScheduler.start_round(state, catalog, events)
	for index: int in 5:
		Sm2TurnScheduler.end_active(state, catalog, events)
	t.equal(state.active_id(), 5, "last Wait: only final main participant remains")
	events.clear()
	Sm2TurnScheduler.wait_active(state, catalog, events)
	t.equal(state.active_id(), 5, "last Wait: immediately resumes same actor")
	t.equal(state.phase, "deferred", "last Wait: genuine phase transition")
	t.equal(state.actor(5).spatial.ap, 9, "last Wait: AP unchanged")
	t.equal(_types(events), ["actor_waited", "activation_resumed"], "last Wait: no duplicate activation start")
	state = _state(t, catalog)
	state.actor(3).morale = "fleeing"
	events.clear()
	Sm2TurnScheduler.start_round(state, catalog, events)
	events.clear()
	var before: String = _hash(state, catalog)
	Sm2TurnScheduler.wait_active(state, catalog, events)
	t.equal(_hash(state, catalog), before, "fleeing Wait: rejected without touching state")
	t.equal(events, [], "fleeing Wait: no event")

static func _initiative_and_next_round(t: Sm2TestHarness) -> void:
	var catalog: Sm2TurnCatalog = _catalog(t)
	var definition: Sm2TurnDefinition = catalog.definition("sword")
	t.equal(Sm2TurnScheduler.compute_initiative(definition, 0, "steady"), 88, "initiative: base minus equipment")
	t.equal(Sm2TurnScheduler.compute_initiative(definition, 1, "wavering"), 78, "initiative: floor 87*90/100")
	t.equal(Sm2TurnScheduler.compute_initiative(definition, 1, "breaking"), 69, "initiative: floor 87*80/100")
	t.equal(Sm2TurnScheduler.compute_initiative(definition, 1, "fleeing"), 87, "initiative: fleeing uses 100 percent")
	t.equal(Sm2TurnScheduler.compute_initiative(definition, 9223372036854775807, "steady"), 0, "initiative: clamp before unsafe subtraction")
	var low: Sm2TurnDefinition = Sm2TurnDefinition.new()
	low.initiative_base = 3
	low.load_penalty = 5
	t.equal(Sm2TurnScheduler.compute_initiative(low, 0, "wavering"), 0, "initiative: negative base clamps to zero")
	var state: Sm2TacticalState = _state(t, catalog)
	state.actor(1).spatial.fatigue = 14
	state.actor(2).spatial.fatigue = 15
	state.actor(3).spatial.fatigue = 16
	state.actor(4).spatial.fatigue = 35
	var events: Array[Dictionary] = []
	Sm2TurnScheduler.start_round(state, catalog, events)
	t.equal(state.actor(1).spatial.fatigue, 0, "recovery: below 15 clamps at zero")
	t.equal(state.actor(2).spatial.fatigue, 0, "recovery: exactly 15 becomes zero")
	t.equal(state.actor(3).spatial.fatigue, 1, "recovery: 16 becomes one")
	t.equal(state.actor(4).spatial.fatigue, 20, "recovery: only fifteen recovered")
	t.equal(events[1].restored_fatigue, 14, "recovery: event reports actual recovered amount")
	t.equal(state.actor(3).round_fatigue, 1, "initiative: anchor captured after recovery")
	t.equal(state.main_queue, [6, 3, 2, 1, 5, 4], "initiative: first round uses recovered resources")
	state = _state(t, catalog)
	events.clear()
	Sm2TurnScheduler.start_round(state, catalog, events)
	state.actor(3).spatial.fatigue = 35
	t.equal(state.actor(3).initiative, 104, "initiative: accumulated fatigue does not change frozen I")
	t.equal(state.main_queue, [3, 6, 2, 4, 1, 5], "initiative: queue stable during round")
	for index: int in 6:
		Sm2TurnScheduler.end_active(state, catalog, events)
	t.equal(state.round, 2, "initiative: completes round")
	t.equal(state.actor(3).round_fatigue, 20, "initiative: next anchor uses recovery once")
	t.equal(state.actor(3).initiative, 84, "initiative: next round recalculates I")
	t.equal(state.main_queue, [6, 2, 3, 4, 1, 5], "initiative: next round has new stable order")
	var tie: Sm2TacticalState = _state(t, catalog, [10, 2])
	Sm2TurnScheduler.start_round(tie, catalog, events)
	t.equal(tie.main_queue, [2, 10], "initiative: equal values use numeric ID, not insertion or text order")

static func _automatic_and_unavailable(t: Sm2TestHarness) -> void:
	var catalog: Sm2TurnCatalog = _catalog(t)
	var state: Sm2TacticalState = _state(t, catalog)
	var events: Array[Dictionary] = []
	Sm2TurnScheduler.start_round(state, catalog, events)
	state.actor(3).spatial.ap = 0
	state.actor(3).spatial.fatigue = 18
	events.clear()
	Sm2TurnScheduler.after_action(state, catalog, events)
	t.equal(state.active_id(), 6, "automatic: zero AP passes activation")
	t.expect(state.actor(3).turn_done, "automatic: exhausted participant completed")
	t.equal(state.actor(3).spatial.fatigue, 18, "automatic: end does not recover fatigue")
	t.equal(events[0], {"type": "turn_ended", "actor_id": "3", "automatic": true}, "automatic: end event identifies automatic transition")
	state = _state(t, catalog)
	state.actor(3).spatial.alive = false
	state.actor(6).spatial.on_field = false
	state.actor(3).spatial.fatigue = 30
	events.clear()
	Sm2TurnScheduler.start_round(state, catalog, events)
	t.equal(state.main_queue, [2, 4, 1, 5], "unavailable: dead and escaped omitted initially")
	for id: int in [3, 6]:
		t.equal(state.actor(id).spatial.ap, 0, "unavailable: no AP grant")
		t.equal(state.actor(id).reactions_left, 0, "unavailable: no reaction grant")
		t.expect(state.actor(id).turn_done and not state.actor(id).activation_started, "unavailable: done without fabricated activation")
	t.equal(state.actor(3).spatial.fatigue, 30, "unavailable: no recovery outside participation")
	t.equal(state.occupancy().size(), 4, "unavailable: occupancy uses same presence rule")
	state = _state(t, catalog)
	events.clear()
	Sm2TurnScheduler.start_round(state, catalog, events)
	Sm2TurnScheduler.wait_active(state, catalog, events)
	state.actor(3).spatial.alive = false
	state.actor(6).spatial.on_field = false
	events.clear()
	Sm2TurnScheduler.after_action(state, catalog, events)
	t.equal(state.active_id(), 2, "unavailable: removes current departed actor")
	t.equal(state.deferred_queue, [], "unavailable: removes a dead waiting actor")
	t.equal(state.actor(3).reactions_left, 0, "unavailable: waiting actor reaction credit cleared")
	t.equal(state.actor(6).spatial.ap, 0, "unavailable: current departed actor AP cleared")
	t.equal(_types(events), ["activation_started"], "unavailable: no simulated death or combat result event")
	Sm2TurnScheduler.end_active(state, catalog, events)
	state.actor(2).spatial.alive = false
	Sm2TurnScheduler.advance(state, catalog, events)
	t.equal(state.actor(2).reactions_left, 0, "unavailable: previously completed actor also normalized")

static func _finish(t: Sm2TestHarness) -> void:
	var catalog: Sm2TurnCatalog = _catalog(t)
	var state: Sm2TacticalState = _state(t, catalog, [1, 2])
	state.round_limit = 2
	var events: Array[Dictionary] = []
	Sm2TurnScheduler.start_round(state, catalog, events)
	for index: int in 4:
		Sm2TurnScheduler.end_active(state, catalog, events)
	t.expect(state.finished, "limit: completing configured round ends scheduler")
	t.equal(state.round, 2, "limit: no extra round allocated")
	t.equal(state.phase, "finished", "limit: finished phase explicit")
	t.equal(state.finish_reason, "round_limit", "limit: no invented battle winner")
	t.equal(state.main_queue, [], "limit: main cleared")
	t.equal(state.deferred_queue, [], "limit: deferred cleared")
	t.equal(state.active_id(), 0, "limit: no active actor")
	t.equal(_count(events, "round_started"), 2, "limit: exactly configured round starts")
	t.equal(_count(events, "round_limit_reached"), 1, "limit: terminal event emitted once")
	for id: int in state.sorted_ids():
		t.expect(state.actor(id).turn_done and state.actor(id).activation_started, "limit: all participants completed naturally")
		t.equal(state.actor(id).spatial.ap, 0, "limit: no residual AP")
	var before: String = _hash(state, catalog)
	events.clear()
	Sm2TurnScheduler.start_round(state, catalog, events)
	Sm2TurnScheduler.after_action(state, catalog, events)
	Sm2TurnScheduler.wait_active(state, catalog, events)
	Sm2TurnScheduler.end_active(state, catalog, events)
	t.equal(_hash(state, catalog), before, "limit: finished scheduler cannot restart")
	t.equal(events, [], "limit: finished calls emit nothing")
	state = _state(t, catalog, [1, 2])
	events.clear()
	Sm2TurnScheduler.start_round(state, catalog, events)
	state.actor(1).spatial.alive = false
	state.actor(2).spatial.on_field = false
	events.clear()
	Sm2TurnScheduler.after_action(state, catalog, events)
	t.equal(state.finish_reason, "no_participants", "empty: protective termination without victory claim")
	t.equal(state.phase, "finished", "empty: no empty live phase published")
	t.equal(state.active_id(), 0, "empty: no active actor")
	t.equal(_types(events), ["no_participants"], "empty: explicit diagnostic terminal event")
	t.equal(state.round, 1, "empty: does not create empty rounds")

static func _copies_and_snapshot(t: Sm2TestHarness) -> void:
	var catalog: Sm2TurnCatalog = _catalog(t)
	var state: Sm2TacticalState = _state(t, catalog)
	state.revision = 9007199254740993
	var events: Array[Dictionary] = []
	Sm2TurnScheduler.start_round(state, catalog, events)
	Sm2TurnScheduler.wait_active(state, catalog, events)
	var hash: String = _hash(state, catalog)
	var copied: Sm2TacticalState = state.copy()
	t.equal(_hash(copied, catalog), hash, "copy: exact typed graph copy")
	t.expect(copied.actor(3) != state.actor(3) and copied.actor(3).spatial != state.actor(3).spatial, "copy: independent actor and spatial instances")
	copied.actor(3).spatial.ap = 1
	copied.actor(3).spatial.position = Vector2i(0, 0)
	copied.deferred_queue.clear()
	copied.main_queue.clear()
	copied.sides.clear()
	copied.rng.next_value()
	var field_data: Dictionary = copied.field.to_data()
	field_data.default_elevation = 2
	copied.field.build(field_data)
	t.equal(_hash(state, catalog), hash, "copy: nested mutable graph fully isolated")
	var exported: Dictionary = state.to_data(catalog.fingerprint())
	t.equal(exported.revision, "9007199254740993", "snapshot: large revision exact decimal")
	t.equal(exported.ruleset, "sm2.m2.turns.1", "snapshot: truthful turns-only ruleset")
	t.equal(exported.schema_version, 2, "snapshot: new battle schema")
	t.equal(exported.main_queue, ["6", "2", "4", "1", "5"], "snapshot: pending queue explicit")
	t.equal(exported.deferred_queue, ["3"], "snapshot: waiting queue explicit")
	t.equal(exported.active_actor_id, "6", "snapshot: active head exact")
	t.expect(Sm2Canonical.is_json_safe(exported), "snapshot: JSON-safe detached state")
	t.equal(Sm2Canonical.hash(JSON.parse_string(JSON.stringify(exported))), hash, "snapshot: canonical JSON roundtrip")
	exported.actors[0].fatigue = 999
	exported.field.surfaces.clear()
	exported.main_queue.clear()
	exported.deferred_queue.clear()
	exported.sides.clear()
	var occupancy: Array[Vector2i] = state.occupancy()
	occupancy.clear()
	var ids: Array[int] = state.sorted_ids()
	ids.clear()
	t.equal(_hash(state, catalog), hash, "snapshot: no container or query aliases state")
	var equal_copy: Sm2TacticalState = state.copy()
	var original_events: Array[Dictionary] = []
	var copied_events: Array[Dictionary] = []
	for index: int in 8:
		Sm2TurnScheduler.end_active(state, catalog, original_events)
		Sm2TurnScheduler.end_active(equal_copy, catalog, copied_events)
	t.equal(original_events, copied_events, "copy: continuation event stream deterministic")
	t.equal(_hash(state, catalog), _hash(equal_copy, catalog), "copy: continuation state deterministic")
	var before_events_mutation: String = _hash(state, catalog)
	original_events[0].actor_id = "999"
	t.equal(_hash(state, catalog), before_events_mutation, "events: payload never references live state")
	t.equal(state.revision, 9007199254740993, "scheduler: all transitions preserve coordinator revision")
	t.equal(state.rng.draws, 0, "scheduler: all transitions preserve RNG draw count")
	t.equal(state.next_actor_id, 7, "scheduler: all transitions preserve allocator")

static func _catalog(t: Sm2TestHarness) -> Sm2TurnCatalog:
	var result: Sm2TurnCatalog = Sm2TurnCatalog.new()
	var raw: Dictionary = {"version": "scheduler.unit.1",
		"profiles": [{"id": "shield", "ap_max": 9, "fatigue_base": 100, "initiative_base": 110},
			{"id": "fighter", "ap_max": 9, "fatigue_base": 100, "initiative_base": 115},
			{"id": "archer", "ap_max": 9, "fatigue_base": 90, "initiative_base": 120}],
		"equipment": [{"id": "sword", "load_penalty": 5}, {"id": "spear", "load_penalty": 6},
			{"id": "axe", "load_penalty": 7}, {"id": "bow", "load_penalty": 4}, {"id": "shield", "load_penalty": 10},
			{"id": "padded", "load_penalty": 8}, {"id": "mail", "load_penalty": 15}, {"id": "helmet", "load_penalty": 4}],
		"loadouts": [{"id": "spear", "profile_id": "shield", "equipment_ids": ["spear", "shield", "mail", "helmet"]},
			{"id": "sword", "profile_id": "fighter", "equipment_ids": ["sword", "shield", "padded", "helmet"]},
			{"id": "axe", "profile_id": "fighter", "equipment_ids": ["axe", "shield", "mail", "helmet"]},
			{"id": "bow", "profile_id": "archer", "equipment_ids": ["bow", "padded", "helmet"]}]}
	t.equal(result.build(raw).size(), 0, "turn scheduler test catalog builds")
	return result

static func _state(t: Sm2TestHarness, catalog: Sm2TurnCatalog, only_ids: Array[int] = []) -> Sm2TacticalState:
	var result: Sm2TacticalState = Sm2TacticalState.new()
	result.battle_id = "unit:turns"
	result.scenario_id = "unit:scheduler"
	result.field = Sm2Battlefield.new()
	t.equal(result.field.build({"id": "unit:field", "version": "unit.1", "width": 8, "height": 4,
		"surfaces": [{"id": "normal", "ap_cost": 2, "fatigue_cost": 4}], "default_surface_id": "normal", "default_elevation": 0, "tiles": []}).size(), 0, "turn scheduler test field builds")
	result.sides.assign(["company", "opposition"])
	var ids: Array[int] = [1, 2, 3, 4, 5, 6]
	if not only_ids.is_empty():
		ids.assign(only_ids)
	var loadouts: Array[String] = ["spear", "sword", "bow", "axe", "spear", "bow"]
	for index: int in ids.size():
		var loadout: String = loadouts[index] if only_ids.is_empty() else "sword"
		var side: String = "company" if index < ids.size() / 2.0 else "opposition"
		var parsed: Dictionary = Sm2TacticalActor.from_setup(_spawn(ids[index], loadout, Vector2i(index, 1), side), catalog)
		t.expect(parsed.ok, "turn scheduler test actor builds")
		result.actors[ids[index]] = parsed.actor
		result.next_actor_id = maxi(result.next_actor_id, ids[index] + 1)
	return result

static func _spawn(id: int, loadout: String, position: Vector2i, side: String) -> Dictionary:
	return {"actor_id": id, "loadout_id": loadout, "side": side, "owner": side, "controller": "player",
		"creator": 0, "q": position.x, "r": position.y, "fatigue": 0, "alive": true, "on_field": true, "morale": "steady"}

static func _types(events: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for event: Dictionary in events:
		result.append(event.type)
	return result

static func _count(events: Array[Dictionary], type: String) -> int:
	var count: int = 0
	for event: Dictionary in events:
		if event.type == type:
			count += 1
	return count

static func _hash(state: Sm2TacticalState, catalog: Sm2TurnCatalog) -> String:
	return Sm2Canonical.hash(state.to_data(catalog.fingerprint()))
