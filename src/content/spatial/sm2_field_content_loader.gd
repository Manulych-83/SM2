class_name Sm2FieldContentLoader
extends RefCounted

const MAX_SPAWNS: int = 4096
const MAX_ACTOR_ID: int = 9223372036854775806


static func load_scenario(path: String = "res://content/m2/skirmish_field.tres") -> Dictionary:
	if not ResourceLoader.exists(path):
		return _failure("Манифест поля не найден: %s" % path)
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded is Sm2FieldManifest:
		return _failure("Ожидался ресурс Sm2FieldManifest: %s" % path)
	var manifest: Sm2FieldManifest = loaded as Sm2FieldManifest
	var raw: Dictionary = {"id": manifest.scenario_id, "version": manifest.version,
		"width": manifest.width, "height": manifest.height,
		"default_surface_id": manifest.default_surface_id,
		"default_elevation": manifest.default_elevation, "surfaces": [], "tiles": []}
	for surface: Sm2SurfaceContent in manifest.surfaces:
		if surface == null:
			return _failure("В манифесте поля пустая ссылка на поверхность.")
		raw["surfaces"].append(surface.to_raw())
	for tile: Sm2CellOverrideContent in manifest.tiles:
		if tile == null:
			return _failure("В манифесте поля пустая ссылка на клетку.")
		raw["tiles"].append(tile.to_raw())
	var candidate: Sm2Battlefield = Sm2Battlefield.new()
	var field_errors: PackedStringArray = candidate.build(raw)
	if not field_errors.is_empty():
		return _failure_list(field_errors)
	if manifest.spawns.size() < 2 or manifest.spawns.size() > MAX_SPAWNS:
		return _failure("Сценарий должен содержать от 2 до 4096 стартовых участников.")
	if manifest.spawns.size() > manifest.width * manifest.height:
		return _failure("Стартовых участников больше, чем клеток на поле.")
	var ids: Dictionary[int, bool] = {}
	var positions: Dictionary[Vector2i, bool] = {}
	var sides: Dictionary[String, bool] = {}
	var spawns: Array[Dictionary] = []
	for marker: Sm2SpawnMarkerContent in manifest.spawns:
		if marker == null:
			return _failure("В манифесте поля пустая стартовая позиция.")
		if marker.id < 1 or marker.id > MAX_ACTOR_ID or ids.has(marker.id):
			return _failure("ID стартового участника недопустим или повторяется.")
		if not _valid_label(marker.side) or not _valid_label(marker.owner) or not _valid_label(marker.controller):
			return _failure("Сторона, владелец и управление участника должны быть непустыми строками длиной до 256 символов.")
		# Bound the int64 coordinates before converting to Vector2i's int32 values.
		if marker.q < 0 or marker.r < 0 or marker.q >= manifest.width or marker.r >= manifest.height:
			return _failure("Стартовая позиция участника находится за пределами поля.")
		var position: Vector2i = Vector2i(marker.q, marker.r)
		if positions.has(position):
			return _failure("Несколько стартовых участников занимают одну клетку.")
		if not candidate.cell(position)["passable"]:
			return _failure("Стартовая позиция участника непроходима.")
		ids[marker.id] = true
		positions[position] = true
		sides[marker.side] = true
		spawns.append(marker.to_raw())
	if sides.size() != 2:
		return _failure("Сценарий должен содержать ровно две стороны.")
	return {"ok": true, "field": candidate, "scenario_id": manifest.scenario_id,
		"seed": manifest.seed, "spawns": spawns, "errors": PackedStringArray()}


static func _valid_label(value: String) -> bool:
	return Sm2Validate.text(value)


static func _failure(message: String) -> Dictionary:
	return _failure_list(PackedStringArray([message]))


static func _failure_list(errors: PackedStringArray) -> Dictionary:
	var empty_spawns: Array[Dictionary] = []
	return {"ok": false, "field": null, "scenario_id": "", "seed": 0,
		"spawns": empty_spawns, "errors": errors.duplicate()}
