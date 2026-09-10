class_name Sm2JourneyWorld
extends Sm2LifeWorld
## Persistent ownership; equipped items are projected into the common battle engine.
var items: Array[Dictionary]=[]
var encounters: Array[Dictionary]=[]
var completed: int=0
var _gear: Sm2CombatCatalog
var _initial_loadout: String

func _init(progress: Sm2ProgressCatalog, definition: Sm2LifeDefinition, combat: Sm2CombatCatalog, meetings: Array, initial_loadout: String) -> void:
	super(progress,definition)
	_gear=combat
	_initial_loadout=initial_loadout
	encounters.assign(meetings.duplicate(true))

func start(id: String) -> void:
	super.start(id)
	for body_id: int in _definition.ids():
		if not bodies[body_id].alive: continue
		for slot: String in Sm2CombatCatalog.SLOTS:
			var definition_id: String=_gear.slots(_initial_loadout).get(slot,"")
			if definition_id.is_empty(): continue
			var gear: Sm2CombatGear=_gear.gear(definition_id)
			items.append({"id":str(next_id),"definition_id":definition_id,"owner_id":str(body_id),"equipped":true,"slot":slot,"current":gear.capacity,"ammo":gear.ammo})
			next_id+=1

func item(id: String) -> Dictionary:
	for entry: Dictionary in items:
		if entry.id==id: return entry.duplicate(true)
	return {}

