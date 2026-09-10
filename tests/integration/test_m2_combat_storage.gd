extends RefCounted

static func run(t: Sm2TestHarness) -> void:
	_roundtrips(t)
	_broken_shield(t)
	_negative_snapshots(t)
	_isolation_and_compatibility(t)
	t.complete_suite("m2_combat_storage")

static func _roundtrips(t: Sm2TestHarness) -> void:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var directory: String = "user://tests/combat_storage_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var store: Sm2SaveStore = Sm2SaveStore.new(directory)
	t.expect(store.save_slot({"sentinel": "M1 untouched"}, "session").ok, "combat storage sentinel written")
	var original_hash: String = FileAccess.get_sha256(directory.path_join("session.json"))
	var session: Sm2TacticalSession = Sm2TacticalSession.new(content.catalog, store, content.combat)
	t.expect(session.new_battle(Sm2CombatFixtures.setup(content, [2, 5], 36)).ok, "combat disk session starts")
	var actions: Array[Array] = [["use_ability", "sword_strike", 5], ["use_ability", "shieldwall", 2],
		["wait", "", 0], ["use_ability", "spear_thrust", 2], ["end_turn", "", 0],
		["end_turn", "", 0], ["use_ability", "spear_thrust", 2]]
	for action: Array in actions:
		var command: Sm2Command = _command(session, action)
		_disk_compare(t, session, content, store, command)
	t.equal(FileAccess.get_sha256(directory.path_join("session.json")), original_hash, "combat save never changes M1 slot bytes")
	t.expect(not FileAccess.file_exists(directory.path_join("session.json.bak")), "combat save does not rotate M1 slot")
	# A ranged save keeps ammunition and both RNG state/counter.
	var bow_setup: Dictionary = Sm2CombatFixtures.setup(content, [3, 5], 36)
	bow_setup.actors[1].q = 6
	t.expect(session.new_battle(bow_setup).ok, "combat ranged persistence start")
	_disk_compare(t, session, content, store, _command(session, ["use_ability", "bow_shot", 5]))
	_disk_compare(t, session, content, store, _command(session, ["use_ability", "bow_shot", 5]))
	t.equal(Sm2CombatFixtures.item(Sm2CombatFixtures.actor(session.capture().battle, 3), "weapon").ammo, 6, "combat saved shots consume exactly two arrows")
	# Damage with death remains excluded from the queue after a disk load.
	var battle: Sm2TacticalBattle = Sm2CombatFixtures.battle(t)
	var snapshot: Dictionary = Sm2CombatFixtures.untyped(battle)
	var victim: Dictionary = Sm2CombatFixtures.actor(snapshot, 5)
	victim.combat.hp = 1
	Sm2CombatFixtures.item(victim, "head").current = 0
	Sm2CombatFixtures.item(victim, "body").current = 0
	var payload: Dictionary = {"format": Sm2TacticalSession.COMBAT_FORMAT, "catalog": content.catalog.fingerprint(), "battle": snapshot}
	t.expect(session.restore_payload(payload).ok, "combat death persistence fixture restores")
	_disk_compare(t, session, content, store, _command(session, ["use_ability", "sword_strike", 5]))
	_disk_compare(t, session, content, store, _command(session, ["end_turn", "", 0]))
	t.equal(Sm2CombatFixtures.actor(session.capture().battle, 5).combat.hp, 0, "combat dead HP stays zero across next round/load")
	# Persist a wall after round reset, before its owner starts the new turn.
	t.expect(session.new_battle(Sm2CombatFixtures.setup(content, [3, 2, 5])).ok, "combat pending wall disk start")
	for action: Array in [["end_turn", "", 0], ["use_ability", "shieldwall", 2], ["wait", "", 0], ["end_turn", "", 0], ["end_turn", "", 0]]:
		t.expect(session.execute(_command(session, action)).accepted, "combat pending wall sequence accepted")
	t.equal(session.view().round, 2, "combat pending wall disk round boundary")
	_disk_compare(t, session, content, store, _command(session, ["end_turn", "", 0]))
	t.equal(Sm2CombatFixtures.actor(session.capture().battle, 2).combat.shieldwall_source, "0", "combat loaded pending wall expires at owner activation")

