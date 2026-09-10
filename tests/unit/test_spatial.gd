class_name Sm2TestSpatial
extends RefCounted

static func run(t: Sm2TestHarness) -> void:
	_hex(t)
	_field(t)
	_steps(t)
	_paths(t)
	_pareto(t)
	_visibility(t)
	_invalid_queries(t)
	t.complete_suite("spatial")

static func _hex(t: Sm2TestHarness) -> void:
	var neighbors: Array[Vector2i] = Sm2Hex.neighbors(Vector2i(3, 4))
	t.equal(neighbors, [Vector2i(4, 4), Vector2i(4, 3), Vector2i(3, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(3, 5)], "hex: six axial neighbors in authored order")
	for cell: Vector2i in neighbors:
		t.equal(Sm2Hex.distance(Vector2i(3, 4), cell), 1, "hex: each neighbor is one step")
		t.expect(Vector2i(3, 4) in Sm2Hex.neighbors(cell), "hex: neighbor relation symmetric")
	t.equal(Sm2Hex.distance(Vector2i(0, 0), Vector2i(2, 2)), 4, "hex: diagonal axial distance")
	t.equal(Sm2Hex.distance(Vector2i(0, 2), Vector2i(4, 0)), 4, "hex: opposite axial increments")
	t.equal(Sm2Hex.distance(Vector2i(2147483647, 2147483647), Vector2i(-2147483648, -2147483648)), 8589934590, "hex: differences promoted before Vector2i overflow")
	t.equal(Sm2Hex.neighbors(Vector2i(2147483647, 0)), [], "hex: unrepresentable neighbors never wrap")
	t.expect(Sm2Hex.numeric_less(Vector2i(9, 2), Vector2i(10, 0)), "hex: numeric q order differs from text order")
	t.expect(Sm2Hex.numeric_less(Vector2i(10, 2), Vector2i(10, 11)), "hex: numeric r order")

static func _field(t: Sm2TestHarness) -> void:
	var raw: Dictionary = _raw(4, 3)
	raw.tiles = [_tile(2, 1, "rough", 1), _tile(0, 2, "normal", 0, false, true)]
	var field: Sm2Battlefield = _build(t, raw)
	t.equal(field.id(), "test:field", "field: identity")
	t.equal(field.width(), 4, "field: width")
	t.equal(field.height(), 3, "field: height")
	t.equal(field.cell(Vector2i(1, 1)), {"q": 1, "r": 1, "surface_id": "normal", "elevation": 0, "passable": true, "opaque": false, "ap_cost": 2, "fatigue_cost": 4}, "field: resolved default cell")
	t.equal(field.cell(Vector2i(2, 1)).ap_cost, 3, "field: surface reference resolved")
	t.equal(field.cell(Vector2i(2, 1)).elevation, 1, "field: full tile override")
	t.equal(field.cell(Vector2i(-1, 1)), {}, "field: negative cell absent")
	t.equal(field.cell(Vector2i(4, 0)), {}, "field: upper edge excluded")
	var fingerprint: String = field.fingerprint()
	raw.surfaces[0].ap_cost = 99
	raw.tiles[0].elevation = 15
	var exported: Dictionary = field.to_data()
	exported.surfaces.clear()
	exported.tiles.clear()
	var cell: Dictionary = field.cell(Vector2i(2, 1))
	cell.passable = false
	t.equal(field.fingerprint(), fingerprint, "field: raw/export/cell mutation detached")
	var reordered: Dictionary = field.to_data()
	reordered.surfaces.reverse()
	reordered.tiles.reverse()
	var second: Sm2Battlefield = _build(t, reordered)
	t.equal(second.fingerprint(), fingerprint, "field: canonical surface/tile order")
	var json_data: Variant = JSON.parse_string(JSON.stringify(field.to_data()))
	t.equal(second.build(json_data).size(), 0, "field: validated integral JSON floats normalize")
	t.equal(second.fingerprint(), fingerprint, "field: JSON roundtrip exact normalized hash")
	reordered.version = "changed"
	t.equal(second.build(reordered).size(), 0, "field: next metadata revision valid")
	t.expect(second.fingerprint() != fingerprint, "field: fingerprint includes metadata")
	var broken: Array[Dictionary] = []
	var item: Dictionary = field.to_data()
	item.width = 65
	broken.append(item)
	item = field.to_data()
	item.height = 0
	broken.append(item)
	item = field.to_data()
	item.width = 3.5
	broken.append(item)
	item = field.to_data()
	item.default_elevation = 17
	broken.append(item)
	item = field.to_data()
	item.default_surface_id = "absent"
	broken.append(item)
	item = field.to_data()
	item.surfaces[0].ap_cost = 0
	broken.append(item)
	item = field.to_data()
	item.surfaces[0].fatigue_cost = -1
	broken.append(item)
	item = field.to_data()
	item.surfaces[0].fatigue_cost = INF
	broken.append(item)
	item = field.to_data()
	item.surfaces.append(item.surfaces[0].duplicate(true))
	broken.append(item)
	item = field.to_data()
	item.tiles.append(item.tiles[0].duplicate(true))
	broken.append(item)
	item = field.to_data()
	item.tiles[0].passable = 1
	broken.append(item)
	item = field.to_data()
	item.tiles[0].opaque = "true"
	broken.append(item)
	item = field.to_data()
	item.tiles[0].q = 4
	broken.append(item)
	item = field.to_data()
	item.tiles[0].surface_id = "absent"
	broken.append(item)
	item = field.to_data()
	item.erase("version")
	broken.append(item)
	item = field.to_data()
	item.unexpected = true
	broken.append(item)
	for index: int in broken.size():
		t.expect(not field.build(broken[index]).is_empty(), "field: rejects corrupt raw %d" % index)
		t.equal(field.fingerprint(), fingerprint, "field: failed build keeps current map %d" % index)

static func _steps(t: Sm2TestHarness) -> void:
	var raw: Dictionary = _raw(5, 4)
	raw.tiles = [_tile(2, 1, "rough", 1), _tile(1, 2, "normal", 2), _tile(0, 2, "normal", 0, false, true)]
	var field: Sm2Battlefield = _build(t, raw)
	t.equal(Sm2SpatialQueries.step(field, Vector2i(1, 1), Vector2i(2, 1), []).ap_cost, 4, "step: rough uphill AP=3+1")
	t.equal(Sm2SpatialQueries.step(field, Vector2i(1, 1), Vector2i(2, 1), []).fatigue_cost, 8, "step: rough uphill fatigue=6+2")
	t.equal(Sm2SpatialQueries.step(field, Vector2i(2, 1), Vector2i(1, 1), []).ap_cost, 2, "step: downhill pays destination only")
	t.equal(Sm2SpatialQueries.step(field, Vector2i(2, 1), Vector2i(1, 1), []).fatigue_cost, 4, "step: downhill has no fatigue surcharge")
	t.equal(Sm2SpatialQueries.step(field, Vector2i(1, 1), Vector2i(1, 2), []).reason, "elevation_gap", "step: elevation two forbidden")
	t.equal(Sm2SpatialQueries.step(field, Vector2i(1, 2), Vector2i(1, 1), []).reason, "elevation_gap", "step: drop two forbidden")
	t.equal(Sm2SpatialQueries.step(field, Vector2i(1, 1), Vector2i(0, 2), []).reason, "impassable", "step: rock blocks passage")
	t.equal(Sm2SpatialQueries.step(field, Vector2i(1, 1), Vector2i(2, 0), [Vector2i(2, 0)]).reason, "occupied", "step: friendly or hostile occupant blocks equally")
	t.equal(Sm2SpatialQueries.step(field, Vector2i(1, 1), Vector2i(4, 1), []).reason, "not_adjacent", "step: command cannot teleport")
	t.equal(Sm2SpatialQueries.step(field, Vector2i(1, 1), Vector2i(1, 1), []).reason, "not_adjacent", "step: no zero-length movement")
	t.equal(Sm2SpatialQueries.step(field, Vector2i(0, 0), Vector2i(-1, 0), []).reason, "out_of_bounds", "step: board edge")
	t.expect(Sm2SpatialQueries.step(field, Vector2i(1, 1), Vector2i(2, 0), [Vector2i(1, 1), Vector2i(1, 1)]).allowed, "step: origin occupant and duplicate origin ignored")
	t.expect(Sm2SpatialQueries.step(field, Vector2i(1, 1), Vector2i(2, 0), []).allowed, "step: absent departed actor creates no occupancy")

static func _paths(t: Sm2TestHarness) -> void:
	var field: Sm2Battlefield = _build(t, _raw(12, 3))
	var origin: Vector2i = Vector2i(10, 1)
	var target: Vector2i = Vector2i(9, 0)
	var route: Dictionary = Sm2SpatialQueries.route(field, origin, target, [], 2, 4)
	t.expect(route.ok, "route: strategic path exists")
	t.equal(route.path, [Vector2i(9, 1), Vector2i(9, 0)], "route: complete numerical q/r sequence breaks equal-cost tie")
	t.equal(route.ap_cost, 4, "route: total AP exceeds per-step limit")
	t.equal(route.fatigue_cost, 8, "route: total fatigue exceeds per-step limit")
	var all: Dictionary = Sm2SpatialQueries.reachable(field, origin, [], 4, 8)
	t.expect(all.ok, "reachable: within-budget area exists")
	t.equal(_find(all.cells, target).path, route.path, "reachable: same canonical path as strategic query")
	t.equal(_find(all.cells, origin), {}, "reachable: origin omitted")
	t.equal(_find(Sm2SpatialQueries.reachable(field, origin, [], 4, 7).cells, target), {}, "reachable: fatigue budget independently enforced")
	t.equal(_find(Sm2SpatialQueries.reachable(field, origin, [], 3, 8).cells, target), {}, "reachable: AP budget independently enforced")
	t.equal(Sm2SpatialQueries.reachable(field, origin, [], 0, 0).cells, [], "reachable: zero budgets are valid and empty")
	t.equal(Sm2SpatialQueries.route(field, origin, origin, [origin], 0, 0), {"ok": true, "reason": "", "path": [], "ap_cost": 0, "fatigue_cost": 0}, "route: current occupied origin is zero-cost goal")
	t.equal(Sm2SpatialQueries.route(field, origin, target, [], 1, 100).reason, "unreachable", "route: every edge must fit maximal AP")
	t.equal(Sm2SpatialQueries.route(field, origin, target, [], 100, 3).reason, "unreachable", "route: every edge must fit maximal fatigue")
	t.equal(Sm2SpatialQueries.route(field, origin, target, [target], 9, 100).reason, "occupied", "route: target occupant is not silently bypassed")
	var large: Dictionary = Sm2SpatialQueries.reachable(field, Vector2i(6, 1), [], 100, 100)
	var prior: Vector2i = Vector2i(-1, -1)
	for cell: Dictionary in large.cells:
		var position: Vector2i = Vector2i(cell.q, cell.r)
		t.expect(Sm2Hex.numeric_less(prior, position), "reachable: deterministic numeric output ordering")
		prior = position
	var far: Dictionary = Sm2SpatialQueries.route(field, Vector2i(0, 1), Vector2i(11, 1), [], 2, 4)
	t.expect(far.ok, "route: distant goal reached across multiple activations")
	t.equal(far.path.size(), 11, "route: long straight path has exact number of steps")
	t.equal(far.ap_cost, 22, "route: long strategic aggregate cost")
	t.equal(_find(Sm2SpatialQueries.reachable(field, Vector2i(0, 1), [], 9, 100).cells, Vector2i(11, 1)), {}, "reachable: same distant goal not reachable this activation")
	var occupancy: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 1)]
	var detour: Dictionary = Sm2SpatialQueries.route(field, Vector2i(0, 1), Vector2i(2, 1), occupancy, 2, 4)
	t.expect(detour.ok, "route: duplicate occupancy normalized and obstacle bypassed")
	t.expect(not Vector2i(1, 1) in detour.path, "route: no passage through occupied actor")
	var fingerprint: String = field.fingerprint()
	route.path.clear()
	all.cells.clear()
	detour.path.append(Vector2i(99, 99))
	t.equal(field.fingerprint(), fingerprint, "query result mutation does not change field")
	t.equal(Sm2SpatialQueries.route(field, origin, target, [], 2, 4).path, [Vector2i(9, 1), Vector2i(9, 0)], "query result mutation does not poison later queries")
	var sealed: Dictionary = _raw(3, 3)
	sealed.tiles = [_tile(1, 0, "normal", 0, false, false), _tile(1, 1, "normal", 0, false, false), _tile(1, 2, "normal", 0, false, false)]
	var sealed_field: Sm2Battlefield = _build(t, sealed)
	t.equal(Sm2SpatialQueries.route(sealed_field, Vector2i(0, 1), Vector2i(2, 1), [], 9, 100).reason, "unreachable", "route: disconnected component returns explicit failure")

