class_name Sm2PhysicalInventory
extends RefCounted
## Every object has one placement. Owners and carried mass are derived.
var items: Dictionary = {}

func copy() -> Sm2PhysicalInventory:
	var result: Sm2PhysicalInventory = Sm2PhysicalInventory.new()
	result.items = items.duplicate(true)
	return result

func to_data() -> Dictionary:
	var rows: Array[Dictionary] = []
	for id: String in ids(): rows.append(items[id].duplicate(true))
	return {"format":"sm2.physical_inventory.1","items":rows}

func ids() -> Array[String]:
	var result: Array[String] = []; result.assign(items.keys())
	result.sort_custom(func(a: String,b: String) -> bool: return int(a)<int(b))
	return result

func add(id: int, definition: String, place: String, holder: String, slot: String = "", current: int = 0, ammo: int = 0) -> void:
	items[str(id)] = {"id":str(id),"definition_id":definition,"place":place,"holder":holder,"slot":slot,"current":current,"ammo":ammo}

func owner(id: String) -> int:
	if not items.has(id): return 0
	var entry: Dictionary = items[id]
	if entry.place in ["equipped","installed"]: return int(entry.holder)
	if entry.place == "container" and items.has(entry.holder):
		var parent: Dictionary = items[entry.holder]
		return int(parent.holder) if parent.place=="equipped" else 0
	return 0

func location(id: String, body_places: Dictionary) -> String:
	if not items.has(id): return ""
	var entry: Dictionary = items[id]
	if entry.place=="ground": return str(entry.holder)
	if entry.place=="container":
		if not items.has(entry.holder): return ""
		var parent: Dictionary=items[entry.holder]
		return str(parent.holder) if parent.place=="ground" else str(body_places.get(parent.holder,""))
	return str(body_places.get(entry.holder,""))

