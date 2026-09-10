class_name Sm2AiContentLoader
extends RefCounted
const ABILITY_PATH: String = "res://content/m4/ai/abilities.tres"
const AREA_PATH: String = "res://content/m4/ai/areas.tres"

static func load_saved_profile(fingerprint: String) -> Dictionary:
	# Known version selection, never replacement or silent migration of a saved policy.
	for path: String in ["res://content/m2/ai/default.tres",ABILITY_PATH,AREA_PATH]:
		var loaded: Dictionary = load_profile(path)
		if loaded.ok and loaded.profile.fingerprint() == fingerprint: return loaded
	return {"ok":false,"errors":PackedStringArray(["saved_ai_profile_unknown"])}

static func load_profile(path: String = "res://content/m2/ai/default.tres") -> Dictionary:
	if not ResourceLoader.exists(path):
		return {"ok": false, "errors": PackedStringArray(["ai_profile_missing"])}
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource is Sm2AiManifest:
		return {"ok": false, "errors": PackedStringArray(["ai_profile_type"])}
	var profile: Sm2AiProfile = Sm2AiProfile.new()
	var errors: PackedStringArray = profile.build((resource as Sm2AiManifest).data)
	return {"ok": errors.is_empty(), "errors": errors, "profile": profile}
