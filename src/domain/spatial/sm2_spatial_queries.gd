class_name Sm2SpatialQueries
extends RefCounted
## Pure spatial queries. Paths contain destinations only, never their origin.
const SEARCH_LIMIT: int = 200000
const VERTICES: Array[Vector2i] = [Vector2i(0, -2), Vector2i(1, -1), Vector2i(1, 1),
	Vector2i(0, 2), Vector2i(-1, 1), Vector2i(-1, -1)]

class PathLabel extends RefCounted:
	var position: Vector2i = Vector2i.ZERO
	var ap_cost: int = 0
	var fatigue_cost: int = 0
	var path: Array[Vector2i] = []
	var discarded: bool = false
	var risk: int = 0

static func step(field: Sm2Battlefield, origin: Vector2i, target: Vector2i, occupied: Array[Vector2i]) -> Dictionary:
	var reason: String = _validate_query(field, origin, occupied)
	if reason.is_empty() and not field.in_bounds(target):
		reason = "out_of_bounds"
	if not reason.is_empty():
		return _step_failure(reason)
	return _step(field, origin, target, _occupancy(occupied, origin))

static func reachable(field: Sm2Battlefield, origin: Vector2i, occupied: Array[Vector2i],
	ap_budget: int, fatigue_budget: int) -> Dictionary:
	var reason: String = _validate_query(field, origin, occupied)
	if reason.is_empty() and (ap_budget < 0 or fatigue_budget < 0):
		reason = "invalid_budget"
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "cells": []}
	if not field.cell(origin).passable:
		return {"ok": false, "reason": "impassable", "cells": []}
	var found: Dictionary = _search(field, origin, Vector2i(-1, -1), _occupancy(occupied, origin), ap_budget, fatigue_budget, false)
	if not found.ok:
		return {"ok": false, "reason": found.reason, "cells": []}
	var coordinates: Array[Vector2i] = []
	for position: Vector2i in found.labels:
		if position != origin:
			coordinates.append(position)
	coordinates.sort_custom(Sm2Hex.numeric_less)
	var cells: Array[Dictionary] = []
	for position: Vector2i in coordinates:
		var best: PathLabel = _best(found.labels[position])
		cells.append({"q": position.x, "r": position.y, "ap_cost": best.ap_cost,
			"fatigue_cost": best.fatigue_cost, "path": best.path.duplicate()})
	return {"ok": true, "reason": "", "cells": cells}

static func route(field: Sm2Battlefield, origin: Vector2i, target: Vector2i, occupied: Array[Vector2i],
	step_ap_limit: int, step_fatigue_limit: int) -> Dictionary:
	var reason: String = _validate_query(field, origin, occupied)
	if reason.is_empty() and not field.in_bounds(target):
		reason = "out_of_bounds"
	if reason.is_empty() and (step_ap_limit < 0 or step_fatigue_limit < 0):
		reason = "invalid_budget"
	if not reason.is_empty():
		return _route_failure(reason)
	if not field.cell(origin).passable or not field.cell(target).passable:
		return _route_failure("impassable")
	var blocked: Dictionary = _occupancy(occupied, origin)
	if blocked.has(target):
		return _route_failure("occupied")
	if origin == target:
		return {"ok": true, "reason": "", "path": [], "ap_cost": 0, "fatigue_cost": 0}
	var found: Dictionary = _search(field, origin, target, blocked, step_ap_limit, step_fatigue_limit, true)
	if not found.ok:
		return _route_failure(found.reason)
	if not found.labels.has(target):
		return _route_failure("unreachable")
	var best: PathLabel = _best(found.labels[target])
	return {"ok": true, "reason": "", "path": best.path.duplicate(), "ap_cost": best.ap_cost, "fatigue_cost": best.fatigue_cost}