func contents(container: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in ids():
		if items[id].place=="container" and items[id].holder==container: result.append(id)
	return result

func usage(container: String,catalog: Sm2SurvivalCatalog) -> Dictionary:
	var mass: int=0; var volume: int=0
	for id: String in contents(container):
		var definition: Dictionary=catalog.item(items[id].definition_id)
		mass+=int(definition.mass); volume+=int(definition.volume)
	return {"mass":mass,"volume":volume}

func carried_mass(body: int,catalog: Sm2SurvivalCatalog) -> int:
	var mass: int=0
	for id: String in ids():
		if owner(id)==body and items[id].place!="installed": mass+=int(catalog.item(items[id].definition_id).mass)
	return mass

func move_error(id: String,place: String,holder: String,catalog: Sm2SurvivalCatalog) -> String:
	if not items.has(id): return "Предмет не найден."
	var entry: Dictionary=items[id]; var definition: Dictionary=catalog.item(entry.definition_id)
	if entry.place=="installed": return "Сначала требуется операция снятия устройства."
	if entry.place==place and entry.holder==holder: return "Предмет уже здесь."
	if place=="container":
		if id==holder or not items.has(holder): return "Место хранения не найдено."
		var target: Dictionary=catalog.item(items[holder].definition_id)
		if int(target.capacity)==0: return "Это не контейнер."
		if int(definition.capacity)>0: return "Вложенные контейнеры пока не поддерживаются."
		if int(definition.size)>int(target.max_size): return "Предмет слишком большой для этого места хранения."
		var used: Dictionary=usage(holder,catalog)
		if int(used.volume)+int(definition.volume)>int(target.capacity): return "Не хватает свободного объёма."
		if int(used.mass)+int(definition.mass)>int(target.max_mass): return "Превышена допустимая масса содержимого."
	elif place=="equipped":
		if str(definition.slot).is_empty(): return "Этот предмет нельзя надеть."
		for other: String in ids():
			if other!=id and items[other].place=="equipped" and items[other].holder==holder and items[other].slot==definition.slot: return "Место экипировки занято."
	elif place!="ground": return "Неверное размещение."
	return ""

func move_item(id: String,place: String,holder: String,catalog: Sm2SurvivalCatalog) -> void:
	items[id].place=place; items[id].holder=holder
	items[id].slot=str(catalog.item(items[id].definition_id).slot) if place=="equipped" else ""

func bandage_for(body: int,catalog: Sm2SurvivalCatalog) -> String:
	for id: String in ids():
		var entry: Dictionary=items[id]
		if entry.definition_id=="bandage" and entry.place=="container" and owner(id)==body and bool(catalog.item(items[entry.holder].definition_id).quick): return id
	return ""

func validate(catalog: Sm2SurvivalCatalog, bodies: Array, places: Array) -> String:
	if items.size()>10000: return "physical_item_limit"
	var definitions: Dictionary={}
	# Validate every referenced row before following any edge to a parent.
	for id: Variant in items:
		var entry: Variant=items[id]
		if not id is String or not entry is Dictionary or not Sm2Validate.fields(entry,["id","definition_id","place","holder","slot","current","ammo"]): return "physical_item_shape"
		for key: String in ["id","definition_id","place","holder","slot"]:
			if not entry[key] is String: return "physical_item_shape"
		if not definitions.has(entry.definition_id): definitions[entry.definition_id]=catalog.item(entry.definition_id)
		if definitions[entry.definition_id].is_empty(): return "physical_item_definition"
	var slots: Dictionary={}
	var totals: Dictionary={}
	var sorted_ids: Array[String]=ids()
	for id: String in sorted_ids:
		var entry: Dictionary=items[id]
		if not Sm2Validate.fields(entry,["id","definition_id","place","holder","slot","current","ammo"]) or entry.id!=id or not Sm2Validate.decimal(id,1,1000000) or not entry.definition_id is String or not entry.place is String or not entry.holder is String or not entry.slot is String: return "physical_item_fields"
		var definition: Dictionary=definitions[entry.definition_id]
		if definition.is_empty() or not Sm2Validate.integer(entry.current,0,10000) or not Sm2Validate.integer(entry.ammo,0,10000): return "physical_item_definition"
		match entry.place:
			"equipped","installed":
				if entry.holder not in bodies or entry.slot.is_empty(): return "physical_body_holder"
				var key: String=entry.holder+":"+entry.slot
				if slots.has(key): return "physical_duplicate_slot"
				slots[key]=true
				if entry.place=="equipped" and entry.slot!=definition.slot: return "physical_slot_definition"
			"ground":
				if entry.holder not in places or not entry.slot.is_empty(): return "physical_ground"
			"container":
				if not entry.slot.is_empty() or int(definition.capacity)>0 or not items.has(entry.holder) or entry.id==entry.holder: return "physical_container_reference"
				var target: Dictionary=definitions[items[entry.holder].definition_id]
				if target.is_empty() or int(target.capacity)<1 or int(definition.size)>int(target.max_size) or items[entry.holder].place not in ["ground","equipped"]: return "physical_container_size"
				if not totals.has(entry.holder): totals[entry.holder]={"mass":0,"volume":0}
				totals[entry.holder].mass+=int(definition.mass)
				totals[entry.holder].volume+=int(definition.volume)
			_: return "physical_placement"
	for id: String in sorted_ids:
		var definition: Dictionary=definitions[items[id].definition_id]
		if int(definition.capacity)>0:
			var used: Dictionary=totals.get(id,{"mass":0,"volume":0})
			if int(used.volume)>int(definition.capacity) or int(used.mass)>int(definition.max_mass): return "physical_capacity"
	return ""

static func decode(raw: Variant,catalog: Sm2SurvivalCatalog,bodies: Array,places: Array) -> Dictionary:
	var failure: Dictionary={"ok":false,"errors":PackedStringArray(["physical_snapshot"])}
	if not raw is Dictionary or not Sm2Validate.fields(raw,["format","items"]) or raw.format!="sm2.physical_inventory.1" or not raw.items is Array or raw.items.size()>10000: return failure
	var result: Sm2PhysicalInventory=Sm2PhysicalInventory.new(); var previous: int=0
	for entry: Variant in raw.items:
		if not entry is Dictionary or not Sm2Validate.decimal(entry.get("id"),previous+1,1000000): return failure
		previous=int(entry.id); result.items[entry.id]=entry.duplicate(true)
	var reason: String=result.validate(catalog,bodies,places)
	return {"ok":true,"inventory":result} if reason.is_empty() else {"ok":false,"errors":PackedStringArray([reason])}
