extends RefCounted
## Independent authored snapshots plus real scheduler continuation across JSON.

static func run(t: Sm2TestHarness) -> void:
	var catalog: Sm2TurnCatalog = _catalog(t)
	var original: Dictionary = _snapshot(catalog)
	var parsed: Dictionary = Sm2TacticalSnapshot.decode(original, catalog)
	t.expect(parsed.ok, "M2 snapshot: independent initial snapshot accepted")
	if not parsed.ok:
		t.complete_suite("m2_snapshot")
		return
	var state: Sm2TacticalState = parsed.state
	t.equal(state.main_queue, [1, 2, 10, 11], "M2 snapshot: numeric ID tie order preserved")
	t.equal(state.actor(1).spatial.ap_max, 9, "M2 snapshot: AP limit reconstructed from catalog")
	t.equal(state.actor(1).spatial.fatigue_max, 90, "M2 snapshot: fatigue limit reconstructed from catalog")
	_roundtrip(t, state, catalog, "initial")
	_shape_and_type_failures(t, original, catalog)
	_queue_failures(t, original, catalog)
	_identity_and_field_failures(t, original, catalog)
	_anchors_and_unavailable(t, original, catalog)
	_finished_cases(t, original, catalog)
	_detachment(t, original, catalog)
	_scheduler_roundtrips(t, state, catalog)
	t.complete_suite("m2_snapshot")

