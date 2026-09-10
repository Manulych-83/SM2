extends RefCounted
const C: GDScript = preload("res://tests/unit/test_m2_consequences.gd")

static func run(t: Sm2TestHarness) -> void:
	_persistence(t)
	_negative(t)
	_panic_wait(t)
	_zero_hp_and_control(t)
	t.complete_suite("m2_consequence_storage")

static func _session(content: Dictionary, store: Sm2SaveStore) -> Sm2TacticalSession:
	return Sm2TacticalSession.new(content.catalog, store, content.combat, true)

static func _payload(content: Dictionary, b: Sm2TacticalBattle) -> Dictionary:
	return {"format": Sm2TacticalSession.CONSEQUENCE_FORMAT, "catalog": content.catalog.fingerprint(), "battle": b.capture(), "result_recorded": false}

static func _command(session: Sm2TacticalSession, kind: String, target: Vector2i = Vector2i.ZERO) -> Sm2Command:
	return Sm2SpatialFixtures.command(session.view().active_actor_id, session.view().revision, target, kind)

static func _disk(t: Sm2TestHarness, session: Sm2TacticalSession, content: Dictionary, store: Sm2SaveStore, command: Sm2Command) -> void:
	var before: String = session.state_hash()
	t.expect(session.save_game().ok, "consequences disk save")
	t.equal(session.state_hash(), before, "save query unchanged")
	var restored: Sm2TacticalSession = _session(content, store)
	t.expect(restored.load_game().ok, "consequences disk load")
	t.equal(restored.state_hash(), before, "disk state including morale/outcome exactly equal")
	if command != null:
		var left: Sm2CommandResult = session.execute(command)
		var right: Sm2CommandResult = restored.execute(command)
		t.expect(left.accepted and right.accepted, "both continuations accepted " + left.code + "/" + right.code)
		t.equal(left.events, right.events, "future event stream equal after load")
		t.equal(session.state_hash(), restored.state_hash(), "future state equal after load")

static func _persistence(t: Sm2TestHarness) -> void:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var directory: String = "user://tests/consequences_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var store: Sm2SaveStore = Sm2SaveStore.new(directory)
	t.expect(store.save_slot({"sentinel": "M1 untouched"}, "session").ok, "M1 test sentinel")
	var sentinel: String = FileAccess.get_sha256(directory.path_join("session.json"))
	var session: Sm2TacticalSession = _session(content, store)
	var b: Sm2TacticalBattle = C.battle(t)
	t.expect(session.restore_payload(_payload(content, b)).ok, "new format session restores")
	_disk(t, session, content, store, _command(session, "move", Vector2i(0, 2)))
	_disk(t, session, content, store, _command(session, "move", Vector2i(0, 2)))
	_disk(t, session, content, store, _command(session, "escape"))
	t.expect(session.view().finished, "saved escape ends battle")
	_disk(t, session, content, store, null)
	var before: String = session.state_hash()
	t.expect(not session.new_battle(content.setup).ok, "unrecorded finished result cannot be replaced")
	t.equal(session.state_hash(), before, "blocked replacement unchanged")
	var recorded: Dictionary = session.record_outcome()
	t.equal(recorded.code, "recorded", "first result recorded")
	t.equal(recorded.outcome.counts.company.escaped, 1, "recorded escaped participant")
	before = session.state_hash()
	t.equal(session.record_outcome().code, "already_recorded", "duplicate result not emitted")
	t.equal(session.state_hash(), before, "duplicate recording unchanged")
	_disk(t, session, content, store, null)
	var restored: Sm2TacticalSession = _session(content, store)
	t.expect(restored.load_game().ok, "record flag disk load")
	t.equal(restored.record_outcome(), {"ok": true, "code": "already_recorded", "outcome": {}}, "recorded result not repeated after restart")
	t.expect(session.new_battle(content.setup).ok, "recorded result permits next battle")
	t.equal(session.capture().result_recorded, false, "next encounter resets recording flag")
	t.expect(not session.record_outcome().ok, "unfinished cannot record")
	t.equal(FileAccess.get_sha256(directory.path_join("session.json")), sentinel, "M1 slot bytes unchanged")
	# Policy executes exactly one step, without acting inside save/load.
	var retreat_ids: Array[int] = [2, 5]
	var retreat_positions: Array[Vector2i] = [Vector2i(3, 2), Vector2i(7, 4)]
	b = C.battle(t, retreat_ids, 1231, retreat_positions)
	var data: Dictionary = Sm2CombatFixtures.untyped(b)
	Sm2CombatFixtures.actor(data, 2).morale = "fleeing"
	C.restore(t, b, data)
	t.expect(session.restore_payload(_payload(content, b)).ok, "fleeing session")
	var rev: int = session.view().revision
	t.expect(session.advance_retreat().accepted, "session executes retreat step")
	t.equal(session.view().revision, rev + 1, "one policy call one command")
	_disk(t, session, content, store, null)
	for index: int in 3:
		if session.view().finished: break
		t.expect(session.advance_retreat().accepted, "session continues retreat")
	t.expect(session.view().finished, "policy reaches escape")

