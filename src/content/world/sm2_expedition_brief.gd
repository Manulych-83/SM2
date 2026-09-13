class_name Sm2ExpeditionBrief
extends RefCounted
## A versioned authored objective over existing world facts, without extra rewards.
static func load_for(world: Sm2JourneyWorld) -> Dictionary:
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/expeditions/first_supplies.json"))
	if not raw is Dictionary or not valid(raw,world): return {}
	raw.quantity=int(raw.quantity); raw.encounter=int(raw.encounter)
	return raw.duplicate(true)

static func valid(raw: Dictionary, world: Sm2JourneyWorld) -> bool:
	if not Sm2Validate.fields(raw,["version","id","title","brief","source_location","home","site","resource","quantity","encounter"]): return false
	if raw.version!="sm2.expedition.brief.1": return false
	for id: String in ["id","title","brief","source_location","home","site","resource"]:
		if not raw[id] is String or str(raw[id]).is_empty(): return false
	if not Sm2Validate.integer(raw.quantity,1,100) or not Sm2Validate.integer(raw.encounter,0,world.encounters.size()-1): return false
	if world.region==null or world.exploration==null or world.survival==null or not world.survival.catalog.has_layers(): return false
	if raw.home not in world.region_catalog.ids() or raw.source_location not in world.region_catalog.ids() or raw.home==raw.source_location: return false
	if raw.site not in world.exploration_catalog.ids(): return false
	var site: Dictionary=world.exploration_catalog.site(raw.site)
	if int(site.rewards.get(raw.resource,0))!=int(raw.quantity): return false
	if world.region_catalog.at("sites",raw.site)!=raw.source_location: return false
	if world.region_catalog.at("encounters",str(int(raw.encounter)))!=raw.source_location: return false
	return world.survival.catalog.to_data().supplies.care.has(raw.resource)
