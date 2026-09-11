class_name Sm2CareState
extends RefCounted
var supplies: Dictionary[String,int]={}
var minutes: int=0

func initialize(catalog: Sm2CareCatalog) -> void:
	supplies.clear(); minutes=0
	for id: String in catalog.resource_ids(): supplies[id]=int(catalog.resource(id).initial)
func copy() -> Sm2CareState:
	var result: Sm2CareState=Sm2CareState.new(); result.supplies=supplies.duplicate(); result.minutes=minutes; return result
func check(command: String,catalog: Sm2CareCatalog) -> String:
	var service: Dictionary=catalog.service(command)
	if service.is_empty(): return ""
	if minutes>Sm2CareCatalog.TIME_LIMIT-int(service.minutes): return "Достигнут предел времени процедур этого примера."
	for id: String in catalog.resource_ids():
		if supplies[id]<int(service.cost.get(id,0)): return "Не хватает: "+str(catalog.resource(id).name)+"."
	return ""
func spend(command: String,catalog: Sm2CareCatalog) -> void:
	var service: Dictionary=catalog.service(command)
	if service.is_empty(): return
	for id: String in service.cost: supplies[id]-=int(service.cost[id])
	minutes+=int(service.minutes)
func validate(catalog: Sm2CareCatalog) -> String:
	if minutes<0 or minutes>Sm2CareCatalog.TIME_LIMIT or supplies.size()!=catalog.resource_ids().size(): return "care_state_bounds"
	for id: String in catalog.resource_ids():
		if not supplies.has(id) or supplies[id]<0 or supplies[id]>catalog.capacity(id): return "care_supply_bounds"
	return ""
func to_data() -> Dictionary:
	var ids: Array[String]=[]; ids.assign(supplies.keys()); ids.sort()
	var rows: Array[Dictionary]=[]
	for id: String in ids: rows.append({"id":id,"amount":supplies[id]})
	return {"format":"sm2.care_state.1","minutes":minutes,"supplies":rows}
