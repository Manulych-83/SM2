extends RefCounted

static func run(t: Sm2TestHarness) -> void:
	_profile(t)
	_choices(t)
	_paths(t)
	_guards(t)
	_full_battle(t)
	t.complete_suite("m2_ai")

static func _profile(t: Sm2TestHarness) -> void:
	var loaded: Dictionary = Sm2AiContentLoader.load_profile()
	t.expect(loaded.ok, "authored AI profile loads")
	var profile: Sm2AiProfile = loaded.profile
	t.equal(profile.to_data().hp_weight, 4, "authored score HP weight")
	var before: String = profile.fingerprint()
	for key: String in ["policy", "hp_weight", "attempt_limit", "query_limit", "extra"]:
		var data: Dictionary = profile.to_data()
		match key:
			"policy": data.policy = "unknown"
			"hp_weight": data.hp_weight = -1
			"attempt_limit": data.attempt_limit = 0
			"query_limit": data.query_limit = 200001
			"extra": data.extra = 1
		t.expect(not profile.build(data).is_empty(), "invalid AI profile " + key)
		t.equal(profile.fingerprint(), before, "AI profile candidate atomic")
	profile.to_data().hp_weight = 999
	t.equal(profile.fingerprint(), before, "AI profile detached")
	# Policy has no execution/capture or random API. Queries never copy actual RNG.
	var policy_source: String = FileAccess.get_file_as_string("res://src/domain/ai/sm2_tactical_ai.gd")
	for forbidden: String in [".capture(", ".execute(", ".rng", "Sm2BattleDice", "Sm2DeterministicRng"]:
		t.expect(not policy_source.contains(forbidden), "AI does not use " + forbidden)

static func battle(t: Sm2TestHarness, ids: Array[int] = [2, 5], seed_value: int = 1231) -> Sm2TacticalBattle:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var b: Sm2TacticalBattle = Sm2TacticalBattle.new(content.catalog, content.combat, true)
	t.expect(b.start(Sm2CombatFixtures.setup(content, ids, seed_value)).ok, "AI fixture starts")
	return b

static func decide(t: Sm2TestHarness, b: Sm2TacticalBattle) -> Dictionary:
	var profile: Sm2AiProfile = Sm2AiContentLoader.load_profile().profile
	var before: String = b.state_hash()
	var result: Dictionary = b.ai_decision(profile)
	t.expect(result.ok, "AI decides " + str(result.get("reason", "")))
	t.equal(b.state_hash(), before, "AI query preserves full battle hash")
	if result.ok:
		t.expect(b.preview(result.command).allowed, "AI command passes shared legality")
		var second: Dictionary = b.ai_decision(profile)
		t.equal(Sm2TacticalAi.command_data(result.command), Sm2TacticalAi.command_data(second.command), "same view same decision")
	return result

static func _restore(t: Sm2TestHarness, b: Sm2TacticalBattle, data: Dictionary) -> void:
	var result: Dictionary = b.restore(data)
	t.expect(result.ok, "AI fixture restore " + str(result.get("errors", [])))

