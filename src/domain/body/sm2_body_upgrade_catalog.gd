class_name Sm2BodyUpgradeCatalog
extends RefCounted
## Closed, additive operations; paths are metadata, never executable combinations.
const IMPLANT_VERSION: String="sm2.p5.body_upgrades.2"
const VERSION: String="sm2.p5.body_upgrades.1"
var _raw: Dictionary={}
var _entries: Dictionary={}
func build(raw: Dictionary, progress: Sm2ProgressCatalog) -> PackedStringArray:
	if progress==null or not Sm2Validate.fields(raw,["version","upgrades"]) or raw.version not in [VERSION,IMPLANT_VERSION] or not raw.upgrades is Array or raw.upgrades.is_empty() or raw.upgrades.size()>1000: return PackedStringArray(["upgrades_shape"])
	var entries: Dictionary={}
	for a: Variant in raw.upgrades:
		if not a is Dictionary or not Sm2Validate.fields(a,["id","name","path","cache_name","doses","modifiers"]): return PackedStringArray(["upgrade_shape"])
		if not Sm2Validate.text(a.id) or entries.has(a.id) or not Sm2Validate.text(a.name) or not Sm2Validate.text(a.cache_name) or a.path not in ["genetics","cybernetics","psionics"] or not Sm2Validate.integer(a.doses,1,100): return PackedStringArray(["upgrade_identity"])
		if not a.modifiers is Array or a.modifiers.is_empty() or a.modifiers.size()>64: return PackedStringArray(["upgrade_modifiers"])
		var seen: Array[String]=[]
		for m: Variant in a.modifiers:
			var operations: Array[String]=["track_bonus","physical_attack_fatigue"]
			if raw.version==IMPLANT_VERSION: operations.append("psionic_focus_cost")
			if not m is Dictionary or m.get("kind") not in operations: return PackedStringArray(["upgrade_operation"])
			var fields: Array[String]=["kind","amount"]
			if m.kind=="track_bonus": fields.append("track_id")
			if not Sm2Validate.fields(m,fields) or not Sm2Validate.integer(m.amount,1,100): return PackedStringArray(["upgrade_amount"])
			if m.kind=="track_bonus" and (not m.track_id is String or progress.track(m.track_id)==null or progress.track(m.track_id).kind!="attribute"): return PackedStringArray(["upgrade_track"])
			var key: String=str(m.kind)+":"+str(m.get("track_id",""))
			if key in seen: return PackedStringArray(["upgrade_duplicate_modifier"])
			seen.append(key)
		entries[a.id]=a.duplicate(true)
	_entries=entries; _raw=raw.duplicate(true); return PackedStringArray()
func to_data() -> Dictionary: return _raw.duplicate(true)
func ids() -> Array[String]:
	var result: Array[String]=[]; result.assign(_entries.keys()); result.sort(); return result
func definition(id: String) -> Dictionary: return _entries.get(id,{}).duplicate(true)
func track_modifiers(state: Sm2BodyUpgradeState) -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	if state!=null:
		for id: String in state.installed:
			for m: Dictionary in _entries[id].modifiers:
				if m.kind=="track_bonus": rows.append({"track_id":m.track_id,"name":_entries[id].name,"amount":int(m.amount)})
	return rows
func attack_fatigue(state: Sm2BodyUpgradeState) -> int:
	var amount: int=0
	if state!=null:
		for id: String in state.installed:
			for m: Dictionary in _entries[id].modifiers:
				if m.kind=="physical_attack_fatigue": amount+=int(m.amount)
	return amount

func supports_implants() -> bool: return _raw.get("version")==IMPLANT_VERSION
func focus_modifiers(state: Sm2BodyUpgradeState) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if state!=null:
		for id: String in state.installed:
			for modifier: Dictionary in _entries[id].modifiers:
				if modifier.kind=="psionic_focus_cost": result.append({"id":id,"name":_entries[id].name,"amount":int(modifier.amount)})
	return result