static func strategic_cells(field: Sm2Battlefield, origin: Vector2i, occupied: Array[Vector2i], ap_limit: int,
	fatigue_limit: int, risk_cells: Dictionary = {}) -> Dictionary:
	var reason: String = _validate_query(field, origin, occupied)
	if not reason.is_empty() or ap_limit < 0 or fatigue_limit < 0:
		return {"ok": false, "reason": reason if not reason.is_empty() else "invalid_budget", "cells": []}
	if not field.cell(origin).passable:
		return {"ok": false, "reason": "impassable", "cells": []}
	for key: Variant in risk_cells:
		if not key is Vector2i or not field.in_bounds(key) or not Sm2Validate.integer(risk_cells[key], 0, 1):
			return {"ok": false, "reason": "invalid_risk_cells", "cells": []}
	var found: Dictionary = _search(field, origin, Vector2i(-1, -1), _occupancy(occupied, origin), ap_limit, fatigue_limit, true, risk_cells)
	if not found.ok:
		return {"ok": false, "reason": found.reason, "cells": []}
	var cells: Array[Dictionary] = []
	var positions: Array[Vector2i] = []
	positions.assign(found.labels.keys())
	positions.sort_custom(Sm2Hex.numeric_less)
	for position: Vector2i in positions:
		var best: PathLabel = _best(found.labels[position])
		cells.append({"position": position, "risk": best.risk, "ap_cost": best.ap_cost, "fatigue_cost": best.fatigue_cost, "path": best.path.duplicate()})
	return {"ok": true, "reason": "", "cells": cells}

static func route_to_boundary(field: Sm2Battlefield, origin: Vector2i, occupied: Array[Vector2i],
	step_ap_limit: int, step_fatigue_limit: int) -> Dictionary:
	var reason: String = _validate_query(field, origin, occupied)
	if not reason.is_empty():
		return _route_failure(reason)
	if step_ap_limit < 2 or step_fatigue_limit < 4 or not field.cell(origin).passable:
		return _route_failure("unreachable")
	var found: Dictionary = _search(field, origin, Vector2i(-1, -1), _occupancy(occupied, origin), step_ap_limit, step_fatigue_limit, true)
	if not found.ok:
		return _route_failure(found.reason)
	var best: PathLabel = null
	for position: Vector2i in found.labels:
		if position.x != 0 and position.y != 0 and position.x != field.width() - 1 and position.y != field.height() - 1:
			continue
		var candidate: PathLabel = _best(found.labels[position])
		if best == null or candidate.ap_cost < best.ap_cost or (candidate.ap_cost == best.ap_cost and
			(candidate.fatigue_cost < best.fatigue_cost or (candidate.fatigue_cost == best.fatigue_cost and Sm2Hex.numeric_less(position, best.position)))):
			best = candidate
	if best == null:
		return _route_failure("unreachable")
	return {"ok": true, "reason": "", "path": best.path.duplicate(), "ap_cost": best.ap_cost + 2, "fatigue_cost": best.fatigue_cost + 4,
		"destination": best.position}

static func los(field: Sm2Battlefield, origin: Vector2i, target: Vector2i, occupied: Array[Vector2i]) -> Dictionary:
	var reason: String = _validate_query(field, origin, occupied)
	if reason.is_empty() and not field.in_bounds(target):
		reason = "out_of_bounds"
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "visible": false, "cells": [], "blockers": []}
	var cells: Array[Vector2i] = []
	var blockers: Array[Dictionary] = []
	if origin == target:
		return {"ok": true, "reason": "", "visible": true, "cells": cells, "blockers": blockers}
	var blocked: Dictionary = _occupancy(occupied, origin)
	blocked.erase(target)
	var start: Vector2i = _center(origin)
	var finish: Vector2i = _center(target)
	var height_limit: int = mini(int(field.cell(origin).elevation), int(field.cell(target).elevation))
	# The complete map has <=4096 cells, and each exact test has six edges.
	# Numeric q/r iteration also defines deterministic, direction-independent output.
	for q: int in field.width():
		for r: int in field.height():
			var position: Vector2i = Vector2i(q, r)
			if position == origin or position == target or not _touches_hex(start, finish, _center(position)):
				continue
			cells.append(position)
			var tile: Dictionary = field.cell(position)
			var blocker_reason: String = ""
			if tile.opaque:
				blocker_reason = "opaque"
			elif blocked.has(position):
				blocker_reason = "occupied"
			elif int(tile.elevation) > height_limit:
				blocker_reason = "elevation"
			if not blocker_reason.is_empty():
				blockers.append({"q": q, "r": r, "reason": blocker_reason})
	return {"ok": true, "reason": "", "visible": blockers.is_empty(), "cells": cells, "blockers": blockers}

