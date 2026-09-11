class_name Sm2ProsthesisInventory
extends RefCounted
## Installed devices retain their unique item identity and condition when detached.
const COMMANDS: Array[String]=["install_prosthesis","remove_prosthesis","transfer_prosthesis","repair_prosthesis"]
var items: Array[Dictionary]=[]

func copy() -> Sm2ProsthesisInventory:
	var result: Sm2ProsthesisInventory=Sm2ProsthesisInventory.new()
	result.items.assign(items.duplicate(true)); return result

func item(id: String) -> Dictionary:
	for entry: Dictionary in items:
		if entry.id==id: return entry.duplicate(true)
	return {}

func create(id: int, definition_id: String) -> void:
	items.append({"id":str(id),"definition_id":definition_id,"owner_id":"6","installed_part":"","working":true})

func check(command: Sm2WorldCommand, world: Sm2JourneyWorld) -> String:
	if world.hero_id()==0: return "Сначала выберите новое тело."
	var entry: Dictionary=item(command.content_id)
	if entry.is_empty(): return "Протез не найден."
	var owner: int=int(entry.owner_id)
	if owner!=6 and owner not in [world.hero_id(),4] and world.bodies[owner].alive: return "Вещи живого противника недоступны."
	match command.kind:
		"install_prosthesis":
			if command.target_id not in [world.hero_id(),4] or not world.bodies[command.target_id].alive: return "Установка доступна живому участнику отряда."
			if not entry.installed_part.is_empty(): return "Протез уже установлен."
			if owner not in [6,command.target_id]: return "Сначала передайте протез этому участнику или в тайник."
			if not entry.working: return "Сначала отремонтируйте протез."
			var part: String=world.body_catalog.prosthesis(entry.definition_id).part_id
			if not world.body_catalog.compatible(entry.definition_id,part): return "Крепление протеза несовместимо с телом."
			var functions: Sm2BodyFunctionState=world.bodies[command.target_id].functions
			if not functions.missing[part]: return "Протез устанавливается только вместо утраченной руки."
			if not functions.prostheses[part].is_empty(): return "Сначала снимите установленный протез."
		"remove_prosthesis":
			if entry.installed_part.is_empty(): return "Протез уже снят."
		"transfer_prosthesis":
			if not entry.installed_part.is_empty(): return "Сначала снимите протез."
			if command.target_id not in [6,world.hero_id(),4] or (command.target_id==4 and not world.bodies[4].alive): return "Получатель недоступен."
			if owner==command.target_id: return "Протез уже у получателя."
		"repair_prosthesis":
			if entry.working: return "Протез исправен."
			if not entry.installed_part.is_empty() and not world.bodies[owner].alive: return "Сначала снимите протез с прежнего тела."
		_: return "Неизвестная операция с протезом."
	return ""

func apply(command: Sm2WorldCommand, world: Sm2JourneyWorld) -> void:
	for entry: Dictionary in items:
		if entry.id!=command.content_id: continue
		match command.kind:
			"install_prosthesis":
				var part: String=world.body_catalog.prosthesis(entry.definition_id).part_id
				entry.owner_id=str(command.target_id); entry.installed_part=part
				var functions: Sm2BodyFunctionState=world.bodies[command.target_id].functions
				functions.prostheses[part]=entry.id; functions.working[part]=true
			"remove_prosthesis":
				var functions: Sm2BodyFunctionState=world.bodies[int(entry.owner_id)].functions
				functions.prostheses[entry.installed_part]=""; functions.working[entry.installed_part]=false
				entry.installed_part=""
			"transfer_prosthesis": entry.owner_id=str(command.target_id)
			"repair_prosthesis":
				entry.working=true
				if not entry.installed_part.is_empty(): world.bodies[int(entry.owner_id)].functions.working[entry.installed_part]=true
		return

func settle(world: Sm2JourneyWorld) -> void:
	for entry: Dictionary in items:
		if not entry.installed_part.is_empty(): entry.working=world.bodies[int(entry.owner_id)].functions.working[entry.installed_part]

func validate(world: Sm2JourneyWorld, reserved: Array[String]) -> String:
	var ids: Array[String]=reserved.duplicate()
	var installed: Dictionary={}
	if items.size()!=world.body_catalog.starters().size(): return "prosthesis_item_count"
	for entry: Dictionary in items:
		if not Sm2Validate.fields(entry,["id","definition_id","owner_id","installed_part","working"]) or not Sm2Validate.decimal(entry.id,1,world.next_id-1) or entry.id in ids or world.bodies.has(int(entry.id)) or not entry.definition_id is String or world.body_catalog.prosthesis(entry.definition_id).is_empty() or not Sm2Validate.decimal(entry.owner_id,1) or not entry.installed_part is String or not entry.working is bool: return "prosthesis_item_fields"
		ids.append(entry.id)
		var owner: int=int(entry.owner_id)
		if owner!=6 and not world.bodies.has(owner): return "prosthesis_item_owner"
		if entry.installed_part.is_empty(): continue
		if owner==6 or not world.body_catalog.compatible(entry.definition_id,entry.installed_part): return "prosthesis_installation"
		var functions: Sm2BodyFunctionState=world.bodies[owner].functions
		if not functions.missing[entry.installed_part] or functions.prostheses[entry.installed_part]!=entry.id or functions.working[entry.installed_part]!=entry.working: return "prosthesis_body_mismatch"
		installed[entry.id]=str(owner)+":"+entry.installed_part
	for id: int in world.bodies:
		for part: String in world.body_catalog.ids():
			var ref_id: String=world.bodies[id].functions.prostheses[part]
			if not ref_id.is_empty() and installed.get(ref_id,"")!=str(id)+":"+part: return "prosthesis_missing_item"
	return ""
