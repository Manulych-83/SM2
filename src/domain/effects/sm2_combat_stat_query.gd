class_name Sm2CombatStatQuery
extends RefCounted
static func explain(state: Sm2TacticalState, actor: Sm2TacticalActor, catalog: Sm2CombatCatalog, stat: String) -> Dictionary:
	var profile: Sm2CombatProfile = catalog.profile(actor.loadout_id)
	var base: int = int(profile.get(stat))
	var flat: int = 0
	var sources: Array[Dictionary] = []
	var modifiers: Array[Dictionary] = []
	var effect_names: Dictionary = {}
	if state.development != null:
		var development_bonus: int = state.development.stat_bonus(actor.spatial.actor_id,stat)
		flat += development_bonus
		if development_bonus != 0:
			sources.append({"kind":"development","amount":development_bonus})
			modifiers.append({"source":"development","operation":"add","amount":development_bonus})
	if state.effect_catalog != null:
		for id: int in state.sorted_effect_ids():
			var instance: Sm2EffectInstance = state.effects[id]
			if instance.target_actor_id != actor.spatial.actor_id: continue
			var definition: Sm2EffectDefinition = state.effect_catalog.definition(instance.definition_id)
			for op: Sm2EffectOperation in definition.operations:
				if op.kind == "flat_stat_modifier" and op.stat == stat:
					flat += op.amount
					sources.append({"effect_id":str(id),"definition_id":instance.definition_id,"amount":op.amount})
					var source: String = "effect:"+str(id)
					effect_names[source] = definition.name
					modifiers.append({"source":source,"operation":"add","amount":op.amount})
	var percent: int = 90 if actor.morale == "wavering" else (80 if actor.morale == "breaking" else 100)
	modifiers.append({"source":"nonnegative","operation":"minimum","amount":0})
	modifiers.append({"source":"morale","operation":"scale_percent","amount":percent})
	modifiers.append({"source":"fleeing_defense","operation":"set","amount":0,"when":{"kind":"all","children":[
		{"kind":"compare","fact":"fleeing","op":"eq","value":true,"reason":"not_fleeing"},
		{"kind":"compare","fact":"defense","op":"eq","value":true,"reason":"not_defense"}]}})
	var calculation: Dictionary = Sm2ModifierPipeline.evaluate(base,modifiers,{"fleeing":actor.morale=="fleeing","defense":stat.ends_with("defense")})
	assert(calculation.valid,"Validated combat stats exceeded modifier contract: "+str(calculation.reason))
	return {"base":base,"flat":flat,"morale_percent":percent,"value":calculation.value,"sources":sources,"steps":calculation.steps,"effect_names":effect_names}
