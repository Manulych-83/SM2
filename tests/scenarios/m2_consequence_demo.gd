extends SceneTree
## Records ordinary transactions and verifies continuation after every disk save.
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
	var content: Dictionary = Sm2CombatFixtures.loaded()
	if content.ok:
		for case_name: String in ["reaction_escape", "panic_wait", "last_kill"]:
			_case(content, case_name)
	else:
		_errors.append("content invalid")
	OS.remove_logger(logger)
	_errors.append_array(logger.messages())
	_check(_cases.size() == 3 and _history.size() == 8, "incomplete diagnostic")
	var report: Dictionary = {"passed": _errors.is_empty(), "errors": _errors, "commands": _history, "cases": _cases,
		"engine_version": Engine.get_version_info().string, "ui_tested": false, "ordinary_ai_tested": false}
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
	print("SM2_CONSEQUENCE_DEMO passed=" + str(report.passed) + " commands=" + str(_history.size()))
	quit(0 if report.passed and error == OK else 1)

func _case(content: Dictionary, case_name: String) -> void:
	var directory: String = "user://tests/consequence_demo_%s_%s_%s" % [case_name, OS.get_process_id(), Time.get_ticks_usec()]
	var store: Sm2SaveStore = Sm2SaveStore.new(directory)
	if not _check(store.save_slot({"sentinel": "M1 retained"}, "session").ok, "sentinel write failed"): return
	var sentinel: String = FileAccess.get_sha256(directory.path_join("session.json"))
	var session: Sm2TacticalSession = Sm2TacticalSession.new(content.catalog, store, content.combat, true)
	if not _check(session.new_battle(Sm2CombatFixtures.setup(content)).ok, "start failed"): return
	# Authored equipment with explicit saved-boundary damage/morale fixtures.
	# Fixture changes are reported separately and are never presented as commands.
	if case_name != "reaction_escape":
		var payload: Dictionary = JSON.parse_string(JSON.stringify(session.capture()))
		var victim: Dictionary = Sm2CombatFixtures.actor(payload.battle, 2 if case_name == "panic_wait" else 5)
		victim.morale = "breaking" if case_name == "panic_wait" else "steady"
		if case_name == "last_kill":
			victim.combat.hp = 1
			payload.battle.round_limit = 1
			Sm2CombatFixtures.actor(payload.battle, 2).ap = 4
		Sm2CombatFixtures.item(victim, "head").current = 0
		Sm2CombatFixtures.item(victim, "body").current = 0
		if not _check(session.restore_payload(payload).ok, "fixture invalid"): return
	var record: Dictionary = {"name": case_name, "initial": session.capture(), "save_directory": ProjectSettings.globalize_path(directory),
		"save_reload_equal": true, "continuation_equal": true}
	var actions: Array[Array] = [["move", "", 0, 0, 2], ["move", "", 0, 0, 2], ["escape", "", 0, 0, 0]]
	if case_name == "panic_wait":
		actions = [["use_ability", "shieldwall", 2, 0, 0], ["wait", "", 0, 0, 0], ["use_ability", "spear_thrust", 2, 0, 0], ["end_turn", "", 0, 0, 0]]
	elif case_name == "last_kill":
		actions = [["use_ability", "sword_strike", 5, 0, 0]]
	for action: Array in actions:
		if not _step(session, store, content, record, action): return
	if case_name == "panic_wait":
		var actor: Dictionary = Sm2CombatFixtures.actor(session.capture().battle, 2)
		_check(actor.morale == "fleeing" and actor.wait_used and actor.combat.shieldwall_source == "0", "panic waiter state wrong")
		_check(session.view().active_actor_id == 2 and not session.view().finished, "panic waiter should resume")
	else:
		_check(session.view().finished, "outcome missing")
		var outcome: Dictionary = session.record_outcome()
		_check(outcome.ok and outcome.code == "recorded", "result not recorded")
		record.outcome = outcome.outcome
		_check(session.save_game().ok, "record save failed")
		var resumed: Sm2TacticalSession = Sm2TacticalSession.new(content.catalog, store, content.combat, true)
		_check(resumed.load_game().ok and resumed.state_hash() == session.state_hash(), "record load mismatch")
		_check(resumed.record_outcome().code == "already_recorded", "result repeated after load")
		_check(record.outcome.winner == ("opposition" if case_name == "reaction_escape" else "company"), "wrong winner")
	record.final = session.capture()
	record.m1_slot_unchanged = FileAccess.get_sha256(directory.path_join("session.json")) == sentinel
	_check(record.m1_slot_unchanged, "M1 slot changed")
	_cases.append(record)

func _step(session: Sm2TacticalSession, store: Sm2SaveStore, content: Dictionary, record: Dictionary, action: Array) -> bool:
	var command: Sm2Command = Sm2SpatialFixtures.command(session.view().active_actor_id, session.view().revision,
		Vector2i(action[3], action[4]), action[0])
	command.ability_id = "m2:ability." + str(action[1]) if not str(action[1]).is_empty() else ""
	command.target_actor_id = action[2]
	var before: String = session.state_hash()
	if not _check(session.preview(command).allowed and session.state_hash() == before, "preview failed/changed state"): return false
	if not _check(session.save_game().ok, "save failed"): return false
	var restored: Sm2TacticalSession = Sm2TacticalSession.new(content.catalog, store, content.combat, true)
	if not _check(restored.load_game().ok, "load failed"): return false
	record.save_reload_equal = record.save_reload_equal and restored.state_hash() == before
	var left: Sm2CommandResult = session.execute(command)
	var right: Sm2CommandResult = restored.execute(command)
	record.continuation_equal = record.continuation_equal and left.accepted and right.accepted and left.events == right.events and session.state_hash() == restored.state_hash()
	_history.append({"case": record.name, "command": {"kind": command.kind, "actor_id": str(command.actor_id),
		"ability_id": command.ability_id, "target_actor_id": str(command.target_actor_id), "q": command.target.x, "r": command.target.y},
		"accepted": left.accepted, "code": left.code, "events": left.events, "state": session.capture(),
		"hash": session.state_hash(), "resumed_hash": restored.state_hash()})
	return _check(record.save_reload_equal and record.continuation_equal, "disk continuation diverged: " + left.code)

func _check(condition: bool, message: String) -> bool:
	if not condition: _errors.append(message)
	return condition
