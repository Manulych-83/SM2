class_name Sm2JourneyGuideView
extends RefCounted
## A recommendation derived from the current world, never a second quest state.
static func build(session: Sm2JourneySession) -> Dictionary:
	var w: Sm2JourneyWorld=session.journey()
	if w.survival==null or not w.survival.catalog.has_layers(): return {}
	var result: Dictionary={"stage":"prepare","completed":w.completed,"total":w.encounters.size(),"location":w.region_catalog.location(w.region.location_id).name,"actions":[],"facts":[],"body":w.hero_id()}
	if w.busy():
		result.stage="battle"; result.actions.append(link("resume","Вернуться в бой")); return result
	if w.hero_id()==0:
		result.stage="soul"
		for id: int in w.bodies:
			if w.region.bodies[str(id)]!=w.region.location_id: continue
			var row: Dictionary=action(session,"incarnate",id,"",str(w._definition.body(id).name))
			if row.reason.is_empty(): result.actions.append(row)
		if result.actions.is_empty(): result.facts.append("Подходящих носителей здесь больше нет. Доступные тела в этом примере конечны.")
		return result
	for id: int in [w.hero_id(),4]:
		if not w.bodies[id].alive: continue
		var body: Sm2Anatomy=w.survival.bodies[str(id)]
		if body.rate()>0:
			result.stage="bleeding"; result.body=id
			result.facts.append("%s: кровотечение %s мл/мин." % ["Герой" if id==w.hero_id() else "Спутник",body.rate()])
			result.actions.append(link("body","Открыть раны",id)); return result
	var ground: int=0
	for id: String in w.survival.inventory.ids():
		var item: Dictionary=w.survival.inventory.items[id]
		if item.place=="ground" and item.holder==w.region.location_id and int(w.survival.catalog.item(item.definition_id).capacity)==0: ground+=1
	if ground>0: result.facts.append("Предметов на земле: %s. Они останутся здесь, если не положить их в контейнер." % ground)
	result.actions.append(link("inventory","Снаряжение и припасы",w.hero_id()))
	result.actions.append(link("development","Развитие героя"))
	if w.completed>=w.encounters.size(): result.stage="complete"
	elif w.region.location_id=="camp": result.stage="develop" if w.completed>0 else "prepare"
	elif w.region.location_id=="ruins":
		result.stage="ruins"
		if ground>0: result.stage="carry"
		else:
			for id: String in w.exploration_catalog.ids():
				var row: Dictionary=action(session,"explore",0,id,"Осмотреть: "+str(w.exploration_catalog.site(id).name))
				if row.reason.is_empty():
					result.stage="explore"; result.actions.push_front(row); break
	else: result.stage="enclave"
	if w.completed<w.encounters.size():
		var place: String=w.region_catalog.at("encounters",str(w.completed))
		if place==w.region.location_id:
			result.actions.append(action(session,"start_battle",0,"","Войти в сражение"))
		else:
			result.actions.append(action(session,"travel",0,place,"В путь: "+str(w.region_catalog.location(place).name)))
	if w.region.location_id!="camp": result.actions.append(action(session,"travel",0,"camp","Вернуться в лагерь"))
	return result

static func link(id: String,title: String,body: int=0) -> Dictionary:
	return {"link":id,"title":title,"body":body,"reason":""}

static func action(session: Sm2JourneySession,kind: String,target: int,id: String,title: String) -> Dictionary:
	var c: Sm2WorldCommand=session.command(kind,target,id)
	return {"kind":kind,"target":target,"content":id,"title":title,"reason":session.world.check(c)}

static func feedback(kind: String,before: Dictionary,after: Dictionary) -> String:
	if kind=="travel": return "Переход завершён. Переносимые вещи прибыли с отрядом; вещи на земле остались на прежнем месте."
	if kind=="explore":
		var added: int=after.survival.inventory.items.size()-before.survival.inventory.items.size()
		return "Осмотр завершён. Найдено предметов: %s. Откройте инвентарь и положите находки с земли в переносимый контейнер. Практика поиска начислена герою." % added
	return "Действие выполнено."