static func _negative(t: Sm2TestHarness) -> void:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var b: Sm2TacticalBattle = C.battle(t)
	var base: Dictionary = Sm2CombatFixtures.untyped(b)
	for kind: String in ["winner", "winner_type", "winner_missing", "unknown", "improved", "fake_finish", "one_side_unfinished", "bad_anchor", "old_schema", "old_ruleset"]:
		var data: Dictionary = base.duplicate(true)
		match kind:
			"winner": data.winner = "company"
			"winner_type": data.winner = 2
			"winner_missing": data.erase("winner")
			"unknown": data.hidden_effect = true
			"improved": Sm2CombatFixtures.actor(data, 2).round_morale = "breaking"
			"fake_finish":
				data.finished = true
				data.finish_reason = "opposition_removed"
			"one_side_unfinished":
				var actor: Dictionary = Sm2CombatFixtures.actor(data, 5)
				actor.on_field = false
				actor.ap = 0
				actor.reactions_left = 0
				actor.turn_done = true
				data.main_queue.erase("5")
			"bad_anchor": Sm2CombatFixtures.actor(data, 2).initiative += 1
			"old_schema": data.schema_version = 3
			"old_ruleset": data.ruleset = Sm2CombatSnapshot.RULESET
		var before: String = b.state_hash()
		t.expect(not b.restore(data).ok, "invalid new snapshot " + kind)
		t.equal(b.state_hash(), before, "snapshot rejection atomic " + kind)
	var old: Sm2TacticalBattle = Sm2TacticalBattle.new(content.catalog, content.combat)
	t.expect(not old.restore(base).ok, "legacy does not silently load new mode")
	var session: Sm2TacticalSession = _session(content, null)
	t.expect(session.restore_payload(_payload(content, b)).ok, "negative session fixture")
	for kind: String in ["recorded_unfinished", "recorded_type", "missing", "extra", "legacy_format"]:
		var data: Dictionary = JSON.parse_string(JSON.stringify(session.capture()))
		match kind:
			"recorded_unfinished": data.result_recorded = true
			"recorded_type": data.result_recorded = "false"
			"missing": data.erase("result_recorded")
			"extra": data.other_battle_result = {}
			"legacy_format": data.format = Sm2TacticalSession.COMBAT_FORMAT
		var before: String = session.state_hash()
		t.expect(not session.restore_payload(data).ok, "invalid session " + kind)
		t.equal(session.state_hash(), before, "session rejection atomic")
	# Outcome collections do not expose live combat objects.
	C.act(t, b, "move", Vector2i(0, 2))
	C.act(t, b, "move", Vector2i(0, 2))
	C.act(t, b, "escape")
	var before: String = b.state_hash()
	var outcome: Dictionary = b.outcome()
	outcome.participants[0].combat.hp = 999
	outcome.counts.clear()
	t.equal(b.state_hash(), before, "outcome detached from live state")

