class_name Sm2JourneyWorld
extends Sm2LifeWorld
## Persistent ownership; equipped items are projected into the common battle engine.
var hybrid_catalog: Sm2HybridCatalog=null
var region_catalog: Sm2RegionCatalog=null
var region: Sm2RegionState=null
var upgrade_catalog: Sm2BodyUpgradeCatalog=null
var upgrade_supply: Sm2BodyUpgradeSupply=null
var psionic_catalog: Sm2PsionicCatalog=null
var body_catalog: Sm2BodyFunctionCatalog=null
var prostheses: Sm2ProsthesisInventory=Sm2ProsthesisInventory.new()
var care_catalog: Sm2CareCatalog=null
var care: Sm2CareState=null
var exploration_catalog: Sm2ExplorationCatalog=null
var exploration: Sm2ExplorationState=null
var items: Array[Dictionary]=[]
var encounters: Array[Dictionary]=[]
var completed: int=0
var _gear: Sm2CombatCatalog
var _initial_loadout: String

func _init(progress: Sm2ProgressCatalog, definition: Sm2LifeDefinition, combat: Sm2CombatCatalog, meetings: Array, initial_loadout: String, functions: Sm2BodyFunctionCatalog=null, services: Sm2CareCatalog=null, places: Sm2ExplorationCatalog=null, psionics: Sm2PsionicCatalog=null, upgrades: Sm2BodyUpgradeCatalog=null, hybrids: Sm2HybridCatalog=null) -> void:
	super(progress,definition)
	hybrid_catalog=hybrids
	upgrade_catalog=upgrades
	if upgrades!=null: upgrade_supply=Sm2BodyUpgradeSupply.new()
	_gear=combat; body_catalog=functions; psionic_catalog=psionics
	care_catalog=services
	if care_catalog!=null: care=Sm2CareState.new()
	exploration_catalog=places
	if places!=null: exploration=Sm2ExplorationState.new()
	_initial_loadout=initial_loadout
	encounters.assign(meetings.duplicate(true))

func start(id: String) -> void:
	super.start(id)
	if region!=null: region.initialize(region_catalog)
	if upgrade_supply!=null:
		upgrade_supply.initialize(upgrade_catalog)
		for body_id: int in bodies: bodies[body_id].upgrades=Sm2BodyUpgradeState.new()
	if care!=null: care.initialize(care_catalog)
	if exploration!=null: exploration=Sm2ExplorationState.new()
	if _progress.is_party():
		bodies[4].progress=Sm2CompanionProgress.new(); bodies[4].progress.id=4
	for body_id: int in _definition.ids():
		if body_catalog!=null: bodies[body_id].functions=body_catalog.initial()
		if not bodies[body_id].alive: continue
		for slot: String in Sm2CombatCatalog.SLOTS:
			var definition_id: String=_gear.slots(_initial_loadout).get(slot,"")
			if definition_id.is_empty(): continue
			var gear: Sm2CombatGear=_gear.gear(definition_id)
			items.append({"id":str(next_id),"definition_id":definition_id,"owner_id":str(body_id),"equipped":true,"slot":slot,"current":gear.capacity,"ammo":gear.ammo})
			next_id+=1
	if has_prostheses():
		for definition_id: String in body_catalog.starters(): prostheses.create(next_id,definition_id); next_id+=1

func has_prostheses() -> bool: return body_catalog!=null and body_catalog.supports_prostheses()

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
	var reason: String=_check_action(command)
	if not reason.is_empty(): return reason
	return care.check(command.kind,care_catalog) if care!=null else ""

