class_name Sm2HeroDevelopmentView
extends RefCounted
## Detached presentation data. Availability comes from the same world command check.
const PAGE_SIZE: int=24
const LINK_SIZE: int=12

static func build(session: Sm2LifeSession, selected_id: String="", options: Dictionary={}) -> Dictionary:
	var world: Sm2LifeWorld=session.world
	var hero: int=world.hero_id()
	var result: Dictionary={"hero_id":hero,"tracks":[],"selected":{},"nodes":[],"links":[],"context":{"world_id":world.world_id,"revision":world.revision,"incarnation_id":world.soul.incarnation_id,"body_id":hero},"message":""}
	result.merge({"node_count":0,"node_page":0,"node_pages":1,"link_count":0,"link_page":0,"link_pages":1})
	if hero==0:
		result.message="Душа без тела. Вернитесь в лагерь и выберите новое воплощение."; return result
	if world.busy():
		result.message="Идёт сражение. Вернитесь к развитию героя после его завершения."; return result
	var progress: Sm2ProgressCatalog=session.world._progress
	var body: Sm2ProgressBodyState=world.bodies[hero].progress
	var modifiers: Array[Dictionary]=(world as Sm2JourneyWorld).upgrade_modifiers(hero) if world is Sm2JourneyWorld else []
	result.tracks=progress.track_summaries() if options.get("compact_tracks",false) else Sm2ProgressRules.tracks(body,progress,modifiers)
	if progress.track(selected_id)==null: selected_id=progress.track_ids()[0]
	result.selected=Sm2ProgressRules.track(body,progress,selected_id,modifiers)
	var relations: Array=progress.related_contributions(selected_id)
	result.link_count=relations.size(); result.link_pages=maxi(1,ceili(float(relations.size())/LINK_SIZE))
	result.link_page=clampi(int(options.get("link_page",0)),0,result.link_pages-1)
	for contribution: Dictionary in relations.slice(result.link_page*LINK_SIZE,(result.link_page+1)*LINK_SIZE):
		result.links.append({"source":contribution.source,"source_name":progress.track(contribution.source).title,"target":contribution.target,"target_name":progress.track(contribution.target).title,"numerator":contribution.numerator,"denominator":contribution.denominator})
	var places: Dictionary={}
	if world is Sm2JourneyWorld:
		var journey: Sm2JourneyWorld=world as Sm2JourneyWorld
		if journey.exploration_catalog!=null:
			for site_id: String in journey.exploration_catalog.ids():
				var site: Dictionary=journey.exploration_catalog.site(site_id)
				for node_id: String in site.get("required_nodes",[]):
					if not places.has(node_id): places[node_id]=[]
					places[node_id].append("Условие доступа к месту: "+str(site.name)+". Остальные условия осмотра сохраняются.")
	var ids: Array=[]; var reasons: Dictionary={}
	var filter: int=int(options.get("filter",0))
	var query: String=str(options.get("query","")).strip_edges().to_lower()
	for id: String in progress.nodes_for_track(selected_id):
		if filter==2 and not body.tracks[selected_id].owns(id): continue
		if not query.is_empty() and not progress.node(id).title.to_lower().contains(query): continue
		if filter==1:
			reasons[id]=world.check(session.command("buy_node",hero,id))
			if not str(reasons[id]).is_empty(): continue
		ids.append(id)
	result.node_count=ids.size(); result.node_pages=maxi(1,ceili(float(ids.size())/PAGE_SIZE))
	result.node_page=clampi(int(options.get("page",0)),0,result.node_pages-1)
	var focus: int=ids.find(str(options.get("focus","")))
	if focus>=0: result.node_page=floori(float(focus)/PAGE_SIZE)
	for id: String in ids.slice(result.node_page*PAGE_SIZE,(result.node_page+1)*PAGE_SIZE):
		var node: Sm2ProgressNodeDefinition=progress.node(id)
		var owned: bool=body.tracks[selected_id].owns(id)
		var reason: String=str(reasons[id]) if reasons.has(id) else world.check(session.command("buy_node",hero,id))
		var row: Dictionary={"id":id,"name":node.title,"track_id":node.track_id,"cost":node.cost,"min_level":node.min_level,"owned":owned,"allowed":reason.is_empty(),"reason":reason_text(reason),"requires":[],"unlocks":[],"effects":[]}
		row["extra_requirements"]=[]; row["extra_costs"]=[]
		for requirement: Dictionary in node.extra_requirements:
			row.extra_requirements.append({"track_id":requirement.track_id,"name":progress.track(requirement.track_id).title,"level":progress.track(requirement.track_id).describe(body.tracks[requirement.track_id].earned).level,"min_level":requirement.min_level})
		for price: Dictionary in node.extra_costs:
			row.extra_costs.append({"track_id":price.track_id,"name":progress.track(price.track_id).title,"cost":price.amount,"available":body.tracks[price.track_id].earned-body.tracks[price.track_id].spent})
		for kind: String in ["requires","unlocks"]:
			var related: Array=node.requires if kind=="requires" else progress.dependents(id)
			var pages: int=maxi(1,ceili(float(related.size())/LINK_SIZE))
			var page: int=clampi(int(options.get("link_offsets",{}).get(id+"/"+kind,0)),0,pages-1)
			row[kind+"_count"]=related.size(); row[kind+"_page"]=page; row[kind+"_pages"]=pages
			for related_id: String in related.slice(page*LINK_SIZE,(page+1)*LINK_SIZE):
				var needed: Sm2ProgressNodeDefinition=progress.node(related_id)
				row[kind].append({"id":needed.id,"name":needed.title,"track_id":needed.track_id,"owned":body.tracks[needed.track_id].owns(needed.id)})
		if node.bonus>0: row.effects.append("+%s к значению направления «%s». Это прибавка узла, не заработанный опыт." % [node.bonus,progress.track(node.track_id).title])
		row.effects.append_array(places.get(id,[]))
		if session._content.development.has_psionics():
			var psi: Sm2PsionicCatalog=session._content.development.psionics()
			for ability_id: String in psi.ids():
				var ability: Dictionary=psi.ability(ability_id)
				if ability.required_node!=id: continue
				if world is Sm2JourneyWorld and (world as Sm2JourneyWorld).upgrade_catalog!=null:
					var cost: Dictionary=Sm2PsionicCostQuery.resolve(int(ability.concentration_cost),(world as Sm2JourneyWorld).upgrade_catalog,world.bodies[hero].upgrades)
					ability.concentration_cost=cost.total
					for source: Dictionary in cost.sources: row.effects.append("%s: +%s к расходу концентрации; базовый расход %s, итоговый %s." % [source.name,source.amount,cost.base,cost.total])
				if ability.get("operation")=="self_barrier":
					row.effects.append("Пси-щит на себя: %s ОД, %s концентрации. До начала следующего хода; повтор обновляет защиту. После брони, против атак; яд проходит." % [ability.ap_cost,ability.concentration_cost])
					row.effects.append(Sm2AbilityParameterText.describe(psi.capacity(ability_id,body,progress,modifiers),"Защита","защиты","защиты"))
					row.effects.append("За применение: Псионика +%s XP, Резонанс +%s XP." % [ability.practice_xp,ability.additional_awards["p4a:stat.resonance"]])
				elif psi.grows():
					row.effects.append("Открывает в бою: %s. %s ОД, %s концентрации; дальность %s–%s. Только видимый противник." % [ability.name,ability.ap_cost,ability.concentration_cost,ability.range_min,ability.range_max])
					row.effects.append(Sm2AbilityParameterText.describe(psi.damage(ability_id,body,progress,modifiers)))
					var awards: Array[String]=[]
					for track_id: String in psi.awards(ability_id): awards.append("%s +%s XP" % [progress.track(track_id).title,psi.awards(ability_id)[track_id]])
					row.effects.append("За применение: "+", ".join(awards)+".")
				else:
					row.effects.append("Открывает в бою: %s. %s ОД, %s концентрации; дальность %s–%s; %s урона HP. Только противник, прямая видимость. За применение: %s опыта Псионики." % [ability.name,ability.ap_cost,ability.concentration_cost,ability.range_min,ability.range_max,ability.damage,ability.practice_xp])
		if session._content.development.has_hybrids():
			var hybrid: Sm2HybridCatalog=session._content.development.hybrids()
			for ability_id: String in hybrid.ids():
				var ability: Dictionary=hybrid.ability(ability_id)
				if ability.required_node!=id: continue
				var attack: Sm2CombatAbility=session._content.combat.ability(ability.base_attack)
				var price: Dictionary=Sm2PsionicCostQuery.resolve(int(ability.concentration_cost),(world as Sm2JourneyWorld).upgrade_catalog,world.bodies[hero].upgrades)
				row.effects.append("Удар экипированным мечом: %s ОД, обычная усталость атаки и %s концентрации. Усиливает только попадание; автоматический ответный удар остаётся обычным." % [attack.ap_cost,price.total])
				row.effects.append(Sm2AbilityParameterText.describe(hybrid.damage(ability_id,body,progress,modifiers),"Пси-урон","урона","урона"))
				row.effects.append("Пси-часть обходит броню; пси-щит поглощает общий урон. При промахе урона нет, затраты и практика сохраняются.")
				var awards: Array[String]=[]
				for track_id: String in ability.awards: awards.append("%s +%s XP" % [progress.track(track_id).title,ability.awards[track_id]])
				row.effects.append("За приём: "+", ".join(awards)+".")
		if row.effects.is_empty(): row.effects.append("Для этого узла нет описанного числового эффекта или места доступа.")
		result.nodes.append(row)
	return result

static func reason_text(reason: String) -> String:
	return {"node_owned":"Уже изучено этим телом.","level_required":"Недостаточно собственного уровня.","prerequisite_required":"Сначала изучите требуемые узлы.","experience_required":"Недостаточно доступного опыта для оплаты узла.","node_missing":"Узел не найден.","companion_automatic_growth":"Спутник развивается автоматически."}.get(reason,reason)

static func track_details(session: Sm2LifeSession,id: String) -> Dictionary:
	var world: Sm2LifeWorld=session.world
	if world.busy() or world.hero_id()==0 or world._progress.track(id)==null: return {}
	var modifiers: Array[Dictionary]=(world as Sm2JourneyWorld).upgrade_modifiers(world.hero_id()) if world is Sm2JourneyWorld else []
	return Sm2ProgressRules.track(world.bodies[world.hero_id()].progress,world._progress,id,modifiers)
