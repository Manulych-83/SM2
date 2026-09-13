extends RefCounted
const EFFECTS = preload("res://tests/scenarios/test_m4_effects.gd")

static func run(t: Sm2TestHarness) -> void:
	_conditions(t)
	_modifiers(t)
	_live(t)
	t.complete_suite("rules")

static func _compare(fact: String, op: String, value: Variant, reason: String = "requirement") -> Dictionary:
	return {"kind":"compare","fact":fact,"op":op,"value":value,"reason":reason}

static func _conditions(t: Sm2TestHarness) -> void:
	var rule: Dictionary = {"kind":"all","children":[
		_compare("practice","gte",10,"practice_required"),
		{"kind":"any","children":[{"kind":"tag","fact":"equipment","tag":"weapon.melee","reason":"melee_required"},_compare("unarmed","eq",true)]},
		{"kind":"not","child":_compare("blocked","eq",true),"reason":"blocked"}]}
	var facts: Dictionary = {"practice":10,"equipment":["weapon.melee.sword"],"unarmed":false,"blocked":false}
	var original: Dictionary = facts.duplicate(true)
	t.expect(Sm2RuleCondition.evaluate(rule,facts).matches,"data composes numeric, hierarchical tag, any and not")
	t.equal(facts,original,"conditions do not write context")
	facts.practice = 9
	t.equal(Sm2RuleCondition.evaluate(rule,facts).reason,"practice_required","ordered refusal explains first failed condition")
	facts.practice = 10; facts.equipment = ["weapon.meleelike.sword"]
	t.expect(not Sm2RuleCondition.evaluate(rule,facts).matches,"tag prefix must end at a segment boundary")
	facts.unarmed = true
	t.expect(Sm2RuleCondition.evaluate(rule,facts).matches,"alternative capability is supported by data")
	facts.blocked = true
	t.equal(Sm2RuleCondition.evaluate(rule,facts).reason,"blocked","not reports its own reason")
	for defect: Variant in [null,{},_compare("missing","eq",true),_compare("practice","script",1),_compare("practice","gte",false),_compare("practice","eq",1.5),_compare("practice","eq",INF),{"kind":"tag","fact":"equipment","tag":"weapon..melee","reason":"bad"}]:
		t.expect(not Sm2RuleCondition.evaluate(defect,facts).valid,"malformed condition is a validation error")
	var hidden: Dictionary = {"kind":"any","children":[_compare("blocked","eq",true),_compare("missing","eq",0)]}
	t.expect(not Sm2RuleCondition.evaluate(hidden,facts).valid,"true branch cannot hide unknown fact")
	var deep: Dictionary = _compare("blocked","eq",true)
	for index: int in 10: deep = {"kind":"not","child":deep,"reason":"depth"}
	t.equal(Sm2RuleCondition.evaluate(deep,facts).reason,"condition_budget","depth is bounded")
	var wide: Array = []
	for index: int in 128: wide.append(_compare("blocked","eq",true))
	t.equal(Sm2RuleCondition.evaluate({"kind":"all","children":wide},facts).reason,"condition_budget","node count includes root")
	t.expect(Sm2RuleCondition.evaluate(_compare("practice","eq",10.0),facts).matches,"integral JSON float accepted")
	for row: Array in [["lt",9,true],["lte",10,true],["gt",11,true],["gte",9,false],["ne",10,false]]:
		t.equal(Sm2RuleCondition.evaluate(_compare("number",row[0],10),{"number":row[1]}).matches,row[2],"comparison boundary "+row[0])

static func _modifiers(t: Sm2TestHarness) -> void:
	var sequence: Array = [
		{"source":"practice","operation":"add","amount":5},
		{"source":"implant","operation":"scale_percent","amount":120},
		{"source":"wound","operation":"add","amount":-2,"when":_compare("wounded","eq",true)}]
	var original: Array = sequence.duplicate(true)
	var result: Dictionary = Sm2ModifierPipeline.evaluate(10,sequence,{"wounded":true})
	t.expect(result.valid,"ordered modifiers accepted")
	t.equal(result.value,16,"independent oracle: (10+5)*120/100-2 = 16")
	t.equal([result.steps[0].after,result.steps[1].after,result.steps[2].after],[15,18,16],"trace gives actual intermediate values")
	t.equal(Sm2ModifierPipeline.evaluate(10,sequence,{"wounded":false}).value,18,"current context changes conditional modifier")
	t.equal(sequence,original,"modifier definition is not mutated")
	result.steps[0].after = 999
	t.equal(Sm2ModifierPipeline.evaluate(10,sequence,{"wounded":true}).steps[0].after,15,"returned trace is detached")
	t.equal(Sm2ModifierPipeline.evaluate(-3,[{"source":"test","operation":"scale_percent","amount":50}]).value,-2,"negative scaling floors without float rounding")
	t.equal(Sm2ModifierPipeline.evaluate(100,[{"source":"a","operation":"maximum","amount":70},{"source":"b","operation":"minimum","amount":80}]).value,80,"explicit order of bounds")
	t.equal(Sm2ModifierPipeline.evaluate(100,[{"source":"a","operation":"set","amount":7}]).value,7,"explicit override")
	for invalid: Array in [[{"source":"x","operation":"script","amount":1}],[{"source":"x","operation":"add","amount":true}],[{"source":"x","operation":"scale_percent","amount":1000001}],[{"source":"x","operation":"set","amount":7,"when":_compare("missing","eq",0)}]]:
		t.expect(not Sm2ModifierPipeline.evaluate(1,invalid).valid,"invalid modifier rejected, including inactive rule")
	t.expect(not Sm2ModifierPipeline.evaluate(Sm2ModifierPipeline.MAX_VALUE,[{"source":"x","operation":"add","amount":1}]).valid,"intermediate range overflow rejected")
	t.equal(Sm2ModifierPipeline.evaluate(10000,[{"source":"development","operation":"add","amount":1010000000000},{"source":"morale","operation":"scale_percent","amount":80}]).value,808000008000,"wide direct progression contributions above 10^12 remain representable")
	t.expect(not Sm2ModifierPipeline.evaluate(-9223372036854775807-1,[]).valid,"minimum signed integer cannot bypass bound")
	var maximal: Array = []
	for index: int in 1024: maximal.append({"source":"effect:"+str(index),"operation":"add","amount":10000})
	maximal.append({"source":"floor","operation":"minimum","amount":0})
	maximal.append({"source":"morale","operation":"scale_percent","amount":80})
	t.equal(Sm2ModifierPipeline.evaluate(70,maximal).value,8192056,"64 effects with 16 operations fit pipeline")
	maximal.resize(2049)
	t.equal(Sm2ModifierPipeline.evaluate(1,maximal).reason,"modifier_budget","step count bounded before inspecting entries")

