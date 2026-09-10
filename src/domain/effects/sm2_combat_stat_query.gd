class_name Sm2CombatStatQuery
extends RefCounted
static func explain(state: Sm2TacticalState, actor: Sm2TacticalActor, catalog: Sm2CombatCatalog, stat: String) -> Dictionary:
	var profile: Sm2CombatProfile = catalog.profile(actor.loadout_id)
	var base: int = int(profile.get(stat))
	var flat: int = 0
	var sources: Array[Dictionary] = []
	if state.development != null:
		var development_bonus: int = state.development.stat_bonus(actor.spatial.actor_id,stat)
		flat += development_bonus
		if development_bonus != 0: sources.append({"kind":"development","amount":development_bonus})
	if state.effect_catalog != null:
		for id: int in state.sorted_effect_ids():
			var instance: Sm2EffectInstance = state.effects[id]
			if instance.target_actor_id != actor.spatial.actor_id: continue
			for op: Sm2EffectOperation in state.effect_catalog.definition(instance.definition_id).operations:
				if op.kind == "flat_stat_modifier" and op.stat == stat:
					flat += op.amount
					sources.append({"effect_id":str(id),"definition_id":instance.definition_id,"amount":op.amount})
	var percent: int = 90 if actor.morale == "wavering" else (80 if actor.morale == "breaking" else 100)
	@warning_ignore("integer_division")
	var result: int = maxi(0,base+flat) * percent / 100
	if stat.ends_with("defense") and actor.morale == "fleeing": result = 0
	return {"base":base,"flat":flat,"morale_percent":percent,"value":result,"sources":sources}