func _check_action(command: Sm2WorldCommand) -> String:
	if command==null or command.world_id!=world_id or command.expected_revision!=revision or command.incarnation_id!=soul.incarnation_id or command.body_id!=hero_id(): return "Устаревшая команда или другой мир."
	if revision>=1000000: return "Достигнут предел действий примера."
	if busy(): return "Сначала завершите сражение."
	if region!=null:
		var local_error: String=region.check(command,self)
		if not local_error.is_empty(): return local_error
		if command.kind=="travel": return ""
	if upgrade_supply!=null and command.kind in ["collect_upgrade","apply_upgrade"]: return upgrade_supply.check(command,self)
	if exploration!=null and command.kind=="explore":
		if hero_id()==0: return "Для осмотра нужно живое воплощение."
		if command.target_id!=0: return "Место выбирается по названию, не по участнику."
		return exploration.check(command.content_id,self)
	if care!=null and command.kind=="heal_hp":
		if hero_id()==0 or command.target_id not in [hero_id(),4] or not bodies[command.target_id].alive: return "Лечение доступно только живому участнику отряда."
		if not command.content_id.is_empty(): return "Для лечения не нужно выбирать предмет."
		return "Здоровье уже восстановлено." if bodies[command.target_id].hp>=60 else ""
	if has_prostheses() and command.kind in Sm2ProsthesisInventory.COMMANDS: return prostheses.check(command,self)
	if body_catalog!=null:
		if command.kind=="heal_hand":
			if hero_id()==0 or command.target_id not in [hero_id(),4] or not bodies[command.target_id].alive: return "Этот участник недоступен для лечения."
			if command.content_id not in body_catalog.ids(): return "Часть тела не найдена."
			if bodies[command.target_id].functions.missing.get(command.content_id,false): return "Утраченную руку лечение не восстановит. Нужен исправный протез."
			return "Рука уже работает." if bodies[command.target_id].functions.working[command.content_id] else ""
		if command.kind=="practice" and command.target_id==hero_id() and hero_id()!=0:
			if not Sm2BodyCapabilityQuery.requirements(bodies[hero_id()].functions,body_catalog.practice(DRILL if command.content_id.is_empty() else command.content_id)): return "Травма руки не позволяет выполнить упражнение."
		if command.kind=="equip":
			var gear_item: Dictionary=item(command.content_id)
			if not gear_item.is_empty() and bodies.has(int(gear_item.owner_id)):
				var gear: Sm2CombatGear=_gear.gear(gear_item.definition_id)
				if not Sm2BodyCapabilityQuery.requirements(bodies[int(gear_item.owner_id)].functions,body_catalog.required("two_handed" if gear.two_handed else gear.slot)): return "Рука не может удерживать этот предмет."
	if command.kind=="start_battle":
		if hero_id()==0: return "Сначала выберите новое тело."
		return "Все встречи этой локации завершены." if completed>=encounters.size() else ""
	if _progress.is_party() and command.kind in ["practice","buy_node"]:
		if hero_id()==0 or command.target_id!=hero_id(): return "Практика и узлы доступны только главному герою."
		if receipt.is_empty() and not _psionic_training(command): return "Развитие в локации доступно после сражения."
		if command.kind=="buy_node": return Sm2ProgressRules.purchase_error(bodies[hero_id()].progress,_progress,command.content_id)
		var activity: Sm2PracticeDefinition=_progress.activity(DRILL if command.content_id.is_empty() else command.content_id)
		if activity==null: return "Упражнение не найдено."
		if activity.id==DRILL:
			var sword: bool=false
			for entry: Dictionary in equipment(hero_id()): sword=sword or entry.definition_id=="m2:equipment.sword"
			if not sword: return "Для упражнения нужно экипировать меч."
		if not Sm2PracticeCapability.query(activity,bodies[hero_id()].progress,_progress).allowed: return "Недостаточно возможностей для упражнения."
		for id: String in activity.awards:
			if bodies[hero_id()].progress.tracks[id].earned>Sm2ProgressCatalog.XP_LIMIT-activity.awards[id]: return "Достигнут предел опыта."
		return ""
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
	if region!=null: region.apply(command,self)
	_apply_action(command)
	if care!=null: care.spend(command.kind,care_catalog)

