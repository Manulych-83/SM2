class_name Sm2HeroDevelopmentView
extends RefCounted
## Detached presentation data. Availability comes from the same world command check.
static func build(session: Sm2LifeSession, selected_id: String="") -> Dictionary:
	var world: Sm2LifeWorld=session.world
	var hero: int=world.hero_id()
	var result: Dictionary={"hero_id":hero,"tracks":[],"selected":{},"nodes":[],"links":[],"context":{"world_id":world.world_id,"revision":world.revision,"incarnation_id":world.soul.incarnation_id,"body_id":hero},"message":""}
	if hero==0:
		result.message="Душа без тела. Вернитесь в лагерь и выберите новое воплощение."; return result
	if world.busy():
		result.message="Идёт сражение. Вернитесь к развитию героя после его завершения."; return result
	var progress: Sm2ProgressCatalog=session._content.development.progression()
	var body: Sm2ProgressBodyState=world.bodies[hero].progress
	var modifiers: Array[Dictionary]=(world as Sm2JourneyWorld).upgrade_modifiers(hero) if world is Sm2JourneyWorld else []
	result.tracks=Sm2ProgressRules.tracks(body,progress,modifiers)
	if progress.track(selected_id)==null: selected_id=progress.track_ids()[0]
	for row: Dictionary in result.tracks:
		if row.id==selected_id: result.selected=row.duplicate(true)
	for contribution: Dictionary in progress.contributions():
		if selected_id not in [contribution.source,contribution.target]: continue
		result.links.append({"source":contribution.source,"source_name":progress.track(contribution.source).title,"target":contribution.target,"target_name":progress.track(contribution.target).title,"numerator":contribution.numerator,"denominator":contribution.denominator})
	var definitions: Dictionary[String,Sm2ProgressNodeDefinition]={}
	var dependents: Dictionary={}; var places: Dictionary={}
	for id: String in progress.node_ids():
		var definition: Sm2ProgressNodeDefinition=progress.node(id); definitions[id]=definition
		for prerequisite: String in definition.requires:
			if not dependents.has(prerequisite): dependents[prerequisite]=[]
			dependents[prerequisite].append({"id":id,"name":definition.title,"track_id":definition.track_id})
	if world is Sm2JourneyWorld:
		var journey: Sm2JourneyWorld=world as Sm2JourneyWorld
		if journey.exploration_catalog!=null:
			for site_id: String in journey.exploration_catalog.ids():
				var site: Dictionary=journey.exploration_catalog.site(site_id)
				for node_id: String in site.get("required_nodes",[]):
					if not places.has(node_id): places[node_id]=[]
					places[node_id].append("Условие доступа к месту: "+str(site.name)+". Остальные условия осмотра сохраняются.")
	for id: String in definitions:
		var node: Sm2ProgressNodeDefinition=definitions[id]
		if node.track_id!=selected_id: continue
		var owned: bool=id in body.tracks[selected_id].nodes
		var reason: String=world.check(session.command("buy_node",hero,id))
		var row: Dictionary={"id":id,"name":node.title,"track_id":node.track_id,"cost":node.cost,"min_level":node.min_level,"owned":owned,"allowed":reason.is_empty(),"reason":reason_text(reason),"requires":[],"unlocks":[],"effects":[]}
		row["extra_requirements"]=[]; row["extra_costs"]=[]
		for requirement: Dictionary in node.extra_requirements:
			row.extra_requirements.append({"track_id":requirement.track_id,"name":progress.track(requirement.track_id).title,"level":progress.track(requirement.track_id).describe(body.tracks[requirement.track_id].earned).level,"min_level":requirement.min_level})
		for price: Dictionary in node.extra_costs:
			row.extra_costs.append({"track_id":price.track_id,"name":progress.track(price.track_id).title,"cost":price.amount,"available":body.tracks[price.track_id].earned-body.tracks[price.track_id].spent})
		for prerequisite: String in node.requires:
			var needed: Sm2ProgressNodeDefinition=definitions[prerequisite]
			row.requires.append({"id":needed.id,"name":needed.title,"track_id":needed.track_id,"owned":needed.id in body.tracks[needed.track_id].nodes})
		row.unlocks=dependents.get(id,[]).duplicate(true)
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
