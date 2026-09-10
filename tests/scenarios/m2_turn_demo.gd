extends SceneTree
## Real M2.2 commands and disk save/load. No attacks, AI or presentation.
var _errors: Array[String] = []
var _history: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--report" or args[1].is_empty():
		push_error("Expected --report path")
		quit(2)
		return
	var captured_errors: Sm2ErrorCapture = Sm2ErrorCapture.new()
	OS.add_logger(captured_errors)
	var report: Dictionary = _perform()
	OS.remove_logger(captured_errors)
	_errors.append_array(captured_errors.messages())
	report["passed"] = _errors.is_empty()
	report["errors"] = _errors.duplicate()
	report["commands"] = _history.duplicate(true)
	report["engine_version"] = Engine.get_version_info().string
	if DirAccess.make_dir_recursive_absolute(args[1].get_base_dir()) != OK:
		quit(2)
		return
	var file: FileAccess = FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		quit(2)
		return
	print("SM2_TURN_DEMO passed=" + str(report.passed) + " commands=" + str(_history.size())
		+ " save_reload_equal=" + str(report.get("save_reload_equal", false))
		+ " continuation_equal=" + str(report.get("continuation_equal", false)))
	quit(0 if report.passed else 1)

func _perform() -> Dictionary:
	var report: Dictionary = {"stage": "M2.2 rounds, Wait and disk save/load; no attacks or UI"}
	var loaded: Dictionary = Sm2TurnContentLoader.load_scenario()
	if not _require(loaded.ok, "Authored turn scenario failed to load"):
		return report
	var catalog: Sm2TurnCatalog = loaded.catalog
	var directory: String = "user://tests/turn_demo_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var store: Sm2SaveStore = Sm2SaveStore.new(directory)
	report["save_directory"] = ProjectSettings.globalize_path(directory)
	if not _require(store.save_slot({"sentinel": "M1 slot retained"}, "session").ok, "Could not create isolated M1 sentinel"):
		return report
	var sentinel_path: String = directory.path_join("session.json")
	var sentinel_hash: String = FileAccess.get_sha256(sentinel_path)
	var continuous: Sm2TacticalSession = Sm2TacticalSession.new(catalog, store)
	var started: Dictionary = continuous.new_battle(loaded.setup)
	if not _require(started.ok, "Tactical session failed to start"):
		return report
	report["initial"] = continuous.capture()
	report["start_events"] = started.events
	if not _require(continuous.view().main_queue == [3, 6, 2, 4, 1, 5], "Initial queue differs from the authored oracle"):
		return report
	if not _step(continuous, "move", Vector2i(2, 4)):
		return report
	var moved_actor: Dictionary = continuous.view().actors[2]
	_require(moved_actor.ap == 7 and moved_actor.fatigue == 4, "Move must spend 2 AP and 4 fatigue")
	if not _step(continuous, "wait"):
		return report
	report["after_wait"] = continuous.capture()
	for expected_actor: int in [6, 2, 4, 1, 5]:
		if not _require(continuous.view().active_actor_id == expected_actor, "Unexpected main-queue active actor"):
			return report
		if not _step(continuous, "end_turn"):
			return report
	var deferred: Dictionary = continuous.view()
	if not _require(deferred.phase == "deferred" and deferred.active_actor_id == 3, "Actor 3 did not resume after the main queue"):
		return report
	_require(deferred.actors[2].ap == 7 and deferred.actors[2].fatigue == 4, "Wait resume refreshed resources")
	var saved_hash: String = continuous.state_hash()
	report["saved"] = continuous.capture()
	report["saved_hash"] = saved_hash
	var saved: Dictionary = continuous.save_game()
	if not _require(saved.ok and continuous.has_save(), "Real M2 save failed"):
		return report
	_require(continuous.state_hash() == saved_hash, "Save changed the live session")
	var restored: Sm2TacticalSession = Sm2TacticalSession.new(catalog, store)
	var reloaded: Dictionary = restored.load_game()
	if not _require(reloaded.ok, "Real M2 reload failed"):
		return report
	report["reloaded"] = restored.capture()
	report["save_reload_equal"] = restored.state_hash() == saved_hash
	_require(report.save_reload_equal, "Reloaded state differs from the saved queue")
	var command: Sm2Command = _command(continuous, "end_turn")
	var resumed_result: Sm2CommandResult = restored.execute(command)
	var original_result: Sm2CommandResult = continuous.execute(command)
	_history.append(_entry(command, original_result, continuous))
	_require(original_result.accepted and resumed_result.accepted, "Next command after reload was rejected")
	report["resumed_result"] = {"accepted": resumed_result.accepted, "code": resumed_result.code,
		"revision": str(resumed_result.revision), "events": resumed_result.events}
	report["continuation_equal"] = original_result.events == resumed_result.events \
		and original_result.code == resumed_result.code and original_result.revision == resumed_result.revision \
		and continuous.state_hash() == restored.state_hash()
	_require(report.continuation_equal, "Reloaded continuation differs in events or state hash")
	var final_view: Dictionary = continuous.view()
	_require(final_view.round == 2 and final_view.active_actor_id == 3 and final_view.phase == "main", "Continuation must begin round 2 with actor 3")
	_require(final_view.actors[2].ap == 9 and final_view.actors[2].fatigue == 0, "Round 2 resources differ from the oracle")
	report["final"] = continuous.capture()
	report["resumed_final"] = restored.capture()
	report["final_hash"] = continuous.state_hash()
	report["resumed_final_hash"] = restored.state_hash()
	report["m1_slot_unchanged"] = FileAccess.get_sha256(sentinel_path) == sentinel_hash
	_require(report.m1_slot_unchanged, "M2 operations changed the isolated M1 sentinel")
	_require(continuous.capture().battle.rng == report.initial.battle.rng, "Queue or storage changed RNG")
	_require(_history.size() == 8, "Expected exactly eight real accepted commands")
	return report

func _step(session: Sm2TacticalSession, kind: String, target: Vector2i = Vector2i.ZERO) -> bool:
	var command: Sm2Command = _command(session, kind, target)
	var before: String = session.state_hash()
	var preview: Dictionary = session.preview(command)
	if not _require(preview.allowed and before == session.state_hash(), "Preview rejected a planned command or mutated state"):
		return false
	var result: Sm2CommandResult = session.execute(command)
	_history.append(_entry(command, result, session))
	return _require(result.accepted, "Command rejected: " + kind + " / " + result.code)

func _entry(command: Sm2Command, result: Sm2CommandResult, session: Sm2TacticalSession) -> Dictionary:
	return {"kind": command.kind, "actor_id": str(command.actor_id), "expected_revision": str(command.expected_revision),
		"target": {"q": command.target.x, "r": command.target.y}, "accepted": result.accepted,
		"code": result.code, "revision": str(result.revision), "events": result.events,
		"state_hash": session.state_hash(), "state": session.capture()}

func _command(session: Sm2TacticalSession, kind: String, target: Vector2i = Vector2i.ZERO) -> Sm2Command:
	var command: Sm2Command = Sm2Command.new()
	command.kind = kind
	command.actor_id = session.view().active_actor_id
	command.expected_revision = session.view().revision
	command.target = target
	return command

func _require(condition: bool, message: String) -> bool:
	if not condition:
		_errors.append(message)
	return condition
