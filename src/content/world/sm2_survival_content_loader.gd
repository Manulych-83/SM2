class_name Sm2SurvivalContentLoader
extends RefCounted
static func load_scenario() -> Dictionary:
	var content: Dictionary=Sm2RegionContentLoader.load_scenario()
	if not content.ok: return content
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/survival/rules.json"))
	if not raw is Dictionary: return {"ok":false,"errors":PackedStringArray(["survival_content_file"])}
	# Device physical defaults are explicit authoring data in the companion file.
	var devices: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/survival/devices.json"))
	if not devices is Array: return {"ok":false,"errors":PackedStringArray(["survival_device_file"])}
	raw.items.append_array(devices)
	var catalog: Sm2SurvivalCatalog=Sm2SurvivalCatalog.new()
	var errors: PackedStringArray=catalog.build(raw)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	for gear: Dictionary in content.combat.to_data().equipment:
		if catalog.item(gear.id).is_empty(): return {"ok":false,"errors":PackedStringArray(["survival_gear_missing:"+str(gear.id)])}
	for id: String in content.development.body_functions().starters():
		if catalog.item(id).is_empty(): return {"ok":false,"errors":PackedStringArray(["survival_device_missing:"+id])}
	content["survival"]=catalog
	content.journey_fingerprint=Sm2Canonical.hash([content.journey_fingerprint,catalog.to_data()])
	return content
