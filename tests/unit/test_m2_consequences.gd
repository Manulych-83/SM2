extends RefCounted

static func run(t: Sm2TestHarness) -> void:
	_reactions(t)
	_morale(t)
	_outcomes(t)
	_retreat(t)
	_atomicity(t)
	t.complete_suite("m2_consequences")

static func battle(t: Sm2TestHarness, ids: Array[int] = [2, 5], seed_value: int = 1231, positions: Array[Vector2i] = []) -> Sm2TacticalBattle:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var setup: Dictionary = Sm2CombatFixtures.setup(content, ids, seed_value)
	for index: int in positions.size():
		setup.actors[index].q = positions[index].x
		setup.actors[index].r = positions[index].y
	var result: Sm2TacticalBattle = Sm2TacticalBattle.new(content.catalog, content.combat, true)
	var started: Dictionary = result.start(setup)
	t.expect(started.ok, "consequence start " + str(started.get("errors", [])))
	return result

static func act(t: Sm2TestHarness, b: Sm2TacticalBattle, kind: String, target: Vector2i = Vector2i.ZERO) -> Sm2CommandResult:
	var revision: int = b.view().revision
	var result: Sm2CommandResult = b.execute(Sm2TurnTestFixtures.command(b, kind, target))
	t.expect(result.accepted, "consequence " + kind + ": " + result.code)
	t.equal(result.revision, revision + 1, "consequence one revision")
	for index: int in result.events.size():
		t.equal(result.events[index].sequence, index, "consequence event order")
	return result

static func events_of(events: Array[Dictionary], kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in events:
		if event.type == kind:
			result.append(event)
	return result

static func restore(t: Sm2TestHarness, b: Sm2TacticalBattle, data: Dictionary) -> void:
	var result: Dictionary = b.restore(data)
	t.expect(result.ok, "consequence fixture restores " + str(result.get("errors", [])))

static func _reactions(t: Sm2TestHarness) -> void:
	var b: Sm2TacticalBattle = battle(t)
	var result: Sm2CommandResult = act(t, b, "move", Vector2i(0, 2))
	t.equal(result.code, "movement_interrupted", "hit stops step")
	var mover: Dictionary = Sm2CombatFixtures.actor(b.view(), 2)
	var guard: Dictionary = Sm2CombatFixtures.actor(b.view(), 5)
	t.equal([mover.q, mover.r, mover.ap, mover.fatigue], [1, 2, 7, 4], "hit retains origin and movement price")
	t.equal([guard.ap, guard.fatigue, guard.reactions_left], [9, 5, 0], "reaction is zero AP, five fatigue, one charge")
	t.equal(events_of(result.events, "attack_hit")[0].roll, 1, "reaction hit oracle")
	t.equal(b.capture().rng.draws, "3", "small hit has exactly hit/zone/damage draws")
	result = act(t, b, "move", Vector2i(0, 2))
	t.equal(events_of(result.events, "reaction_spent").size(), 0, "spent charge cannot react again")
	t.equal(Sm2CombatFixtures.actor(b.view(), 2).q, 0, "second step succeeds")
	b = battle(t, [2, 5], 76)
	result = act(t, b, "move", Vector2i(0, 2))
	t.equal(result.code, "accepted", "miss allows departure")
	t.equal(b.capture().rng.draws, "1", "miss consumes hit draw only")
	# Any step from control, including staying adjacent, provokes.
	b = battle(t)
	result = act(t, b, "move", Vector2i(1, 3))
	t.equal(result.code, "movement_interrupted", "adjacent to adjacent provokes")
	b = battle(t, [2, 5], 1231, [Vector2i(0, 2), Vector2i(2, 2)])
	result = act(t, b, "move", Vector2i(1, 2))
	t.equal(b.capture().rng.draws, "0", "entry into control does not provoke")
	for condition: String in ["fatigue", "fleeing", "no_charge"]:
		b = battle(t)
		var data: Dictionary = Sm2CombatFixtures.untyped(b)
		guard = Sm2CombatFixtures.actor(data, 5)
		match condition:
			"fatigue": guard.fatigue = 61
			"fleeing": guard.morale = "fleeing"
			"no_charge": guard.reactions_left = 0
		restore(t, b, data)
		result = act(t, b, "move", Vector2i(0, 2))
		t.equal(events_of(result.events, "reaction_spent").size(), 0, "unavailable reaction " + condition)
	# Numeric controller order, first miss then hit; later guards remain unspent.
	b = battle(t, [2, 4, 5], 36, [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3)])
	result = act(t, b, "move", Vector2i(1, 2))
	var reactions: Array[Dictionary] = events_of(result.events, "reaction_spent")
	t.equal([reactions[0].actor_id, reactions[1].actor_id], ["4", "5"], "reaction numeric ID order")
	t.equal(result.code, "movement_interrupted", "second guard hit stops move")
	b = battle(t, [2, 4, 5], 1231, [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3)])
	result = act(t, b, "move", Vector2i(1, 2))
	t.equal(events_of(result.events, "reaction_spent").size(), 1, "first hit prevents later reactions")
	t.equal(Sm2CombatFixtures.actor(b.view(), 5).reactions_left, 1, "later charge retained")
	# Guard may react even with zero AP after its own completed activation.
	b = battle(t)
	act(t, b, "end_turn")
	result = act(t, b, "move", Vector2i(3, 2))
	t.equal(events_of(result.events, "reaction_spent")[0].actor_id, "2", "completed actor reacts")
	t.equal(Sm2CombatFixtures.actor(b.view(), 2).ap, 0, "reaction never restores AP")
	# A killed mover must never be replaced by a stale movement copy.
	b = battle(t)
	var data: Dictionary = Sm2CombatFixtures.untyped(b)
	mover = Sm2CombatFixtures.actor(data, 2)
	mover.combat.hp = 1
	Sm2CombatFixtures.item(mover, "body").current = 0
	Sm2CombatFixtures.item(mover, "head").current = 0
	restore(t, b, data)
	result = act(t, b, "move", Vector2i(0, 2))
	mover = Sm2CombatFixtures.actor(b.view(), 2)
	t.equal([mover.alive, mover.combat.hp, mover.q, mover.ap], [false, 0, 1, 0], "reaction death cannot resurrect mover")
	t.equal(b.outcome().winner, "opposition", "reaction death resolves victory")

