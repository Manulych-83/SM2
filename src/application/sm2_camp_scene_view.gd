class_name Sm2CampSceneView
extends RefCounted
## Detached visual facts; no artwork or game commands enter this projection.
static func build(session: Sm2JourneySession) -> Dictionary:
	var world: Sm2JourneyWorld=session.journey()
	var result: Dictionary={"location":world.region.location_id,"hero":{},"objects":[]}
	if world.busy(): return result
	var id: int=world.hero_id()
	if id!=0:
		var actor: Dictionary={"side":"company","combat":{"items":[]},"body_functions":{"parts":[]},"upgrades":world.bodies[id].upgrades.installed.duplicate()}
		for part: String in world.survival.bodies[str(id)].layers:
			actor.body_functions.parts.append({"id":part,"working":Sm2SurvivalDevices.working(world.survival,str(id),part),"prosthesis_id":Sm2SurvivalDevices.installed(world.survival,str(id),part)})
		result.hero=actor
	for item_id: String in world.survival.inventory.ids():
		var item: Dictionary=world.survival.inventory.items[item_id]
		if id!=0 and item.place=="equipped" and str(item.holder)==str(id):
			result.hero.combat.items.append({"definition_id":item.definition_id,"slot":world.survival.catalog.item(item.definition_id).slot,"current":item.current})
		if item.place=="ground" and str(item.holder)==str(result.location):
			result.objects.append({"id":item_id,"visual":str(item.definition_id)})
	return result
