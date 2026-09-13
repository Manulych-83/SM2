class_name Sm2EffectSequenceContentLoader
extends RefCounted
## Authored additions to the old technical scenario; never replaces a campaign catalog.
static func load_scenario(path: String = "res://content/effects/sequences.json") -> Dictionary:
	var content: Dictionary = Sm2EffectContentLoader.load_scenario()
	if not content.ok: return content
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	if file == null: return _error("sequence_content_missing")
	if file.get_length() > 8*1024*1024: return _error("sequence_content_size")
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary: return _error("sequence_content_json")
	var package: Dictionary = json.data
	if not Sm2Validate.fields(package,["version","actions","grants"]) or package.version != Sm2EffectCatalog.SEQUENCE_VERSION or not package.actions is Array or not package.grants is Array: return _error("sequence_content_shape")
	var raw: Dictionary = content.effects.to_data()
	raw.version = package.version
	raw.actions.append_array(package.actions)
	var seen: Dictionary = {}
	for grant: Variant in package.grants:
		if not grant is Dictionary or not Sm2Validate.fields(grant,["profile_id","actions"]) or not Sm2Validate.text(grant.profile_id) or not grant.actions is Array or seen.has(grant.profile_id): return _error("sequence_content_grant")
		seen[grant.profile_id] = true
		var found: bool = false
		for profile: Dictionary in raw.profiles:
			if profile.id == grant.profile_id:
				profile.actions.append_array(grant.actions)
				found = true
		if not found: return _error("sequence_content_profile")
	var catalog: Sm2EffectCatalog = Sm2EffectCatalog.new()
	var errors: PackedStringArray = catalog.build(raw,content.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	content.effects = catalog
	content.setup.battle_id = "effect_sequences_demo"
	content.setup.scenario_id = "sequences:scenario.demo"
	return content

static func _error(reason: String) -> Dictionary:
	return {"ok":false,"errors":PackedStringArray([reason])}