static func _state(t: Sm2TestHarness, ids: Array[int] = [2, 5]) -> Dictionary:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var b: Sm2TacticalBattle = battle(t, ids)
	var decoded: Dictionary = Sm2CombatSnapshot.decode(b.capture(), content.catalog, content.combat, true)
	t.expect(decoded.ok, "morale detached fixture")
	return {"state": decoded.state, "catalog": content.combat}

static func _morale(t: Sm2TestHarness) -> void:
	# Independent threshold oracles: fighter HP60, resolve45, one enemy => M35.
	for row: Array in [[11, 16, "steady", 0], [12, 85, "steady", 1], [12, 16, "wavering", 1]]:
		var fixture: Dictionary = _state(t)
		var state: Sm2TacticalState = fixture.state
		state.rng = Sm2DeterministicRng.new(row[1])
		var events: Array[Dictionary] = []
		t.expect(Sm2MoraleResolver.after_hit(state, fixture.catalog, state.actor(2), row[0], Sm2ConsequenceContext.new(), events), "morale oracle completes")
		t.equal(state.actor(2).morale, row[2], "HP threshold and M/M+1 oracle " + str(row))
		t.equal(state.rng.draws, row[3], "morale threshold draw count")
		if row[3] == 1:
			t.equal(events[0].threshold, 35, "resolve45 minus penalty10")
	var fixture: Dictionary = _state(t, [2, 4, 5])
	var state: Sm2TacticalState = fixture.state
	state.actor(5).spatial.position = Vector2i(1, 3)
	for seed_value: int in [30, 61]:
		state.rng = Sm2DeterministicRng.new(seed_value)
		state.actor(2).morale = "steady"
		var events: Array[Dictionary] = []
		t.expect(Sm2MoraleResolver.after_hit(state, fixture.catalog, state.actor(2), 12, Sm2ConsequenceContext.new(), events), "surround morale check")
		t.equal(events[0].threshold, 30, "two enemies add five penalty")
		t.equal(state.actor(2).morale, "steady" if seed_value == 30 else "wavering", "surround M/M+1")
	# Death -> first ally panics -> farther ally receives its first panic cause.
	fixture = _state(t, [1, 2, 3, 5])
	state = fixture.state
	state.actor(1).spatial.position = Vector2i(0, 2)
	state.actor(2).spatial.position = Vector2i(4, 2)
	state.actor(3).spatial.position = Vector2i(7, 2)
	state.actor(5).spatial.position = Vector2i(7, 4)
	state.actor(1).spatial.alive = false
	state.actor(1).combat.hp = 0
	state.actor(2).morale = "breaking"
	state.rng = Sm2DeterministicRng.new(1)
	var context: Sm2ConsequenceContext = Sm2ConsequenceContext.new()
	var events: Array[Dictionary] = []
	t.expect(Sm2MoraleResolver.after_hit(state, fixture.catalog, state.actor(1), 1, context, events), "death panic FIFO")
	var checks: Array[Dictionary] = events_of(events, "morale_checked")
	t.equal([checks[0].actor_id, checks[0].cause, checks[1].actor_id, checks[1].cause], ["2", "ally_died", "3", "ally_fled"], "radius four and queued panic cascade")
	t.equal(state.actor(2).morale, "fleeing", "breaking becomes fleeing")
	var draws: int = state.rng.draws
	t.expect(Sm2MoraleResolver.after_hit(state, fixture.catalog, state.actor(3), 50, context, events), "same context reused")
	t.equal(state.rng.draws, draws, "at most one morale check per command")
	# Immunity, escaped, already fleeing have no draw even from large damage fact.
	for mode: String in ["immune", "escaped", "fleeing", "dead"]:
		fixture = _state(t)
		state = fixture.state
		var catalog: Sm2CombatCatalog = fixture.catalog
		if mode == "immune":
			var raw: Dictionary = catalog.to_data()
			for profile: Dictionary in raw.profiles:
				profile.morale_immune = true
			catalog = Sm2CombatCatalog.new()
			var content: Dictionary = Sm2CombatFixtures.loaded()
			t.expect(catalog.build(raw, content.catalog).is_empty(), "immune profile valid")
		elif mode == "escaped": state.actor(2).spatial.on_field = false
		elif mode == "fleeing": state.actor(2).morale = "fleeing"
		else: state.actor(2).spatial.alive = false
		events = []
		t.expect(Sm2MoraleResolver.after_hit(state, catalog, state.actor(2), 60, Sm2ConsequenceContext.new(), events), "morale skip " + mode)
		t.equal(state.rng.draws, 0, "ineligible morale no draw " + mode)

