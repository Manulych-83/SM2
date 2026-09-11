class_name Sm2BodyUpgradeSupply
extends RefCounted
## Persistent finite stash; conservation includes enhancements on deceased bodies.
var collected: Array[String]=[]
var remaining: Dictionary={}
func initialize(catalog: Sm2BodyUpgradeCatalog) -> void:
	collected.clear(); remaining.clear()
	for id: String in catalog.ids(): remaining[id]=0
func to_data() -> Dictionary: return {"collected":collected.duplicate(),"remaining":remaining.duplicate(true)}
func copy() -> Sm2BodyUpgradeSupply:
	var result: Sm2BodyUpgradeSupply=Sm2BodyUpgradeSupply.new(); result.collected.assign(collected); result.remaining=remaining.duplicate(true); return result
func check(command: Sm2WorldCommand, world: Sm2JourneyWorld) -> String:
	if world.hero_id()==0: return "Для работы с препаратом нужно живое воплощение."
	if world.upgrade_catalog.definition(command.content_id).is_empty(): return "Препарат не найден."
	if command.kind=="collect_upgrade":
		if command.target_id!=0: return "Препарат забирается в общий запас."
		return "Этот тайник уже собран." if command.content_id in collected else ""
	if command.target_id!=world.hero_id(): return "Модификация доступна только главному герою."
	if command.content_id in world.bodies[world.hero_id()].upgrades.installed: return "Эта модификация уже действует."
	return "Не осталось препарата." if int(remaining[command.content_id])<1 else ""
func apply(command: Sm2WorldCommand, world: Sm2JourneyWorld) -> void:
	if command.kind=="collect_upgrade":
		collected.append(command.content_id); collected.sort(); remaining[command.content_id]=int(world.upgrade_catalog.definition(command.content_id).doses)
	else:
		remaining[command.content_id]=int(remaining[command.content_id])-1
		world.bodies[world.hero_id()].upgrades.installed.append(command.content_id); world.bodies[world.hero_id()].upgrades.installed.sort()
func validate(world: Sm2JourneyWorld) -> String:
	if remaining.size()!=world.upgrade_catalog.ids().size() or not Sm2Validate.string_list(collected): return "upgrade_supply_shape"
	var sorted: Array[String]=collected.duplicate(); sorted.sort()
	if sorted!=collected: return "upgrade_supply_order"
	for id: String in collected:
		if world.upgrade_catalog.definition(id).is_empty(): return "upgrade_supply_reference"
	for id: String in world.upgrade_catalog.ids():
		var doses: int=int(world.upgrade_catalog.definition(id).doses) if id in collected else 0
		if not Sm2Validate.integer(remaining.get(id),0,doses): return "upgrade_supply_count"
		var used: int=0
		for body_id: int in world.bodies:
			var body: Sm2WorldBody=world.bodies[body_id]
			if body.upgrades==null or not Sm2BodyUpgradeState.decode(body.upgrades.to_data(),world.upgrade_catalog).ok: return "upgrade_body_state"
			if not body.upgrades.installed.is_empty():
				var was_hero: bool=false
				for life: Dictionary in world.incarnations: was_hero=was_hero or int(life.body_id)==body_id
				if not was_hero: return "upgrade_body_owner"
			if id in body.upgrades.installed: used+=1
		if used+int(remaining[id])!=doses: return "upgrade_supply_conservation"
	return ""
