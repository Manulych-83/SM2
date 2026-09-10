extends RefCounted
## Real SaveStore round trips at stable queue boundaries; uses authored M2 inputs.

static func run(t: Sm2TestHarness) -> void:
	var loaded: Dictionary = Sm2TurnContentLoader.load_scenario()
	t.expect(loaded.ok, "turn storage: authored scenario available")
	if not loaded.ok:
		t.complete_suite("m2_turn_storage")
		return
	var directory: String = "user://tests/m2_turn_storage_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var catalog: Sm2TurnCatalog = loaded.catalog
	var store: Sm2SaveStore = Sm2SaveStore.new(directory)
	t.expect(store.save_slot({"sentinel": "untouched M1 slot", "revision": "17"}, "session").ok, "turn storage: M1 slot sentinel created")
	var m1_path: String = directory.path_join("session.json")
	var sentinel_hash: String = FileAccess.get_sha256(m1_path)
	_authored_boundaries(t, catalog, loaded.setup, store)
	_auto_end(t, catalog, loaded.setup, directory.path_join("auto_end"))
	_round_limit(t, catalog, loaded.setup, directory.path_join("round_limit"))
	_rejections(t, catalog, loaded.setup, directory.path_join("rejections"))
	t.equal(FileAccess.get_sha256(m1_path), sentinel_hash, "turn storage: M2 operations preserve exact M1 slot bytes")
	t.expect(not FileAccess.file_exists(m1_path + ".bak"), "turn storage: M2 never rotates M1 slot")
	t.complete_suite("m2_turn_storage")

static func _authored_boundaries(t: Sm2TestHarness, catalog: Sm2TurnCatalog, setup: Dictionary, store: Sm2SaveStore) -> void:
	var session: Sm2TacticalSession = Sm2TacticalSession.new(catalog, store)
	t.expect(session.new_battle(setup).ok, "turn storage: authored session starts")
	t.equal(session.view().active_actor_id, 3, "turn storage: initial actor")
	_roundtrip_next(t, session, catalog, store, "initial", "move", Vector2i(2, 4))
	t.equal([session.view().actors[2].ap, session.view().actors[2].fatigue], [7, 4], "turn storage: movement before Wait costs 2/4")
	_roundtrip_next(t, session, catalog, store, "before Wait", "wait")
	t.equal([session.view().active_actor_id, session.view().deferred_queue], [6, [3]], "turn storage: Wait transfers control")
	_roundtrip_next(t, session, catalog, store, "after Wait", "end_turn")
	for expected_actor: int in [2, 4, 1, 5]:
		t.equal(session.view().active_actor_id, expected_actor, "turn storage: authored pending actor")
		if not _execute(t, session, "end_turn", "finish main queue").accepted:
			return
	t.equal([session.view().phase, session.view().active_actor_id], ["deferred", 3], "turn storage: saved Wait returns in deferred phase")
	t.equal([session.view().actors[2].ap, session.view().actors[2].fatigue], [7, 4], "turn storage: Wait resume has no resource refresh")
	_roundtrip_next(t, session, catalog, store, "deferred", "move", Vector2i(3, 4))
	t.equal([session.view().actors[2].ap, session.view().actors[2].fatigue], [5, 8], "turn storage: deferred movement uses remaining resources")
	_roundtrip_next(t, session, catalog, store, "before round boundary", "end_turn")
	t.equal([session.view().round, session.view().active_actor_id], [2, 3], "turn storage: round boundary continues identically")
	t.equal([session.view().actors[2].ap, session.view().actors[2].fatigue], [9, 0], "turn storage: next round restores resources once")
	t.equal(session.capture().battle.rng.draws, "0", "turn storage: all queue and storage operations preserve RNG draws")

static func _auto_end(t: Sm2TestHarness, authored: Sm2TurnCatalog, setup: Dictionary, directory: String) -> void:
	var raw: Dictionary = authored.to_data()
	for profile: Dictionary in raw.profiles:
		profile.ap_max = 2
	var catalog: Sm2TurnCatalog = Sm2TurnCatalog.new()
	t.expect(catalog.build(raw).is_empty(), "turn storage: synthetic AP2 catalog validated")
	var store: Sm2SaveStore = Sm2SaveStore.new(directory)
	var session: Sm2TacticalSession = Sm2TacticalSession.new(catalog, store)
	t.expect(session.new_battle(setup).ok, "turn storage: AP2 session starts")
	var moved: Sm2CommandResult = _execute(t, session, "move", "AP exhaustion", Vector2i(2, 4))
	var automatic_end: bool = false
	for event: Dictionary in moved.events:
		if event.type == "turn_ended" and event.actor_id == "3":
			automatic_end = event.automatic
	t.expect(automatic_end, "turn storage: accepted movement really auto-ended actor")
	t.equal([session.view().active_actor_id, session.view().actors[2].ap], [6, 0], "turn storage: auto-end stable boundary")
	_roundtrip_next(t, session, catalog, store, "after automatic end", "end_turn")

static func _round_limit(t: Sm2TestHarness, catalog: Sm2TurnCatalog, authored_setup: Dictionary, directory: String) -> void:
	var setup: Dictionary = authored_setup.duplicate(true)
	setup.round_limit = 1
	var store: Sm2SaveStore = Sm2SaveStore.new(directory)
	var session: Sm2TacticalSession = Sm2TacticalSession.new(catalog, store)
	t.expect(session.new_battle(setup).ok, "turn storage: one-round session starts")
	for expected_actor: int in [3, 6, 2, 4, 1]:
		t.equal(session.view().active_actor_id, expected_actor, "turn storage: round limit main queue")
		if not _execute(t, session, "end_turn", "approach round limit").accepted:
			return
	_roundtrip_next(t, session, catalog, store, "before round limit", "end_turn")
	t.equal([session.view().finished, session.view().finish_reason, session.view().round], [true, "round_limit", 1], "turn storage: limit reached without invented next round")
	_roundtrip_next(t, session, catalog, store, "after round limit", "end_turn", Vector2i.ZERO, false)