static func _outcomes(t: Sm2TestHarness) -> void:
	var b: Sm2TacticalBattle = battle(t, [2, 5], 1231, [Vector2i(0, 0), Vector2i(7, 4)])
	var result: Sm2CommandResult = act(t, b, "escape")
	t.equal(b.outcome().winner, "opposition", "last company departure loses")
	t.equal(b.outcome().counts.company, {"dead": 0, "escaped": 1, "on_field": 0}, "escaped differs from dead")
	t.equal(b.capture().rng.draws, "0", "voluntary escape no morale RNG")
	t.equal(events_of(result.events, "battle_finished").size(), 1, "one finish event")
	t.equal([b.view().active_actor_id, b.view().main_queue, b.view().deferred_queue], [0, [], []], "finished queues empty")
	var before: String = b.state_hash()
	t.expect(not b.execute(Sm2TurnTestFixtures.command(b, "end_turn")).accepted, "finished rejects commands")
	t.equal(b.state_hash(), before, "finished rejection unchanged")
	b = battle(t, [2, 5], 1231, [Vector2i(0, 2), Vector2i(1, 2)])
	result = act(t, b, "escape")
	t.equal(result.code, "movement_interrupted", "escape provokes")
	t.expect(Sm2CombatFixtures.actor(b.view(), 2).on_field, "interrupted escape remains present")
	act(t, b, "escape")
	t.expect(b.view().finished, "second escape after spent reaction ends battle")
	b = battle(t, [2, 5, 1], 76, [Vector2i(0, 2), Vector2i(1, 2), Vector2i(7, 4)])
	act(t, b, "escape")
	t.equal(b.view().active_actor_id, 1, "escape activates next numeric tie winner")
	t.expect(not b.view().finished, "remaining allies keep battle active")
	# Both panicked but present still participate; last round alone produces draw.
	b = battle(t)
	var data: Dictionary = Sm2CombatFixtures.untyped(b)
	data.round_limit = 1
	for actor: Dictionary in data.actors: actor.morale = "fleeing"
	restore(t, b, data)
	t.expect(not b.view().finished, "panic is not removal")
	act(t, b, "end_turn")
	result = act(t, b, "end_turn")
	t.equal([b.outcome().reason, b.outcome().winner], ["round_limit", null], "round limit draw")
	t.equal(events_of(result.events, "battle_finished").size(), 1, "round limit emits one outcome")
	# Last kill on final round wins before scheduler replenishes any resources.
	b = battle(t)
	data = Sm2CombatFixtures.untyped(b)
	data.round_limit = 1
	Sm2CombatFixtures.actor(data, 2).ap = 4
	var victim: Dictionary = Sm2CombatFixtures.actor(data, 5)
	victim.combat.hp = 1
	Sm2CombatFixtures.item(victim, "body").current = 0
	Sm2CombatFixtures.item(victim, "head").current = 0
	restore(t, b, data)
	result = Sm2CombatFixtures.act(t, b, "sword_strike", 5)
	t.equal([b.outcome().reason, b.outcome().winner, b.view().round], ["opposition_removed", "company", 1], "victory before limit")
	t.equal(events_of(result.events, "round_started").size(), 0, "no resource reset after victory")
	var fixture: Dictionary = _state(t)
	var state: Sm2TacticalState = fixture.state
	for id: int in state.sorted_ids():
		state.actor(id).spatial.on_field = false
		state.actor(id).reactions_left = 0
	var events: Array[Dictionary] = []
	Sm2BattleOutcome.evaluate(state, events)
	t.equal([state.finish_reason, state.winner], ["mutual_removal", ""], "compound mutual removal outcome")
	var content: Dictionary = Sm2CombatFixtures.loaded()
	t.expect(Sm2CombatSnapshot.decode(state.to_data(content.catalog.fingerprint()), content.catalog, content.combat, true).ok, "mutual removal snapshot valid")

