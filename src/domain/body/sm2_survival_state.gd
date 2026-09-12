class_name Sm2SurvivalState
extends RefCounted
var catalog: Sm2SurvivalCatalog
var bodies: Dictionary = {}
var inventory: Sm2PhysicalInventory = Sm2PhysicalInventory.new()
var places: Array = []
var seconds: int = 0
var last_round: int = 0
var missing: Dictionary = {}

func copy() -> Sm2SurvivalState:
	var result: Sm2SurvivalState=Sm2SurvivalState.new()
	result.catalog=catalog; result.places=places.duplicate(); result.seconds=seconds; result.last_round=last_round
	result.inventory=inventory.copy(); result.missing=missing.duplicate(true)
	for id: String in bodies: result.bodies[id]=(bodies[id] as Sm2Anatomy).copy()
	return result

func to_data() -> Dictionary:
	var rows: Dictionary={}
	for id: String in bodies: rows[id]=bodies[id].to_data()
	var data: Dictionary={"format":catalog.state_format(),"catalog":catalog.fingerprint(),"bodies":rows,"inventory":inventory.to_data(),"seconds":seconds,"last_round":last_round}
	if catalog.has_devices(): data["missing"]=missing.duplicate(true)
	return data

static func decode(raw: Variant,initial: Sm2SurvivalState) -> Dictionary:
	var failure: Dictionary={"ok":false,"errors":PackedStringArray(["survival_state_invalid"])}
	var fields: Array[String]=["format","catalog","bodies","inventory","seconds","last_round"]
	if initial.catalog.has_devices(): fields.append("missing")
	if not raw is Dictionary or not Sm2Validate.fields(raw,fields) or raw.format!=initial.catalog.state_format() or raw.catalog!=initial.catalog.fingerprint() or not raw.bodies is Dictionary or raw.bodies.size()!=initial.bodies.size(): return failure
	if not Sm2Validate.integer(raw.seconds,0,1000000000) or not Sm2Validate.integer(raw.last_round,0,1000): return failure
	var result: Sm2SurvivalState=initial.copy()
	for id: String in initial.bodies:
		var checked: Dictionary=Sm2Anatomy.decode(raw.bodies.get(id),initial.catalog.to_data())
		if not checked.ok: return checked
		result.bodies[id]=checked.body
	var checked: Dictionary=Sm2PhysicalInventory.decode(raw.inventory,initial.catalog,initial.bodies.keys(),initial.places)
	if not checked.ok: return checked
	result.inventory=checked.inventory; result.seconds=int(raw.seconds); result.last_round=int(raw.last_round)
	if initial.catalog.has_devices():
		if not raw.missing is Dictionary: return failure
		result.missing=raw.missing.duplicate(true)
		var reason: String=Sm2SurvivalDevices.validate_state(result)
		if not reason.is_empty(): return {"ok":false,"errors":PackedStringArray([reason])}
	return {"ok":true,"state":result}

func initialize(world: Sm2JourneyWorld) -> void:
	places=Array(world.region_catalog.ids())
	for id: int in world.bodies:
		var body: Sm2Anatomy=Sm2Anatomy.fresh(catalog.to_data())
		if not world.bodies[id].alive: body.death="prepared_carrier"
		bodies[str(id)]=body
		if catalog.has_devices(): missing[str(id)]=[]
	for entry: Dictionary in world.items:
		inventory.add(int(entry.id),entry.definition_id,"equipped",entry.owner_id,entry.slot,int(entry.current),int(entry.ammo))
	# Existing detachable prostheses remain in the old profile in this first slice.
	for entry: Dictionary in world.prostheses.items:
		inventory.add(int(entry.id),entry.definition_id,"ground",str(world.region_catalog.to_data().stash))
	var stash: int=world.next_id; world.next_id+=1
	inventory.add(stash,"stash","ground",str(world.region_catalog.to_data().stash))
	for body_id: int in [world.hero_id(),4]:
		for definition: String in ["pockets","belt","backpack"]:
			var id: int=world.next_id; world.next_id+=1
			inventory.add(id,definition,"equipped",str(body_id),str(catalog.item(definition).slot))
			if definition=="belt":
				for index: int in 3:
					inventory.add(world.next_id,"bandage","container",str(id)); world.next_id+=1
	for index: int in 8:
		inventory.add(world.next_id,"bandage","container",str(stash)); world.next_id+=1
	# A new incarnation can obtain actual clothes and containers from the stash location.
	for definition: String in ["pockets","belt","backpack"]:
		inventory.add(world.next_id,definition,"ground",str(world.region_catalog.to_data().stash)); world.next_id+=1
	if catalog.has_devices():
		for id: String in inventory.ids():
			var definition: Dictionary=catalog.device(inventory.items[id].definition_id)
			if not definition.is_empty(): inventory.items[id].current=int(definition.capacity)
		for index: int in (0 if catalog.has_layers() else int(catalog.devices().starter_parts)):
			inventory.add(world.next_id,"repair_parts","container",str(stash)); world.next_id+=1
	if catalog.has_layers(): Sm2PhysicalSupplies.initialize(self,world,str(stash))
	sync_world(world)

