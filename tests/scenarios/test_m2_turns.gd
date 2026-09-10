extends RefCounted

static func run(t: Sm2TestHarness) -> void:
	_authored(t)
	_wait_and_resume(t)
	_wait_edges(t)
	_auto_end(t)
	_new_initiative(t)
	_limits_and_presence(t)
	_reject_and_isolate(t)
	_restore_continuations(t)
	t.complete_suite("m2_turns")

static func _battle(t: Sm2TestHarness, catalog: Sm2TurnCatalog = null, setup: Dictionary = {}) -> Sm2TacticalBattle:
	var result: Sm2TacticalBattle = Sm2TacticalBattle.new(catalog if catalog != null else Sm2TurnTestFixtures.catalog())
	var started: Dictionary = result.start(setup if not setup.is_empty() else Sm2TurnTestFixtures.setup())
	t.expect(started.ok, "M2 turns: valid start " + str(started.get("errors", [])))
	return result

static func _act(t: Sm2TestHarness, battle: Sm2TacticalBattle, kind: String,
	target: Vector2i = Vector2i.ZERO) -> Sm2CommandResult:
	var before: Dictionary = battle.capture()
	var result: Sm2CommandResult = battle.execute(Sm2TurnTestFixtures.command(battle, kind, target))
	t.expect(result.accepted, "M2 turns accepted " + kind + ": " + result.code)
	t.equal(result.revision, int(before.revision) + 1, "M2 one revision per complete transition")
	t.equal(battle.capture().rng, before.rng, "M2 turns never draw RNG")
	t.equal(battle.capture().next_actor_id, before.next_actor_id, "M2 turns preserve ID sequence")
	for i: int in result.events.size():
		t.expect(result.events[i].sequence == i and result.events[i].revision == str(result.revision)
			and result.events[i].battle_id == before.battle_id, "M2 event transaction metadata")
	return result

static func _authored(t: Sm2TestHarness) -> void:
	var loaded: Dictionary = Sm2TurnContentLoader.load_scenario()
	t.expect(loaded.ok, "M2 authored turns load")
	var battle: Sm2TacticalBattle = _battle(t, loaded.catalog, loaded.setup)
	t.equal(battle.view().main_queue, [3, 6, 2, 4, 1, 5], "M2 authored exact initial initiative order")
	t.equal(battle.view().round, 1, "M2 authored starts round one")
	var expected_i: Array[int] = [75, 88, 104, 79, 75, 104]
	var expected_cap: Array[int] = [65, 73, 74, 64, 65, 74]
	for i: int in 6:
		var actor: Dictionary = battle.view().actors[i]
		t.equal(actor.initiative, expected_i[i], "M2 authored initiative oracle")
		t.equal(actor.fatigue_max, expected_cap[i], "M2 authored load capacity oracle")
		t.equal(actor.ap, 9, "M2 authored AP granted once")
		t.equal(actor.reactions_left, 1, "M2 reaction budget prepared")
	for id: int in [3, 6, 2, 4, 1, 5]:
		t.equal(battle.view().active_actor_id, id, "M2 main scenario activation sequence")
		_act(t, battle, "end_turn")
	t.equal(battle.view().round, 2, "M2 next authored round starts")
	t.equal(battle.view().main_queue, [3, 6, 2, 4, 1, 5], "M2 unchanged fatigue preserves next order")

