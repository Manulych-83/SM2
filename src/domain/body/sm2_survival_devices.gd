class_name Sm2SurvivalDevices
extends RefCounted
## Biological absence, wounds and physical device condition have separate owners.
const COMMANDS: Array[String]=["attach_device","detach_device","repair_device"]

static func validate_catalog(raw: Variant,items: Array,parts: Array[String]) -> String:
	if not raw is Dictionary or not Sm2Validate.fields(raw,["version","interfaces","definitions","procedures","locations","starter_parts"]) or raw.version!="sm2.survival.devices.1": return "survival_devices_shape"
	if not raw.interfaces is Dictionary or raw.interfaces.is_empty() or not raw.definitions is Array or raw.definitions.is_empty() or raw.definitions.size()>256: return "survival_devices_groups"
	for part: Variant in raw.interfaces:
		if not part is String or part not in parts or not Sm2Validate.text(raw.interfaces[part]): return "survival_device_interface"
	var ids: Array[String]=[]
	for row: Variant in raw.definitions:
		if not row is Dictionary or not Sm2Validate.fields(row,["id","part","interface","capacity"]) or not Sm2Validate.text(row.id) or row.id in ids or not row.part is String or not raw.interfaces.has(row.part) or not Sm2Validate.text(row.interface) or not Sm2Validate.integer(row.capacity,1,10000): return "survival_device_definition"
		var found: bool=false
		for item: Dictionary in items:
			if item.id==row.id:
				found=true
				if item.slot!="" or int(item.capacity)!=0: return "survival_device_physical_definition"
		if not found: return "survival_device_physical_missing"
		ids.append(row.id)
	if not raw.procedures is Dictionary or not Sm2Validate.fields(raw.procedures,COMMANDS): return "survival_device_procedures"
	for kind: String in COMMANDS:
		var row: Variant=raw.procedures[kind]
		if not row is Dictionary or not Sm2Validate.fields(row,["seconds","parts"]) or not Sm2Validate.integer(row.seconds,1,3600) or not Sm2Validate.integer(row.parts,0,16): return "survival_device_price"
	if not Sm2Validate.string_list(raw.locations) or raw.locations.is_empty() or not Sm2Validate.integer(raw.starter_parts,0,64): return "survival_device_locations"
	return ""

static func installed(s: Sm2SurvivalState,body: String,part: String) -> String:
	for id: String in s.inventory.ids():
		var item: Dictionary=s.inventory.items[id]
		if item.place=="installed" and item.holder==body and item.slot==part: return id
	return ""

static func working(s: Sm2SurvivalState,body: String,part: String) -> bool:
	if not s.missing.get(body,[]).has(part): return s.bodies[body].working(part)
	var id: String=installed(s,body,part)
	return not id.is_empty() and int(s.inventory.items[id].current)>0

static func project_functions(s: Sm2SurvivalState,body: String,functions: Sm2BodyFunctionState) -> void:
	for part: String in functions.working:
		functions.working[part]=working(s,body,part)
		functions.missing[part]=s.missing.get(body,[]).has(part)
		functions.prostheses[part]=installed(s,body,part)

static func validate_state(s: Sm2SurvivalState) -> String:
	if s.missing.size()!=s.bodies.size(): return "survival_missing_bodies"
	for body: String in s.bodies:
		var absent: Variant=s.missing.get(body)
		if not Sm2Validate.string_list(absent): return "survival_missing_parts"
		for part: String in absent:
			if not s.catalog.devices().interfaces.has(part) or int(s.bodies[body].tissues[part])!=0: return "survival_missing_tissue"
	for id: String in s.inventory.ids():
		var item: Dictionary=s.inventory.items[id]
		var definition: Dictionary=s.catalog.device(item.definition_id)
		if definition.is_empty():
			if item.place=="installed": return "survival_installed_nondevice"
			continue
		if int(item.current)>int(definition.capacity) or int(item.ammo)!=0: return "survival_device_condition"
		if item.place=="installed":
			if item.slot!=definition.part or not s.missing.get(item.holder,[]).has(item.slot) or s.catalog.devices().interfaces.get(item.slot)!=definition.interface: return "survival_device_attachment"
	return ""

