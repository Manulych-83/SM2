class_name Sm2CompanionProgress
extends Sm2ProgressBodyState
## One personal XP pool; attributes are derived, never independently trained.
var earned: int = 0

func to_data() -> Dictionary:
	return {"id":str(id),"template_id":"p1:body.human","growth":{"format":"sm2.companion_growth.1","earned_total":earned}}

func describe(catalog: Sm2ProgressCatalog) -> Dictionary:
	var spec: Dictionary=catalog.companion_growth()
	var curve: Sm2ProgressTrackDefinition=Sm2ProgressTrackDefinition.new()
	curve.base_level=1; curve.step=int(spec.step); curve.growth=int(spec.growth)
	var data: Dictionary=curve.describe(earned)
	data["earned"]=earned
	return data

func attributes(catalog: Sm2ProgressCatalog) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var gained: int=int(describe(catalog).level)-1
	for row: Dictionary in catalog.companion_growth().attributes:
		var amount: int=int(row.base)+gained*int(row.per_level)
		result.append({"id":row.track_id,"name":catalog.track(row.track_id).title,"kind":"attribute","level":amount,"effective":amount,"earned":0,"spent":0,"available":0,"progress":0,"needed":1,"node_bonus":0,"sources":[],"nodes":[]})
	return result

static func validate_definition(raw: Variant, catalog: Sm2ProgressCatalog) -> String:
	if not raw is Dictionary or not Sm2Validate.fields(raw,["step","growth","attack_xp","melee_per_level","attributes"]): return "companion_growth_fields"
	if not Sm2Validate.integer(raw.step,1,10000) or not Sm2Validate.integer(raw.growth,0,10000) or not Sm2Validate.integer(raw.attack_xp,1,10000) or not Sm2Validate.integer(raw.melee_per_level,0,10): return "companion_growth_curve"
	if not raw.attributes is Array or raw.attributes.is_empty(): return "companion_attributes"
	var ids: Array[String]=[]
	for row: Variant in raw.attributes:
		if not row is Dictionary or not Sm2Validate.fields(row,["track_id","base","per_level"]) or not row.track_id is String: return "companion_attribute_fields"
		var definition: Sm2ProgressTrackDefinition=catalog.track(row.track_id)
		if definition==null or definition.kind!="attribute" or row.track_id in ids or not Sm2Validate.integer(row.base,0,10000) or not Sm2Validate.integer(row.per_level,0,10): return "companion_attribute_value"
		ids.append(row.track_id)
	for id_value: String in catalog.track_ids():
		if catalog.track(id_value).kind=="attribute" and id_value not in ids: return "companion_attribute_missing"
	return ""

static func decode(raw: Dictionary, catalog: Sm2ProgressCatalog) -> Dictionary:
	var failure: Dictionary={"ok":false,"errors":PackedStringArray(["companion_progress_invalid"])}
	if not catalog.is_party() or not Sm2Validate.fields(raw,["id","template_id","growth"]) or not Sm2Validate.decimal(raw.id,1) or raw.template_id!="p1:body.human": return failure
	if not raw.growth is Dictionary or not Sm2Validate.fields(raw.growth,["format","earned_total"]) or raw.growth.format!="sm2.companion_growth.1" or not Sm2Validate.integer(raw.growth.earned_total,0,Sm2ProgressCatalog.XP_LIMIT): return failure
	var body: Sm2CompanionProgress=Sm2CompanionProgress.new()
	body.id=int(raw.id); body.earned=int(raw.growth.earned_total)
	return {"ok":true,"body":body,"errors":PackedStringArray()}