static func _choices(t: Sm2TestHarness) -> void:
	var b: Sm2TacticalBattle = battle(t)
	var decision: Dictionary = decide(t, b)
	t.equal([decision.choice, decision.command.ability_id, decision.command.target_actor_id], ["attack", "m2:ability.sword_strike", 5], "ordinary attack priority")
	var preview: Dictionary = b.preview(decision.command)
	t.equal(decision.score, 4 * int(preview.expected_hp_loss_x100) + int(preview.expected_armor_loss_x100), "score uses shared expectation")
	var data: Dictionary = Sm2CombatFixtures.untyped(b)
	data.rng.state = "76"
	data.rng.draws = "999"
	_restore(t, b, data)
	t.equal(Sm2TacticalAi.command_data(decide(t, b).command), Sm2TacticalAi.command_data(decision.command), "future RNG cannot affect AI selection")
	# Shieldwall is only the remaining-AP fallback, not preferred to an attack.
	data = Sm2CombatFixtures.untyped(b)
	Sm2CombatFixtures.actor(data, 2).ap = 3
	_restore(t, b, data)
	t.equal(decide(t, b).choice, "shieldwall", "three AP shield fallback")
	data = Sm2CombatFixtures.untyped(b)
	Sm2CombatFixtures.actor(data, 2).fatigue = 70
	_restore(t, b, data)
	t.equal(decide(t, b).command.kind, "end_turn", "no wandering when in range but exhausted")
	b = battle(t, [2, 4])
	Sm2CombatFixtures.end(t, b)
	t.equal(decide(t, b).choice, "attack", "full inactive shield not split")
	data = Sm2CombatFixtures.untyped(b)
	Sm2CombatFixtures.item(Sm2CombatFixtures.actor(data, 2), "shield").current = 16
	_restore(t, b, data)
	t.equal(decide(t, b).choice, "shield_break", "shield16 split before damage")
	b = battle(t, [2, 4])
	Sm2CombatFixtures.act(t, b, "shieldwall", 2)
	Sm2CombatFixtures.end(t, b)
	t.equal(decide(t, b).choice, "shield_break", "active shield24 split priority")
	b = battle(t, [3, 5])
	data = Sm2CombatFixtures.untyped(b)
	Sm2CombatFixtures.item(Sm2CombatFixtures.actor(data, 3), "weapon").ammo = 0
	_restore(t, b, data)
	t.equal(decide(t, b).choice, "retreat", "no ammunition uses escape policy")
	b = battle(t)
	data = Sm2CombatFixtures.untyped(b)
	Sm2CombatFixtures.actor(data, 2).morale = "fleeing"
	_restore(t, b, data)
	t.equal(decide(t, b).choice, "retreat", "panic overrides all combat choices")
	# Equal targets use numeric IDs, regardless of input/read-model iteration.
	b = battle(t, [2, 5, 1])
	data = Sm2CombatFixtures.untyped(b)
	var ally: Dictionary = Sm2CombatFixtures.actor(data, 1)
	ally.side = "opposition"
	ally.q = 1
	ally.r = 3
	_restore(t, b, data)
	t.equal(decide(t, b).command.target_actor_id, 1, "equal attack score picks lower numeric ID")

static func _paths(t: Sm2TestHarness) -> void:
	var b: Sm2TacticalBattle = battle(t)
	var data: Dictionary = Sm2CombatFixtures.untyped(b)
	Sm2CombatFixtures.actor(data, 5).q = 6
	_restore(t, b, data)
	var decision: Dictionary = decide(t, b)
	t.equal(decision.choice, "approach", "out of range approaches")
	t.equal(decision.command.target, Vector2i(2, 2), "first shortest approach step")
	t.equal(decision.route.ap_cost, 8, "route reaches adjacent attack tile")
	t.equal(decision.route.risk, 0, "safe route risk zero")
	data = Sm2CombatFixtures.untyped(b)
	Sm2CombatFixtures.actor(data, 2).ap = 1
	_restore(t, b, data)
	t.equal(decide(t, b).choice, "movement_resources", "unaffordable first step ends turn")
	# Risk outranks route AP. Same general spatial search, independent path oracle.
	var field: Sm2Battlefield = Sm2SpatialFixtures.field(5, 4)
	for risks: Dictionary in [{Vector2i(1, 1): -1}, {Vector2i(9, 1): 1}, {"cell": 1}]:
		t.equal(Sm2SpatialQueries.strategic_cells(field, Vector2i(0, 1), [], 9, 65, risks).reason, "invalid_risk_cells", "invalid risk cannot create negative cycles")
	var routes: Dictionary = Sm2SpatialQueries.strategic_cells(field, Vector2i(0, 1), [], 9, 65, {Vector2i(1, 1): 1})
	for cell: Dictionary in routes.cells:
		if cell.position == Vector2i(3, 1):
			t.equal(cell.risk, 0, "risk search avoids controlled departure")
			t.expect(cell.ap_cost > 6, "safer route may cost more AP")
	# A future archer position removes the old occupancy, avoiding a ghost blocker.
	b = battle(t, [3, 5])
	data = Sm2CombatFixtures.untyped(b)
	Sm2CombatFixtures.actor(data, 3).q = 2
	Sm2CombatFixtures.actor(data, 5).q = 3
	_restore(t, b, data)
	decision = decide(t, b)
	t.equal(decision.choice, "approach", "controlled archer seeks firing tile")
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var state: Sm2TacticalState = Sm2CombatSnapshot.decode(b.capture(), content.catalog, content.combat, true).state
	var query: Sm2AiQueries = Sm2AiQueries.new(state, content.combat)
	var shot: Sm2Command = Sm2CombatFixtures.command(b, "bow_shot", 5)
	t.expect(query.attack(shot, Vector2i(1, 2), true).allowed, "old archer position no longer blocks projected LOS")
	t.expect(not query.attack(shot, Vector2i(2, 2), true).allowed, "actual controlled position still blocks shot")
	var profile: Sm2AiProfile = Sm2AiProfile.new()
	var raw: Dictionary = Sm2AiContentLoader.load_profile().profile.to_data()
	raw.query_limit = 1
	t.expect(profile.build(raw).is_empty(), "small query budget profile valid")
	var before: String = b.state_hash()
	t.equal(b.ai_decision(profile).reason, "ai_query_limit", "query limit is explicit technical failure")
	t.equal(b.state_hash(), before, "query limit leaves battle intact")