func _apply_action(command: Sm2WorldCommand) -> void:
	if region!=null and command.kind=="travel": revision+=1; return
	if upgrade_supply!=null and command.kind in ["collect_upgrade","apply_upgrade"]: upgrade_supply.apply(command,self); revision+=1; return
	if exploration!=null and command.kind=="explore": exploration.apply(command.content_id,self); revision+=1; return
	if care!=null and command.kind=="heal_hp":
		bodies[command.target_id].hp=mini(60,bodies[command.target_id].hp+int(care_catalog.service("heal_hp").heal_hp)); revision+=1; return
	if has_prostheses() and command.kind in Sm2ProsthesisInventory.COMMANDS:
		prostheses.apply(command,self); revision+=1; return
	if body_catalog!=null and command.kind=="heal_hand":
		bodies[command.target_id].functions.working[command.content_id]=true; revision+=1; return
	if _progress.is_party() and command.kind=="practice":
		var activity: Sm2PracticeDefinition=_progress.activity(DRILL if command.content_id.is_empty() else command.content_id)
		for id: String in activity.awards: bodies[command.target_id].progress.tracks[id].earned+=activity.awards[id]
		bodies[command.target_id].drills+=1; revision+=1; return
	if command.kind=="start_battle": battle_started=true; receipt=""; revision+=1; return
	if command.kind in ["equip","unequip","transfer"]:
		for entry: Dictionary in items:
			if entry.id!=command.content_id: continue
			entry.equipped=command.kind=="equip"
			if command.kind=="transfer": entry.owner_id=str(command.target_id)
		revision+=1
		return
	super.apply(command)
	if body_catalog!=null and command.kind=="incarnate": bodies[command.target_id].functions=body_catalog.initial()

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
		if upgrade_catalog!=null: actor_rows.back()["upgrades"]=body.upgrades.to_data()
		if body_catalog!=null: actor_rows.back()["body_functions"]=body.functions.to_data()
		if index<2: members.append({"actor_id":str(index+1),"body":body.progress.to_data()})
	return {"version":Sm2EncounterOrigin.HYBRID_RULESET if hybrid_catalog!=null else Sm2EncounterOrigin.IMPLANT_RULESET if upgrade_catalog!=null and upgrade_catalog.supports_implants() else Sm2EncounterOrigin.UPGRADE_RULESET if upgrade_catalog!=null else Sm2EncounterOrigin.PSIONIC_SHIELD_RULESET if psionic_catalog!=null and psionic_catalog.shields() else Sm2EncounterOrigin.PSIONIC_GROWTH_RULESET if psionic_catalog!=null and psionic_catalog.grows() else Sm2EncounterOrigin.PSIONIC_RULESET if psionic_catalog!=null else Sm2EncounterOrigin.PROSTHESIS_RULESET if has_prostheses() else Sm2EncounterOrigin.BODY_RULESET if body_catalog!=null else Sm2EncounterOrigin.PARTY_RULESET if _progress.is_party() else Sm2EncounterOrigin.RULESET,"world_id":world_id,"battle_id":world_id+":encounter:"+str(completed+1),"incarnation_id":str(soul.incarnation_id),"members":members,"actors":actor_rows}

func settle(state: Sm2TacticalState, hash_value: String) -> String:
	if not busy() or not state.finished or Sm2Canonical.stringify(state.development.origin)!=Sm2Canonical.stringify(origin()): return "encounter_result_context"
	var ids: Array[int]=binding()
	for index: int in ids.size():
		var body: Sm2WorldBody=bodies[ids[index]]
		var actor: Sm2TacticalActor=state.actor(index+1)
		if body_catalog!=null: body.functions=actor.body_functions.copy()
		body.hp=actor.combat.hp; body.alive=actor.spatial.alive
		body.death_cause="" if body.alive else "battle"
		if index<2: body.progress=Sm2ProgressRules.decode_body(state.development.bodies[index+1].to_data(),_progress).body
		for entry: Dictionary in items:
			if int(entry.owner_id)==body.id and entry.equipped:
				var local_item: Sm2CombatItem=actor.combat.item(entry.slot)
				entry.current=local_item.current; entry.ammo=local_item.ammo
	if has_prostheses(): prostheses.settle(self)
	if not bodies[ids[0]].alive: _end_incarnation()
	receipt=hash_value; completed+=1
	return ""