static func _shape_and_type_failures(t: Sm2TestHarness, original: Dictionary, catalog: Sm2TurnCatalog) -> void:
	for key: String in original:
		var missing: Dictionary = original.duplicate(true)
		missing.erase(key)
		_reject(t, missing, catalog, "missing top-level " + key)
	var extra: Dictionary = original.duplicate(true)
	extra["future_feature"] = {}
	_reject(t, extra, catalog, "unknown top-level field")
	for key: String in original.actors[0]:
		var missing: Dictionary = original.duplicate(true)
		missing.actors[0].erase(key)
		_reject(t, missing, catalog, "missing actor " + key)
	extra = original.duplicate(true)
	extra.actors[0]["ap_max"] = 9
	_reject(t, extra, catalog, "snapshot cannot author derived AP maximum")
	var changes: Array[Dictionary] = [
		{"path": ["format"], "value": "sm2.field_probe"},
		{"path": ["format"], "value": {}},
		{"path": ["schema_version"], "value": 1},
		{"path": ["schema_version"], "value": 3},
		{"path": ["schema_version"], "value": true},
		{"path": ["ruleset"], "value": "sm2.m1.1"},
		{"path": ["ruleset"], "value": []},
		{"path": ["catalog_fingerprint"], "value": "different"},
		{"path": ["catalog_fingerprint"], "value": 1},
		{"path": ["battle_id"], "value": "  "},
		{"path": ["scenario_id"], "value": false},
		{"path": ["round_limit"], "value": 0},
		{"path": ["round_limit"], "value": 1001},
		{"path": ["round_limit"], "value": 2.5},
		{"path": ["round"], "value": "0"},
		{"path": ["round"], "value": "4"},
		{"path": ["round"], "value": 1},
		{"path": ["round"], "value": "01"},
		{"path": ["revision"], "value": -1},
		{"path": ["revision"], "value": "-1"},
		{"path": ["revision"], "value": "9223372036854775807"},
		{"path": ["next_actor_id"], "value": "9223372036854775807"},
		{"path": ["next_actor_id"], "value": "1"},
		{"path": ["active_actor_id"], "value": 1},
		{"path": ["active_actor_id"], "value": "01"},
		{"path": ["actors"], "value": {}},
		{"path": ["actors", 0], "value": null},
		{"path": ["sides"], "value": ["red", "blue"]},
		{"path": ["sides"], "value": ["blue", "blue"]},
		{"path": ["sides"], "value": ["blue", 7]},
		{"path": ["sides"], "value": ["blue"]},
		{"path": ["main_queue"], "value": {}},
		{"path": ["deferred_queue"], "value": {}},
		{"path": ["phase"], "value": "intermediate"},
		{"path": ["phase"], "value": null},
		{"path": ["finished"], "value": 0},
		{"path": ["finish_reason"], "value": "victory"},
		{"path": ["rng"], "value": []},
		{"path": ["rng", "version"], "value": "future.rng"},
		{"path": ["rng", "state"], "value": "0"},
		{"path": ["rng", "state"], "value": "2147483647"},
		{"path": ["rng", "state"], "value": 7},
		{"path": ["rng", "draws"], "value": "00"},
		{"path": ["rng", "draws"], "value": "9223372036854775807"},
		{"path": ["actors", 0, "actor_id"], "value": 1},
		{"path": ["actors", 0, "actor_id"], "value": "01"},
		{"path": ["actors", 0, "actor_id"], "value": "9223372036854775806"},
		{"path": ["actors", 0, "creator"], "value": 0},
		{"path": ["actors", 0, "loadout_id"], "value": "test:missing"},
		{"path": ["actors", 0, "owner"], "value": ""},
		{"path": ["actors", 0, "controller"], "value": true},
		{"path": ["actors", 0, "q"], "value": 0.5},
		{"path": ["actors", 0, "r"], "value": true},
		{"path": ["actors", 0, "ap"], "value": 10},
		{"path": ["actors", 0, "ap"], "value": 1.5},
		{"path": ["actors", 0, "ap"], "value": true},
		{"path": ["actors", 0, "fatigue"], "value": 91},
		{"path": ["actors", 0, "fatigue"], "value": -1},
		{"path": ["actors", 0, "fatigue"], "value": INF},
		{"path": ["actors", 0, "fatigue"], "value": NAN},
		{"path": ["actors", 0, "round_fatigue"], "value": -1},
		{"path": ["actors", 0, "round_fatigue"], "value": 91},
		{"path": ["actors", 0, "initiative"], "value": "110"},
		{"path": ["actors", 0, "morale"], "value": "happy"},
		{"path": ["actors", 0, "round_morale"], "value": 100},
		{"path": ["actors", 0, "alive"], "value": 1},
		{"path": ["actors", 0, "on_field"], "value": "true"},
		{"path": ["actors", 0, "activation_started"], "value": 1},
		{"path": ["actors", 0, "wait_used"], "value": 0},
		{"path": ["actors", 0, "turn_done"], "value": 0},
		{"path": ["actors", 0, "reactions_left"], "value": 2},
		{"path": ["actors", 0, "reactions_left"], "value": 0.5}
	]
	for index: int in changes.size():
		var change: Dictionary = changes[index]
		_reject(t, _changed(original, change.path, change.value), catalog, "typed mutation %d %s" % [index, str(change.path)])
	for key: String in original.rng:
		var missing: Dictionary = original.duplicate(true)
		missing.rng.erase(key)
		_reject(t, missing, catalog, "missing RNG " + key)
	extra = original.duplicate(true)
	extra.rng["extra"] = 0
	_reject(t, extra, catalog, "unknown RNG field")
	var oversized: Dictionary = original.duplicate(true)
	oversized.actors.resize(4097)
	_reject(t, oversized, catalog, "actor collection bound")
	var null_catalog: Dictionary = Sm2TacticalSnapshot.decode(original, null)
	t.expect(not null_catalog.ok and null_catalog.state == null and not null_catalog.errors.is_empty(), "M2 snapshot: null catalog rejected")

