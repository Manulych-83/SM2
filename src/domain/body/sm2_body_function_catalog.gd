class_name Sm2BodyFunctionCatalog
extends RefCounted
var _raw: Dictionary={}

func build(raw: Dictionary, combat: Sm2CombatCatalog, progress: Sm2ProgressCatalog) -> PackedStringArray:
	var enhanced: bool=raw.get("version")=="sm2.body_functions.content.2"
	var fields: Array[String]=["version","parts","bindings","trauma_abilities","practice_requirements","trauma_armor_slot"]
	if enhanced: fields.append_array(["sever_abilities","prostheses","starter_prostheses"])
	if not Sm2Validate.fields(raw,fields) or raw.version not in ["sm2.body_functions.content.1","sm2.body_functions.content.2"]: return PackedStringArray(["body_content_version"])
	if raw.trauma_armor_slot not in ["body","head"]: return PackedStringArray(["body_trauma_armor"])
	if not raw.parts is Array or raw.parts.is_empty() or raw.parts.size()>32 or not raw.bindings is Dictionary or not Sm2Validate.fields(raw.bindings,["weapon","shield","two_handed"]) or not raw.trauma_abilities is Dictionary or raw.trauma_abilities.is_empty() or not raw.practice_requirements is Dictionary: return PackedStringArray(["body_content_groups"])
	var part_ids: Array[String]=[]
	for part: Variant in raw.parts:
		var part_fields: Array[String]=["id","name"]
		if enhanced: part_fields.append("interface")
		if not part is Dictionary or not Sm2Validate.fields(part,part_fields) or not Sm2Validate.text(part.id) or not Sm2Validate.text(part.name) or part.id in part_ids: return PackedStringArray(["body_content_part"])
		if enhanced and not Sm2Validate.text(part.interface): return PackedStringArray(["body_content_interface"])
		part_ids.append(part.id)
	for slot: String in raw.bindings:
		if not Sm2Validate.string_list(raw.bindings[slot]) or raw.bindings[slot].is_empty(): return PackedStringArray(["body_content_binding"])
		for id: String in raw.bindings[slot]:
			if id not in part_ids: return PackedStringArray(["body_content_binding"])
	for ability_id: Variant in raw.trauma_abilities:
		if not ability_id is String or raw.trauma_abilities[ability_id] not in part_ids: return PackedStringArray(["body_content_trauma"])
		var ability: Sm2CombatAbility=combat.ability(ability_id)
		if ability==null or ability.mode!="melee" or ability.operation!="damage": return PackedStringArray(["body_content_trauma"])
	for activity_id: Variant in raw.practice_requirements:
		if not activity_id is String or progress.activity(activity_id)==null or not Sm2Validate.string_list(raw.practice_requirements[activity_id]): return PackedStringArray(["body_content_practice"])
		for id: String in raw.practice_requirements[activity_id]:
			if id not in part_ids: return PackedStringArray(["body_content_practice"])
	if enhanced:
		if not raw.sever_abilities is Dictionary or raw.sever_abilities.is_empty() or not raw.prostheses is Array or raw.prostheses.is_empty() or raw.prostheses.size()>256 or not raw.starter_prostheses is Array or raw.starter_prostheses.size()>64: return PackedStringArray(["prosthesis_content_groups"])
		for ability_id: Variant in raw.sever_abilities:
			if not ability_id is String or raw.sever_abilities[ability_id] not in part_ids or raw.trauma_abilities.has(ability_id): return PackedStringArray(["body_content_sever"])
			var ability: Sm2CombatAbility=combat.ability(ability_id)
			if ability==null or ability.mode!="melee" or ability.operation!="damage": return PackedStringArray(["body_content_sever"])
		var definitions: Array[String]=[]
		for entry: Variant in raw.prostheses:
			if not entry is Dictionary or not Sm2Validate.fields(entry,["id","name","part_id","interface"]) or not Sm2Validate.text(entry.id) or entry.id in definitions or not Sm2Validate.text(entry.name) or entry.part_id not in part_ids or not Sm2Validate.text(entry.interface): return PackedStringArray(["prosthesis_definition"])
			definitions.append(entry.id)
		for id: Variant in raw.starter_prostheses:
			if not id is String or id not in definitions: return PackedStringArray(["prosthesis_starter"])
	_raw=raw.duplicate(true)
	return PackedStringArray()

func to_data() -> Dictionary: return _raw.duplicate(true)
func ids() -> Array[String]:
	var result: Array[String]=[]
	for row: Dictionary in _raw.parts: result.append(row.id)
	result.sort(); return result
func title(id: String) -> String:
	for row: Dictionary in _raw.parts:
		if row.id==id: return row.name
	return id
func initial() -> Sm2BodyFunctionState:
	var state: Sm2BodyFunctionState=Sm2BodyFunctionState.new()
	for id: String in ids():
		state.working[id]=true
		if supports_prostheses(): state.missing[id]=false; state.prostheses[id]=""
	return state
func required(slot: String) -> Array[String]:
	var result: Array[String]=[]; result.assign(_raw.bindings.get(slot,[])); return result
func trauma(ability_id: String) -> String: return _raw.trauma_abilities.get(ability_id,_raw.get("sever_abilities",{}).get(ability_id,""))
func armor_slot() -> String: return _raw.trauma_armor_slot
func practice(id: String) -> Array[String]:
	var result: Array[String]=[]; result.assign(_raw.practice_requirements.get(id,[])); return result

func supports_prostheses() -> bool: return _raw.get("version")=="sm2.body_functions.content.2"
func severs(ability_id: String) -> bool: return _raw.get("sever_abilities",{}).has(ability_id)
func prosthesis(id: String) -> Dictionary:
	for entry: Dictionary in _raw.get("prostheses",[]):
		if entry.id==id: return entry.duplicate(true)
	return {}
func compatible(id: String, part_id: String) -> bool:
	var entry: Dictionary=prosthesis(id)
	if entry.is_empty() or entry.part_id!=part_id: return false
	for part: Dictionary in _raw.parts:
		if part.id==part_id: return part.get("interface","")==entry.interface
	return false
func starters() -> Array[String]:
	var result: Array[String]=[]; result.assign(_raw.get("starter_prostheses",[])); return result