static func _live(t: Sm2TestHarness) -> void:
	var c: Dictionary = Sm2EffectContentLoader.load_scenario()
	t.expect(c.ok,"real authored effects load")
	if not c.ok: return
	var b: Sm2TacticalBattle = EFFECTS._battle(t,c)
	EFFECTS._inject(t,b,[EFFECTS._effect(1,"weakness",2,4)])
	var state: Sm2TacticalState = b.state_copy()
	var actor: Sm2TacticalActor = state.actor(2)
	for morale: String in ["steady","wavering","breaking","fleeing"]:
		actor.morale = morale
		for stat: String in Sm2EffectCatalog.STATS:
			var base: int = int(c.combat.profile(actor.loadout_id).get(stat))
			var flat: int = -10 if stat.ends_with("skill") else 0
			var percent: int = {"steady":100,"wavering":90,"breaking":80,"fleeing":100}[morale]
			@warning_ignore("integer_division")
			var expected: int = maxi(0,base+flat)*percent/100
			if morale == "fleeing" and stat.ends_with("defense"): expected = 0
			var calculation: Dictionary = Sm2CombatStatQuery.explain(state,actor,c.combat,stat)
			t.equal(calculation.value,expected,"all four stats preserve legacy formula: "+morale+" "+stat)
			t.equal(calculation.steps[-1].after,expected,"explanation matches executable value")
	actor.morale = "wavering"
	var calculation: Dictionary = Sm2CombatStatQuery.explain(state,actor,c.combat,"melee_skill")
	t.equal(calculation.value,54,"weakness and morale numerical oracle")
	var text_value: String = Sm2BattleText.stat_calculation("melee_skill",calculation)
	t.expect(text_value.contains("основа 70") and text_value.contains("Ослабление") and text_value.contains("90%") and text_value.contains("54"),"UI translates trace with effect name and morale")
	actor.spatial.ap = 0; actor.spatial.fatigue = actor.spatial.fatigue_max
	t.equal(Sm2ActionRequirements.resources(actor,4,10).reason,"insufficient_ap","AP wins simultaneous resource failure")
	actor.spatial.ap = 4
	t.equal(Sm2ActionRequirements.resources(actor,4,10).reason,"fatigue_limit","fatigue fails after AP satisfied")
	actor.spatial.fatigue -= 10
	t.expect(Sm2ActionRequirements.resources(actor,4,10).matches,"exact resource boundary accepted")
	var before: String = b.state_hash()
	var command: Sm2Command = EFFECTS._command(b,"use_ability","m2:ability.sword_strike",4)
	var check: Dictionary = b.preview(command)
	t.expect(check.allowed,"real attack preview legal")
	t.equal(check.modifiers.skill,60,"preview uses shared weakened skill")
	var decision: Dictionary = b.ai_decision(Sm2AiContentLoader.load_profile().profile)
	t.expect(decision.ok and b.preview(decision.command).allowed,"AI uses shared eligibility and stats")
	t.equal(b.state_hash(),before,"queries, AI and view leave world RNG and revisions unchanged")
	var saved: Dictionary = b.capture()
	var restored: Sm2TacticalBattle = EFFECTS._battle(t,c)
	t.expect(restored.restore(saved).ok,"saved battle restores")
	t.equal(restored.view(),b.view(),"derived explanations recomputed identically on restore")
	var resolved: Sm2CommandResult = b.execute(command)
	t.expect(resolved.accepted,"real action executes")
	for event: Dictionary in resolved.events:
		if event.type == "attack_attempted": t.equal(event.hit_chance,check.hit_chance,"execution agrees with forecast")
	t.equal(restored.execute(command).events,resolved.events,"save continuation remains deterministic")
	t.equal(restored.capture(),b.capture(),"save continuation keeps exact state")