func equipment(body_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for slot: String in Sm2CombatCatalog.SLOTS:
		for entry: Dictionary in items:
			if int(entry.owner_id)==body_id and entry.equipped and entry.slot==slot:
				result.append({"id":entry.id,"definition_id":entry.definition_id,"slot":slot,"current":entry.current,"ammo":entry.ammo})
	return result

func check(command: Sm2WorldCommand) -> String:
	if command==null or command.world_id!=world_id or command.expected_revision!=revision or command.incarnation_id!=soul.incarnation_id or command.body_id!=hero_id(): return "Устаревшая команда или другой мир."
	if revision>=1000000: return "Достигнут предел действий примера."
	if busy(): return "Сначала завершите сражение."
	if command.kind=="start_battle":
		if hero_id()==0: return "Сначала выберите новое тело."
		return "Все встречи этой локации завершены." if completed>=encounters.size() else ""
	if command.kind=="practice":
		var has_sword: bool=false
		for entry: Dictionary in equipment(command.target_id):
			has_sword=has_sword or entry.definition_id=="m2:equipment.sword"
		if not has_sword: return "Для упражнения нужно экипировать меч."
	if command.kind in ["equip","unequip","transfer"]:
		if hero_id()==0: return "Сначала выберите новое тело."
		var entry: Dictionary=item(command.content_id)
		if entry.is_empty(): return "Предмет не найден."
		var owner: int=int(entry.owner_id)
		if owner!=6 and owner not in [hero_id(),4] and bodies[owner].alive: return "Вещи живого противника недоступны."
		if command.kind=="transfer":
			if command.target_id not in [6,hero_id(),4] or (command.target_id==4 and not bodies[4].alive): return "Получатель недоступен."
			return "Предмет уже у получателя." if owner==command.target_id else ""
		if owner not in [hero_id(),4] or not bodies[owner].alive: return "Экипировать можно только живого участника отряда."
		if command.kind=="unequip": return "Предмет уже снят." if not entry.equipped else ""
		if entry.equipped: return "Предмет уже надет."
		for other: Dictionary in equipment(owner):
			if other.slot==entry.slot: return "Сначала снимите предмет из этого слота."
			if (entry.slot=="shield" and other.slot=="weapon" and _gear.gear(other.definition_id).two_handed) or (entry.slot=="weapon" and _gear.gear(entry.definition_id).two_handed and other.slot=="shield"): return "Двуручное оружие несовместимо со щитом."
		return ""
	return super.check(command)

func apply(command: Sm2WorldCommand) -> void:
	if command.kind=="start_battle": battle_started=true; receipt=""; revision+=1; return
	if command.kind in ["equip","unequip","transfer"]:
		for entry: Dictionary in items:
			if entry.id!=command.content_id: continue
			entry.equipped=command.kind=="equip"
			if command.kind=="transfer": entry.owner_id=str(command.target_id)
		revision+=1
		return
	super.apply(command)

func binding() -> Array[int]:
	var result: Array[int]=[hero_id(),4]
	if completed<encounters.size():
		for id: Variant in encounters[completed].enemies: result.append(int(id))
	return result

func origin() -> Dictionary:
	var actor_rows: Array[Dictionary]=[]
	var members: Array[Dictionary]=[]
	var bindings: Array[int]=binding()
	for index: int in bindings.size():
		var body: Sm2WorldBody=bodies[bindings[index]]
		actor_rows.append({"actor_id":str(index+1),"body_id":str(body.id),"hp":body.hp,"items":equipment(body.id)})
		if index<2: members.append({"actor_id":str(index+1),"body":body.progress.to_data()})
	return {"version":Sm2EncounterOrigin.RULESET,"world_id":world_id,"battle_id":world_id+":encounter:"+str(completed+1),"incarnation_id":str(soul.incarnation_id),"members":members,"actors":actor_rows}

func settle(state: Sm2TacticalState, hash_value: String) -> String:
	if not busy() or not state.finished or Sm2Canonical.stringify(state.development.origin)!=Sm2Canonical.stringify(origin()): return "encounter_result_context"
	var ids: Array[int]=binding()
	for index: int in ids.size():
		var body: Sm2WorldBody=bodies[ids[index]]
		var actor: Sm2TacticalActor=state.actor(index+1)
		body.hp=actor.combat.hp; body.alive=actor.spatial.alive
		body.death_cause="" if body.alive else "battle"
		if index<2: body.progress=Sm2ProgressRules.decode_body(state.development.bodies[index+1].to_data(),_progress).body
		for entry: Dictionary in items:
			if int(entry.owner_id)==body.id and entry.equipped:
				var local_item: Sm2CombatItem=actor.combat.item(entry.slot)
				entry.current=local_item.current; entry.ammo=local_item.ammo
	if not bodies[ids[0]].alive: _end_incarnation()
	receipt=hash_value; completed+=1
	return ""

func capture() -> Dictionary:
	var data: Dictionary=super.capture()
	data.format="sm2.world.p4.1"; data.erase("binding"); data.erase("battle_id")
	data["items"]=items.duplicate(true); data["completed"]=completed
	return data

func view() -> Dictionary:
	var data: Dictionary=super.view()
	data["items"]=items.duplicate(true); data["completed"]=completed; data["encounter_count"]=encounters.size()
	data["encounter_name"]=encounters[completed].name if completed<encounters.size() else "Все встречи завершены"
	return data

func copy_world() -> Sm2JourneyWorld:
	var value: Sm2JourneyWorld=Sm2JourneyWorld.new(_progress,_definition,_gear,encounters,_initial_loadout)
	value.world_id=world_id; value.revision=revision; value.next_id=next_id
	value.soul.incarnation_id=soul.incarnation_id; value.soul.knowledge=soul.knowledge.duplicate()
	value.incarnations.assign(incarnations.duplicate(true))
	value.item_owner=item_owner; value.battle_started=battle_started; value.receipt=receipt
	value.items.assign(items.duplicate(true)); value.completed=completed
	for id: int in bodies:
		var body: Sm2WorldBody=Sm2WorldBody.new()
		body.id=id; body.hp=bodies[id].hp; body.alive=bodies[id].alive; body.death_cause=bodies[id].death_cause; body.drills=bodies[id].drills
		body.progress=Sm2ProgressRules.decode_body(bodies[id].progress.to_data(),_progress).body
		value.bodies[id]=body
	return value

func validate() -> String:
	if revision<0 or revision>1000000 or completed<0 or completed>encounters.size() or bodies.size()!=_definition.ids().size() or incarnations.is_empty(): return "journey_world_bounds"
	for id: int in _definition.ids():
		if not bodies.has(id): return "journey_missing_body"
		var body: Sm2WorldBody=bodies[id]
		if body.id!=id or body.hp<0 or body.hp>60 or body.alive!=(body.hp>0) or body.progress.id!=id or not Sm2ProgressRules.decode_body(body.progress.to_data(),_progress).ok: return "journey_body_state"
	if hero_id()!=0 and (not bodies.has(hero_id()) or not bodies[hero_id()].alive): return "journey_hero_state"
	var ids: Array[String]=[]
	var slots: Dictionary={}
	for entry: Dictionary in items:
		var gear: Sm2CombatGear=_gear.gear(entry.definition_id)
		if not Sm2Validate.decimal(entry.id,1,next_id-1) or entry.id in ids or gear==null or gear.slot!=entry.slot: return "journey_item_identity"
		ids.append(entry.id)
		var owner: int=int(entry.owner_id)
		if owner!=6 and not bodies.has(owner): return "journey_item_owner"
		if not Sm2Validate.integer(entry.current,0,gear.capacity) or not Sm2Validate.integer(entry.ammo,0,gear.ammo): return "journey_item_condition"
		if entry.equipped:
			var key: String=entry.owner_id+":"+entry.slot
			if owner==6 or slots.has(key): return "journey_item_slot"
			slots[key]=true
	for id: int in bodies:
		var two_handed: bool=false; var shield: bool=false
		for entry: Dictionary in equipment(id):
			two_handed=two_handed or _gear.gear(entry.definition_id).two_handed
			shield=shield or entry.slot=="shield"
		if two_handed and shield: return "journey_two_handed_shield"
	return ""