func capture() -> Dictionary:
	var data: Dictionary=super.capture()
	data.format="sm2.world.p4.prosthesis.1" if has_prostheses() else "sm2.world.p4.body.1" if body_catalog!=null else "sm2.world.p4.party.1" if _progress.is_party() else "sm2.world.p4.1"; data.erase("binding"); data.erase("battle_id")
	if care!=null: data.format="sm2.world.p4.care.1"; data["care"]=care.to_data()
	if exploration!=null: data.format="sm2.world.p4.discovery.1" if exploration_catalog.has_requirements() else "sm2.world.p4.search.1" if exploration_catalog.has_practice() else "sm2.world.p4.exploration.1"; data["exploration"]=exploration.to_data()
	if psionic_catalog!=null: data.format="sm2.world.p5.psionic_shield.1" if psionic_catalog.shields() else "sm2.world.p5.psionic_growth.1" if psionic_catalog.grows() else "sm2.world.p5.psionic.1"
	if upgrade_supply!=null: data.format="sm2.world.p5.hybrids.1" if hybrid_catalog!=null else "sm2.world.p5.implants.1" if upgrade_catalog.supports_implants() else "sm2.world.p5.upgrades.1"; data["upgrade_supply"]=upgrade_supply.to_data()
	if has_prostheses(): data["prostheses"]=prostheses.items.duplicate(true)
	data["items"]=items.duplicate(true); data["completed"]=completed
	if region!=null:
		data.format="sm2.world.p6.region.1"; data.location_id=region.location_id
		data["region"]=region.to_data()
	return data

func view() -> Dictionary:
	var data: Dictionary=super.view()
	if care!=null: data["care"]=care.to_data()
	if exploration!=null: data["exploration"]=exploration.to_data()
	for body: Dictionary in data.bodies:
		if upgrade_catalog!=null: body.tracks=Sm2ProgressRules.tracks(bodies[body.id].progress,_progress,upgrade_modifiers(body.id))
		if body_catalog!=null:
			body["functions"]=[]
			for id: String in body_catalog.ids():
				body.functions.append({"id":id,"name":body_catalog.title(id),"working":bodies[body.id].functions.working[id]})
				if has_prostheses():
					body.functions.back()["missing"]=bodies[body.id].functions.missing[id]; body.functions.back()["prosthesis_id"]=bodies[body.id].functions.prostheses[id]
		if bodies[body.id].progress is Sm2CompanionProgress: body["growth"]=(bodies[body.id].progress as Sm2CompanionProgress).describe(_progress)
	data["items"]=items.duplicate(true); data["completed"]=completed; data["encounter_count"]=encounters.size()
	if upgrade_supply!=null: data.format="sm2.world.p5.hybrids.1" if hybrid_catalog!=null else "sm2.world.p5.implants.1" if upgrade_catalog.supports_implants() else "sm2.world.p5.upgrades.1"; data["upgrade_supply"]=upgrade_supply.to_data()
	if has_prostheses(): data["prostheses"]=prostheses.items.duplicate(true)
	data["encounter_name"]=encounters[completed].name if completed<encounters.size() else "Все встречи завершены"
	if region!=null:
		data["region"]=region.to_data()
		for body: Dictionary in data.bodies: body["location_id"]=region.bodies[str(body.id)]
	return data