static func _queue_failures(t: Sm2TestHarness, original: Dictionary, catalog: Sm2TurnCatalog) -> void:
	var changes: Array[Dictionary] = [
		{"path": ["main_queue"], "value": ["2", "1", "10", "11"]},
		{"path": ["main_queue"], "value": ["1", "2", "11", "10"]},
		{"path": ["main_queue"], "value": ["1", "1", "10", "11"]},
		{"path": ["main_queue"], "value": ["1", "2", "10", "12"]},
		{"path": ["main_queue"], "value": [1, "2", "10", "11"]},
		{"path": ["main_queue"], "value": ["01", "2", "10", "11"]},
		{"path": ["main_queue"], "value": ["1", "2", "10"]},
		{"path": ["main_queue"], "value": []},
		{"path": ["deferred_queue"], "value": ["1"]},
		{"path": ["active_actor_id"], "value": "2"},
		{"path": ["active_actor_id"], "value": "0"},
		{"path": ["actors", 0, "activation_started"], "value": false},
		{"path": ["actors", 1, "activation_started"], "value": true},
		{"path": ["actors", 0, "wait_used"], "value": true},
		{"path": ["actors", 0, "turn_done"], "value": true},
		{"path": ["actors", 0, "ap"], "value": 0},
		{"path": ["actors", 0, "alive"], "value": false},
		{"path": ["actors", 0, "on_field"], "value": false},
		{"path": ["phase"], "value": "deferred"},
		{"path": ["phase"], "value": "finished"},
		{"path": ["finish_reason"], "value": "round_limit"},
		{"path": ["finished"], "value": true}
	]
	for index: int in changes.size():
		_reject(t, _changed(original, changes[index].path, changes[index].value), catalog, "queue mutation %d" % index)
	var hidden: Dictionary = original.duplicate(true)
	hidden.main_queue.pop_back()
	_finish_actor(hidden.actors[3])
	_reject(t, hidden, catalog, "lower initiative cannot finish before an unstarted higher actor")
	hidden.actors[3].activation_started = false
	_reject(t, hidden, catalog, "unstarted actor cannot disappear from queue")
	var waited: Dictionary = _waited_snapshot(original)
	t.expect(Sm2TacticalSnapshot.decode(waited, catalog).ok, "M2 snapshot: independent valid Wait state")
	var skipped_waiter: Dictionary = waited.duplicate(true)
	skipped_waiter.deferred_queue = []
	_finish_actor(skipped_waiter.actors[0])
	_reject(t, skipped_waiter, catalog, "Wait cannot finish while main phase still has actors")
	var waited_changes: Array[Dictionary] = [
		{"path": ["actors", 0, "wait_used"], "value": false},
		{"path": ["actors", 0, "activation_started"], "value": false},
		{"path": ["actors", 0, "turn_done"], "value": true},
		{"path": ["actors", 0, "ap"], "value": 0},
		{"path": ["deferred_queue"], "value": ["1", "1"]},
		{"path": ["active_actor_id"], "value": "1"}
	]
	for index: int in waited_changes.size():
		_reject(t, _changed(waited, waited_changes[index].path, waited_changes[index].value), catalog, "deferred flag mutation %d" % index)
	var early_waiter: Dictionary = original.duplicate(true)
	early_waiter.main_queue.pop_back()
	early_waiter.deferred_queue = ["11"]
	early_waiter.actors[3].wait_used = true
	early_waiter.actors[3].activation_started = true
	_reject(t, early_waiter, catalog, "later actor cannot Wait before active main head")
	var deferred: Dictionary = waited.duplicate(true)
	deferred.main_queue = []
	deferred.deferred_queue = ["1", "2"]
	deferred.actors[1].wait_used = true
	_finish_actor(deferred.actors[2])
	_finish_actor(deferred.actors[3])
	deferred.phase = "deferred"
	deferred.active_actor_id = "1"
	t.expect(Sm2TacticalSnapshot.decode(deferred, catalog).ok, "M2 snapshot: independent deferred phase accepted")
	_reject(t, _changed(deferred, ["deferred_queue"], ["2", "1"]), catalog, "deferred queue cannot be sorted on load")
	_reject(t, _changed(deferred, ["active_actor_id"], "2"), catalog, "deferred head exact")
	_reject(t, _changed(deferred, ["phase"], "main"), catalog, "main phase cannot have empty main queue")
	var premature_waiter: Dictionary = deferred.duplicate(true)
	premature_waiter.actors[3].wait_used = true
	_reject(t, premature_waiter, catalog, "later deferred waiter cannot finish before its higher-initiative head")
	deferred.actors[0].morale = "fleeing"
	deferred.actors[0].round_morale = "fleeing"
	_reject(t, deferred, catalog, "fleeing cannot have used Wait")

