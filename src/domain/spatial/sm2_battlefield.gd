class_name Sm2Battlefield
extends RefCounted
## Validated immutable-by-interface map. Actor occupancy is supplied by callers.
var _data: Dictionary = {}
var _surfaces: Dictionary = {}
var _tiles: Dictionary = {}

func build(raw: Dictionary) -> PackedStringArray:
	if not Sm2Validate.fields(raw, ["id", "version", "width", "height", "surfaces", "default_surface_id", "default_elevation", "tiles"]):
		return PackedStringArray(["battlefield: missing or unexpected fields"])
	if not Sm2Validate.text(raw.id) or not Sm2Validate.text(raw.version) \
		or not Sm2Validate.integer(raw.width, 1, 64) or not Sm2Validate.integer(raw.height, 1, 64) \
		or not Sm2Validate.text(raw.default_surface_id) or not Sm2Validate.integer(raw.default_elevation, 0, 16):
		return PackedStringArray(["battlefield: invalid identity, dimensions or defaults"])
	if not raw.surfaces is Array or raw.surfaces.is_empty() or raw.surfaces.size() > 10000 \
		or not raw.tiles is Array or raw.tiles.size() > int(raw.width) * int(raw.height):
		return PackedStringArray(["battlefield: invalid surface or override collection"])
	var surfaces: Dictionary = {}
	var surface_data: Array[Dictionary] = []
	for entry: Variant in raw.surfaces:
		if not entry is Dictionary or not Sm2Validate.fields(entry, ["id", "ap_cost", "fatigue_cost"]) \
			or not Sm2Validate.text(entry.id) or not Sm2Validate.integer(entry.ap_cost, 1, 100) \
			or not Sm2Validate.integer(entry.fatigue_cost, 0, 100):
			return PackedStringArray(["battlefield: invalid surface definition"])
		if surfaces.has(entry.id):
			return PackedStringArray(["battlefield: duplicate surface " + entry.id])
		var normalized: Dictionary = {"id": entry.id, "ap_cost": int(entry.ap_cost), "fatigue_cost": int(entry.fatigue_cost)}
		surfaces[entry.id] = normalized
		surface_data.append(normalized)
	if not surfaces.has(raw.default_surface_id):
		return PackedStringArray(["battlefield: missing default surface"])
	var tiles: Dictionary = {}
	var tile_data: Array[Dictionary] = []
	for entry: Variant in raw.tiles:
		if not entry is Dictionary or not Sm2Validate.fields(entry, ["q", "r", "surface_id", "elevation", "passable", "opaque"]) \
			or not Sm2Validate.integer(entry.q, 0, int(raw.width) - 1) or not Sm2Validate.integer(entry.r, 0, int(raw.height) - 1) \
			or not Sm2Validate.text(entry.surface_id) or not Sm2Validate.integer(entry.elevation, 0, 16) \
			or not entry.passable is bool or not entry.opaque is bool:
			return PackedStringArray(["battlefield: invalid tile override"])
		var position: Vector2i = Vector2i(int(entry.q), int(entry.r))
		if tiles.has(position):
			return PackedStringArray(["battlefield: duplicate tile (%d,%d)" % [position.x, position.y]])
		if not surfaces.has(entry.surface_id):
			return PackedStringArray(["battlefield: missing surface " + entry.surface_id])
		var normalized: Dictionary = {"q": position.x, "r": position.y, "surface_id": entry.surface_id,
			"elevation": int(entry.elevation), "passable": entry.passable, "opaque": entry.opaque}
		tiles[position] = normalized
		tile_data.append(normalized)
	surface_data.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return left.id < right.id)
	tile_data.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return Sm2Hex.numeric_less(Vector2i(left.q, left.r), Vector2i(right.q, right.r)))
	var candidate: Dictionary = {"id": raw.id, "version": raw.version, "width": int(raw.width), "height": int(raw.height),
		"surfaces": surface_data, "default_surface_id": raw.default_surface_id, "default_elevation": int(raw.default_elevation), "tiles": tile_data}
	_data = candidate
	_surfaces = surfaces
	_tiles = tiles
	return PackedStringArray()

func to_data() -> Dictionary:
	return _data.duplicate(true)

func fingerprint() -> String:
	return Sm2Canonical.hash(_data)

func id() -> String:
	return _data.get("id", "")

func width() -> int:
	return int(_data.get("width", 0))

func height() -> int:
	return int(_data.get("height", 0))

func in_bounds(position: Vector2i) -> bool:
	return position.x >= 0 and position.y >= 0 and position.x < width() and position.y < height()

func cell(position: Vector2i) -> Dictionary:
	if not in_bounds(position):
		return {}
	var entry: Dictionary = _tiles.get(position, {"q": position.x, "r": position.y,
		"surface_id": _data.default_surface_id, "elevation": _data.default_elevation, "passable": true, "opaque": false})
	var surface: Dictionary = _surfaces[entry.surface_id]
	return {"q": position.x, "r": position.y, "surface_id": entry.surface_id, "elevation": int(entry.elevation),
		"passable": entry.passable, "opaque": entry.opaque, "ap_cost": int(surface.ap_cost), "fatigue_cost": int(surface.fatigue_cost)}