func copy_world() -> Sm2JourneyWorld:
	var value: Sm2JourneyWorld=Sm2JourneyWorld.new(_progress,_definition,_gear,encounters,_initial_loadout,body_catalog,care_catalog,exploration_catalog,psionic_catalog,upgrade_catalog,hybrid_catalog)
	value.region_catalog=region_catalog
	if region!=null: value.region=region.copy()
	if upgrade_supply!=null: value.upgrade_supply=upgrade_supply.copy()
	if exploration!=null: value.exploration=exploration.copy()
	if care!=null: value.care=care.copy()
	value.world_id=world_id; value.revision=revision; value.next_id=next_id
	value.soul.incarnation_id=soul.incarnation_id; value.soul.knowledge=soul.knowledge.duplicate()
	value.incarnations.assign(incarnations.duplicate(true))
	value.item_owner=item_owner; value.battle_started=battle_started; value.receipt=receipt
	value.items.assign(items.duplicate(true)); value.completed=completed
	value.prostheses=prostheses.copy()
	for id: int in bodies:
		var body: Sm2WorldBody=Sm2WorldBody.new()
		body.id=id; body.hp=bodies[id].hp; body.alive=bodies[id].alive; body.death_cause=bodies[id].death_cause; body.drills=bodies[id].drills
		body.progress=Sm2ProgressRules.decode_body(bodies[id].progress.to_data(),_progress).body
		body.upgrades=bodies[id].upgrades.copy() if bodies[id].upgrades!=null else null
		body.functions=bodies[id].functions.copy() if bodies[id].functions!=null else null
		value.bodies[id]=body
	return value

func upgrade_modifiers(id: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if upgrade_catalog!=null and bodies.has(id): result=upgrade_catalog.track_modifiers(bodies[id].upgrades)
	return result

func eligible(id: int) -> String:
	if region!=null and not region.local_owner(id,region_catalog): return "Тело находится в другом месте."
	if bodies.has(id) and bodies[id].upgrades!=null and not bodies[id].upgrades.installed.is_empty(): return "Тело изменено: Душе нужен чистый человек."
	return super.eligible(id)

func validate() -> String:
	if (region_catalog!=null)!=(region!=null): return "region_profile_state"
	if region!=null:
		var region_error: String=region.validate(self)
		if not region_error.is_empty(): return region_error
	if upgrade_catalog!=null:
		if upgrade_supply==null: return "upgrade_supply_missing"
		var upgrade_error: String=upgrade_supply.validate(self)
		if not upgrade_error.is_empty(): return upgrade_error
	else:
		if upgrade_supply!=null: return "unexpected_upgrade_supply"
		for id: int in bodies:
			if bodies[id].upgrades!=null: return "unexpected_body_upgrades"
	if (exploration_catalog!=null)!=(exploration!=null): return "exploration_profile_state"
	if exploration!=null:
		if care_catalog==null or not care_catalog.expandable(): return "exploration_care_profile"
		var exploration_error: String=exploration.validate(exploration_catalog,completed)
		if not exploration_error.is_empty(): return exploration_error
	elif care_catalog!=null and care_catalog.expandable(): return "unexpected_care_capacity"
	if (care_catalog!=null)!=(care!=null): return "care_profile_state"
	if care!=null:
		if not has_prostheses(): return "care_profile_body"
		var reason: String=care.validate(care_catalog)
		if not reason.is_empty(): return reason
	if revision<0 or revision>1000000 or completed<0 or completed>encounters.size() or bodies.size()!=_definition.ids().size() or incarnations.is_empty(): return "journey_world_bounds"
	for id: int in _definition.ids():
		if not bodies.has(id): return "journey_missing_body"
		var body: Sm2WorldBody=bodies[id]
		if body_catalog!=null and (body.functions==null or not Sm2BodyFunctionState.decode(body.functions.to_data(),body_catalog).ok): return "journey_functions_invalid"
		if body_catalog==null and body.functions!=null: return "journey_unexpected_functions"
		if (body.progress is Sm2CompanionProgress)!=(_progress.is_party() and id==4): return "journey_progression_role"
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
	if has_prostheses(): return prostheses.validate(self,ids)
	if not prostheses.items.is_empty(): return "journey_unexpected_prostheses"
	return ""

func _psionic_training(command: Sm2WorldCommand) -> bool:
	if psionic_catalog==null: return false
	if command.kind=="buy_node":
		for id: String in psionic_catalog.ids():
			if psionic_catalog.ability(id).required_node==command.content_id: return true
	if command.kind=="practice":
		var activity: Sm2PracticeDefinition=_progress.activity(command.content_id)
		return activity!=null and activity.awards.size()==1 and activity.awards.has(psionic_catalog.to_data().track_id)
	return false
