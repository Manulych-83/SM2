class_name Sm2SoulView
extends RefCounted
## A read-only projection of existing incarnations and local incarnation rules.
static func build(session: Sm2JourneySession) -> Dictionary:
	var world: Sm2JourneyWorld=session.journey()
	if world.region==null or world.survival==null or not world.survival.catalog.has_layers(): return {}
	var result: Dictionary={"hero":world.hero_id(),"busy":world.busy(),"location":world.region_catalog.location(world.region.location_id).name,"knowledge":[],"history":[],"carriers":[],"available":0,"companion":""}
	for id: String in world.soul.knowledge: result.knowledge.append(world._progress.knowledge_name(id))
	for entry: Dictionary in world.incarnations:
		var body_id: int=int(entry.body_id)
		var place: String=world.region.bodies[str(body_id)]
		result.history.append({"number":result.history.size()+1,"id":body_id,"name":world._definition.body(body_id).name,"ended":entry.ended,"location":world.region_catalog.location(place).name})
	# The campaign's body state is not authoritative while the battle is running.
	if world.busy(): result.companion="В сражении. Состояние участников смотрите в бою."; return result
	result.companion="Спутник погиб и не вернётся при новом воплощении." if not world.bodies[4].alive else "Спутник ждёт нового воплощения и сохраняет свой опыт." if world.hero_id()==0 else "Спутник в отряде. Его уровень и общий опыт развиваются отдельно."
	for body_id: int in world._definition.ids():
		if world.bodies[body_id].alive or world.region.bodies[str(body_id)]!=world.region.location_id: continue
		var reason: String=world.check(session.command("incarnate",body_id))
		var eligibility: String=world.eligible(body_id)
		result.carriers.append({"id":body_id,"name":world._definition.body(body_id).name,"reason":reason,"eligibility":eligibility})
		if reason.is_empty(): result.available+=1
	return result