static func _retreat(t: Sm2TestHarness) -> void:
	var b: Sm2TacticalBattle = battle(t, [2, 5], 1231, [Vector2i(3, 2), Vector2i(7, 4)])
	var data: Dictionary = Sm2CombatFixtures.untyped(b)
	Sm2CombatFixtures.actor(data, 2).morale = "fleeing"
	restore(t, b, data)
	var decision: Dictionary = b.retreat_decision()
	t.expect(decision.ok, "retreat route available")
	t.equal(decision.route.destination, Vector2i(1, 4), "two diagonal steps reach lower q boundary before equally distant upper edge")
	t.equal([decision.route.ap_cost, decision.route.fatigue_cost], [6, 12], "route includes escape price")
	var prior: String = b.state_hash()
	b.retreat_decision().route.path.clear()
	t.equal(b.state_hash(), prior, "retreat query detached")
	for kind: String in ["wait", "use_ability"]:
		var command: Sm2Command = Sm2TurnTestFixtures.command(b, kind)
		command.ability_id = "m2:ability.sword_strike"
		command.target_actor_id = 5
		t.expect(not b.execute(command).accepted, "fleeing rejects " + kind)
		t.equal(b.state_hash(), prior, "fleeing rejection atomic")
	data = Sm2CombatFixtures.untyped(b)
	Sm2CombatFixtures.actor(data, 2).ap = 1
	restore(t, b, data)
	t.equal(b.retreat_decision().command.kind, "end_turn", "low AP ends activation")
	act(t, b, "end_turn")
	act(t, b, "end_turn")
	t.equal(b.view().round, 2, "retreat resumes next round")
	for index: int in 4:
		if b.view().finished: break
		decision = b.retreat_decision()
		t.expect(b.execute(decision.command).accepted, "retreat ordinary command executes")
	t.expect(b.view().finished, "retreat reaches escape over rounds")
	# Completely blocked interior has no path and never teleports.
	var field: Sm2Battlefield = Sm2SpatialFixtures.field(5, 5)
	var occupied: Array[Vector2i] = Sm2Hex.neighbors(Vector2i(2, 2))
	var route: Dictionary = Sm2SpatialQueries.route_to_boundary(field, Vector2i(2, 2), occupied, 9, 65)
	t.equal([route.ok, route.reason], [false, "unreachable"], "surrounded retreat no path")
	# Occupying the previous chosen step forces deterministic replanning.
	var route1: Dictionary = Sm2SpatialQueries.route_to_boundary(field, Vector2i(2, 2), [], 9, 65)
	var route2: Dictionary = Sm2SpatialQueries.route_to_boundary(field, Vector2i(2, 2), [route1.path[0]], 9, 65)
	t.expect(route2.ok and route2.path[0] != route1.path[0], "retreat replans blocked first step")

static func _atomicity(t: Sm2TestHarness) -> void:
	for extra_draws: int in [0, 1, 2, 3]:
		var b: Sm2TacticalBattle = battle(t)
		var data: Dictionary = Sm2CombatFixtures.untyped(b)
		data.rng.draws = str(Sm2BattleDice.MAX_COUNTER - extra_draws)
		var mover: Dictionary = Sm2CombatFixtures.actor(data, 2)
		Sm2CombatFixtures.item(mover, "head").current = 0
		Sm2CombatFixtures.item(mover, "body").current = 0
		restore(t, b, data)
		var before: String = b.state_hash()
		var result: Sm2CommandResult = b.execute(Sm2TurnTestFixtures.command(b, "move", Vector2i(0, 2)))
		t.equal([result.accepted, result.code], [false, "rng_counter_limit"], "ceiling at hit/zone/damage/morale " + str(extra_draws))
		t.equal(b.state_hash(), before, "ceiling rolls back costs, damage, RNG and queues")
		t.expect(result.events.is_empty(), "failed transaction emits no events")
	var b: Sm2TacticalBattle = battle(t)
	var before: String = b.state_hash()
	var command: Sm2Command = Sm2TurnTestFixtures.command(b, "move", Vector2i(2, 2))
	t.equal(b.execute(command).code, "occupied", "occupied target rejected before reaction")
	t.equal(b.state_hash(), before, "invalid step no reaction cost")
	t.equal(b.execute(Sm2TurnTestFixtures.command(b, "escape")).code, "escape_boundary_required", "interior escape rejected")
	t.equal(b.state_hash(), before, "invalid escape atomic")