func sync_world(world: Sm2JourneyWorld) -> void:
	for id: String in bodies:
		var anatomy: Sm2Anatomy=bodies[id]
		var body: Sm2WorldBody=world.bodies[int(id)]
		body.hp=anatomy.summary(catalog.to_data())
		body.alive=anatomy.cause(catalog.to_data()).is_empty(); body.death_cause=anatomy.death
		for part: String in body.functions.working: body.functions.working[part]=anatomy.working(part)
		if catalog.has_devices(): Sm2SurvivalDevices.project_functions(self,id,body.functions)
	for entry: Dictionary in world.items:
		var item: Dictionary=inventory.items[entry.id]
		entry.owner_id=str(inventory.owner(entry.id)) if inventory.owner(entry.id)!=0 else "6"
		entry.equipped=item.place=="equipped"
		entry.current=item.current; entry.ammo=item.ammo
	if catalog.has_devices():
		for entry: Dictionary in world.prostheses.items:
			var item: Dictionary=inventory.items[entry.id]
			entry.owner_id=str(inventory.owner(entry.id)) if inventory.owner(entry.id)!=0 else "6"
			entry.installed_part=item.slot if item.place=="installed" else ""
			entry.working=int(item.current)>0
	if catalog.has_layers(): Sm2PhysicalSupplies.project(self,world)
	world.region.seconds=seconds

func advance(duration: int,critical_bodies: Array[String]=[]) -> int:
	var actual: int=duration
	for id: String in bodies:
		var body: Sm2Anatomy=bodies[id]
		if (critical_bodies.is_empty() or id in critical_bodies) and body.cause(catalog.to_data()).is_empty(): actual=mini(actual,body.until_death(catalog.to_data()))
	for id: String in bodies: bodies[id].advance(actual,catalog.to_data())
	seconds+=actual
	return actual