static func _pareto(t: Sm2TestHarness) -> void:
	# O(0,1) -> A(1,0) -> C(2,0): 2 AP / 8 fatigue.
	# O(0,1) -> B(1,1) -> C(2,0): 4 AP / 0 fatigue.
	# Final C -> T(3,0) costs 1 AP / 4 fatigue. Both labels at C matter.
	var raw: Dictionary = _raw(4, 2)
	raw.surfaces = [{"id": "normal", "ap_cost": 1, "fatigue_cost": 0},
		{"id": "fast_tiring", "ap_cost": 1, "fatigue_cost": 8}, {"id": "slow_easy", "ap_cost": 3, "fatigue_cost": 0},
		{"id": "final", "ap_cost": 1, "fatigue_cost": 4}]
	raw.tiles = [_tile(0, 0, "normal", 0, false, false), _tile(2, 1, "normal", 0, false, false),
		_tile(3, 1, "normal", 0, false, false), _tile(1, 0, "fast_tiring"), _tile(1, 1, "slow_easy"), _tile(3, 0, "final")]
	var field: Sm2Battlefield = _build(t, raw)
	var reachable: Dictionary = Sm2SpatialQueries.reachable(field, Vector2i(0, 1), [], 5, 9)
	t.expect(reachable.ok, "Pareto: independent-cost synthetic map accepted")
	t.equal(_find(reachable.cells, Vector2i(2, 0)).path, [Vector2i(1, 0), Vector2i(2, 0)], "Pareto: best path at merge uses less AP")
	var destination: Dictionary = _find(reachable.cells, Vector2i(3, 0))
	t.expect(not destination.is_empty(), "Pareto: later destination survives via resource-saving label")
	if not destination.is_empty():
		t.equal(destination.path, [Vector2i(1, 1), Vector2i(2, 0), Vector2i(3, 0)], "Pareto: retained expensive-AP label is required for destination")
		t.equal(destination.ap_cost, 5, "Pareto: alternative path AP oracle")
		t.equal(destination.fatigue_cost, 4, "Pareto: alternative path fatigue oracle")
	t.equal(_find(Sm2SpatialQueries.reachable(field, Vector2i(0, 1), [], 4, 9).cells, Vector2i(3, 0)), {}, "Pareto: neither resource-infeasible path fabricates success")
	var strategic: Dictionary = Sm2SpatialQueries.route(field, Vector2i(0, 1), Vector2i(3, 0), [], 3, 9)
	t.equal(strategic.path, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], "Pareto: strategic optimum is unconstrained in aggregate")
	t.equal(strategic.fatigue_cost, 12, "Pareto: strategic aggregate fatigue may exceed per-step maximum")
	strategic = Sm2SpatialQueries.route(field, Vector2i(0, 1), Vector2i(3, 0), [], 3, 4)
	t.equal(strategic.path, [Vector2i(1, 1), Vector2i(2, 0), Vector2i(3, 0)], "Pareto: strategic route excludes individually impossible tiring edge")