static func _wait_and_resume(t: Sm2TestHarness) -> void:
	var battle: Sm2TacticalBattle = _battle(t)
	_act(t, battle, "move", Vector2i(1, 0))
	var moved: Dictionary = battle.view().actors[0]
	t.equal([moved.ap, moved.fatigue], [7, 4], "M2 movement resource oracle before wait")
	var waited: Sm2CommandResult = _act(t, battle, "wait")
	t.equal(Sm2TurnTestFixtures.types(waited.events), ["actor_waited", "activation_started"], "M2 wait only activates next actor")
	t.equal(battle.view().deferred_queue, [1], "M2 wait queue contains actor")
	_act(t, battle, "wait")
	var returned: Sm2CommandResult = _act(t, battle, "end_turn")
	t.equal(Sm2TurnTestFixtures.types(returned.events), ["turn_ended", "activation_resumed"], "M2 wait resume has no start effects/resources")
	t.equal(battle.view().phase, "deferred", "M2 deferred phase reached")
	t.equal(battle.view().deferred_queue, [1, 2], "M2 deferred initiative order")
	t.equal([battle.view().actors[0].ap, battle.view().actors[0].fatigue], [7, 4], "M2 resumed resources identical")
	_reject(t, battle, Sm2TurnTestFixtures.command(battle, "wait"), "wait_already_used")
	var again: Sm2CommandResult = _act(t, battle, "move", Vector2i(2, 0))
	t.equal(Sm2TurnTestFixtures.types(again.events), ["resources_spent", "moved"], "M2 deferred move does not emit a second resume")
	_act(t, battle, "end_turn")
	t.equal(battle.view().active_actor_id, 2, "M2 next deferred actor")
	var round_start: Sm2CommandResult = _act(t, battle, "end_turn")
	t.equal(Sm2TurnTestFixtures.types(round_start.events), ["turn_ended", "round_started", "round_resources", "round_resources", "round_resources", "activation_started"], "M2 whole round transition in one command")
	t.equal([battle.view().round, battle.view().actors[0].ap, battle.view().actors[0].fatigue], [2, 9, 0], "M2 new round AP and fatigue recovery")
	t.expect(not battle.view().actors[0].wait_used, "M2 wait available again next round")

static func _wait_edges(t: Sm2TestHarness) -> void:
	var battle: Sm2TacticalBattle = _battle(t)
	for id: int in [1, 2, 3]:
		t.equal(battle.view().active_actor_id, id, "M2 everyone can wait in main order")
		_act(t, battle, "wait")
	t.equal(battle.view().deferred_queue, [1, 2, 3], "M2 everyone waits without ending round")
	t.equal(battle.view().round, 1, "M2 all waits still round one")
	for id: int in [1, 2, 3]:
		t.equal(battle.view().active_actor_id, id, "M2 all wait resume ordering")
		_act(t, battle, "end_turn")
	var last: Sm2TacticalBattle = _battle(t)
	_act(t, last, "end_turn")
	_act(t, last, "end_turn")
	var result: Sm2CommandResult = _act(t, last, "wait")
	t.equal(Sm2TurnTestFixtures.types(result.events), ["actor_waited", "activation_resumed"], "M2 last wait immediately resumes same actor")
	t.equal([last.view().active_actor_id, last.view().actors[2].ap], [3, 9], "M2 last wait keeps all AP")
	_reject(t, last, Sm2TurnTestFixtures.command(last, "wait"), "wait_already_used")
	var setup: Dictionary = Sm2TurnTestFixtures.setup()
	setup.actors[0].morale = "fleeing"
	var fleeing: Sm2TacticalBattle = _battle(t, null, setup)
	_reject(t, fleeing, Sm2TurnTestFixtures.command(fleeing, "wait"), "fleeing_cannot_wait")

static func _auto_end(t: Sm2TestHarness) -> void:
	var battle: Sm2TacticalBattle = _battle(t, Sm2TurnTestFixtures.catalog(2))
	var result: Sm2CommandResult = _act(t, battle, "move", Vector2i(1, 0))
	t.equal(Sm2TurnTestFixtures.types(result.events), ["resources_spent", "moved", "turn_ended", "activation_started"], "M2 exact AP depletion automatically advances")
	t.expect(result.events[2].automatic, "M2 automatic end event")
	t.equal([battle.view().actors[0].ap, battle.view().actors[0].fatigue, battle.view().active_actor_id], [0, 4, 2], "M2 automatic end state")
	t.expect(battle.view().actors[0].turn_done, "M2 AP exhausted actor done")