static func accessible(s: Sm2SurvivalState,world: Sm2JourneyWorld,id: String) -> bool:
	if s.inventory.location(id,world.region.bodies)!=world.region.location_id: return false
	var owner: int=s.inventory.owner(id)
	return owner in [0,world.hero_id(),4] or (world.bodies.has(owner) and not world.bodies[owner].alive)

static func materials(s: Sm2SurvivalState,world: Sm2JourneyWorld) -> Array[String]:
	var result: Array[String]=[]
	for id: String in s.inventory.ids():
		if s.inventory.items[id].definition_id=="repair_parts" and accessible(s,world,id): result.append(id)
	return result

static func check(command: Sm2WorldCommand,world: Sm2JourneyWorld) -> String:
	var s: Sm2SurvivalState=world.survival
	if world.hero_id()==0: return "Сначала выберите новое тело."
	if world.region.location_id not in s.catalog.devices().locations: return "Нужна мастерская в лагере или анклаве."
	if not s.inventory.items.has(command.content_id) or not accessible(s,world,command.content_id): return "Устройство недоступно в этом месте."
	var item: Dictionary=s.inventory.items[command.content_id]
	var definition: Dictionary=s.catalog.device(item.definition_id)
	if definition.is_empty(): return "Этот предмет не является протезом."
	match command.kind:
		"attach_device":
			if command.target_id not in [world.hero_id(),4] or not world.bodies[command.target_id].alive or world.region.bodies[str(command.target_id)]!=world.region.location_id: return "Нужен живой участник отряда рядом."
			if item.place=="installed": return "Протез уже установлен."
			if int(item.current)==0: return "Сначала отремонтируйте устройство."
			if definition.interface!=s.catalog.devices().interfaces[definition.part]: return "Крепление несовместимо с телом."
			if not s.missing[str(command.target_id)].has(definition.part): return "Протез ставится только вместо отсутствующей руки."
			if not installed(s,str(command.target_id),definition.part).is_empty(): return "Сначала снимите прежнее устройство."
		"detach_device":
			if command.target_id!=0: return "Снятый протез кладётся на землю в этом месте."
			if item.place!="installed": return "Протез уже снят."
		"repair_device":
			if command.target_id!=0: return "Для ремонта выберите предмет."
			if int(item.current)==int(definition.capacity): return "Протез уже исправен."
			if item.place=="installed" and not world.bodies[int(item.holder)].alive: return "Сначала снимите устройство с прежнего тела."
		_: return "Неизвестная процедура."
	var price: Dictionary=s.catalog.devices().procedures[command.kind]
	if s.seconds>Sm2RegionCatalog.TIME_LIMIT-int(price.seconds): return "Достигнут предел времени примера."
	if materials(s,world).size()<int(price.parts): return "Не хватает физических комплектов деталей."
	return ""

static func apply(command: Sm2WorldCommand,world: Sm2JourneyWorld) -> void:
	var s: Sm2SurvivalState=world.survival
	var item: Dictionary=s.inventory.items[command.content_id]
	# Physiology has already advanced; an interrupted procedure must not finish.
	if command.kind=="attach_device" and not world.bodies[command.target_id].alive: world.revision+=1; return
	if command.kind=="repair_device" and item.place=="installed" and not world.bodies[int(item.holder)].alive: world.revision+=1; return
	var required: int=int(s.catalog.devices().procedures[command.kind].parts)
	var parts: Array[String]=materials(s,world)
	for index: int in required: s.inventory.items.erase(parts[index])
	match command.kind:
		"attach_device":
			item.place="installed"; item.holder=str(command.target_id); item.slot=s.catalog.device(item.definition_id).part
		"detach_device": item.place="ground"; item.holder=world.region.location_id; item.slot=""
		"repair_device": item.current=int(s.catalog.device(item.definition_id).capacity)
	s.sync_world(world); world.revision+=1

static func battle_item_valid(before: Dictionary,after: Dictionary,catalog: Sm2SurvivalCatalog,participants: Array[String]) -> bool:
	if before.place!="installed" or before.holder not in participants or catalog.device(before.definition_id).is_empty(): return Sm2Canonical.hash(before)==Sm2Canonical.hash(after)
	var expected: Dictionary=before.duplicate(true); expected.current=after.current
	return int(after.current)<=int(before.current) and Sm2Canonical.hash(expected)==Sm2Canonical.hash(after)
