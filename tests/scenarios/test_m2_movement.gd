extends RefCounted

static func run(t: Sm2TestHarness) -> void:
	_steps(t)
	_rejections(t)
	_initialization(t)
	_isolation(t)
	_presence(t)
	_paths_and_replay(t)
	_main_scenario(t)
	t.complete_suite("m2_movement")

static func _steps(t: Sm2TestHarness) -> void:
	var field: Sm2Battlefield = Sm2SpatialFixtures.field(6, 4, [
		Sm2SpatialFixtures.tile(2, 1, "rough", 1)])
	var session: Sm2FieldSession = Sm2FieldSession.new()
	t.expect(session.start(field, [Sm2SpatialFixtures.actor(1, 0, 1)], 1, 20260909).ok, "M2 move: start")
	var first: Sm2Command = Sm2SpatialFixtures.command(1, 0, Vector2i(1, 1))
	var before: String = session.state_hash()
	var preview: Dictionary = session.preview(first)
	t.expect(preview.allowed, "M2 move: ground allowed")
	t.equal(preview.ap_cost, 2, "M2 move: ground AP oracle")
	t.equal(preview.fatigue_cost, 4, "M2 move: ground fatigue oracle")
	t.equal(session.state_hash(), before, "M2 preview: unchanged full hash")
	var rng_before: Dictionary = session.capture().rng
	var moved: Sm2CommandResult = session.execute(first)
	t.expect(moved.accepted, "M2 move: command accepted")
	t.equal(moved.revision, 1, "M2 move: exactly one revision")
	t.equal(moved.events.size(), 2, "M2 move: costs then position")
	t.equal(moved.events[0].type, "resources_spent", "M2 move: cost event first")
	t.equal(session.view().actors[0].ap, 7, "M2 move: AP after ground")
	t.equal(session.view().actors[0].fatigue, 4, "M2 move: fatigue after ground")
	var second: Sm2Command = Sm2SpatialFixtures.command(1, 1, Vector2i(2, 1))
	t.equal(session.preview(second).ap_cost, 4, "M2 move: rough uphill AP oracle")
	t.equal(session.preview(second).fatigue_cost, 8, "M2 move: rough uphill fatigue oracle")
	t.expect(session.execute(second).accepted, "M2 move: uphill accepted")
	t.equal(session.view().actors[0].ap, 3, "M2 move: AP after rough uphill")
	t.equal(session.view().actors[0].fatigue, 12, "M2 move: fatigue after rough uphill")
	t.expect(session.execute(Sm2SpatialFixtures.command(1, 2, Vector2i(3, 1))).accepted, "M2 move: downhill accepted")
	t.equal(session.view().actors[0].ap, 1, "M2 move: downhill no AP surcharge")
	t.equal(session.view().actors[0].fatigue, 16, "M2 move: downhill no fatigue surcharge")
	t.equal(session.capture().rng, rng_before, "M2 move: no random draws on three steps")

static func _rejections(t: Sm2TestHarness) -> void:
	var field: Sm2Battlefield = Sm2SpatialFixtures.field(4, 4, [
		Sm2SpatialFixtures.tile(1, 0, "ground", 0, false, true), Sm2SpatialFixtures.tile(0, 1, "ground", 2)])
	var session: Sm2FieldSession = Sm2FieldSession.new()
	session.start(field, [Sm2SpatialFixtures.actor(1, 1, 1), Sm2SpatialFixtures.actor(2, 2, 1)], 1)
	_reject(t, session, null, "invalid_command")
	_reject(t, session, Sm2SpatialFixtures.command(1, 1, Vector2i(1, 2)), "stale_revision")
	_reject(t, session, Sm2SpatialFixtures.command(2, 0, Vector2i(2, 2)), "not_active_actor")
	_reject(t, session, Sm2SpatialFixtures.command(1, 0, Vector2i(1, 2), "end_turn"), "unsupported_command")
	_reject(t, session, Sm2SpatialFixtures.command(1, 0, Vector2i(-1, 1)), "out_of_bounds")
	_reject(t, session, Sm2SpatialFixtures.command(1, 0, Vector2i(2, 1)), "occupied")
	_reject(t, session, Sm2SpatialFixtures.command(1, 0, Vector2i(1, 0)), "impassable")
	_reject(t, session, Sm2SpatialFixtures.command(1, 0, Vector2i(0, 1)), "elevation_gap")
	_reject(t, session, Sm2SpatialFixtures.command(1, 0, Vector2i(3, 3)), "not_adjacent")
	var empty: Sm2FieldSession = Sm2FieldSession.new()
	_reject(t, empty, Sm2SpatialFixtures.command(1, 0, Vector2i.ZERO), "not_started")
	session.start(field, [Sm2SpatialFixtures.actor(1, 1, 1, 1)], 1)
	_reject(t, session, Sm2SpatialFixtures.command(1, 0, Vector2i(1, 2)), "insufficient_ap")
	session.start(field, [Sm2SpatialFixtures.actor(1, 1, 1, 9, 62)], 1)
	_reject(t, session, Sm2SpatialFixtures.command(1, 0, Vector2i(1, 2)), "fatigue_limit")
	session.start(field, [Sm2SpatialFixtures.actor(1, 1, 1, 2, 61)], 1)
	t.expect(session.execute(Sm2SpatialFixtures.command(1, 0, Vector2i(1, 2))).accepted, "M2 exact resource boundary accepted")
	t.equal(session.view().actors[0].ap, 0, "M2 exact AP exhausted")
	t.equal(session.view().actors[0].fatigue, 65, "M2 exact fatigue filled")