static func _identity_and_field_failures(t: Sm2TestHarness, original: Dictionary, catalog: Sm2TurnCatalog) -> void:
	var changes: Array[Dictionary] = [
		{"path": ["actors", 1, "actor_id"], "value": "1"},
		{"path": ["actors", 1, "actor_id"], "value": "12"},
		{"path": ["next_actor_id"], "value": "11"},
		{"path": ["actors", 0, "creator"], "value": "1"},
		{"path": ["actors", 1, "creator"], "value": "10"},
		{"path": ["actors", 2, "creator"], "value": "9"},
		{"path": ["actors", 0, "side"], "value": "green"},
		{"path": ["sides"], "value": ["blue", "green"]},
		{"path": ["actors", 0, "q"], "value": 4},
		{"path": ["actors", 0, "r"], "value": 3},
		{"path": ["actors", 0, "q"], "value": 1},
		{"path": ["field"], "value": []},
		{"path": ["field", "width"], "value": true},
		{"path": ["field", "width"], "value": 65},
		{"path": ["field", "default_surface_id"], "value": "missing"},
		{"path": ["field_fingerprint"], "value": "wrong"},
		{"path": ["field_fingerprint"], "value": 0},
		{"path": ["field", "id"], "value": "valid-but-different"}
	]
	for index: int in changes.size():
		_reject(t, _changed(original, changes[index].path, changes[index].value), catalog, "identity/field mutation %d" % index)
	var reordered: Dictionary = original.duplicate(true)
	var first: Dictionary = reordered.actors[0]
	reordered.actors[0] = reordered.actors[1]
	reordered.actors[1] = first
	_reject(t, reordered, catalog, "actor array must already be sorted")
	var blocked: Dictionary = original.duplicate(true)
	blocked.actors[0].q = 3
	blocked.actors[0].r = 2
	_reject(t, blocked, catalog, "live actor cannot occupy rock")
	var single_side: Dictionary = original.duplicate(true)
	for actor: Dictionary in single_side.actors:
		actor.side = "blue"
	_reject(t, single_side, catalog, "both original sides must have records")
	var creator: Dictionary = original.duplicate(true)
	creator.actors[1].creator = "1"
	creator.actors[2].creator = "2"
	t.expect(Sm2TacticalSnapshot.decode(creator, catalog).ok, "M2 snapshot: earlier existing creator chain accepted")
	var large: Dictionary = original.duplicate(true)
	large.actors[3].actor_id = "9223372036854775805"
	large.main_queue[3] = "9223372036854775805"
	large.next_actor_id = "9223372036854775806"
	large.revision = "9223372036854775806"
	large.rng.draws = "9223372036854775806"
	var decoded: Dictionary = Sm2TacticalSnapshot.decode(JSON.parse_string(Sm2Canonical.stringify(large)), catalog)
	t.expect(decoded.ok, "M2 snapshot: exact int64 identifiers and counters survive JSON")
	if decoded.ok:
		t.equal(decoded.state.to_data(catalog.fingerprint()), large, "M2 snapshot: no precision loss for large decimal strings")

