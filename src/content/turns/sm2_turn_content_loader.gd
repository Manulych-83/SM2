class_name Sm2TurnContentLoader
extends RefCounted
const MAX_ACTOR_ID: int = 9223372036854775805

static func load_catalog(path: String = "res://content/m2/turns/catalog.tres") -> Dictionary:
	if not ResourceLoader.exists(path):
		return _failure("Каталог очереди не найден: " + path)
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded is Sm2TurnContentManifest:
		return _failure("Ожидался ресурс Sm2TurnContentManifest: " + path)
	return _build_catalog(loaded as Sm2TurnContentManifest)

static func load_scenario(path: String = "res://content/m2/turn_scenario.tres") -> Dictionary:
	if not ResourceLoader.exists(path):
		return _failure("Сценарий очереди не найден: " + path)
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded is Sm2TurnScenarioContent:
		return _failure("Ожидался ресурс Sm2TurnScenarioContent: " + path)
	var scenario: Sm2TurnScenarioContent = loaded as Sm2TurnScenarioContent
	if not Sm2Validate.text(scenario.battle_id) or scenario.round_limit < 1 or scenario.round_limit > 1000:
		return _failure("Недопустимый ID боя или предел раундов.")
	if scenario.field_manifest == null or scenario.field_manifest.resource_path.is_empty():
		return _failure("Сценарий должен ссылаться на сохранённый манифест поля.")
	var field_result: Dictionary = Sm2FieldContentLoader.load_scenario(scenario.field_manifest.resource_path)
	if not field_result.ok:
		return _failure_list(field_result.errors)
	var catalog_result: Dictionary = _build_catalog(scenario.catalog_manifest)
	if not catalog_result.ok:
		return catalog_result
	var catalog: Sm2TurnCatalog = catalog_result.catalog
	if scenario.assignments.size() != field_result.spawns.size() or scenario.assignments.size() > 4096:
		return _failure("Каждому маркеру поля требуется ровно одно назначение экипировки.")
	var assignments: Dictionary[int, String] = {}
	for assignment: Sm2TurnAssignmentContent in scenario.assignments:
		if assignment == null or assignment.actor_id < 1 or assignment.actor_id > MAX_ACTOR_ID:
			return _failure("Недопустимый ID назначения участника.")
		if assignments.has(assignment.actor_id):
			return _failure("ID назначения участника повторяется.")
		if not catalog.has_loadout(assignment.loadout_id):
			return _failure("Неизвестный комплект экипировки: " + assignment.loadout_id)
		assignments[assignment.actor_id] = assignment.loadout_id
	var actors: Array[Dictionary] = []
	for marker: Dictionary in field_result.spawns:
		if marker.actor_id > MAX_ACTOR_ID or not assignments.has(marker.actor_id):
			return _failure("Назначения не покрывают точный состав поля.")
		actors.append({"actor_id": marker.actor_id, "loadout_id": assignments[marker.actor_id],
			"side": marker.side, "owner": marker.owner, "controller": marker.controller,
			"creator": 0, "q": marker.q, "r": marker.r, "fatigue": 0,
			"alive": true, "on_field": true, "morale": "steady"})
	actors.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return left.actor_id < right.actor_id)
	var field: Sm2Battlefield = field_result.field
	var setup: Dictionary = {"battle_id": scenario.battle_id, "scenario_id": field_result.scenario_id,
		"seed": field_result.seed, "field": field.to_data(), "round_limit": scenario.round_limit, "actors": actors}
	return {"ok": true, "catalog": catalog, "setup": setup, "errors": PackedStringArray()}

static func _build_catalog(manifest: Sm2TurnContentManifest) -> Dictionary:
	if manifest == null:
		return _failure("Не указан каталог характеристик и нагрузки.")
	var raw: Dictionary = {"version": manifest.version, "profiles": [], "equipment": [], "loadouts": []}
	if manifest.profiles.size() > 10000 or manifest.equipment.size() > 10000 or manifest.loadouts.size() > 10000:
		return _failure("Слишком много определений в каталоге.")
	for profile: Sm2TurnProfileContent in manifest.profiles:
		if profile == null:
			return _failure("Пустая ссылка на профиль.")
		raw.profiles.append(profile.to_raw())
	for equipment: Sm2TurnEquipmentContent in manifest.equipment:
		if equipment == null:
			return _failure("Пустая ссылка на предмет.")
		raw.equipment.append(equipment.to_raw())
	for loadout: Sm2TurnLoadoutContent in manifest.loadouts:
		if loadout == null:
			return _failure("Пустая ссылка на комплект экипировки.")
		raw.loadouts.append(loadout.to_raw())
	var catalog: Sm2TurnCatalog = Sm2TurnCatalog.new()
	var errors: PackedStringArray = catalog.build(raw)
	if not errors.is_empty():
		return _failure_list(errors)
	return {"ok": true, "catalog": catalog, "setup": {}, "errors": PackedStringArray()}

static func _failure(message: String) -> Dictionary:
	return _failure_list(PackedStringArray([message]))

static func _failure_list(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "catalog": null, "setup": {}, "errors": errors.duplicate()}
