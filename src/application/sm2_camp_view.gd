class_name Sm2CampView
extends RefCounted
## Detached camp data. Viewing a destination never moves the party or advances time.
static func build(session: Sm2JourneySession) -> Dictionary:
	var w: Sm2JourneyWorld=session.journey()
	if w.region==null or w.survival==null or not w.survival.catalog.has_layers(): return {}
	var result: Dictionary={"location":w.region.location_id,"seconds":w.region.seconds,"hero":w.hero_id(),"busy":w.busy(),"places":[],"routes":w.region_catalog.to_data().routes,"party":[],"activities":[],"carriers":[],"knowledge":session.view().knowledge,"completed":w.completed,"total":w.encounters.size()}
	for id: String in w.region_catalog.ids():
		var definition: Dictionary=w.region_catalog.location(id)
		result.places.append({"id":id,"name":definition.name,"description":definition.description,"here":id==w.region.location_id,"visited":id in w.region.visited,"seconds":w.region_catalog.route(w.region.location_id,id),"reason":w.check(session.command("travel",0,id))})
	for id: int in [w.hero_id(),4]:
		if id==0 or not w.bodies.has(id): continue
		if w.busy(): result.party.append({"id":id,"name":"Герой" if id==w.hero_id() else "Спутник"}); continue
		var body: Sm2Anatomy=w.survival.bodies[str(id)]
		var location: String=w.region.bodies[str(id)]
		var damaged: int=0
		for part: String in body.layers:
			if not Sm2SurvivalDevices.working(w.survival,str(id),part): damaged+=1
		result.party.append({"id":id,"name":"Герой" if id==w.hero_id() else "Спутник","alive":w.bodies[id].alive,"blood":body.blood,"blood_max":int(w.survival.catalog.to_data().blood_max),"bleeding":body.rate(),"lost_functions":damaged,"local":location==w.region.location_id,"location":w.region_catalog.location(location).name,"mass":w.survival.inventory.carried_mass(id,w.survival.catalog)})
	if w.busy(): return result
	if w.hero_id()==0:
		for id: int in w.bodies:
			if w.bodies[id].alive or w.region.bodies[str(id)]!=w.region.location_id: continue
			result.carriers.append(action(session,"incarnate",id,"",str(w._definition.body(id).name),"Душа","Новое тело начинает с собственной чистой практикой."))
		return result
	var progress: Sm2ProgressCatalog=session.world._progress
	if w.region_catalog.at("services","practice")==w.region.location_id:
		for id: String in progress.activity_ids():
			var activity: Sm2PracticeDefinition=progress.activity(id); var awards: Array[String]=[]
			for track: String in activity.awards: awards.append("%s +%s XP" % [progress.track(track).title,activity.awards[track]])
			result.activities.append(action(session,"practice",w.hero_id(),id,activity.title,"Упражнения","%s сек · %s" % [activity.seconds,", ".join(awards)]))
	if w.exploration_catalog!=null:
		for id: String in w.exploration_catalog.ids():
			if w.region_catalog.at("sites",id)!=w.region.location_id: continue
			var site: Dictionary=w.exploration_catalog.site(id); var rewards: Array[String]=[]
			for resource: String in site.rewards: rewards.append("%s +%s" % [w.care_catalog.resource(resource).name,int(site.rewards[resource])])
			for track: String in site.get("practice",{}): rewards.append("%s +%s XP" % [progress.track(track).title,int(site.practice[track])])
			result.activities.append(action(session,"explore",0,id,site.name,"Исследование",site.description+"\n%s мин · %s" % [int(site.minutes),", ".join(rewards)]+"\nНаходки остаются на земле, пока вы не заберёте их в контейнер."))
	if w.upgrade_catalog!=null:
		for id: String in w.upgrade_catalog.ids():
			var definition: Dictionary=w.upgrade_catalog.definition(id)
			var effects: Array[String]=[]
			for modifier: Dictionary in definition.modifiers:
				if modifier.kind=="track_bonus": effects.append("%s +%s" % [progress.track(modifier.track_id).title,int(modifier.amount)])
				elif modifier.kind=="psionic_focus_cost": effects.append("+%s концентрации за применение" % int(modifier.amount))
				else: effects.append("+%s усталости за физическую атаку" % int(modifier.amount))
			for entry: Array in [["collect_upgrade","collect",0,"Забрать: "],["apply_upgrade","apply",w.hero_id(),"Применить: "]]:
				if w.region_catalog.upgrade(id,entry[1])!=w.region.location_id: continue
				result.activities.append(action(session,entry[0],entry[2],id,entry[3]+definition.name,"Улучшения тела",", ".join(effects)+"\nУлучшение принадлежит этому телу. Расходник тратится при применении."))
	var groups: Dictionary={}
	for row: Dictionary in result.activities:
		if not groups.has(row.group): groups[row.group]=groups.size()
	result.activities.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if a.group!=b.group: return int(groups[a.group])<int(groups[b.group])
		if str(a.reason).is_empty()!=str(b.reason).is_empty(): return str(a.reason).is_empty()
		return str(a.title).naturalnocasecmp_to(str(b.title))<0)
	return result

static func action(s: Sm2JourneySession,kind: String,target: int,id: String,title: String,group: String,description: String) -> Dictionary:
	return {"kind":kind,"target":target,"content":id,"title":title,"group":group,"description":description,"reason":s.world.check(s.command(kind,target,id))}