static func _runner(content: Dictionary, profile: Sm2AiProfile, self_play: bool = true, store: Sm2SaveStore = null) -> Sm2BattleRunner:
	return Sm2BattleRunner.new(content.catalog, content.combat, profile, store, self_play)

static func _guards(t: Sm2TestHarness) -> void:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var profile: Sm2AiProfile = Sm2AiContentLoader.load_profile().profile
	var runner: Sm2BattleRunner = _runner(content, profile, false)
	t.expect(runner.new_battle(content.setup).ok, "interactive runner starts")
	var before: String = runner.state_hash()
	t.equal(runner.step().status, "player_turn", "default stops for player")
	t.equal(runner.state_hash(), before, "player pause is pure")
	var command: Sm2Command = Sm2SpatialFixtures.command(runner.view().active_actor_id, runner.view().revision, Vector2i.ZERO, "end_turn")
	t.expect(runner.execute_player(command).accepted, "player command accepted")
	t.expect(runner.step().has("command"), "enemy AI takes one step")
	# Force normal rejection with exhausted combat RNG: one reread, then diagnostic.
	runner = _runner(content, profile)
	t.expect(runner.new_battle(Sm2CombatFixtures.setup(content)).ok, "rejection runner starts")
	var data: Dictionary = JSON.parse_string(JSON.stringify(runner.capture()))
	data.session.battle.rng.draws = str(Sm2BattleDice.MAX_COUNTER)
	t.expect(runner.restore(data).ok, "RNG ceiling runner fixture")
	var battle_before: String = Sm2Canonical.hash(runner.capture().session)
	t.equal(runner.step().reason, "ai_command_rejected:rng_counter_limit", "second rejection ends diagnostics")
	t.equal(runner.capture().attempts, 2, "exactly one retry")
	t.equal(Sm2Canonical.hash(runner.capture().session), battle_before, "failed AI changes no combat state")
	t.expect(not runner.view().finished, "technical failure not victory")
	before = runner.state_hash()
	t.expect(not runner.step().ok, "failed runner stays stopped")
	t.equal(runner.state_hash(), before, "stopped diagnostic stable")
	var raw: Dictionary = profile.to_data()
	raw.attempt_limit = 1
	var limited: Sm2AiProfile = Sm2AiProfile.new()
	limited.build(raw)
	runner = _runner(content, limited)
	t.expect(runner.new_battle(Sm2CombatFixtures.setup(content)).ok, "activation budget fixture")
	t.expect(runner.step().ok, "first decision within limit")
	battle_before = Sm2Canonical.hash(runner.capture().session)
	t.equal(runner.step().reason, "ai_attempt_limit", "per activation guard")
	t.equal(Sm2Canonical.hash(runner.capture().session), battle_before, "guard no fabricated end turn")
	var saved_guard: Dictionary = runner.capture()
	var restored_guard: Sm2BattleRunner = _runner(content, limited)
	t.expect(restored_guard.restore(saved_guard).ok, "diagnostic stop restores")
	t.equal(restored_guard.step().reason, "ai_attempt_limit", "reload does not reset activation guard")
	runner = _runner(content, profile)
	t.expect(runner.new_battle(content.setup).ok, "bounded runner starts")
	t.equal(runner.run_to_end(1).reason, "runner_command_limit", "runner command budget is technical result")
	t.expect(not runner.view().finished and not runner.capture().session.result_recorded, "runner budget cannot invent a draw or recorded outcome")

