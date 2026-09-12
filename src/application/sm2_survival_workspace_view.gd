class_name Sm2SurvivalWorkspaceView
extends RefCounted
## Detached read model; command availability remains owned by JourneyWorld.
static func build(session: Sm2JourneySession,selected: int=0) -> Dictionary:
	var world: Sm2JourneyWorld=session.journey()
	var s: Sm2SurvivalState=world.survival
	var result: Dictionary={"message":"","people":[],"body":{},"parts":[],"items":[],"containers":[],"location":""}
	if s==null or not s.catalog.has_layers(): result.message="Этот экран доступен в режиме «Ткани и припасы»."; return result
	if world.busy(): result.message="Идёт бой. Вернитесь в сражение; вещи можно перекладывать после его завершения."; return result
	result.location=world.region_catalog.location(world.region.location_id).name
	var ids: Array[int]=[]
	for id: int in [world.hero_id(),4]:
		if id!=0 and world.region.bodies[str(id)]==world.region.location_id: ids.append(id)
	for id: int in world.bodies:
		if id not in ids and not world.bodies[id].alive and world.region.bodies[str(id)]==world.region.location_id: ids.append(id)
	for id: int in ids:
		result.people.append({"id":id,"name":person(world,id),"alive":world.bodies[id].alive})
	if selected not in ids: selected=ids[0] if not ids.is_empty() else 0
	if selected!=0:
		var body: Sm2Anatomy=s.bodies[str(selected)]
		result.body={"id":selected,"name":person(world,selected),"alive":world.bodies[selected].alive,"blood":body.blood,"blood_max":int(s.catalog.to_data().blood_max),"bleeding":body.rate(),"mass":s.inventory.carried_mass(selected,s.catalog)}
		for definition: Dictionary in s.catalog.to_data().parts:
			var part: String=definition.id
			var device_id: String=Sm2SurvivalDevices.installed(s,str(selected),part)
			var missing: bool=part in s.missing[str(selected)]
			var working: bool=Sm2SurvivalDevices.working(s,str(selected),part)
			var row: Dictionary={"id":part,"name":definition.name,"layers":[],"wounds":[],"damaged":false,"bleeding":0,"device":"","status":"Функция сохранена","working":working,"missing":missing,"device_id":device_id}
			for layer: Dictionary in body.layer_rules[part]:
				var current: int=int(body.layers[part][layer.id])
				row.layers.append({"name":layer.name,"current":current,"capacity":int(layer.capacity)})
				row.damaged=row.damaged or current<int(layer.capacity)
			for wound: Dictionary in body.wounds:
				if wound.part!=part: continue
				row.wounds.append(wound.duplicate(true)); row.bleeding+=int(wound.rate)
			if missing: row.status="Естественная часть отсутствует"
			elif not working: row.status="Естественная функция утрачена"
			elif row.damaged: row.status="Повреждение · функция сохранена"
			if not device_id.is_empty():
				var item: Dictionary=s.inventory.items[device_id]
				row.device="%s · прочность %s / %s" % [s.catalog.item(item.definition_id).name,int(item.current),int(s.catalog.device(item.definition_id).capacity)]
				row.status+=" · протез работает" if working else " · протез не работает"
			result.parts.append(row)
	for id: String in s.inventory.ids():
		if s.inventory.location(id,world.region.bodies)!=world.region.location_id: continue
		var item: Dictionary=s.inventory.items[id]
		var definition: Dictionary=s.catalog.item(item.definition_id)
		var owner: int=s.inventory.owner(id)
		var row: Dictionary={"id":id,"definition_id":item.definition_id,"name":definition.name,"owner":owner,"place":item.place,"holder":item.holder,"where":placement(world,id),"mass":int(definition.mass),"volume":int(definition.volume),"size":int(definition.size),"device":not s.catalog.device(item.definition_id).is_empty(),"current":int(item.current),"capacity":int(definition.capacity),"slot":definition.slot,"stash":false}
		row.stash=item.place=="container" and s.inventory.items[item.holder].definition_id=="stash"
		if row.device: row["device_max"]=int(s.catalog.device(item.definition_id).capacity)
		result.items.append(row)
		if int(definition.capacity)>0 and item.place in ["equipped","ground"]:
			var usage: Dictionary=s.inventory.usage(id,s.catalog)
			result.containers.append({"id":id,"name":definition.name,"where":placement(world,id),"owner":owner,"volume":int(usage.volume),"capacity":int(definition.capacity),"mass":int(usage.mass),"max_mass":int(definition.max_mass),"quick":definition.quick})
	return result

static func person(world: Sm2JourneyWorld,id: int) -> String:
	if id==world.hero_id(): return "Герой"
	if id==4: return "Спутник" if world.bodies[id].alive else "Спутник · погиб"
	return str(world._definition.body(id).get("name","Тело"))+" · "+("носитель" if world.bodies[id].death_cause=="prepared_carrier" else "погиб")

static func placement(world: Sm2JourneyWorld,id: String) -> String:
	var inv: Sm2PhysicalInventory=world.survival.inventory
	var item: Dictionary=inv.items[id]
	if item.place=="ground": return "На земле"
	if item.place in ["equipped","installed"]: return ("Установлен · " if item.place=="installed" else "На теле · ")+person(world,int(item.holder))
	var parent: Dictionary=inv.items[item.holder]
	return str(world.survival.catalog.item(parent.definition_id).name)+" · "+(person(world,int(parent.holder)) if parent.place=="equipped" else "здесь")
