class_name Sm2CharacterView
extends RefCounted
## Detached character overview. Resolves attributes only, never the full skill tree.
static func build(session: Sm2JourneySession, body_id: int) -> Dictionary:
	var w: Sm2JourneyWorld=session.journey()
	var result: Dictionary={"message":"","attributes":[],"upgrades":[],"companion":{},"incarnation":w.soul.incarnation_id,"hero":w.hero_id(),"body_id":body_id}
	if w.busy(): result.message="Идёт сражение. Осмотр доступен после боя."; return result
	if body_id==0 or not w.bodies.has(body_id): result.message="Душа без тела. Выберите новое воплощение в разделе «Душа»."; return result
	var body: Sm2ProgressBodyState=w.bodies[body_id].progress
	var modifiers: Array[Dictionary]=w.upgrade_modifiers(body_id)
	if body is Sm2CompanionProgress: result.companion=(body as Sm2CompanionProgress).describe(w._progress)
	for row: Dictionary in w._progress.track_summaries():
		if row.kind=="attribute": result.attributes.append(Sm2ProgressRules.track(body,w._progress,row.id,modifiers))
	if w.upgrade_catalog!=null:
		for id: String in w.bodies[body_id].upgrades.installed:
			var definition: Dictionary=w.upgrade_catalog.definition(id)
			var effects: Array[String]=[]
			for modifier: Dictionary in definition.modifiers:
				match str(modifier.kind):
					"track_bonus": effects.append("%s +%s" % [w._progress.track(modifier.track_id).title,int(modifier.amount)])
					"psionic_focus_cost": effects.append("Расход концентрации: +%s за применение" % int(modifier.amount))
					"physical_attack_fatigue": effects.append("Усталость за физическую атаку: +%s" % int(modifier.amount))
			result.upgrades.append({"id":id,"name":definition.name,"path":definition.path,"effects":effects})
	return result
