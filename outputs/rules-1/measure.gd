extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var c: Dictionary = Sm2EffectContentLoader.load_scenario()
	var b: Sm2TacticalBattle = Sm2TacticalBattle.new(c.catalog,c.combat,true,c.effects)
	if not b.start(Sm2CombatFixtures.setup(c,[2,4],1231)).ok: quit(1); return
	var state: Sm2TacticalState = b.state_copy()
	var actor: Sm2TacticalActor = state.actor(2)
	actor.morale="wavering"
	var effect: Sm2EffectInstance=Sm2EffectInstance.new()
	effect.effect_id=1; effect.target_actor_id=2; effect.definition_id="m4:effect.weakness"
	state.effects[1]=effect
	var samples: Array[Dictionary]=[]
	for round_index: int in 5:
		var start: int=Time.get_ticks_usec()
		for index: int in 1000:
			if legacy(state,actor,c.combat,"melee_skill").value!=54: quit(2); return
		var old_ms: float=(Time.get_ticks_usec()-start)/1000.0
		start=Time.get_ticks_usec()
		for index: int in 1000:
			if Sm2CombatStatQuery.explain(state,actor,c.combat,"melee_skill").value!=54: quit(3); return
		samples.append({"legacy_1000_ms":old_ms,"rules_1000_ms":(Time.get_ticks_usec()-start)/1000.0})
	var report: Dictionary={"samples":samples,"scope":"1000 actual stat queries, one active weakness; legacy formula below versus complete new trace; not full command timing"}
	var file: FileAccess=FileAccess.open("res://outputs/rules-1/measure.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print(JSON.stringify(report)); quit(0)

static func legacy(state: Sm2TacticalState, actor: Sm2TacticalActor, catalog: Sm2CombatCatalog, stat: String) -> Dictionary:
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
