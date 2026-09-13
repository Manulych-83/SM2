class_name Sm2ExpeditionView
extends RefCounted
## Reconstruct once per changed capture; a completion is a fact of history, not UI state.
var _key: String=""
var _cached: Dictionary={}

func build(session: Sm2JourneySession) -> Dictionary:
	var projected: Variant=session.checkpoint_projection("expedition")
	if projected!=null: return projected
	var world: Sm2JourneyWorld=session.journey()
	var brief: Dictionary=Sm2ExpeditionBrief.load_for(world)
	if brief.is_empty(): return {"ok":false}
	var key: String=Sm2Canonical.hash([session.capture(),brief])
	if key==_key: return _cached.duplicate(true)
	var state: Dictionary={"ids":[],"old_ids":[],"old_hero":0,"old_xp":{},"old_companion":0,"gained":{},"companion_xp":0,"battle":{},"summary":{},"started":-1}
	var valid: bool=Sm2JourneyHistoryReader.visit(session,func(shadow: Sm2JourneySession,entry: Dictionary,index: int,after: bool) -> void:
		observe(shadow,entry,index,after,brief,state))
	if not valid: return {"ok":false}
	var result: Dictionary=from_state(session,state,brief)
	_key=key; _cached=result.duplicate(true)
	return result

static func from_state(session: Sm2JourneySession,state: Dictionary,brief: Dictionary) -> Dictionary:
	var world: Sm2JourneyWorld=session.journey()
	var deposited: int=stored(world,state.ids,brief)
	var result: Dictionary={"ok":true,"brief":brief,"world_id":world.world_id,"revision":world.revision,"ids":state.ids.duplicate(),"found":not state.ids.is_empty(),"encounter_done":not state.battle.is_empty(),"deposited":deposited,"summary":state.summary.duplicate(true),"complete":not state.summary.is_empty(),"steps":[],"actions":[],"facts":[],"stage":"prepare"}
	result["finds"]=[]
	for id: String in state.ids:
		var place: String=item_location(world,id)
		result.finds.append({"id":id,"location":place,"where":world.region_catalog.location(place).get("name","Недоступен"),"delivered":stored(world,[id],brief)==1})
	result.steps=[{"done":not state.battle.is_empty(),"text":"Пройти встречу: "+str(world.encounters[brief.encounter].name)}, {"done":not state.ids.is_empty(),"text":"Найти медикаменты в санитарной сумке"}, {"done":result.complete or deposited>=int(brief.quantity),"text":"Доставить в сундук лагеря: %s/%s" % [int(brief.quantity) if result.complete else deposited,brief.quantity]}]
	if result.complete: result.stage="complete"
	else: next_step(session,result,state)
	return result

static func observe(shadow: Sm2JourneySession, entry: Dictionary, index: int, after: bool, brief: Dictionary, state: Dictionary) -> void:
	if not state.summary.is_empty(): return
	var world: Sm2JourneyWorld=shadow.journey()
	var command: Dictionary=entry.get("command",{})
	if not after:
		state.old_ids=world.survival.inventory.ids(); state.old_hero=world.hero_id(); state.old_xp={}
		if state.old_hero!=0:
			for id: String in world.bodies[state.old_hero].progress.tracks: state.old_xp[id]=world.bodies[state.old_hero].progress.tracks[id].earned
		state.old_companion=(world.bodies[4].progress as Sm2CompanionProgress).earned
		if state.started<0 and command.get("kind")=="travel" and command.get("content_id")==brief.source_location: state.started=world.region.seconds
		return
	if state.old_hero!=0:
		for id: String in state.old_xp:
			var delta: int=world.bodies[state.old_hero].progress.tracks[id].earned-int(state.old_xp[id])
			if delta>0: state.gained[id]=int(state.gained.get(id,0))+delta
	state.companion_xp+=(world.bodies[4].progress as Sm2CompanionProgress).earned-int(state.old_companion)
	if command.get("kind")=="explore" and command.get("content_id")==brief.site and world.region.location_id==brief.source_location:
		var definition: String=world.survival.catalog.to_data().supplies.care[brief.resource]
		for id: String in world.survival.inventory.ids():
			if id not in state.old_ids and world.survival.inventory.items[id].definition_id==definition: state.ids.append(id)
	if entry.kind=="outcome" and world.completed==int(brief.encounter)+1:
		state.battle=Sm2BattleResultsView.build(shadow)
	if state.ids.size()!=int(brief.quantity) or state.battle.is_empty() or world.busy() or world.hero_id()==0 or world.region.location_id!=brief.home: return
	if stored(world,state.ids,brief)!=int(brief.quantity): return
	for id: int in [world.hero_id(),4]:
		if world.bodies[id].alive and world.survival.bodies[str(id)].rate()>0: return
	var practice: Array=[]
	for id: String in state.gained: practice.append({"title":world._progress.track(id).title,"xp":state.gained[id]})
	state.summary={"event":index,"seconds":world.region.seconds,"elapsed":world.region.seconds-maxi(0,int(state.started)),"battle":state.battle.duplicate(true),"party":Sm2CampView.build(shadow).party,"practice":practice,"companion_xp":state.companion_xp,"incarnation":world.incarnations.size(),"items":state.ids.duplicate()}