static func _roundtrip_next(t: Sm2TestHarness, continuous: Sm2TacticalSession, catalog: Sm2TurnCatalog,
	store: Sm2SaveStore, label: String, kind: String, target: Vector2i = Vector2i.ZERO, accepted: bool = true) -> void:
	var before: String = continuous.state_hash()
	var saved: Dictionary = continuous.save_game()
	t.expect(saved.ok and continuous.has_save(), "turn storage: real save " + label)
	if not saved.ok:
		return
	t.equal(continuous.state_hash(), before, "turn storage: save does not mutate live state " + label)
	var resumed: Sm2TacticalSession = Sm2TacticalSession.new(catalog, store)
	var loaded: Dictionary = resumed.load_game()
	t.expect(loaded.ok and resumed.has_active_game(), "turn storage: real reload " + label)
	if not loaded.ok:
		return
	t.equal(resumed.state_hash(), before, "turn storage: exact resumed session hash " + label)
	var command: Sm2Command = _command(continuous, kind, target)
	var expected: Sm2CommandResult = continuous.execute(command)
	var actual: Sm2CommandResult = resumed.execute(command)
	t.equal([expected.accepted, actual.accepted], [accepted, accepted], "turn storage: next acceptance " + label)
	t.equal([actual.code, actual.revision, actual.events], [expected.code, expected.revision, expected.events], "turn storage: next result/events identical " + label)
	t.equal(resumed.state_hash(), continuous.state_hash(), "turn storage: subsequent session hash identical " + label)
	if not accepted:
		t.equal(expected.code, "battle_finished", "turn storage: finished battle rejects continuation")
		t.equal(continuous.state_hash(), before, "turn storage: finished rejection inert")

static func _rejections(t: Sm2TestHarness, catalog: Sm2TurnCatalog, setup: Dictionary, directory: String) -> void:
	var store: Sm2SaveStore = Sm2SaveStore.new(directory)
	var session: Sm2TacticalSession = Sm2TacticalSession.new(catalog, store)
	t.expect(session.new_battle(setup).ok, "turn storage: rejection fixture starts")
	_execute(t, session, "move", "rejection fixture movement", Vector2i(2, 4))
	t.expect(session.save_game().ok, "turn storage: valid prior M2 slot")
	var before: String = session.state_hash()
	var slot_path: String = directory.path_join(Sm2TacticalSession.SLOT + ".json")
	var valid_file_hash: String = FileAccess.get_sha256(slot_path)
	var valid_payload: Dictionary = session.capture()
	var malformed: Dictionary = valid_payload.duplicate(true)
	malformed.battle = []
	t.expect(not session.restore_payload(malformed).ok, "turn storage: malformed payload rejected before publication")
	t.equal(session.state_hash(), before, "turn storage: malformed payload keeps live session")
	t.equal(FileAccess.get_sha256(slot_path), valid_file_hash, "turn storage: direct rejected payload keeps existing save")
	for reason: String in ["wrong_queue", "unsupported_session", "unsupported_battle", "wrong_catalog"]:
		var payload: Dictionary = valid_payload.duplicate(true)
		match reason:
			"wrong_queue": payload.battle.main_queue.reverse()
			"unsupported_session": payload.format = "sm2.session.future"
			"unsupported_battle": payload.battle.schema_version = 1
			"wrong_catalog": payload.catalog = "0".repeat(64)
		t.expect(store.save_slot(payload, Sm2TacticalSession.SLOT).ok, "turn storage: valid checksummed envelope for " + reason)
		var faulty_hash: String = FileAccess.get_sha256(slot_path)
		t.expect(store.load_slot(Sm2TacticalSession.SLOT).ok, "turn storage: envelope itself is valid " + reason)
		t.expect(not session.load_game().ok, "turn storage: domain/application reject " + reason)
		t.equal(session.state_hash(), before, "turn storage: rejected file keeps live session " + reason)
		t.equal(FileAccess.get_sha256(slot_path), faulty_hash, "turn storage: rejected load does not rewrite file " + reason)
	t.expect(session.save_game().ok, "turn storage: valid session can replace valid-envelope unsupported payload")
	var file: FileAccess = FileAccess.open(slot_path, FileAccess.WRITE)
	t.expect(file != null, "turn storage: isolated corrupt-file fixture opens")
	if file != null:
		file.store_string("{broken json")
		file.close()
		var corrupt_hash: String = FileAccess.get_sha256(slot_path)
		t.expect(not session.load_game().ok, "turn storage: malformed envelope rejected")
		t.equal(session.state_hash(), before, "turn storage: malformed file keeps live state")
		t.expect(not session.save_game().ok, "turn storage: save refuses to destroy corrupt prior file")
		t.equal(FileAccess.get_sha256(slot_path), corrupt_hash, "turn storage: failed save preserves corrupt prior bytes")

static func _execute(t: Sm2TestHarness, session: Sm2TacticalSession, kind: String, label: String,
	target: Vector2i = Vector2i.ZERO) -> Sm2CommandResult:
	var result: Sm2CommandResult = session.execute(_command(session, kind, target))
	t.expect(result.accepted, "turn storage: accepted " + label + " / " + result.code)
	return result

static func _command(session: Sm2TacticalSession, kind: String, target: Vector2i = Vector2i.ZERO) -> Sm2Command:
	var command: Sm2Command = Sm2Command.new()
	command.actor_id = session.view().active_actor_id
	command.expected_revision = session.view().revision
	command.kind = kind
	command.target = target
	return command