static func _validate_query(field: Sm2Battlefield, origin: Vector2i, occupied: Array[Vector2i]) -> String:
	if field == null or field.width() == 0 or field.height() == 0:
		return "invalid_field"
	if not field.in_bounds(origin):
		return "out_of_bounds"
	for position: Vector2i in occupied:
		if not field.in_bounds(position):
			return "invalid_occupancy"
	return ""

static func _occupancy(occupied: Array[Vector2i], origin: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	for position: Vector2i in occupied:
		if position != origin:
			result[position] = true
	return result

static func _step(field: Sm2Battlefield, origin: Vector2i, target: Vector2i, blocked: Dictionary) -> Dictionary:
	if not field.in_bounds(target):
		return _step_failure("out_of_bounds")
	var source: Dictionary = field.cell(origin)
	var destination: Dictionary = field.cell(target)
	if not source.passable or not destination.passable:
		return _step_failure("impassable")
	if blocked.has(target):
		return _step_failure("occupied")
	if Sm2Hex.distance(origin, target) != 1:
		return _step_failure("not_adjacent")
	var climb: int = int(destination.elevation) - int(source.elevation)
	if absi(climb) > 1:
		return _step_failure("elevation_gap")
	return {"allowed": true, "reason": "", "ap_cost": int(destination.ap_cost) + maxi(climb, 0),
		"fatigue_cost": int(destination.fatigue_cost) + maxi(climb, 0) * 2}

static func _step_failure(reason: String) -> Dictionary:
	return {"allowed": false, "reason": reason, "ap_cost": 0, "fatigue_cost": 0}

static func _route_failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "path": [], "ap_cost": 0, "fatigue_cost": 0}

static func _search(field: Sm2Battlefield, origin: Vector2i, target: Vector2i, blocked: Dictionary,
	ap_limit: int, fatigue_limit: int, strategic: bool, risk_cells: Dictionary = {}) -> Dictionary:
	var first: PathLabel = PathLabel.new()
	first.position = origin
	var heap: Array[PathLabel] = [first]
	var labels: Dictionary = {origin: [first]}
	var settled: int = 0
	while not heap.is_empty():
		var current: PathLabel = _heap_pop(heap)
		if current.discarded:
			continue
		if settled >= SEARCH_LIMIT:
			return {"ok": false, "reason": "search_limit"}
		settled += 1
		if strategic and current.position == target:
			return {"ok": true, "reason": "", "labels": labels}
		for destination: Vector2i in Sm2Hex.neighbors(current.position):
			var price: Dictionary = _step(field, current.position, destination, blocked)
			if not price.allowed:
				continue
			var edge_ap: int = int(price.ap_cost)
			var edge_fatigue: int = int(price.fatigue_cost)
			if strategic and (edge_ap > ap_limit or edge_fatigue > fatigue_limit):
				continue
			# Positive AP and Pareto dominance discard all cycles. A surviving
			# path visits <=4096 cells, so costs <=4095*102 cannot overflow.
			var total_ap: int = current.ap_cost + edge_ap
			var total_fatigue: int = current.fatigue_cost + edge_fatigue
			if not strategic and (total_ap > ap_limit or total_fatigue > fatigue_limit):
				continue
			var label: PathLabel = PathLabel.new()
			label.position = destination
			label.risk = current.risk + int(risk_cells.get(current.position, 0))
			label.ap_cost = total_ap
			label.fatigue_cost = total_fatigue
			label.path.assign(current.path)
			label.path.append(destination)
			if _insert_label(labels, label):
				_heap_push(heap, label)
	return {"ok": true, "reason": "", "labels": labels}

static func _insert_label(labels: Dictionary, candidate: PathLabel) -> bool:
	var existing: Array = labels.get(candidate.position, [])
	for current: PathLabel in existing:
		if current.risk <= candidate.risk and current.ap_cost <= candidate.ap_cost and current.fatigue_cost <= candidate.fatigue_cost:
			if current.risk != candidate.risk or current.ap_cost != candidate.ap_cost or current.fatigue_cost != candidate.fatigue_cost \
				or not Sm2Hex.path_less(candidate.path, current.path):
				return false
	var kept: Array[PathLabel] = []
	for current: PathLabel in existing:
		if candidate.risk <= current.risk and candidate.ap_cost <= current.ap_cost and candidate.fatigue_cost <= current.fatigue_cost:
			current.discarded = true
		else:
			kept.append(current)
	kept.append(candidate)
	labels[candidate.position] = kept
	return true