static func _new_initiative(t: Sm2TestHarness) -> void:
	var battle: Sm2TacticalBattle = _battle(t, Sm2TurnTestFixtures.catalog(9, true))
	for target: Vector2i in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)]:
		_act(t, battle, "move", target)
	t.equal(battle.view().actors[0].initiative, 100, "M2 fatigue does not alter frozen initiative")
	t.equal(battle.view().main_queue, [1, 2, 3], "M2 queue does not reorder during activation")
	_act(t, battle, "end_turn")
	_act(t, battle, "end_turn")
	_act(t, battle, "end_turn")
	t.equal(battle.view().actors[0].fatigue, 1, "M2 exactly 15 fatigue recovered")
	t.equal(battle.view().actors[0].round_fatigue, 1, "M2 next anchor reflects recovery")
	t.equal(battle.view().main_queue, [2, 1, 3], "M2 next round recomputes initiative")
	t.equal(battle.view().actors[0].initiative, 99, "M2 next initiative arithmetic oracle")
	var setup: Dictionary = Sm2TurnTestFixtures.setup()
	setup.actors[0].fatigue = 20
	var initial: Sm2TacticalBattle = _battle(t, null, setup)
	t.equal([initial.view().actors[0].fatigue, initial.view().actors[0].initiative], [5, 95], "M2 initial fatigue recovers before initiative")

static func _limits_and_presence(t: Sm2TestHarness) -> void:
	var battle: Sm2TacticalBattle = _battle(t, null, Sm2TurnTestFixtures.setup(2))
	var last: Sm2CommandResult = null
	for i: int in 6:
		last = _act(t, battle, "end_turn")
	t.equal([battle.view().finished, battle.view().round, battle.view().active_actor_id, battle.view().finish_reason], [true, 2, 0, "round_limit"], "M2 no round beyond scenario limit")
	t.equal(Sm2TurnTestFixtures.types(last.events), ["turn_ended", "round_limit_reached"], "M2 limit causes no resource reset")
	_reject(t, battle, Sm2TurnTestFixtures.command(battle, "end_turn"), "battle_finished")
	for absence: String in ["dead", "escaped"]:
		var setup: Dictionary = Sm2TurnTestFixtures.setup()
		setup.actors[1].alive = absence != "dead"
		setup.actors[1].on_field = absence != "escaped"
		setup.actors[1].q = 0
		var absent: Sm2TacticalBattle = _battle(t, null, setup)
		t.equal(absent.view().main_queue, [1, 3], "M2 absent skipped: " + absence)
		t.equal([absent.view().actors[1].ap, absent.view().actors[1].reactions_left], [0, 0], "M2 absent gets no resources")
		_act(t, absent, "end_turn")
		_act(t, absent, "end_turn")
		t.equal(absent.view().round, 2, "M2 absent does not block next round")