static func _anchors_and_unavailable(t: Sm2TestHarness, original: Dictionary, catalog: Sm2TurnCatalog) -> void:
	var moved: Dictionary = original.duplicate(true)
	moved.actors[0].fatigue = 20
	moved.actors[0].ap = 3
	t.expect(Sm2TacticalSnapshot.decode(moved, catalog).ok, "M2 snapshot: movement fatigue does not recalculate round initiative")
	_reject(t, _changed(moved, ["actors", 0, "initiative"], 90), catalog, "initiative cannot use current fatigue")
	_reject(t, _changed(original, ["actors", 0, "round_fatigue"], 1), catalog, "fatigue below saved round anchor")
	_reject(t, _changed(original, ["actors", 0, "morale"], "wavering"), catalog, "mid-round morale unsupported in ruleset")
	var steady_anchor: Dictionary = original.duplicate(true)
	steady_anchor.actors[0].round_morale = "wavering"
	_reject(t, steady_anchor, catalog, "round morale must match current morale")
	for morale: String in ["wavering", "breaking", "fleeing"]:
		var anchored: Dictionary = original.duplicate(true)
		anchored.actors[0].morale = morale
		anchored.actors[0].round_morale = morale
		anchored.actors[0].round_fatigue = 11
		anchored.actors[0].fatigue = 20
		# (120 - 10 - 11) gives 99 before the morale multiplier.
		anchored.actors[0].initiative = 89 if morale == "wavering" else (79 if morale == "breaking" else 99)
		anchored.actors[0].activation_started = false
		anchored.actors[1].activation_started = true
		anchored.active_actor_id = "2"
		anchored.main_queue = ["2", "1", "10", "11"] if morale == "fleeing" else ["2", "10", "11", "1"]
		t.expect(Sm2TacticalSnapshot.decode(anchored, catalog).ok, "M2 snapshot: independent rounded anchor " + morale)
	var zero_initiative: Dictionary = original.duplicate(true)
	for index: int in [2, 3]:
		zero_initiative.actors[index].fatigue = 90
		zero_initiative.actors[index].round_fatigue = 90
		zero_initiative.actors[index].initiative = 0
	t.expect(Sm2TacticalSnapshot.decode(zero_initiative, catalog).ok, "M2 snapshot: zero initiative retains numeric tie order")
	var unavailable: Dictionary = original.duplicate(true)
	unavailable.main_queue = ["1", "2", "10"]
	unavailable.actors[3].on_field = false
	unavailable.actors[3].ap = 0
	unavailable.actors[3].turn_done = true
	unavailable.actors[3].reactions_left = 0
	t.expect(Sm2TacticalSnapshot.decode(unavailable, catalog).ok, "M2 snapshot: escaped unstarted actor is unavailable")
	unavailable.actors[3].alive = false
	unavailable.actors[3].on_field = true
	unavailable.actors[3].q = 0
	t.expect(Sm2TacticalSnapshot.decode(unavailable, catalog).ok, "M2 snapshot: dead record may share occupied position")
	_reject(t, _changed(unavailable, ["actors", 3, "reactions_left"], 1), catalog, "unavailable actor has zero reactions")
	_reject(t, _changed(unavailable, ["actors", 3, "turn_done"], false), catalog, "unavailable must be completed")
	_reject(t, _changed(unavailable, ["actors", 3, "wait_used"], true), catalog, "Wait flag implies started even for unavailable")
	var json: Variant = JSON.parse_string(Sm2Canonical.stringify(original))
	t.expect(typeof(json.actors[0].ap) == TYPE_FLOAT, "M2 snapshot: JSON parser exercises integral float input")
	t.expect(Sm2TacticalSnapshot.decode(json, catalog).ok, "M2 snapshot: small integral JSON floats accepted")