static func _full_battle(t: Sm2TestHarness) -> void:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var profile: Sm2AiProfile = Sm2AiContentLoader.load_profile().profile
	var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/ai_full_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()])
	var runner: Sm2BattleRunner = _runner(content, profile, true, store)
	t.expect(runner.new_battle(content.setup).ok, "authored 3v3 starts")
	for index: int in 12:
		var step: Dictionary = runner.step()
		t.expect(step.ok and step.has("command"), "opening step accepted " + str(step.get("reason", "")))
	t.expect(not runner.view().finished, "save boundary is mid-battle")
	var checkpoint: String = runner.state_hash()
	var initial_session: Dictionary = runner.capture().session
	t.expect(runner.save_game().ok, "full AI save to disk")
	var loaded: Sm2BattleRunner = _runner(content, profile, true, store)
	t.expect(loaded.load_game().ok, "full AI disk load")
	t.equal(loaded.state_hash(), checkpoint, "AI counters/profile/session restored")
	var left: Dictionary = runner.run_to_end()
	var right: Dictionary = loaded.run_to_end()
	t.expect(left.ok and right.ok, "full 3v3 completes " + str(left.get("reason", "")))
	t.equal(left, right, "entire future commands/events/outcome identical after disk load")
	t.equal(runner.state_hash(), loaded.state_hash(), "final snapshots identical")
	var replay: Dictionary = Sm2BattleReplay.replay(content.catalog, content.combat, initial_session, left.history)
	t.expect(replay.ok, "recorded commands replay without AI")
	if replay.ok:
		t.equal(replay.session, runner.capture().session, "command replay final session equal")
	var broken_history: Array = left.history.duplicate(true)
	broken_history[0].command.expected_revision = "0"
	t.equal(Sm2BattleReplay.replay(content.catalog, content.combat, initial_session, broken_history).reason, "replay_diverged", "journal stale revision detected")
	broken_history = left.history.duplicate(true)
	broken_history[0].events.clear()
	t.equal(Sm2BattleReplay.replay(content.catalog, content.combat, initial_session, broken_history).reason, "replay_diverged", "journal event corruption detected")
	if left.ok:
		t.equal(left.status, "finished", "natural full battle finished")
		t.equal(left.outcome.reason, "opposition_removed", "authored battle has ordinary result")
		t.expect(left.history.size() > 10, "full battle is not a one-command fixture")
		t.equal(left.outcome.participants.size(), 6, "all six original participants retained")
		t.equal(runner.step().record.code, "already_recorded", "full runner records outcome once")
	for kind: String in ["profile", "attempts", "activation_key", "self_play", "extra"]:
		var data: Dictionary = JSON.parse_string(JSON.stringify(runner.capture()))
		match kind:
			"profile": data.profile = "other"
			"attempts": data.attempts = 999
			"activation_key": data.activation_key = "other"
			"self_play": data.self_play = false
			"extra": data.extra = true
		var before: String = runner.state_hash()
		t.expect(not runner.restore(data).ok, "invalid runner save " + kind)
		t.equal(runner.state_hash(), before, "runner restore candidate atomic")
