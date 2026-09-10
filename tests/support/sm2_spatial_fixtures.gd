class_name Sm2SpatialFixtures
extends RefCounted
## Mobility inputs for spatial tests, not a second authored character/equipment catalog.

static func field(width: int = 6, height: int = 4, overrides: Array[Dictionary] = []) -> Sm2Battlefield:
	var result: Sm2Battlefield = Sm2Battlefield.new()
	result.build({"id": "test:field", "version": "1", "width": width, "height": height,
		"surfaces": [{"id": "ground", "ap_cost": 2, "fatigue_cost": 4},
			{"id": "rough", "ap_cost": 3, "fatigue_cost": 6}],
		"default_surface_id": "ground", "default_elevation": 0, "tiles": overrides})
	return result

static func tile(q: int, r: int, surface: String = "ground", elevation: int = 0,
	passable: bool = true, opaque: bool = false) -> Dictionary:
	return {"q": q, "r": r, "surface_id": surface, "elevation": elevation, "passable": passable, "opaque": opaque}

static func actor(actor_id: int, q: int, r: int, ap: int = 9, fatigue: int = 0,
	fatigue_max: int = 65, alive: bool = true, on_field: bool = true) -> Dictionary:
	return {"actor_id": actor_id, "side": "company" if actor_id == 1 else "opposition",
		"owner": "fixture", "controller": "fixture", "q": q, "r": r, "ap_max": 9,
		"ap": ap, "fatigue_max": fatigue_max, "fatigue": fatigue, "alive": alive, "on_field": on_field}

static func from_markers(spawns: Array[Dictionary]) -> Array[Dictionary]:
	var limits: Dictionary[int, int] = {1: 65, 2: 73, 3: 74, 4: 64, 5: 65, 6: 74}
	var result: Array[Dictionary] = []
	for marker: Dictionary in spawns:
		var raw: Dictionary = actor(marker.actor_id, marker.q, marker.r, 9, 0, limits.get(marker.actor_id, 65))
		raw.side = marker.side
		raw.owner = marker.owner
		raw.controller = marker.controller
		result.append(raw)
	return result

static func command(actor_id: int, revision: int, target: Vector2i, kind: String = "move") -> Sm2Command:
	var result: Sm2Command = Sm2Command.new()
	result.kind = kind
	result.actor_id = actor_id
	result.expected_revision = revision
	result.target = target
	return result