static func _panic_wait(t: Sm2TestHarness) -> void:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var b: Sm2TacticalBattle = C.battle(t)
	Sm2CombatFixtures.act(t, b, "shieldwall", 2)
	C.act(t, b, "wait")
	var data: Dictionary = Sm2CombatFixtures.untyped(b)
	var target: Dictionary = Sm2CombatFixtures.actor(data, 2)
	target.morale = "breaking"
	Sm2CombatFixtures.item(target, "body").current = 0
	Sm2CombatFixtures.item(target, "head").current = 0
	C.restore(t, b, data)
	var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/panic_wait_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()])
	var session: Sm2TacticalSession = _session(content, store)
	t.expect(session.restore_payload(_payload(content, b)).ok, "pending panic session")
	var command: Sm2Command = _command(session, "use_ability")
	command.ability_id = "m2:ability.spear_thrust"
	command.target_actor_id = 2
	_disk(t, session, content, store, command)
	target = Sm2CombatFixtures.actor(session.capture().battle, 2)
	t.equal([target.morale, target.round_morale, target.initiative, target.wait_used], ["fleeing", "steady", 88, true], "panic after Wait preserves frozen order and history")
	t.equal(target.combat.shieldwall_source, "0", "panic clears active shieldwall")
	t.equal([target.owner, target.controller, target.side], [Sm2CombatFixtures.actor(data, 2).owner, Sm2CombatFixtures.actor(data, 2).controller, "company"], "panic preserves permanent control")
	_disk(t, session, content, store, _command(session, "end_turn"))
	t.equal(session.view().active_actor_id, 2, "panicked waiter resumes deferred activation")
	_disk(t, session, content, store, null)
	t.expect(session.advance_retreat().accepted, "resumed waiter uses retreat policy")

static func _zero_hp_and_control(t: Sm2TestHarness) -> void:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var raw: Dictionary = content.combat.to_data()
	for gear: Dictionary in raw.equipment:
		if gear.slot in ["body", "head"]: gear.capacity = 1000
	var catalog: Sm2CombatCatalog = Sm2CombatCatalog.new()
	t.expect(catalog.build(raw, content.catalog).is_empty(), "thick armor fixture is valid custom content")
	var b: Sm2TacticalBattle = Sm2TacticalBattle.new(content.catalog, catalog, true)
	t.expect(b.start(Sm2CombatFixtures.setup(content)).ok, "thick armor scenario starts")
	var result: Sm2CommandResult = C.act(t, b, "move", Vector2i(0, 2))
	t.equal(C.events_of(result.events, "hp_damaged")[0].loss, 0, "reaction zero HP damage oracle")
	t.equal(result.code, "movement_interrupted", "zero HP hit still stops move")
	t.equal(b.capture().rng.draws, "3", "zero damage does not trigger morale")
	# A bow never controls; elevation gap prevents otherwise available melee reaction.
	var bow_ids: Array[int] = [2, 6]
	b = C.battle(t, bow_ids, 1231)
	C.act(t, b, "end_turn")
	result = C.act(t, b, "move", Vector2i(0, 2))
	t.equal(C.events_of(result.events, "reaction_spent").size(), 0, "bow does not react")
	var setup: Dictionary = Sm2CombatFixtures.setup(content)
	setup.field = Sm2SpatialFixtures.field(8, 5, [Sm2SpatialFixtures.tile(2, 2, "ground", 2)]).to_data()
	b = Sm2TacticalBattle.new(content.catalog, content.combat, true)
	t.expect(b.start(setup).ok, "height scenario starts")
	result = C.act(t, b, "move", Vector2i(0, 2))
	t.equal(C.events_of(result.events, "reaction_spent").size(), 0, "height gap prevents control")
