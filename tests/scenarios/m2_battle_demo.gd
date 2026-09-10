extends SceneTree
var _errors: Array[String] = []
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
	var content: Dictionary = Sm2CombatContentLoader.load_scenario()
	var ai: Dictionary = Sm2AiContentLoader.load_profile()
	if content.ok and ai.ok:
		for seed_value: int in [20260909, 1, 76]:
			_case(content, ai.profile, seed_value)
	else:
		_errors.append("content/AI profile failed to load")
	OS.remove_logger(logger)
	_errors.append_array(logger.messages())
	_check(_cases.size() == 3, "missing full battle cases")
	var report: Dictionary = {"passed": _errors.is_empty(), "errors": _errors, "cases": _cases,
		"engine_version": Engine.get_version_info().string, "ui_tested": false, "self_play": true}
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
	print("SM2_BATTLE_DEMO passed=" + str(report.passed) + " cases=" + str(_cases.size()))
	quit(0 if report.passed and error == OK else 1)

func _case(content: Dictionary, profile: Sm2AiProfile, seed_value: int) -> void:
	var directory: String = "user://tests/battle_demo_%s_%s_%s" % [seed_value, OS.get_process_id(), Time.get_ticks_usec()]
	var store: Sm2SaveStore = Sm2SaveStore.new(directory)
	if not _check(store.save_slot({"sentinel": "M1 preserved"}, "session").ok, "cannot write test sentinel"): return
	var sentinel: String = FileAccess.get_sha256(directory.path_join("session.json"))
	var setup: Dictionary = content.setup.duplicate(true)
	setup.seed = seed_value
	var runner: Sm2BattleRunner = Sm2BattleRunner.new(content.catalog, content.combat, profile, store, true)
	if not _check(runner.new_battle(setup).ok, "cannot start authored field"): return
	var record: Dictionary = {"seed": seed_value, "setup": setup, "profile": profile.to_data(), "initial": runner.capture(),
		"save_directory": ProjectSettings.globalize_path(directory)}
	var opening: Array[Dictionary] = []
	for index: int in 12:
		var action: Dictionary = runner.step()
		if not _check(action.ok and action.has("command"), "opening failed " + str(action.get("reason", ""))): return
		opening.append(action)
	if not _check(not runner.view().finished, "checkpoint should be during battle"): return
	record.saved = runner.capture()
	if not _check(runner.save_game().ok, "cannot save mid battle"): return
	var resumed: Sm2BattleRunner = Sm2BattleRunner.new(content.catalog, content.combat, profile, store, true)
	if not _check(resumed.load_game().ok, "cannot load battle"): return
	record.reloaded = resumed.capture()
	record.save_reload_equal = runner.state_hash() == resumed.state_hash()
	var continuous: Dictionary = runner.run_to_end()
	var continuation: Dictionary = resumed.run_to_end()
	if not _check(continuous.ok and continuation.ok, "full battle diagnostic failed " + str(continuous.get("reason", ""))): return
	record.continuation_equal = continuous == continuation and runner.state_hash() == resumed.state_hash()
	var fresh: Sm2BattleRunner = Sm2BattleRunner.new(content.catalog, content.combat, profile, null, true)
	if not _check(fresh.new_battle(setup).ok, "fresh replay start failed"): return
	var replay: Dictionary = fresh.run_to_end()
	var history: Array[Dictionary] = opening.duplicate(true)
	history.append_array(continuous.history)
	record.fresh_replay_equal = replay.ok and replay.history == history and fresh.state_hash() == runner.state_hash()
	record.history = history
	var recorded_replay: Dictionary = Sm2BattleReplay.replay(content.catalog, content.combat, record.initial.session, history)
	record.command_replay_equal = recorded_replay.ok and recorded_replay.session == runner.capture().session
	record.command_count = history.size()
	record.outcome = continuous.outcome
	record.final = runner.capture()
	record.final_hash = runner.state_hash()
	record.resumed_final_hash = resumed.state_hash()
	record.replay_final_hash = fresh.state_hash()
	record.retries = 0
	for action: Dictionary in history:
		record.retries += int(action.retries)
	record.result_recorded_once = runner.step().record.code == "already_recorded" and resumed.step().record.code == "already_recorded"
	record.m1_slot_unchanged = FileAccess.get_sha256(directory.path_join("session.json")) == sentinel
	for key: String in ["save_reload_equal", "continuation_equal", "fresh_replay_equal", "command_replay_equal", "result_recorded_once", "m1_slot_unchanged"]:
		_check(record[key], "failed " + key)
	_check(record.outcome.finished and record.outcome.reason == "opposition_removed" and record.outcome.participants.size() == 6, "ordinary six-participant outcome missing")
	_check(record.retries == 0, "main battle used rejection retry")
	_cases.append(record)

func _check(condition: bool, message: String) -> bool:
	if not condition: _errors.append(message)
	return condition