func check_world(command: Sm2WorldCommand,world: Sm2JourneyWorld) -> String:
	if catalog.has_layers():
		var supply_error: String=Sm2PhysicalSupplies.check(command,world)
		if not supply_error.is_empty(): return supply_error
	if catalog.has_devices() and command.kind in Sm2SurvivalDevices.COMMANDS: return Sm2SurvivalDevices.check(command,world)
	if world.hero_id()==0 and command.kind in ["bandage","store_item","wear_item","drop_item"]: return "Сначала выберите новое тело."
	if command.kind in ["heal_hp","heal_hand","install_prosthesis","remove_prosthesis","repair_prosthesis","transfer_prosthesis"]: return "Эта процедура относится к прежнему профилю тела. В новом примере доступна перевязка."
	if command.kind in ["equip","unequip","transfer"]: return "Выберите размещение в физическом инвентаре."
	if command.kind=="bandage":
		if command.target_id not in [world.hero_id(),4] or not world.bodies[command.target_id].alive: return "Нужен живой участник отряда."
		if inventory.bandage_for(world.hero_id(),catalog).is_empty(): return "Нет перевязочного материала в карманах или на поясе."
		var wound: Dictionary=bodies[str(command.target_id)].wound(command.content_id)
		if wound.is_empty() or int(wound.rate)==0: return "Выберите кровоточащую рану."
		if not has_hand(str(world.hero_id())): return "Нет действующей руки для перевязки."
		if world.region.bodies[str(command.target_id)]!=world.region.location_id: return "Участник находится в другом месте."
	if command.kind in ["store_item","wear_item","drop_item"]:
		if not inventory.items.has(command.content_id): return "Предмет не найден."
		if inventory.location(command.content_id,world.region.bodies)!=world.region.location_id: return "Предмет находится в другом месте."
		var owner: int=inventory.owner(command.content_id)
		if owner!=0 and owner not in [world.hero_id(),4] and world.bodies[owner].alive: return "Вещи живого противника недоступны."
		var place: String="container" if command.kind=="store_item" else "equipped" if command.kind=="wear_item" else "ground"
		var holder: String=str(command.target_id) if place!="ground" else world.region.location_id
		if place=="equipped" and (command.target_id not in [world.hero_id(),4] or not world.bodies[command.target_id].alive): return "Нужен живой участник отряда."
		if place=="equipped":
			var gear: Sm2CombatGear=world._gear.gear(inventory.items[command.content_id].definition_id)
			if gear!=null:
				for equipped: Dictionary in world.equipment(command.target_id):
					var other: Sm2CombatGear=world._gear.gear(equipped.definition_id)
					if (gear.slot=="weapon" and gear.two_handed and other.slot=="shield") or (gear.slot=="shield" and other.slot=="weapon" and other.two_handed): return "Двуручное оружие несовместимо со щитом."
		if place=="container":
			if inventory.location(holder,world.region.bodies)!=world.region.location_id: return "Контейнер находится в другом месте."
			var target_owner: int=inventory.owner(holder)
			if target_owner!=0 and target_owner not in [world.hero_id(),4]: return "Контейнер получателя недоступен."
		return inventory.move_error(command.content_id,place,holder,catalog)
	return ""

func has_hand(body: String) -> bool:
	if catalog.has_devices(): return bodies.has(body) and (Sm2SurvivalDevices.working(self,body,"left_hand") or Sm2SurvivalDevices.working(self,body,"right_hand"))
	return bodies.has(body) and (bodies[body].working("left_hand") or bodies[body].working("right_hand"))

func apply_world(command: Sm2WorldCommand,world: Sm2JourneyWorld) -> bool:
	var before_hero: int=world.hero_id()
	var duration: int=int(catalog.to_data().bandage_seconds) if command.kind=="bandage" else world.region.duration(command,world)
	if catalog.has_devices() and command.kind in Sm2SurvivalDevices.COMMANDS: duration=int(catalog.devices().procedures[command.kind].seconds)
	var tracked: Array[String]=[]
	if catalog.has_devices(): tracked.assign([str(before_hero),"4"])
	var actual: int=advance(duration,tracked)
	sync_world(world)
	if before_hero!=0 and not world.bodies[before_hero].alive:
		world._end_incarnation(); world.revision+=1; return true
	if actual<duration:
		world.revision+=1; return true
	if catalog.has_devices() and command.kind in Sm2SurvivalDevices.COMMANDS:
		Sm2SurvivalDevices.apply(command,world); return true
	if command.kind=="bandage":
		if not world.bodies[command.target_id].alive:
			world.revision+=1; return true
		inventory.items.erase(inventory.bandage_for(before_hero,catalog))
		bodies[str(command.target_id)].bandage(command.content_id)
		world.revision+=1; return true
	if command.kind in ["store_item","wear_item","drop_item"]:
		var place: String="container" if command.kind=="store_item" else "equipped" if command.kind=="wear_item" else "ground"
		inventory.move_item(command.content_id,place,str(command.target_id) if place!="ground" else world.region.location_id,catalog)
		sync_world(world); world.revision+=1; return true
	# Existing region.apply accounts for duration; reserve the same interval, never twice.
	world.region.seconds-=duration
	return false

func after_world(command: Sm2WorldCommand,world: Sm2JourneyWorld) -> void:
	if catalog.has_layers(): Sm2PhysicalSupplies.after_world(command,world)
	if command.kind=="end_life": bodies[str(command.body_id)].injure("heart",10000,false,catalog.to_data())
	if command.kind=="incarnate":
		bodies[str(world.hero_id())]=Sm2Anatomy.fresh(catalog.to_data())
		if catalog.has_devices(): missing[str(world.hero_id())]=[]
	sync_world(world)
