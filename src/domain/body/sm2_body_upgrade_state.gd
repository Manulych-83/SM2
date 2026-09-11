class_name Sm2BodyUpgradeState
extends RefCounted
var installed: Array[String]=[]
func to_data() -> Dictionary: return {"installed":installed.duplicate()}
func copy() -> Sm2BodyUpgradeState:
	var result: Sm2BodyUpgradeState=Sm2BodyUpgradeState.new(); result.installed.assign(installed); return result
static func decode(raw: Variant, catalog: Sm2BodyUpgradeCatalog) -> Dictionary:
	var bad: Dictionary={"ok":false,"errors":PackedStringArray(["upgrade_state"])}
	if catalog==null or not raw is Dictionary or not Sm2Validate.fields(raw,["installed"]) or not Sm2Validate.string_list(raw.installed) or raw.installed.size()>1000: return bad
	var result: Sm2BodyUpgradeState=Sm2BodyUpgradeState.new(); result.installed.assign(raw.installed)
	var sorted: Array[String]=result.installed.duplicate(); sorted.sort()
	if sorted!=result.installed: return bad
	for id: String in result.installed:
		if catalog.definition(id).is_empty(): return bad
	return {"ok":true,"state":result,"errors":PackedStringArray()}