static func _finished_cases(t: Sm2TestHarness, original: Dictionary, catalog: Sm2TurnCatalog) -> void:
	var finished: Dictionary = original.duplicate(true)
	finished.round = "3"
	finished.main_queue = []
	finished.phase = "finished"
	finished.active_actor_id = "0"
	finished.finished = true
	finished.finish_reason = "round_limit"
	for actor: Dictionary in finished.actors:
		_finish_actor(actor)
	t.expect(Sm2TacticalSnapshot.decode(finished, catalog).ok, "M2 snapshot: round-limit terminal state accepted")
	_reject(t, _changed(finished, ["round"], "2"), catalog, "round-limit requires limit round")
	_reject(t, _changed(finished, ["finish_reason"], ""), catalog, "finished needs reason")
	_reject(t, _changed(finished, ["finish_reason"], "no_participants"), catalog, "no-participants cannot hide living participants")
	_reject(t, _changed(finished, ["active_actor_id"], "1"), catalog, "finished cannot retain active actor")
	_reject(t, _changed(finished, ["phase"], "main"), catalog, "finished requires finished phase")
	_reject(t, _changed(finished, ["actors", 0, "turn_done"], false), catalog, "finished actor cannot remain pending")
	_reject(t, _changed(finished, ["actors", 0, "activation_started"], false), catalog, "finished living actor cannot skip activation")
	var empty: Dictionary = finished.duplicate(true)
	empty.round = "1"
	empty.finish_reason = "no_participants"
	for actor: Dictionary in empty.actors:
		actor.on_field = false
		actor.activation_started = false
		actor.reactions_left = 0
	t.expect(Sm2TacticalSnapshot.decode(empty, catalog).ok, "M2 snapshot: defensive no-participants terminal accepted")
	_reject(t, _changed(empty, ["finished"], false), catalog, "no participants cannot be unfinished")

static func _detachment(t: Sm2TestHarness, original: Dictionary, catalog: Sm2TurnCatalog) -> void:
	var mutable: Dictionary = original.duplicate(true)
	var decoded: Dictionary = Sm2TacticalSnapshot.decode(mutable, catalog)
	if not decoded.ok:
		t.expect(false, "M2 snapshot: detachment fixture decoded")
		return
	var state: Sm2TacticalState = decoded.state
	var before: String = Sm2Canonical.hash(state.to_data(catalog.fingerprint()))
	mutable.main_queue.clear()
	mutable.actors[0].owner = "changed"
	mutable.field.surfaces[0].ap_cost = 99
	mutable.rng.state = "1"
	t.equal(Sm2Canonical.hash(state.to_data(catalog.fingerprint())), before, "M2 snapshot: source nested containers detached")
	var second: Dictionary = Sm2TacticalSnapshot.decode(original, catalog)
	state.actor(1).spatial.ap = 1
	state.main_queue.pop_back()
	t.equal(Sm2Canonical.hash(second.state.to_data(catalog.fingerprint())), before, "M2 snapshot: independent candidates do not alias")

static func _scheduler_roundtrips(t: Sm2TestHarness, initial: Sm2TacticalState, catalog: Sm2TurnCatalog) -> void:
	var state: Sm2TacticalState = initial.copy()
	var events: Array[Dictionary] = []
	state.actor(1).spatial.ap = 7
	state.actor(1).spatial.fatigue = 4
	Sm2TurnScheduler.wait_active(state, catalog, events)
	t.equal(state.active_id(), 2, "M2 snapshot: actual Wait advances main queue")
	var resumed: Sm2TacticalState = _roundtrip(t, state, catalog, "after movement and Wait")
	if resumed == null:
		return
	_compare_next_end(t, state, resumed, catalog, "after Wait")
	Sm2TurnScheduler.wait_active(state, catalog, events)
	Sm2TurnScheduler.wait_active(state, catalog, events)
	t.equal(state.phase, "deferred", "M2 snapshot: scheduler reaches deferred")
	t.equal(state.active_id(), 1, "M2 snapshot: scheduler resumes first waiter")
	t.equal(state.actor(1).spatial.ap, 7, "M2 snapshot: Wait did not reset AP")
	t.equal(state.actor(1).spatial.fatigue, 4, "M2 snapshot: Wait did not restore fatigue")
	resumed = _roundtrip(t, state, catalog, "in deferred")
	if resumed == null:
		return
	_compare_next_end(t, state, resumed, catalog, "deferred continuation")
	Sm2TurnScheduler.end_active(state, catalog, events)
	t.equal(state.active_id(), 11, "M2 snapshot: last deferred actor before next round")
	resumed = _roundtrip(t, state, catalog, "before next round")
	if resumed == null:
		return
	_compare_next_end(t, state, resumed, catalog, "round transition")
	t.equal(state.round, 2, "M2 snapshot: next round starts exactly once")
	t.equal(state.actor(1).spatial.fatigue, 0, "M2 snapshot: fatigue restored at new round")
	_roundtrip(t, state, catalog, "new round")
	state.actor(state.active_id()).spatial.ap = 0
	state.actor(state.active_id()).spatial.fatigue = 18
	Sm2TurnScheduler.after_action(state, catalog, events)
	t.equal(state.active_id(), 2, "M2 snapshot: AP exhaustion automatically advances")
	resumed = _roundtrip(t, state, catalog, "after AP-zero auto-end")
	if resumed == null:
		return
	_compare_next_end(t, state, resumed, catalog, "auto-end continuation")
	var guard: int = 0
	while not state.finished and guard < 20:
		Sm2TurnScheduler.end_active(state, catalog, events)
		guard += 1
	t.expect(state.finished and state.finish_reason == "round_limit" and state.round == 3, "M2 snapshot: scheduler reaches round limit")
	_roundtrip(t, state, catalog, "round limit")
	t.equal(state.rng.draws, 0, "M2 snapshot: queue and restore do not consume RNG")
	t.equal(state.next_actor_id, 12, "M2 snapshot: queue and restore do not issue actor IDs")

