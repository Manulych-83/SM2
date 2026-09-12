class_name Sm2PhysicalSupplies
extends RefCounted
## Compatibility counters are projections of actual items, never spendable stores.

static func matching(s: Sm2SurvivalState,definition: String,world: Sm2JourneyWorld=null) -> Array[String]:
	var result: Array[String]=[]
	for id: String in s.inventory.ids():
		if s.inventory.items[id].definition_id==definition and (world==null or Sm2SurvivalDevices.accessible(s,world,id)): result.append(id)
	return result

static func spawn(s: Sm2SurvivalState,world: Sm2JourneyWorld,definition: String,count: int,place: String,holder: String) -> void:
	for index: int in count:
		s.inventory.add(world.next_id,definition,place,holder); world.next_id+=1

static func initialize(s: Sm2SurvivalState,world: Sm2JourneyWorld,stash: String) -> void:
	for id: String in world.care_catalog.resource_ids():
		spawn(s,world,s.catalog.to_data().supplies.care[id],int(world.care_catalog.resource(id).initial),"container",stash)

static func project(s: Sm2SurvivalState,world: Sm2JourneyWorld) -> void:
	for id: String in world.care.supplies: world.care.supplies[id]=matching(s,s.catalog.to_data().supplies.care[id]).size()
	for id: String in world.upgrade_supply.remaining: world.upgrade_supply.remaining[id]=matching(s,s.catalog.to_data().supplies.upgrades[id]).size()

static func validate(s: Sm2SurvivalState,world: Sm2JourneyWorld) -> String:
	for id: String in world.care.supplies:
		if world.care.supplies[id]!=matching(s,s.catalog.to_data().supplies.care[id]).size(): return "physical_care_projection"
	for id: String in world.upgrade_supply.remaining:
		if int(world.upgrade_supply.remaining[id])!=matching(s,s.catalog.to_data().supplies.upgrades[id]).size(): return "physical_upgrade_projection"
	return ""

static func check(command: Sm2WorldCommand,world: Sm2JourneyWorld) -> String:
	var s: Sm2SurvivalState=world.survival
	var binding: Dictionary=s.catalog.to_data().supplies
	if command.kind=="apply_upgrade" and binding.upgrades.has(command.content_id):
		if matching(s,binding.upgrades[command.content_id],world).is_empty(): return "Нужный препарат или комплект остался в другом месте либо уже израсходован."
	var count: int=0
	if command.kind=="collect_upgrade": count=int(world.upgrade_catalog.definition(command.content_id).get("doses",0))
	if command.kind=="explore":
		for value: int in world.exploration_catalog.site(command.content_id).get("rewards",{}).values(): count+=value
	if count>0 and (s.inventory.items.size()>10000-count or world.next_id>1000000-count): return "Достигнут предел физических предметов этого примера."
	return ""

static func after_world(command: Sm2WorldCommand,world: Sm2JourneyWorld) -> void:
	var s: Sm2SurvivalState=world.survival
	var binding: Dictionary=s.catalog.to_data().supplies
	if command.kind=="collect_upgrade":
		spawn(s,world,binding.upgrades[command.content_id],int(world.upgrade_catalog.definition(command.content_id).doses),"ground",world.region.location_id)
	if command.kind=="apply_upgrade": s.inventory.items.erase(matching(s,binding.upgrades[command.content_id],world)[0])
	if command.kind=="explore":
		var site: Dictionary=world.exploration_catalog.site(command.content_id)
		for id: String in site.rewards: spawn(s,world,binding.care[id],int(site.rewards[id]),"ground",world.region.location_id)
	project(s,world)
