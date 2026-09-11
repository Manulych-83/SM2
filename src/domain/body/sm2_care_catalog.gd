class_name Sm2CareCatalog
extends RefCounted
## Costs describe camp procedures only, not a general campaign calendar.
const COMMANDS: Array[String]=["heal_hp","heal_hand","install_prosthesis","remove_prosthesis","repair_prosthesis"]
const TIME_LIMIT: int=1000000
var _raw: Dictionary={}

func build(raw: Dictionary) -> PackedStringArray:
	if not Sm2Validate.fields(raw,["version","resources","services"]) or raw.version not in ["sm2.care.content.1","sm2.care.content.2"]: return PackedStringArray(["care_content_version"])
	if not raw.resources is Array or raw.resources.is_empty() or raw.resources.size()>32 or not raw.services is Array or raw.services.size()!=COMMANDS.size(): return PackedStringArray(["care_content_groups"])
	var ids: Array[String]=[]
	for row: Variant in raw.resources:
		var fields: Array[String]=["id","name","initial"]
		if raw.version=="sm2.care.content.2": fields.append("capacity")
		if not row is Dictionary or not Sm2Validate.fields(row,fields) or not Sm2Validate.text(row.id) or row.id in ids or not Sm2Validate.text(row.name) or not Sm2Validate.integer(row.initial,0,1000000): return PackedStringArray(["care_resource"])
		if raw.version=="sm2.care.content.2" and not Sm2Validate.integer(row.capacity,int(row.initial),1000000): return PackedStringArray(["care_capacity"])
		ids.append(row.id)
	var commands: Array[String]=[]
	for row: Variant in raw.services:
		if not row is Dictionary or not Sm2Validate.fields(row,["command","name","minutes","cost","heal_hp"]) or row.command not in COMMANDS or row.command in commands or not Sm2Validate.text(row.name) or not Sm2Validate.integer(row.minutes,1,1440) or not Sm2Validate.integer(row.heal_hp,1 if row.command=="heal_hp" else 0,60 if row.command=="heal_hp" else 0) or not row.cost is Dictionary: return PackedStringArray(["care_service"])
		for id: Variant in row.cost:
			if not id is String or id not in ids or not Sm2Validate.integer(row.cost[id],1,1000000): return PackedStringArray(["care_cost"])
		commands.append(row.command)
	_raw=raw.duplicate(true); return PackedStringArray()

func to_data() -> Dictionary: return _raw.duplicate(true)
func expandable() -> bool: return _raw.get("version")=="sm2.care.content.2"
func capacity(id: String) -> int: return int(resource(id).get("capacity",resource(id).initial))
func service(command: String) -> Dictionary:
	for row: Dictionary in _raw.services:
		if row.command==command: return row.duplicate(true)
	return {}
func resource_ids() -> Array[String]:
	var ids: Array[String]=[]
	for row: Dictionary in _raw.resources: ids.append(row.id)
	ids.sort(); return ids
func resource(id: String) -> Dictionary:
	for row: Dictionary in _raw.resources:
		if row.id==id: return row.duplicate(true)
	return {}
func description(command: String) -> String:
	var row: Dictionary=service(command)
	if row.is_empty(): return ""
	var costs: PackedStringArray=[]
	for id: String in resource_ids():
		if row.cost.has(id): costs.append("%s: %s" % [resource(id).name,int(row.cost[id])])
	return ("Без расходников" if costs.is_empty() else ", ".join(costs))+" · %s мин." % int(row.minutes)