static func _reject_and_isolate(t: Sm2TestHarness) -> void:
	var catalog: Sm2TurnCatalog = Sm2TurnTestFixtures.catalog()
	var setup: Dictionary = Sm2TurnTestFixtures.setup()
	var battle: Sm2TacticalBattle = _battle(t, catalog, setup)
	_reject(t, battle, null, "invalid_command")
	_reject(t, battle, Sm2SpatialFixtures.command(1, 1, Vector2i.ZERO, "wait"), "stale_revision")
	_reject(t, battle, Sm2SpatialFixtures.command(2, 0, Vector2i.ZERO, "wait"), "not_active_actor")
	_reject(t, battle, Sm2TurnTestFixtures.command(battle, "attack"), "unsupported_command")
	_reject(t, battle, Sm2TurnTestFixtures.command(battle, "move", Vector2i(5, 3)), "not_adjacent")
	var hash_before: String = battle.state_hash()
	setup.actors[0].fatigue = 99
	var raw: Dictionary = catalog.to_data()
	raw.profiles[0].ap_max = 1
	catalog.build(raw)
	var view: Dictionary = battle.view()
	view.actors[0].ap = 0
	view.main_queue.clear()
	view.field.width = 1
	var captured: Dictionary = battle.capture()
	captured.actors.clear()
	captured.rng.draws = "9"
	t.equal(battle.state_hash(), hash_before, "M2 inputs, definitions, views and snapshots detached")
	var allowed: Dictionary = battle.preview(Sm2TurnTestFixtures.command(battle, "move", Vector2i(1, 0)))
	t.expect(allowed.allowed, "M2 preview valid action")
	battle.reachable(1)
	battle.route(1, Vector2i(3, 3))
	battle.line_of_sight(1, 2)
	t.equal(battle.state_hash(), hash_before, "M2 preview and spatial queries inert")
	var bad_setups: Array[Dictionary] = []
	var duplicate: Dictionary = Sm2TurnTestFixtures.setup()
	duplicate.actors[1].actor_id = 1
	bad_setups.append(duplicate)
	var overlap: Dictionary = Sm2TurnTestFixtures.setup()
	overlap.actors[1].q = 0
	bad_setups.append(overlap)
	var creator: Dictionary = Sm2TurnTestFixtures.setup()
	creator.actors[1].creator = 3
	bad_setups.append(creator)
	var nobody: Dictionary = Sm2TurnTestFixtures.setup()
	for actor: Dictionary in nobody.actors:
		actor.alive = false
	bad_setups.append(nobody)
	var one_side: Dictionary = Sm2TurnTestFixtures.setup()
	one_side.actors[0].side = "opposition"
	bad_setups.append(one_side)
	for invalid: Dictionary in bad_setups:
		t.expect(not battle.start(invalid).ok, "M2 invalid setup rejected")
		t.equal(battle.state_hash(), hash_before, "M2 failed start preserves live state")
	var bad: Dictionary = battle.capture()
	bad.main_queue.reverse()
	t.expect(not battle.restore(bad).ok, "M2 invalid restore rejected")
	t.equal(battle.state_hash(), hash_before, "M2 failed restore inert")
	var ceiling: Dictionary = battle.capture()
	ceiling.revision = "9223372036854775806"
	t.expect(battle.restore(ceiling).ok, "M2 valid counter ceiling loads")
	_reject(t, battle, Sm2TurnTestFixtures.command(battle, "wait"), "counter_limit")

static func _reject(t: Sm2TestHarness, battle: Sm2TacticalBattle, command: Sm2Command, reason: String) -> void:
	var before: String = battle.state_hash()
	var preview: Dictionary = battle.preview(command)
	t.expect(not preview.allowed and preview.reason == reason, "M2 preview rejection " + reason)
	var result: Sm2CommandResult = battle.execute(command)
	t.expect(not result.accepted and result.code == reason and result.events.is_empty(), "M2 execute rejection " + reason)
	t.equal(battle.state_hash(), before, "M2 rejected action leaves state/RNG/ID/revision")

static func _restore_continuations(t: Sm2TestHarness) -> void:
	var catalog: Sm2TurnCatalog = Sm2TurnTestFixtures.catalog()
	var uninterrupted: Sm2TacticalBattle = _battle(t, catalog)
	for operation: String in ["move", "wait", "wait", "end_turn", "move", "end_turn", "end_turn", "wait"]:
		var restored: Sm2TacticalBattle = Sm2TacticalBattle.new(catalog)
		var snapshot: Dictionary = uninterrupted.capture()
		var json_copy: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
		t.expect(restored.restore(json_copy).ok, "M2 JSON restore at command boundary")
		t.equal(restored.state_hash(), uninterrupted.state_hash(), "M2 exact restored hash without scheduling")
		var target: Vector2i = Vector2i(1, 0) if uninterrupted.view().revision == 0 else Vector2i(2, 0)
		var command: Sm2Command = Sm2TurnTestFixtures.command(uninterrupted, operation, target)
		var expected: Sm2CommandResult = uninterrupted.execute(command)
		var actual: Sm2CommandResult = restored.execute(command)
		t.expect(expected.accepted and actual.accepted, "M2 continuous and restored action accepted")
		t.equal(actual.events, expected.events, "M2 exact next events after reload")
		t.equal(restored.state_hash(), uninterrupted.state_hash(), "M2 exact next full hash after reload")