static func _broken_shield(t: Sm2TestHarness) -> void:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/combat_break_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()])
	var session: Sm2TacticalSession = Sm2TacticalSession.new(content.catalog, store, content.combat)
	# Actor2 is faster, so its active wall is present for axe actor4.
	t.expect(session.new_battle(Sm2CombatFixtures.setup(content, [2, 4])).ok, "combat shield persistence start")
	t.expect(session.execute(_command(session, ["use_ability", "shieldwall", 2])).accepted, "combat shield effect before enemy")
	t.expect(session.execute(_command(session, ["wait", "", 0])).accepted, "combat protected target waits")
	var before: Dictionary = session.capture().battle.rng
	_disk_compare(t, session, content, store, _command(session, ["use_ability", "split_shield", 2]))
	_disk_compare(t, session, content, store, _command(session, ["use_ability", "split_shield", 2]))
	var actor: Dictionary = Sm2CombatFixtures.actor(session.capture().battle, 2)
	t.equal([Sm2CombatFixtures.item(actor, "shield").current, actor.combat.shieldwall_source], [0, "0"], "combat broken shield clears active effect")
	t.equal(session.capture().battle.rng, before, "combat breaking protected shield takes no draws")
	_disk_compare(t, session, content, store, _command(session, ["end_turn", "", 0]))
	t.equal(session.view().active_actor_id, 2, "combat target resumes with broken shield")
	t.expect(not session.preview(_command(session, ["use_ability", "shieldwall", 2])).allowed, "combat broken shield offers no shieldwall")

static func _disk_compare(t: Sm2TestHarness, session: Sm2TacticalSession, content: Dictionary, store: Sm2SaveStore, command: Sm2Command) -> void:
	var before: String = session.state_hash()
	t.expect(session.save_game().ok, "combat real disk save")
	t.equal(session.state_hash(), before, "combat saving does not alter state")
	var restored: Sm2TacticalSession = Sm2TacticalSession.new(content.catalog, store, content.combat)
	t.expect(restored.load_game().ok, "combat real disk load")
	t.equal(restored.state_hash(), before, "combat disk exact restoration")
	var predicted: Dictionary = session.preview(command)
	t.equal(restored.preview(command), predicted, "combat restored attack prediction identical")
	var continuous: Sm2CommandResult = session.execute(command)
	var resumed: Sm2CommandResult = restored.execute(command)
	t.expect(continuous.accepted and resumed.accepted, "combat continuous/restored action accepted: " + continuous.code)
	t.equal(continuous.events, resumed.events, "combat disk next full event stream equal")
	t.equal(session.state_hash(), restored.state_hash(), "combat disk next full state equal")

