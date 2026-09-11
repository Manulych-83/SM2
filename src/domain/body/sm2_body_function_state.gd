class_name Sm2BodyFunctionState
extends RefCounted
var working: Dictionary[String,bool]={}
var missing: Dictionary[String,bool]={}
var prostheses: Dictionary[String,String]={}

func copy() -> Sm2BodyFunctionState:
	var result: Sm2BodyFunctionState=Sm2BodyFunctionState.new()
	result.working=working.duplicate()
	result.missing=missing.duplicate(); result.prostheses=prostheses.duplicate()
	return result

func to_data() -> Dictionary:
	var ids: Array[String]=[]; ids.assign(working.keys()); ids.sort()
	var rows: Array[Dictionary]=[]
	for id: String in ids:
		rows.append({"id":id,"working":working[id]})
		if not missing.is_empty():
			rows.back()["missing"]=missing.get(id,false); rows.back()["prosthesis_id"]=prostheses.get(id,"")
	return {"format":"sm2.body_functions.2" if not missing.is_empty() else "sm2.body_functions.1","parts":rows}

static func decode(raw: Variant, catalog: Sm2BodyFunctionCatalog) -> Dictionary:
	var failure: Dictionary={"ok":false,"errors":PackedStringArray(["body_functions_invalid"])}
	if catalog==null or not raw is Dictionary: return failure
	var enhanced: bool=catalog.supports_prostheses()
	if not Sm2Validate.fields(raw,["format","parts"]) or raw.format!=("sm2.body_functions.2" if enhanced else "sm2.body_functions.1") or not raw.parts is Array or raw.parts.size()!=catalog.ids().size(): return failure
	var result: Sm2BodyFunctionState=Sm2BodyFunctionState.new()
	for index: int in raw.parts.size():
		var entry: Variant=raw.parts[index]
		var fields: Array[String]=["id","working"]
		if enhanced: fields.append_array(["missing","prosthesis_id"])
		if not entry is Dictionary or not Sm2Validate.fields(entry,fields) or entry.id!=catalog.ids()[index] or not entry.working is bool: return failure
		result.working[entry.id]=entry.working
		if enhanced:
			if not entry.missing is bool or not entry.prosthesis_id is String: return failure
			if not entry.prosthesis_id.is_empty() and (not Sm2Validate.decimal(entry.prosthesis_id,1) or not entry.missing or entry.prosthesis_id in result.prostheses.values()): return failure
			if entry.missing and entry.prosthesis_id.is_empty() and entry.working: return failure
			result.missing[entry.id]=entry.missing; result.prostheses[entry.id]=entry.prosthesis_id
	return {"ok":true,"state":result}