static func _compare_next_end(t: Sm2TestHarness, state: Sm2TacticalState, resumed: Sm2TacticalState, catalog: Sm2TurnCatalog, label: String) -> void:
	var expected_events: Array[Dictionary] = []
	var actual_events: Array[Dictionary] = []
	Sm2TurnScheduler.end_active(state, catalog, expected_events)
	Sm2TurnScheduler.end_active(resumed, catalog, actual_events)
	t.equal(actual_events, expected_events, "M2 snapshot: continued events " + label)
	t.equal(resumed.to_data(catalog.fingerprint()), state.to_data(catalog.fingerprint()), "M2 snapshot: continued state " + label)

static func _roundtrip(t: Sm2TestHarness, state: Sm2TacticalState, catalog: Sm2TurnCatalog, label: String) -> Sm2TacticalState:
	var data: Dictionary = state.to_data(catalog.fingerprint())
	var before: String = Sm2Canonical.hash(data)
	var decoded: Dictionary = Sm2TacticalSnapshot.decode(JSON.parse_string(Sm2Canonical.stringify(data)), catalog)
	t.expect(decoded.ok and decoded.errors.is_empty(), "M2 snapshot: JSON roundtrip " + label)
	if not decoded.ok:
		return null
	t.equal(Sm2Canonical.hash(decoded.state.to_data(catalog.fingerprint())), before, "M2 snapshot: exact stable boundary " + label)
	t.equal(Sm2Canonical.hash(state.to_data(catalog.fingerprint())), before, "M2 snapshot: decode leaves source state intact " + label)
	return decoded.state

static func _reject(t: Sm2TestHarness, data: Dictionary, catalog: Sm2TurnCatalog, label: String) -> void:
	# Hash only JSON-safe inputs: invalid nonfinite values are intentional type cases.
	var safe: bool = Sm2Canonical.is_json_safe(data)
	var before: String = Sm2Canonical.hash(data) if safe else ""
	var catalog_before: String = catalog.fingerprint()
	var result: Dictionary = Sm2TacticalSnapshot.decode(data, catalog)
	t.expect(not result.ok and result.state == null and result.errors is PackedStringArray and not result.errors.is_empty(), "M2 snapshot rejects: " + label)
	if safe:
		t.equal(Sm2Canonical.hash(data), before, "M2 snapshot: invalid input unchanged " + label)
	t.equal(catalog.fingerprint(), catalog_before, "M2 snapshot: catalog unchanged " + label)