static func _visibility(t: Sm2TestHarness) -> void:
	var field: Sm2Battlefield = _build(t, _raw(7, 7))
	var flat: Dictionary = Sm2SpatialQueries.los(field, Vector2i(0, 1), Vector2i(3, 1), [])
	t.equal(flat.cells, [Vector2i(1, 1), Vector2i(2, 1)], "LOS: centerline golden")
	t.expect(flat.visible, "LOS: clear centerline")
	t.equal(Sm2SpatialQueries.los(field, Vector2i(0, 0), Vector2i(2, 1), []).cells, [Vector2i(1, 0), Vector2i(1, 1)], "LOS: skew line golden")
	# Goldens independently derived by rational clipping against six halfplanes.
	var edge_cells: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 1)]
	var along_edge: Dictionary = Sm2SpatialQueries.los(field, Vector2i(0, 0), Vector2i(2, 2), [])
	t.equal(along_edge.cells, edge_cells, "LOS: shared closed edge includes cells on both sides")
	var vertex_cells: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)]
	t.equal(Sm2SpatialQueries.los(field, Vector2i(0, 0), Vector2i(1, 4), []).cells, vertex_cells, "LOS: isolated vertex contact golden")
	t.expect(not Sm2SpatialQueries.los(field, Vector2i(0, 0), Vector2i(1, 4), [Vector2i(0, 3)]).visible, "LOS: actor touching only a corner blocks")
	t.expect(not Sm2SpatialQueries.los(field, Vector2i(0, 0), Vector2i(2, 2), [Vector2i(0, 1)]).visible, "LOS: actor beside shared edge blocks")
	t.expect(Sm2SpatialQueries.los(field, Vector2i(0, 1), Vector2i(3, 1), [Vector2i(0, 1), Vector2i(3, 1), Vector2i(3, 1)]).visible, "LOS: source and target occupants excluded, duplicates harmless")
	t.expect(Sm2SpatialQueries.los(field, Vector2i(0, 1), Vector2i(3, 1), [Vector2i(1, 3)]).visible, "LOS: off-ray actor does not block")
	t.expect(Sm2SpatialQueries.los(field, Vector2i(0, 0), Vector2i(6, 1), []).visible, "LOS: geometry query does not impose weapon range")
	t.equal(Sm2SpatialQueries.los(field, Vector2i(2, 2), Vector2i(2, 2), [Vector2i(2, 2)]).cells, [], "LOS: same-cell ray empty")
	t.expect(Sm2SpatialQueries.los(field, Vector2i(2, 2), Vector2i(2, 2), []).visible, "LOS: same-cell geometry visible")
	t.equal(Sm2SpatialQueries.los(field, Vector2i(0, 0), Vector2i(1, 0), []).cells, [], "LOS: adjacent cells have no intermediate blocker")
	var raw: Dictionary = _raw(7, 7)
	raw.tiles = [_tile(0, 3, "normal", 0, false, true)]
	var rock_field: Sm2Battlefield = _build(t, raw)
	var corner: Dictionary = Sm2SpatialQueries.los(rock_field, Vector2i(0, 0), Vector2i(1, 4), [])
	t.equal(corner.blockers, [{"q": 0, "r": 3, "reason": "opaque"}], "LOS: corner rock blocks for explicit opacity reason")
	raw.tiles = [_tile(1, 1, "normal", 0, false, false)]
	var transparent: Sm2Battlefield = _build(t, raw)
	t.expect(Sm2SpatialQueries.los(transparent, Vector2i(0, 1), Vector2i(3, 1), []).visible, "LOS: impassable does not imply opaque")
	raw.tiles = [_tile(1, 1, "normal", 0, true, true)]
	var opaque_passage: Sm2Battlefield = _build(t, raw)
	t.expect(Sm2SpatialQueries.step(opaque_passage, Vector2i(0, 1), Vector2i(1, 1), []).allowed, "step: opacity does not imply impassable")
	t.expect(not Sm2SpatialQueries.los(opaque_passage, Vector2i(0, 1), Vector2i(3, 1), []).visible, "LOS: passable opaque cell still blocks sight")
	raw.tiles = [_tile(1, 1, "normal", 1)]
	var raised: Sm2Battlefield = _build(t, raw)
	t.equal(Sm2SpatialQueries.los(raised, Vector2i(0, 1), Vector2i(3, 1), []).blockers, [{"q": 1, "r": 1, "reason": "elevation"}], "LOS: intermediate terrain above lower endpoint blocks")
	raw.tiles = [_tile(0, 1, "normal", 1), _tile(1, 1, "normal", 1), _tile(3, 1, "normal", 1)]
	raised = _build(t, raw)
	t.expect(Sm2SpatialQueries.los(raised, Vector2i(0, 1), Vector2i(3, 1), []).visible, "LOS: terrain equal to both elevated endpoints does not block")
	raw.tiles = [_tile(0, 1, "normal", 1), _tile(1, 1, "normal", 1)]
	raised = _build(t, raw)
	t.expect(not Sm2SpatialQueries.los(raised, Vector2i(0, 1), Vector2i(3, 1), []).visible, "LOS: uses minimum endpoint height, not maximum")
	var symmetric_raw: Dictionary = _raw(4, 4)
	symmetric_raw.tiles = [_tile(1, 1, "normal", 0, false, true), _tile(2, 2, "normal", 1)]
	var symmetric: Sm2Battlefield = _build(t, symmetric_raw)
	var occupied: Array[Vector2i] = [Vector2i(0, 2), Vector2i(3, 1)]
	var positions: Array[Vector2i] = []
	for q: int in 4:
		for r: int in 4:
			positions.append(Vector2i(q, r))
	for left_index: int in positions.size():
		for right_index: int in range(left_index + 1, positions.size()):
			var forward: Dictionary = Sm2SpatialQueries.los(symmetric, positions[left_index], positions[right_index], occupied)
			var reverse: Dictionary = Sm2SpatialQueries.los(symmetric, positions[right_index], positions[left_index], occupied)
			t.equal(forward, reverse, "LOS: full result symmetric for endpoint pair %d/%d" % [left_index, right_index])
	var fingerprint: String = field.fingerprint()
	flat.cells.clear()
	along_edge.cells.append(Vector2i(99, 99))
	t.equal(field.fingerprint(), fingerprint, "LOS: detached query result")
	t.equal(Sm2SpatialQueries.los(field, Vector2i(0, 0), Vector2i(2, 2), []).cells, edge_cells, "LOS: no mutable cache exposed")

