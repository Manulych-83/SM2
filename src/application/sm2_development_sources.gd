class_name Sm2DevelopmentSources
extends RefCounted
## Read-only explanations of authored XP sources and the separate companion model.
static func build(session: Sm2LifeSession,track_id: String) -> Dictionary:
	var result: Dictionary={"practice":[],"companion":{},"message":""}
	var world: Sm2LifeWorld=session.world
	if world.busy(): result.message="Развитие доступно после завершения боя."; return result
	var development: Sm2DevelopmentCatalog=session._content.development
	var catalog: Sm2ProgressCatalog=world._progress
	for body_id: int in world.bodies:
		var state: Sm2ProgressBodyState=world.bodies[body_id].progress
		if not state is Sm2CompanionProgress: continue
		var companion: Sm2CompanionProgress=state as Sm2CompanionProgress
		var data: Dictionary=companion.describe(catalog)
		data.merge({"body_id":body_id,"alive":world.bodies[body_id].alive,"attributes":companion.attributes(catalog),"attack_xp":catalog.companion_growth().attack_xp,"melee_per_level":catalog.companion_growth().melee_per_level})
		for row: Dictionary in data.attributes:
			for rule: Dictionary in catalog.companion_growth().attributes:
				if row.id==rule.track_id: row["per_level"]=rule.per_level
		result.companion=data; break
	if world.hero_id()==0 or catalog.track(track_id)==null: return result
	for id: String in catalog.activities_for_track(track_id):
		var activity: Sm2PracticeDefinition=catalog.activity(id)
		if not activity.awards.has(track_id): continue
		var reason: String=world.check(session.command("practice",world.hero_id(),id))
		result.practice.append({"kind":"practice","id":id,"name":activity.title,"xp":activity.awards[track_id],"seconds":activity.seconds,"reason":reason})
	for id: String in development.ability_ids():
		var awards: Dictionary=development.awards(id)
		if not awards.has(track_id): continue
		var name: String=""; var required: String=""
		if development.has_psionics():
			var ability: Dictionary=development.psionics().ability(id)
			if not ability.is_empty(): name=ability.name; required=ability.required_node
		if development.has_hybrids():
			var ability: Dictionary=development.hybrids().ability(id)
			if not ability.is_empty(): name=ability.name; required=ability.required_node
		var reason: String="Условия выполнения проверяются в бою."
		if not required.is_empty():
			var node: Sm2ProgressNodeDefinition=catalog.node(required)
			if required not in world.bodies[world.hero_id()].progress.tracks[node.track_id].nodes: reason="Сначала изучите «%s»." % node.title
		result.practice.append({"kind":"combat","id":id,"name":name,"xp":awards[track_id],"seconds":0,"reason":reason})
	if world is Sm2JourneyWorld:
		var journey: Sm2JourneyWorld=world as Sm2JourneyWorld
		if journey.exploration_catalog!=null:
			for id: String in journey.exploration_catalog.ids():
				var site: Dictionary=journey.exploration_catalog.site(id)
				if not site.get("practice",{}).has(track_id): continue
				result.practice.append({"kind":"explore","id":id,"name":site.name,"xp":site.practice[track_id],"seconds":int(site.minutes)*60,"reason":world.check(session.command("explore",0,id))})
	return result