static func _changed(original: Dictionary, path: Array, value: Variant) -> Dictionary:
	# External JSON arrays are untyped. A typed actor array would refuse null
	# before decode runs, leaving the valid fixture unchanged and masking the case.
	var changed: Dictionary = JSON.parse_string(Sm2Canonical.stringify(original))
	var parent: Variant = changed
	for index: int in range(path.size() - 1):
		parent = parent[path[index]]
	parent[path[-1]] = value
	return changed

static func _finish_actor(actor: Dictionary) -> void:
	actor.ap = 0
	actor.turn_done = true
	actor.activation_started = true

static func _waited_snapshot(original: Dictionary) -> Dictionary:
	var data: Dictionary = original.duplicate(true)
	data.main_queue = ["2", "10", "11"]
	data.deferred_queue = ["1"]
	data.active_actor_id = "2"
	data.actors[0].wait_used = true
	data.actors[1].activation_started = true
	return data

static func _catalog(t: Sm2TestHarness) -> Sm2TurnCatalog:
	var catalog: Sm2TurnCatalog = Sm2TurnCatalog.new()
	var errors: PackedStringArray = catalog.build({"version": "test.turns.1", "profiles": [
		{"id": "test:profile.fast", "ap_max": 9, "fatigue_base": 100, "initiative_base": 120},
		{"id": "test:profile.slow", "ap_max": 9, "fatigue_base": 100, "initiative_base": 100}],
		"equipment": [{"id": "test:equipment.light", "load_penalty": 10}],
		"loadouts": [
			{"id": "test:loadout.fast", "profile_id": "test:profile.fast", "equipment_ids": ["test:equipment.light"]},
			{"id": "test:loadout.slow", "profile_id": "test:profile.slow", "equipment_ids": ["test:equipment.light"]}]})
	t.expect(errors.is_empty(), "M2 snapshot: independent catalog fixture builds")
	return catalog

static func _snapshot(catalog: Sm2TurnCatalog) -> Dictionary:
	var field: Dictionary = {"id": "test:field.snapshot", "version": "sm2.m2.field.1", "width": 4, "height": 3,
		"surfaces": [{"id": "test:surface.ground", "ap_cost": 2, "fatigue_cost": 4}],
		"default_surface_id": "test:surface.ground", "default_elevation": 0,
		"tiles": [{"q": 3, "r": 2, "surface_id": "test:surface.ground", "elevation": 0, "passable": false, "opaque": true}]}
	var actors: Array[Dictionary] = []
	var ids: Array[int] = [1, 2, 10, 11]
	for index: int in ids.size():
		var fast: bool = index < 2
		actors.append({"actor_id": str(ids[index]), "loadout_id": "test:loadout.fast" if fast else "test:loadout.slow",
			"side": "blue" if fast else "red", "owner": "test:owner", "controller": "test:controller", "creator": "0",
			"q": index, "r": 0, "ap": 9, "fatigue": 0, "alive": true, "on_field": true,
			"morale": "steady", "round_fatigue": 0, "round_morale": "steady", "initiative": 110 if fast else 90,
			"activation_started": index == 0, "wait_used": false, "turn_done": false, "reactions_left": 1})
	return {"format": "sm2.battle", "schema_version": 2, "ruleset": "sm2.m2.turns.1", "catalog_fingerprint": catalog.fingerprint(),
		"battle_id": "test:battle.snapshot", "scenario_id": "test:scenario.snapshot", "field": field, "field_fingerprint": Sm2Canonical.hash(field),
		"round_limit": 3, "round": "1", "revision": "0", "next_actor_id": "12", "actors": actors, "sides": ["blue", "red"],
		"main_queue": ["1", "2", "10", "11"], "deferred_queue": [], "phase": "main", "active_actor_id": "1",
		"finished": false, "finish_reason": "", "rng": {"version": Sm2DeterministicRng.VERSION, "state": "20260909", "draws": "0"}}
