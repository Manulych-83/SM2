class_name Sm2RegionState
extends RefCounted
## Location and elapsed simulation time survive bodies; no clock or RNG dependency.
var location_id: String=""
var seconds: int=0
var visited: Array[String]=[]
var bodies: Dictionary[String,String]={}

func initialize(catalog: Sm2RegionCatalog) -> void:
	location_id=catalog.to_data().start; seconds=0; visited=[location_id]; bodies.clear()
	for row: Dictionary in catalog.to_data().bodies: bodies[row.id]=row.location
func copy() -> Sm2RegionState:
	var value: Sm2RegionState=Sm2RegionState.new(); value.location_id=location_id; value.seconds=seconds; value.visited=visited.duplicate(); value.bodies=bodies.duplicate(); return value
func to_data() -> Dictionary:
	return {"format":"sm2.region_state.1","location_id":location_id,"seconds":seconds,"visited":visited.duplicate(),"bodies":bodies.duplicate()}
func owner_location(owner: int,catalog: Sm2RegionCatalog) -> String:
	return str(catalog.to_data().stash) if owner==6 else bodies.get(str(owner),"")
func local_owner(owner: int,catalog: Sm2RegionCatalog) -> bool: return owner_location(owner,catalog)==location_id

func duration(command: Sm2WorldCommand,world: Sm2JourneyWorld) -> int:
	match command.kind:
		"travel": return world.region_catalog.route(location_id,command.content_id)
		"practice":
			var exercise: Sm2PracticeDefinition=world._progress.activity(Sm2LifeWorld.DRILL if command.content_id.is_empty() else command.content_id)
			return exercise.seconds if exercise!=null else 0
		"explore": return int(world.exploration_catalog.site(command.content_id).get("minutes",0))*60
	return int(world.care_catalog.service(command.kind).get("minutes",0))*60

func check(command: Sm2WorldCommand,world: Sm2JourneyWorld) -> String:
	var catalog: Sm2RegionCatalog=world.region_catalog
	if seconds>Sm2RegionCatalog.TIME_LIMIT-duration(command,world): return "Достигнут предел времени этого примера."
	if command.kind=="travel":
		if command.target_id!=0: return "Выберите место на карте."
		if world.hero_id()==0: return "Для путешествия нужно новое воплощение в этом месте."
		if catalog.route(location_id,command.content_id)<=0: return "Между этими местами нет прямого пути."
		return ""
	var required: String=""
	match command.kind:
		"start_battle": required=catalog.at("encounters",str(world.completed))
		"explore": required=catalog.at("sites",command.content_id)
		"collect_upgrade": required=catalog.upgrade(command.content_id,"collect")
		"apply_upgrade": required=catalog.upgrade(command.content_id,"apply")
		"deposit": required=catalog.to_data().stash
		"take": required=owner_location(world.item_owner,catalog)
	if command.kind in Sm2RegionCatalog.LOCAL_COMMANDS: required=catalog.at("services",command.kind)
	if not required.is_empty() and required!="*" and required!=location_id: return "Доступно в месте: "+str(catalog.location(required).name)+"."
	if command.target_id!=0 and command.kind!="travel" and not local_owner(command.target_id,catalog): return "Получатель или тело находится в другом месте."
	var item: Dictionary={}
	if command.kind in ["equip","unequip","transfer"]: item=world.item(command.content_id)
	if command.kind in Sm2ProsthesisInventory.COMMANDS: item=world.prostheses.item(command.content_id)
	if not item.is_empty() and not local_owner(int(item.owner_id),catalog): return "Предмет остался в другом месте."
	return ""

func apply(command: Sm2WorldCommand,world: Sm2JourneyWorld) -> void:
	seconds+=duration(command,world)
	if command.kind!="travel": return
	var previous: String=location_id; location_id=command.content_id
	bodies[str(world.hero_id())]=location_id
	if world.bodies[4].alive and bodies["4"]==previous: bodies["4"]=location_id
	if location_id not in visited: visited.append(location_id)

func validate(world: Sm2JourneyWorld) -> String:
	var catalog: Sm2RegionCatalog=world.region_catalog
	if location_id not in catalog.ids() or seconds<0 or seconds>Sm2RegionCatalog.TIME_LIMIT or bodies.size()!=world.bodies.size(): return "region_state_bounds"
	if not Sm2Validate.string_list(visited) or location_id not in visited or str(catalog.to_data().start) not in visited: return "region_visits"
	for id: String in visited:
		if id not in catalog.ids(): return "region_visit_reference"
	for id: int in world.bodies:
		if bodies.get(str(id),"") not in catalog.ids(): return "region_body_reference"
	if world.hero_id()!=0 and bodies[str(world.hero_id())]!=location_id: return "region_hero_location"
	if world.bodies[4].alive and bodies["4"]!=location_id: return "region_companion_location"
	return ""
