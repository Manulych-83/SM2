extends SceneTree
## Three small diagnostics with authored equipment. These are not a full AI battle.
var _errors: Array[String] = []
var _history: Array[Dictionary] = []
var _cases: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--report":
		quit(2)
		return
	var logger: Sm2ErrorCapture = Sm2ErrorCapture.new()
	OS.add_logger(logger)
	var loaded: Dictionary = Sm2CombatContentLoader.load_scenario()
	if loaded.ok:
		for name_value: String in ["melee", "shield", "ranged"]:
			_case(name_value, loaded)
	else:
		_errors.append("Combat content failed to load: " + str(loaded.errors))
	OS.remove_logger(logger)
	_errors.append_array(logger.messages())
	_check(_history.size() == 9 and _cases.size() == 3, "Incomplete diagnostic sequence")
	var report: Dictionary = {"passed": _errors.is_empty(), "errors": _errors, "commands": _history,
		"cases": _cases, "engine_version": Engine.get_version_info().string, "ui_tested": false, "full_battle_tested": false}
	if DirAccess.make_dir_recursive_absolute(args[1].get_base_dir()) != OK:
		quit(2)
		return
	var file: FileAccess = FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	print("SM2_ATTACK_DEMO passed=" + str(report.passed) + " commands=" + str(_history.size()))
	quit(0 if report.passed and error == OK else 1)

func _case(name_value: String, loaded: Dictionary) -> void:
	var directory: String = "user://tests/attack_demo_%s_%s_%s" % [name_value, OS.get_process_id(), Time.get_ticks_usec()]
	var store: Sm2SaveStore = Sm2SaveStore.new(directory)
	if not _check(store.save_slot({"sentinel": "M1 retained"}, "session").ok, "Could not create M1 sentinel"):
		return
	var sentinel_hash: String = FileAccess.get_sha256(directory.path_join("session.json"))
	var ids: Array[int] = [2, 5]
	if name_value == "shield": ids.assign([2, 4])
	if name_value == "ranged": ids.assign([3, 5])
	var setup: Dictionary = Sm2CombatFixtures.setup(loaded, ids, 1231)
	if name_value == "ranged": setup.actors[1].q = 6
	var session: Sm2TacticalSession = Sm2TacticalSession.new(loaded.catalog, store, loaded.combat)
	if not _check(session.new_battle(setup).ok, "Could not start " + name_value):
		return
	var record: Dictionary = {"name": name_value, "initial": session.capture(), "save_directory": ProjectSettings.globalize_path(directory)}
	var action: Array = ["use_ability", "sword_strike", 5]
	if name_value == "shield":
		if not _step(session, name_value, ["use_ability", "shieldwall", 2]): return
		if not _step(session, name_value, ["wait", "", 0]): return
		if not _step(session, name_value, ["use_ability", "split_shield", 2]): return
		if not _step(session, name_value, ["use_ability", "split_shield", 2]): return
		var victim: Dictionary = Sm2CombatFixtures.actor(session.capture().battle, 2)
		_check(Sm2CombatFixtures.item(victim, "shield").current == 0 and victim.combat.shieldwall_source == "0", "Shield did not break/clear effect")
		_check(session.capture().battle.rng == record.initial.battle.rng, "Shield actions changed RNG")
		action = ["end_turn", "", 0]
	else:
		if name_value == "ranged": action = ["use_ability", "bow_shot", 5]
		if not _step(session, name_value, action): return
		var victim: Dictionary = Sm2CombatFixtures.actor(session.capture().battle, 5)
		_check(victim.combat.hp == (60 if name_value == "ranged" else 64), "First hit HP oracle mismatch")
		_check(Sm2CombatFixtures.item(victim, "body").current == (79 if name_value == "ranged" else 64), "First hit armor oracle mismatch")
	var saved_hash: String = session.state_hash()
	record.saved = session.capture()
	if not _check(session.save_game().ok, "Could not save combat state"): return
	var restored: Sm2TacticalSession = Sm2TacticalSession.new(loaded.catalog, store, loaded.combat)
	if not _check(restored.load_game().ok, "Could not load combat state"): return
	record.reloaded = restored.capture()
	record.save_reload_equal = restored.state_hash() == saved_hash
	_check(record.save_reload_equal, "Snapshot differs after disk load")
	var command: Sm2Command = _command(session, action)
	var resumed: Sm2CommandResult = restored.execute(command)
	var continuous: Sm2CommandResult = session.execute(command)
	_history.append(_entry(name_value, command, continuous, session))
	record.continuation_equal = resumed.accepted and continuous.accepted and resumed.events == continuous.events and restored.state_hash() == session.state_hash()
	_check(record.continuation_equal, "Future dice/events/state differ after load")
	record.continuation_events = resumed.events
	record.final = session.capture()
	record.final_hash = session.state_hash()
	record.resumed_final_hash = restored.state_hash()
	record.m1_slot_unchanged = FileAccess.get_sha256(directory.path_join("session.json")) == sentinel_hash
	_check(record.m1_slot_unchanged, "M1 sentinel changed")
	_cases.append(record)

func _step(session: Sm2TacticalSession, name_value: String, action: Array) -> bool:
	var command: Sm2Command = _command(session, action)
	var before: String = session.state_hash()
	var preview: Dictionary = session.preview(command)
	if not _check(preview.allowed and session.state_hash() == before, "Preview rejected or changed state"):
		return false
	var result: Sm2CommandResult = session.execute(command)
	_history.append(_entry(name_value, command, result, session))
	return _check(result.accepted, "Command rejected: " + result.code)

func _entry(name_value: String, command: Sm2Command, result: Sm2CommandResult, session: Sm2TacticalSession) -> Dictionary:
	return {"case": name_value, "kind": command.kind, "actor_id": str(command.actor_id), "ability_id": command.ability_id,
		"target_actor_id": str(command.target_actor_id), "accepted": result.accepted, "code": result.code,
		"revision": str(result.revision), "events": result.events, "state": session.capture(), "hash": session.state_hash()}

func _command(session: Sm2TacticalSession, action: Array) -> Sm2Command:
	var result: Sm2Command = Sm2Command.new()
	result.kind = action[0]
	result.actor_id = session.view().active_actor_id
	result.expected_revision = session.view().revision
	result.ability_id = "m2:ability." + str(action[1]) if not str(action[1]).is_empty() else ""
	result.target_actor_id = action[2]
	return result

func _check(condition: bool, message: String) -> bool:
	if not condition: _errors.append(message)
	return condition
