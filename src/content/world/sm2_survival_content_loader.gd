class_name Sm2SurvivalContentLoader
extends RefCounted
static func load_scenario(with_devices: bool=false,with_layers: bool=false) -> Dictionary:
	with_devices=with_devices or with_layers
	var content: Dictionary=Sm2RegionContentLoader.load_scenario()
	if not content.ok: return content
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/survival/rules.json"))
	if not raw is Dictionary: return {"ok":false,"errors":PackedStringArray(["survival_content_file"])}
	# Device physical defaults are explicit authoring data in the companion file.
	var devices: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/survival/devices.json"))
	if not devices is Array: return {"ok":false,"errors":PackedStringArray(["survival_device_file"])}
	raw.items.append_array(devices)
	if with_devices:
		var rules: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/survival/prostheses.json"))
		if not rules is Dictionary: return {"ok":false,"errors":PackedStringArray(["survival_prostheses_file"])}
		raw.version="sm2.survival.content.2"; raw["devices"]=rules
		raw.items.append({"id":"repair_parts","name":"Комплект деталей","mass":100,"volume":1,"size":1,"capacity":0,"max_mass":0,"max_size":0,"quick":false,"slot":""})
	if with_layers:
		var extension: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/survival/tissues.json"))
		if not extension is Dictionary or not Sm2Validate.fields(extension,["tissue_layers","supplies","items"]) or not extension.items is Array: return {"ok":false,"errors":PackedStringArray(["tissue_content_file"])}
		raw.version="sm2.survival.content.3"; raw["tissue_layers"]=extension.tissue_layers; raw["supplies"]=extension.supplies; raw.items.append_array(extension.items)
	var catalog: Sm2SurvivalCatalog=Sm2SurvivalCatalog.new()
	var errors: PackedStringArray=catalog.build(raw)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	for gear: Dictionary in content.combat.to_data().equipment:
		if catalog.item(gear.id).is_empty(): return {"ok":false,"errors":PackedStringArray(["survival_gear_missing:"+str(gear.id)])}
	for id: String in content.development.body_functions().starters():
		if catalog.item(id).is_empty(): return {"ok":false,"errors":PackedStringArray(["survival_device_missing:"+id])}
	if with_devices:
		for location: String in catalog.devices().locations:
			if location not in content.region.ids(): return {"ok":false,"errors":PackedStringArray(["survival_device_location"])}
		for device: Dictionary in catalog.devices().definitions:
			var legacy: Dictionary=content.development.body_functions().prosthesis(device.id)
			if legacy.is_empty() or legacy.part_id!=device.part or legacy.interface!=device.interface: return {"ok":false,"errors":PackedStringArray(["survival_device_binding"])}
	if with_layers:
		var binding: Dictionary=catalog.to_data().supplies
		if binding.care.size()!=content.care.resource_ids().size() or binding.upgrades.size()!=content.development.upgrades().ids().size(): return {"ok":false,"errors":PackedStringArray(["supply_binding_size"])}
		for id: String in content.care.resource_ids():
			if not binding.care.has(id): return {"ok":false,"errors":PackedStringArray(["supply_care_reference"])}
		for id: String in content.development.upgrades().ids():
			if not binding.upgrades.has(id): return {"ok":false,"errors":PackedStringArray(["supply_upgrade_reference"])}
	if with_layers:
		var care_raw: Dictionary=content.care.to_data()
		for resource: Dictionary in care_raw.resources: resource.capacity=10000
		var care: Sm2CareCatalog=Sm2CareCatalog.new()
		var care_errors: PackedStringArray=care.build(care_raw)
		if not care_errors.is_empty(): return {"ok":false,"errors":care_errors}
		content.care=care
		content.journey_fingerprint=Sm2Canonical.hash([content.journey_fingerprint,care_raw])
	content["survival"]=catalog
	content.journey_fingerprint=Sm2Canonical.hash([content.journey_fingerprint,catalog.to_data()])
	return content