static func _reject(t: Sm2TestHarness, session: Sm2FieldSession, command: Sm2Command, reason: String) -> void:
	var before: String = session.state_hash()
	var check: Dictionary = session.preview(command)
	t.expect(not check.allowed, "M2 rejected preview: " + reason)
	t.equal(check.reason, reason, "M2 rejection preview reason")
	var result: Sm2CommandResult = session.execute(command)
	t.expect(not result.accepted, "M2 rejected execute: " + reason)
	t.equal(result.code, reason, "M2 rejection execute reason")
	t.expect(result.events.is_empty(), "M2 rejected command: no events")
	t.equal(session.state_hash(), before, "M2 rejected command: state/RNG/IDs/revision unchanged")

static func _initialization(t: Sm2TestHarness) -> void:
	var field: Sm2Battlefield = Sm2SpatialFixtures.field()
	var session: Sm2FieldSession = Sm2FieldSession.new()
	session.start(field, [Sm2SpatialFixtures.actor(1, 0, 0)], 1)
	var before: String = session.state_hash()
	var invalid: Array[Dictionary] = [
		Sm2SpatialFixtures.actor(0, 0, 0), Sm2SpatialFixtures.actor(1, 9, 0),
		Sm2SpatialFixtures.actor(1, 0, 0, 10), Sm2SpatialFixtures.actor(1, 0, 0, 9, 66),
		Sm2SpatialFixtures.actor(1, 0, 0, 9, 0, 65, false),
		Sm2SpatialFixtures.actor(1, 0, 0, 9, 0, 65, true, false)]
	var fractional: Dictionary = Sm2SpatialFixtures.actor(1, 0, 0)
	fractional.actor_id = 1.0
	invalid.append(fractional)
	for raw: Dictionary in invalid:
		t.expect(not session.start(field, [raw], 1).ok, "M2 invalid candidate actor rejected")
		t.equal(session.state_hash(), before, "M2 failed initialization preserves previous state")
	t.expect(not session.start(null, [], 0).ok, "M2 missing field rejected")
	t.expect(not session.start(field, [Sm2SpatialFixtures.actor(1, 0, 0), Sm2SpatialFixtures.actor(1, 1, 0)], 1).ok, "M2 duplicate ID rejected")
	t.expect(not session.start(field, [Sm2SpatialFixtures.actor(1, 0, 0), Sm2SpatialFixtures.actor(2, 0, 0)], 1).ok, "M2 duplicate living position rejected")
	t.equal(session.state_hash(), before, "M2 all failed starts preserve state")
	var one_cell: Sm2Battlefield = Sm2SpatialFixtures.field(1, 1)
	for absent_kind: String in ["dead", "escaped"]:
		var inactive: Dictionary = Sm2SpatialFixtures.actor(2, 0, 0, 9, 0, 65, absent_kind != "dead", absent_kind != "escaped")
		t.expect(session.start(one_cell, [Sm2SpatialFixtures.actor(1, 0, 0), inactive], 1).ok,
			"M2 actor count independent of living cell capacity: " + absent_kind)
	var big_id: int = 9007199254740993
	t.expect(session.start(field, [Sm2SpatialFixtures.actor(big_id, 0, 0)], big_id).ok, "M2 ID above JSON exact-number range accepted as int")
	t.equal(session.capture().actors[0].actor_id, "9007199254740993", "M2 snapshot ID is exact decimal")
	t.expect(Sm2Canonical.is_json_safe(session.capture()), "M2 capture is JSON safe")

static func _isolation(t: Sm2TestHarness) -> void:
	var field: Sm2Battlefield = Sm2SpatialFixtures.field()
	var actors: Array[Dictionary] = [Sm2SpatialFixtures.actor(1, 0, 0)]
	var session: Sm2FieldSession = Sm2FieldSession.new()
	session.start(field, actors, 1)
	var before: String = session.state_hash()
	actors[0].ap = 0
	field.build(Sm2SpatialFixtures.field(1, 1).to_data())
	var view: Dictionary = session.view()
	view.actors[0].q = 5
	view.field.surfaces.clear()
	var snapshot: Dictionary = session.capture()
	snapshot.rng.state = "77"
	snapshot.actors.clear()
	t.equal(session.state_hash(), before, "M2 input/view/snapshot mutations cannot alter state")
	var queries_before: String = session.state_hash()
	var reachable: Dictionary = session.reachable(1)
	t.expect(reachable.ok, "M2 detached reachable request")
	if not reachable.cells.is_empty():
		reachable.cells[0].path.clear()
	session.route(1, Vector2i(5, 0))
	session.line_of_sight(1, 1)
	t.equal(session.state_hash(), queries_before, "M2 path/LOS queries do not mutate state")
	var moved: Sm2CommandResult = session.execute(Sm2SpatialFixtures.command(1, 0, Vector2i(1, 0)))
	var after: String = session.state_hash()
	moved.events[1].q = 99
	t.equal(session.state_hash(), after, "M2 events detached from state")