static func _negative_snapshots(t: Sm2TestHarness) -> void:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var battle: Sm2TacticalBattle = Sm2CombatFixtures.battle(t)
	Sm2CombatFixtures.act(t, battle, "shieldwall", 2)
	var before: String = battle.state_hash()
	for mutation: String in ["version", "rules", "catalog", "extra", "missing", "hp", "alive", "hp_type", "item_id", "duplicate_id", "foreign_id", "slot", "item_def", "durability", "ammo", "item_null", "item_missing", "item_order", "next_id", "source", "expiry", "wall_missing", "wall_used", "wall_dead", "rng", "queue"]:
		var data: Dictionary = Sm2CombatFixtures.untyped(battle)
		var actor: Dictionary = Sm2CombatFixtures.actor(data, 2)
		match mutation:
			"version": data.schema_version = 2
			"rules": data.ruleset = "sm2.m2.turns.1"
			"catalog": data.combat_fingerprint = "wrong"
			"extra": data.ignored = true
			"missing": actor.erase("combat")
			"hp": actor.combat.hp = 999
			"alive": actor.combat.hp = 0
			"hp_type": actor.combat.hp = true
			"item_id": actor.combat.items[0].item_id = 1
			"duplicate_id": actor.combat.items[1].item_id = actor.combat.items[0].item_id
			"foreign_id": Sm2CombatFixtures.actor(data, 5).combat.items[0].item_id = actor.combat.items[0].item_id
			"slot": actor.combat.items[0].slot = "body"
			"item_def": actor.combat.items[0].definition_id = "m2:equipment.bow"
			"durability": Sm2CombatFixtures.item(actor, "shield").current = 25
			"ammo": Sm2CombatFixtures.item(actor, "weapon").ammo = 1
			"item_null": actor.combat.items[0] = null
			"item_missing": actor.combat.items.pop_back()
			"item_order": actor.combat.items.reverse()
			"next_id": data.next_item_id = "2"
			"source": actor.combat.shieldwall_source = actor.combat.items[0].item_id
			"expiry": actor.combat.shieldwall_until_round = "1"
			"wall_missing":
				actor.combat.shieldwall_source = "0"
				actor.combat.shieldwall_until_round = "0"
			"wall_used": actor.combat.shieldwall_used = false
			"wall_dead": Sm2CombatFixtures.item(actor, "shield").current = 0
			"rng": data.rng.state = "0"
			"queue": data.main_queue.reverse()
		t.expect(not battle.restore(data).ok, "combat rejects corrupted snapshot " + mutation)
		t.equal(battle.state_hash(), before, "combat invalid candidate never published " + mutation)
	var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/combat_invalid_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()])
	var session: Sm2TacticalSession = Sm2TacticalSession.new(content.catalog, store, content.combat)
	t.expect(session.new_battle(Sm2CombatFixtures.setup(content)).ok, "combat invalid file fixture starts")
	var live_hash: String = session.state_hash()
	var payload: Dictionary = session.capture()
	payload.battle.actors[0].combat.items[0].definition_id = "missing"
	t.expect(store.save_slot(payload, Sm2TacticalSession.SLOT).ok, "combat malformed domain in valid checksummed envelope")
	t.expect(not session.load_game().ok, "combat valid envelope cannot bypass domain validation")
	t.equal(session.state_hash(), live_hash, "combat invalid file leaves current session")

static func _isolation_and_compatibility(t: Sm2TestHarness) -> void:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var battle: Sm2TacticalBattle = Sm2CombatFixtures.battle(t)
	var before: String = battle.state_hash()
	var view: Dictionary = battle.view()
	view.actors[0].combat.items[0].ammo = 100
	view.actors[0].abilities.clear()
	var snapshot: Dictionary = battle.capture()
	snapshot.actors[0].combat.hp = 1
	t.equal(battle.state_hash(), before, "combat views and nested item snapshots detached")
	var result: Sm2CommandResult = battle.execute(Sm2CombatFixtures.command(battle, "sword_strike", 5))
	t.expect(result.accepted, "combat detachment attack")
	var after: String = battle.state_hash()
	result.events[0].ap = 999
	t.equal(battle.state_hash(), after, "combat detached event payload")
	t.expect(before != after, "combat accepted attack changes hash")
	var legacy: Sm2TacticalBattle = Sm2TacticalBattle.new(content.catalog)
	t.expect(legacy.start(Sm2CombatFixtures.setup(content)).ok, "combat old queue mode still available")
	var legacy_hash: String = legacy.state_hash()
	t.expect(not legacy.restore(battle.capture()).ok, "combat old mode rejects new schema")
	t.equal(legacy.state_hash(), legacy_hash, "combat old mode kept on incompatible load")
	t.expect(not battle.restore(legacy.capture()).ok, "combat new mode refuses old snapshot without migration")
	t.equal(battle.state_hash(), after, "combat new mode kept on incompatible load")
	var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/combat_versions_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()])
	var old_session: Sm2TacticalSession = Sm2TacticalSession.new(content.catalog, store)
	t.expect(old_session.new_battle(Sm2CombatFixtures.setup(content)).ok and old_session.save_game().ok, "combat old-mode disk save")
	var new_session: Sm2TacticalSession = Sm2TacticalSession.new(content.catalog, store, content.combat)
	t.expect(not new_session.load_game().ok and not new_session.has_active_game(), "combat session rejects old-format disk save")

static func _command(session: Sm2TacticalSession, action: Array) -> Sm2Command:
	var command: Sm2Command = Sm2Command.new()
	command.actor_id = session.view().active_actor_id
	command.expected_revision = session.view().revision
	command.kind = action[0]
	command.ability_id = "m2:ability." + str(action[1]) if not str(action[1]).is_empty() else ""
	command.target_actor_id = action[2]
	return command