static func _invalid_queries(t: Sm2TestHarness) -> void:
	var field: Sm2Battlefield = _build(t, _raw(3, 3))
	var empty: Sm2Battlefield = Sm2Battlefield.new()
	t.equal(Sm2SpatialQueries.step(null, Vector2i.ZERO, Vector2i.ONE, []).reason, "invalid_field", "query: null field step")
	t.equal(Sm2SpatialQueries.reachable(empty, Vector2i.ZERO, [], 9, 10).reason, "invalid_field", "query: unbuilt field reachable")
	t.equal(Sm2SpatialQueries.route(null, Vector2i.ZERO, Vector2i.ONE, [], 9, 10).reason, "invalid_field", "query: null field route")
	t.equal(Sm2SpatialQueries.los(empty, Vector2i.ZERO, Vector2i.ONE, []).reason, "invalid_field", "query: unbuilt field LOS")
	t.equal(Sm2SpatialQueries.reachable(field, Vector2i.ZERO, [], -1, 10).reason, "invalid_budget", "query: negative reachable AP")
	t.equal(Sm2SpatialQueries.reachable(field, Vector2i.ZERO, [], 1, -10).reason, "invalid_budget", "query: negative reachable fatigue")
	t.equal(Sm2SpatialQueries.route(field, Vector2i.ZERO, Vector2i.ONE, [], -1, 10).reason, "invalid_budget", "query: negative route step limit")
	var outside: Array[Vector2i] = [Vector2i(3, 0)]
	t.equal(Sm2SpatialQueries.step(field, Vector2i.ZERO, Vector2i(1, 0), outside).reason, "invalid_occupancy", "query: step rejects outside occupancy")
	t.equal(Sm2SpatialQueries.reachable(field, Vector2i.ZERO, outside, 9, 10).reason, "invalid_occupancy", "query: reachable rejects outside occupancy")
	t.equal(Sm2SpatialQueries.route(field, Vector2i.ZERO, Vector2i.ONE, outside, 9, 10).reason, "invalid_occupancy", "query: route rejects outside occupancy")
	t.equal(Sm2SpatialQueries.los(field, Vector2i.ZERO, Vector2i.ONE, outside).reason, "invalid_occupancy", "query: LOS rejects outside occupancy")
	t.equal(Sm2SpatialQueries.reachable(field, Vector2i(-1, 0), [], 9, 10).reason, "out_of_bounds", "query: reachable origin outside")
	t.equal(Sm2SpatialQueries.route(field, Vector2i.ZERO, Vector2i(3, 1), [], 9, 10).reason, "out_of_bounds", "query: route destination outside")
	t.equal(Sm2SpatialQueries.los(field, Vector2i.ZERO, Vector2i(2147483647, 0), []).reason, "out_of_bounds", "query: LOS guards coordinates before plane arithmetic")
	t.expect(Sm2SpatialQueries.reachable(field, Vector2i.ZERO, [], 9223372036854775807, 9223372036854775807).ok, "query: huge budgets do not overflow bounded path costs")

static func _raw(width_value: int, height_value: int) -> Dictionary:
	return {"id": "test:field", "version": "test.1", "width": width_value, "height": height_value,
		"surfaces": [{"id": "normal", "ap_cost": 2, "fatigue_cost": 4}, {"id": "rough", "ap_cost": 3, "fatigue_cost": 6}],
		"default_surface_id": "normal", "default_elevation": 0, "tiles": []}

static func _tile(q: int, r: int, surface: String, elevation: int = 0, passable: bool = true, opaque: bool = false) -> Dictionary:
	return {"q": q, "r": r, "surface_id": surface, "elevation": elevation, "passable": passable, "opaque": opaque}

static func _build(t: Sm2TestHarness, raw: Dictionary) -> Sm2Battlefield:
	var field: Sm2Battlefield = Sm2Battlefield.new()
	t.equal(field.build(raw).size(), 0, "spatial test field builds")
	return field

static func _find(cells: Array, position: Vector2i) -> Dictionary:
	for cell: Dictionary in cells:
		if int(cell.q) == position.x and int(cell.r) == position.y:
			return cell
	return {}
