class_name Sm2ExplorationState
extends RefCounted
var collected: Array[String]=[]
var minutes: int=0
func copy() -> Sm2ExplorationState:
	var result: Sm2ExplorationState=Sm2ExplorationState.new(); result.collected=collected.duplicate(); result.minutes=minutes; return result
func check(id: String,world: Sm2JourneyWorld) -> String:
	var site: Dictionary=world.exploration_catalog.site(id)
	if site.is_empty(): return "Место не найдено."
	if id in collected: return "Здесь уже всё собрано."
	var access: String=world.exploration_catalog.access_error(id,world.bodies[world.hero_id()].progress)
	if not access.is_empty(): return access
	if world.completed<int(site.after_encounters): return "Доступно после %s завершённых встреч." % int(site.after_encounters)
	if minutes>Sm2ExplorationCatalog.TIME_LIMIT-int(site.minutes): return "Достигнут предел времени осмотра."
	for resource_id: String in site.rewards:
		if world.care.supplies[resource_id]>world.care_catalog.capacity(resource_id)-int(site.rewards[resource_id]): return "Недостаточно места в тайнике: "+str(world.care_catalog.resource(resource_id).name)+"."
	if world.exploration_catalog.has_practice():
		return Sm2ProgressRules.award_error(world.bodies[world.hero_id()].progress,site.practice)
	return ""
func apply(id: String,world: Sm2JourneyWorld) -> void:
	var site: Dictionary=world.exploration_catalog.site(id)
	for resource_id: String in site.rewards: world.care.supplies[resource_id]+=int(site.rewards[resource_id])
	if world.exploration_catalog.has_practice(): Sm2ProgressRules.award(world.bodies[world.hero_id()].progress,site.practice)
	minutes+=int(site.minutes); collected.append(id)
func validate(catalog: Sm2ExplorationCatalog,completed: int) -> String:
	var seen: Array[String]=[]; var expected: int=0
	for id: String in collected:
		var site: Dictionary=catalog.site(id)
		if site.is_empty() or id in seen or completed<int(site.after_encounters): return "exploration_collected"
		seen.append(id); expected+=int(site.minutes)
	if minutes!=expected or minutes>Sm2ExplorationCatalog.TIME_LIMIT: return "exploration_time"
	return ""
func to_data() -> Dictionary:
	var ids: Array[String]=collected.duplicate(); ids.sort()
	return {"format":"sm2.exploration_state.1","collected":ids,"minutes":minutes}
