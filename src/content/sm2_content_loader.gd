class_name Sm2ContentLoader
extends RefCounted


static func load_catalog(path: String = "res://content/core/manifest.tres") -> Dictionary:
	if not ResourceLoader.exists(path):
		return _failure("Манифест контента не найден: %s" % path)
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not loaded is Sm2ContentManifest:
		return _failure("Ожидался ресурс Sm2ContentManifest: %s" % path)
	var manifest: Sm2ContentManifest = loaded as Sm2ContentManifest
	var raw: Dictionary = {"version": manifest.version, "actors": [],
		"weapons": [], "abilities": [], "statuses": []}
	for actor: Sm2ActorContent in manifest.actors:
		if actor == null:
			return _failure("В манифесте пустая ссылка на существо.")
		raw["actors"].append(actor.to_raw())
	for weapon: Sm2WeaponContent in manifest.weapons:
		if weapon == null:
			return _failure("В манифесте пустая ссылка на оружие.")
		raw["weapons"].append(weapon.to_raw())
	for ability: Sm2AbilityContent in manifest.abilities:
		if ability == null:
			return _failure("В манифесте пустая ссылка на способность.")
		raw["abilities"].append(ability.to_raw())
	for status: Sm2StatusContent in manifest.statuses:
		if status == null:
			return _failure("В манифесте пустая ссылка на эффект.")
		raw["statuses"].append(status.to_raw())
	var candidate: Sm2Catalog = Sm2Catalog.new()
	var errors: PackedStringArray = candidate.build(raw)
	if not errors.is_empty():
		return {"ok": false, "catalog": null, "errors": errors}
	return {"ok": true, "catalog": candidate, "errors": PackedStringArray()}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "catalog": null, "errors": PackedStringArray([message])}