static func _presence(t: Sm2TestHarness) -> void:
	var field: Sm2Battlefield = Sm2SpatialFixtures.field()
	for absent_kind: String in ["dead", "escaped"]:
		var session: Sm2FieldSession = Sm2FieldSession.new()
		var absent: Dictionary = Sm2SpatialFixtures.actor(2, 1, 0, 9, 0, 65, absent_kind != "dead", absent_kind != "escaped")
		session.start(field, [Sm2SpatialFixtures.actor(1, 0, 0), absent, Sm2SpatialFixtures.actor(3, 2, 0)], 1)
		t.expect(session.line_of_sight(1, 3).visible, "M2 absent actor does not block LOS: " + absent_kind)
		t.expect(session.execute(Sm2SpatialFixtures.command(1, 0, Vector2i(1, 0))).accepted, "M2 absent actor does not occupy: " + absent_kind)
		t.expect(not session.reachable(2).ok, "M2 absent actor has no reachable request: " + absent_kind)
	var session: Sm2FieldSession = Sm2FieldSession.new()
	session.start(field, [Sm2SpatialFixtures.actor(1, 0, 0), Sm2SpatialFixtures.actor(2, 1, 0), Sm2SpatialFixtures.actor(3, 2, 0)], 1)
	t.expect(not session.line_of_sight(1, 3).visible, "M2 living ally/enemy blocks LOS equally")

static func _paths_and_replay(t: Sm2TestHarness) -> void:
	var field: Sm2Battlefield = Sm2SpatialFixtures.field(11, 2)
	var left: Sm2FieldSession = Sm2FieldSession.new()
	var right: Sm2FieldSession = Sm2FieldSession.new()
	left.start(field, [Sm2SpatialFixtures.actor(1, 0, 0, 2)], 1, 37)
	right.start(field, [Sm2SpatialFixtures.actor(1, 0, 0, 2)], 1, 37)
	var strategic: Dictionary = left.route(1, Vector2i(10, 0))
	t.expect(strategic.ok, "M2 strategic route exceeds one activation")
	t.equal(strategic.ap_cost, 20, "M2 strategic route AP oracle")
	t.equal(strategic.fatigue_cost, 40, "M2 strategic route fatigue oracle")
	t.equal(strategic.path.size(), 10, "M2 full strategic route retained")
	var current: Dictionary = left.reachable(1)
	var contains_far: bool = false
	for cell: Dictionary in current.cells:
		contains_far = contains_far or (cell.q == 10 and cell.r == 0)
	t.expect(not contains_far, "M2 current reachability excludes distant goal")
	var move: Sm2Command = Sm2SpatialFixtures.command(1, 0, Vector2i(1, 0))
	left.route(1, Vector2i(10, 0))
	left.preview(move)
	t.equal(left.execute(move).events, right.execute(move).events, "M2 same command replay events after extra queries")
	t.equal(left.state_hash(), right.state_hash(), "M2 same command replay state")
	_reject(t, left, Sm2SpatialFixtures.command(1, 1, Vector2i(2, 0)), "insufficient_ap")

static func _main_scenario(t: Sm2TestHarness) -> void:
	var loaded: Dictionary = Sm2FieldContentLoader.load_scenario()
	t.expect(loaded.ok, "M2 authored main scenario loads")
	if not loaded.ok:
		return
	var markers: Array[Dictionary] = []
	markers.assign(loaded.spawns)
	var session: Sm2FieldSession = Sm2FieldSession.new()
	t.expect(session.start(loaded.field, Sm2SpatialFixtures.from_markers(markers), 1, loaded.seed).ok, "M2 authored six actors initialize spatial rehearsal")
	var route: Dictionary = session.route(1, Vector2i(8, 2))
	t.expect(route.ok, "M2 main field has strategic approach")
	t.equal(route.ap_cost, 16, "M2 main approach AP independently specified")
	t.equal(route.fatigue_cost, 32, "M2 main approach fatigue independently specified")
	t.expect(session.execute(Sm2SpatialFixtures.command(1, 0, Vector2i(2, 2))).accepted, "M2 authored hill movement command")
	t.equal(session.view().actors[0].ap, 6, "M2 main hill AP 9 minus3")
	t.equal(session.view().actors[0].fatigue, 6, "M2 main hill fatigue6")
	t.equal(session.capture().rng.draws, "0", "M2 authored rehearsal never draws RNG")
