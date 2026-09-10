extends SceneTree
## A real command-driven M2.1 rehearsal. Does not claim to run a complete battle.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var captured_errors: Sm2ErrorCapture = Sm2ErrorCapture.new()
	OS.add_logger(captured_errors)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--report" or args[1].is_empty():
		push_error("Expected --report path")
		quit(2)
		return
	var loaded: Dictionary = Sm2FieldContentLoader.load_scenario()
	if not loaded.ok:
		push_error(str(loaded.errors))
		quit(1)
		return
	var markers: Array[Dictionary] = []
	markers.assign(loaded.spawns)
	var session: Sm2FieldSession = Sm2FieldSession.new()
	if not session.start(loaded.field, Sm2SpatialFixtures.from_markers(markers), 1, loaded.seed).ok:
		push_error("Field rehearsal could not start")
		quit(1)
		return
	var initial: Dictionary = session.capture()
	var route: Dictionary = session.route(1, Vector2i(8, 2))
	var available: Dictionary = session.reachable(1)
	var sight: Dictionary = session.line_of_sight(3, 4)
	var history: Array[Dictionary] = []
	var passed: bool = route.ok and route.ap_cost == 16 and route.fatigue_cost == 32 and available.ok and sight.ok
	var points: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)]
	for point: Vector2i in points:
		var command: Sm2Command = Sm2SpatialFixtures.command(1, int(session.view().revision), point)
		var before: String = session.state_hash()
		var preview: Dictionary = session.preview(command)
		passed = passed and before == session.state_hash()
		var result: Sm2CommandResult = session.execute(command)
		passed = passed and result.accepted
		history.append({"target": point, "preview": preview, "accepted": result.accepted,
			"revision": str(result.revision), "events": result.events, "state_hash": session.state_hash()})
	var hash_before_rejection: String = session.state_hash()
	var rejected: Sm2CommandResult = session.execute(Sm2SpatialFixtures.command(1, 3, Vector2i(5, 2)))
	passed = passed and not rejected.accepted and rejected.code == "insufficient_ap" and session.state_hash() == hash_before_rejection
	var final_state: Dictionary = session.capture()
	passed = passed and final_state.actors[0].ap == 1 and final_state.actors[0].fatigue == 16 \
		and final_state.actors[0].q == 4 and final_state.actors[0].r == 2 and final_state.rng == initial.rng
	OS.remove_logger(captured_errors)
	passed = passed and captured_errors.messages().is_empty()
	var report: Dictionary = {"passed": passed, "stage": "M2.1 spatial rehearsal; no turns or attacks",
		"scenario_id": loaded.scenario_id, "initial": initial, "route": route, "reachable": available,
		"line_of_sight_3_to_4": sight, "commands": history, "rejected_code": rejected.code,
		"rejection_preserved_state": session.state_hash() == hash_before_rejection,
		"final": final_state, "errors": captured_errors.messages(), "engine_version": Engine.get_version_info().string}
	if DirAccess.make_dir_recursive_absolute(args[1].get_base_dir()) != OK:
		quit(2)
		return
	var file: FileAccess = FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(_json_safe(report), "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		quit(2)
		return
	print("SM2_FIELD_DEMO passed=" + str(passed) + " moves=3 rejected=insufficient_ap ap=1 fatigue=16 rng_draws=0")
	quit(0 if passed else 1)

func _json_safe(value: Variant) -> Variant:
	if value is Vector2i:
		return {"q": value.x, "r": value.y}
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_json_safe(item))
		return items
	if value is Dictionary:
		var data: Dictionary = {}
		for key: String in value:
			data[key] = _json_safe(value[key])
		return data
	return value
