class_name Sm2CombatContentLoader
extends RefCounted

static func load_scenario(turn_path: String = "res://content/m2/turn_scenario.tres",
	combat_path: String = "res://content/m2/combat/catalog.tres") -> Dictionary:
	var loaded: Dictionary = Sm2TurnContentLoader.load_scenario(turn_path)
	if not loaded.ok:
		return loaded
	if not ResourceLoader.exists(combat_path):
		return _failure("Боевой каталог не найден.")
	var resource: Resource = ResourceLoader.load(combat_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource is Sm2CombatContentManifest:
		return _failure("Неверный тип боевого каталога.")
	var combat: Sm2CombatCatalog = Sm2CombatCatalog.new()
	var errors: PackedStringArray = combat.build((resource as Sm2CombatContentManifest).data, loaded.catalog)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true, "catalog": loaded.catalog, "combat": combat, "setup": loaded.setup, "errors": PackedStringArray()}

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([reason])}