static func _best(labels: Array) -> PathLabel:
	var result: PathLabel = labels[0]
	for candidate: PathLabel in labels:
		if _label_less(candidate, result):
			result = candidate
	return result

static func _label_less(left: PathLabel, right: PathLabel) -> bool:
	if left.risk != right.risk:
		return left.risk < right.risk
	if left.ap_cost != right.ap_cost:
		return left.ap_cost < right.ap_cost
	if left.fatigue_cost != right.fatigue_cost:
		return left.fatigue_cost < right.fatigue_cost
	return Sm2Hex.path_less(left.path, right.path)

static func _heap_push(heap: Array[PathLabel], value: PathLabel) -> void:
	heap.append(value)
	var index: int = heap.size() - 1
	while index > 0:
		@warning_ignore("integer_division")
		var parent: int = (index - 1) / 2
		if not _label_less(heap[index], heap[parent]):
			break
		var swap: PathLabel = heap[parent]
		heap[parent] = heap[index]
		heap[index] = swap
		index = parent

static func _heap_pop(heap: Array[PathLabel]) -> PathLabel:
	var result: PathLabel = heap[0]
	var last: PathLabel = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = last
	var index: int = 0
	while index * 2 + 1 < heap.size():
		var child: int = index * 2 + 1
		if child + 1 < heap.size() and _label_less(heap[child + 1], heap[child]):
			child += 1
		if not _label_less(heap[child], heap[index]):
			break
		var swap: PathLabel = heap[index]
		heap[index] = heap[child]
		heap[child] = swap
		index = child
	return result

static func _center(position: Vector2i) -> Vector2i:
	return Vector2i(position.x * 2 + position.y, position.y * 3)

static func _touches_hex(start: Vector2i, finish: Vector2i, center: Vector2i) -> bool:
	# Endpoint containment also handles a degenerate segment completely inside.
	if _inside_hex(start, center) or _inside_hex(finish, center):
		return true
	for index: int in VERTICES.size():
		var edge_start: Vector2i = center + VERTICES[index]
		var edge_finish: Vector2i = center + VERTICES[(index + 1) % VERTICES.size()]
		if _segments_touch(start, finish, edge_start, edge_finish):
			return true
	return false

static func _inside_hex(point: Vector2i, center: Vector2i) -> bool:
	var has_positive: bool = false
	var has_negative: bool = false
	for index: int in VERTICES.size():
		var orientation: int = _cross(center + VERTICES[index], center + VERTICES[(index + 1) % VERTICES.size()], point)
		has_positive = has_positive or orientation > 0
		has_negative = has_negative or orientation < 0
		if has_positive and has_negative:
			return false
	return true

static func _segments_touch(a: Vector2i, b: Vector2i, c: Vector2i, d: Vector2i) -> bool:
	var ac: int = _cross(a, b, c)
	var ad: int = _cross(a, b, d)
	var ca: int = _cross(c, d, a)
	var cb: int = _cross(c, d, b)
	if ac == 0 and _on_segment(a, b, c):
		return true
	if ad == 0 and _on_segment(a, b, d):
		return true
	if ca == 0 and _on_segment(c, d, a):
		return true
	if cb == 0 and _on_segment(c, d, b):
		return true
	return ((ac < 0 and ad > 0) or (ac > 0 and ad < 0)) \
		and ((ca < 0 and cb > 0) or (ca > 0 and cb < 0))

static func _on_segment(a: Vector2i, b: Vector2i, point: Vector2i) -> bool:
	return point.x >= mini(a.x, b.x) and point.x <= maxi(a.x, b.x) \
		and point.y >= mini(a.y, b.y) and point.y <= maxi(a.y, b.y)

static func _cross(a: Vector2i, b: Vector2i, point: Vector2i) -> int:
	var dx: int = int(b.x) - int(a.x)
	var dy: int = int(b.y) - int(a.y)
	return dx * (int(point.y) - int(a.y)) - dy * (int(point.x) - int(a.x))