static func stored(world: Sm2JourneyWorld, ids: Array, brief: Dictionary) -> int:
	var inventory: Sm2PhysicalInventory=world.survival.inventory
	var count: int=0
	for id: String in ids:
		var item: Dictionary=inventory.items.get(id,{})
		if item.get("place")!="container": continue
		var container: Dictionary=inventory.items.get(item.holder,{})
		if container.get("definition_id")=="stash" and container.get("place")=="ground" and container.get("holder")==brief.home: count+=1
	return count

static func next_step(session: Sm2JourneySession, view: Dictionary, state: Dictionary) -> void:
	var world: Sm2JourneyWorld=session.journey(); var brief: Dictionary=view.brief
	var guide: Dictionary=Sm2JourneyGuideView.build(session)
	if guide.stage in ["battle","soul","bleeding"]:
		view.stage=guide.stage; view.actions=guide.actions; view.facts=guide.facts; return
	view.actions.append(Sm2JourneyGuideView.link("inventory","Открыть снаряжение и припасы",world.hero_id()))
	if not view.encounter_done:
		view.stage="battle_ready" if world.region.location_id==brief.source_location else "prepare"
		view.actions.append(Sm2JourneyGuideView.action(session,"start_battle" if world.region.location_id==brief.source_location else "travel",0,"" if world.region.location_id==brief.source_location else str(brief.source_location),"Первая встреча" if world.region.location_id==brief.source_location else "Отправиться в руины"))
	elif not view.found:
		view.stage="search"
		view.actions.append(Sm2JourneyGuideView.action(session,"explore" if world.region.location_id==brief.source_location else "travel",0,str(brief.site) if world.region.location_id==brief.source_location else str(brief.source_location),"Осмотреть санитарную сумку" if world.region.location_id==brief.source_location else "Вернуться в руины"))
	else:
		var carried: int=0; var elsewhere: int=0; var missing_place: String=""
		for id: String in state.ids:
			if not world.survival.inventory.items.has(id): elsewhere+=1; continue
			if world.survival.inventory.owner(id) in [world.hero_id(),4] and world.bodies[world.survival.inventory.owner(id)].alive: carried+=1
			elif stored(world,[id],brief)==0 and item_location(world,id)!=world.region.location_id: missing_place=item_location(world,id)
		view.stage="deposit" if world.region.location_id==brief.home else "return" if carried+int(view.deposited)==int(brief.quantity) else "pickup"
		view.facts.append("Нужные находки при живом отряде: %s; в сундуке: %s. Стартовые запасы не учитываются." % [carried,view.deposited])
		if elsewhere>0: view.facts.append("Часть нужных находок недоступна. Итог не будет засчитан без доставки всех экземпляров.")
		if world.region.location_id!=brief.home: view.actions.append(Sm2JourneyGuideView.action(session,"travel",0,str(brief.home),"Вернуться в лагерь"))
		if not missing_place.is_empty(): view.actions.append(Sm2JourneyGuideView.action(session,"travel",0,missing_place,"Забрать находки: "+str(world.region_catalog.location(missing_place).name)))

static func item_location(world: Sm2JourneyWorld,id: String) -> String:
	var inventory: Sm2PhysicalInventory=world.survival.inventory
	if not inventory.items.has(id): return ""
	var owner: int=inventory.owner(id)
	if owner!=0: return world.region.bodies.get(str(owner),"")
	var item: Dictionary=inventory.items[id]
	if item.place=="ground": return str(item.holder)
	if item.place=="container": return str(inventory.items[item.holder].holder)
	return ""
