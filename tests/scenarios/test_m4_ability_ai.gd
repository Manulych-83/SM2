extends RefCounted
const BOLT: String = "m4:spell.arcane_bolt"

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary = Sm2MagicContentLoader.load_scenario()
	var loaded: Dictionary = Sm2AiContentLoader.load_profile(Sm2AiContentLoader.ABILITY_PATH)
	t.expect(c.ok and loaded.ok,"authored ability AI loads")
	if not c.ok or not loaded.ok: return
	_profile(t,loaded.profile)
	_choices(t,c,loaded.profile)
	_support(t,c,loaded.profile)
	_guards(t,c,loaded.profile)
	_full(t,c,loaded.profile)
	var effects_only: Dictionary = Sm2EffectContentLoader.load_scenario()
	effects_only["magic"] = null
	_full(t,effects_only,loaded.profile)
	t.complete_suite("m4_ability_ai")

static func _battle(t: Sm2TestHarness,c: Dictionary,ids: Array[int] = [3,4]) -> Sm2TacticalBattle:
	var b: Sm2TacticalBattle = Sm2TacticalBattle.new(c.catalog,c.combat,true,c.effects,c.magic)
	t.expect(b.start(Sm2CombatFixtures.setup(c,ids,1231)).ok,"ability AI fixture starts")
	return b

static func _decide(t: Sm2TestHarness,b: Sm2TacticalBattle,p: Sm2AiProfile) -> Dictionary:
	var before: String = b.state_hash()
	var decision: Dictionary = b.ai_decision(p)
	t.expect(decision.ok,"ability AI decides "+str(decision.get("reason","")))
	t.equal(b.state_hash(),before,"decision preserves state mana RNG effects and allocators")
	if decision.ok:
		t.expect(b.preview(decision.command).allowed,"chosen command is legal")
		var repeated: Dictionary = b.ai_decision(p)
		t.equal(Sm2TacticalAi.command_data(repeated.command),Sm2TacticalAi.command_data(decision.command),"same state same decision")
	return decision

static func _limited(c: Dictionary,effect_names: Array[String],mana: int = 0) -> Dictionary:
	var result: Dictionary = c.duplicate()
	var raw: Dictionary = c.effects.to_data()
	var grants: Array[String] = []
	for name: String in effect_names: grants.append("m4:ability."+name)
	for profile: Dictionary in raw.profiles: profile.actions = grants.duplicate()
	result.effects = Sm2EffectCatalog.new()
	result.effects.build(raw,c.combat)
	raw = c.magic.to_data()
	for profile: Dictionary in raw.profiles:
		profile.mana_max = mana
		profile.mana_per_round = 0
	result.magic = Sm2MagicCatalog.new()
	result.magic.build(raw,c.combat,result.effects)
	return result

static func _restore(t: Sm2TestHarness,b: Sm2TacticalBattle,data: Dictionary) -> void:
	var result: Dictionary = b.restore(data)
	t.expect(result.ok,"AI fixture validates "+str(result.get("errors",[])))

static func _empty_bow(t: Sm2TestHarness,b: Sm2TacticalBattle) -> void:
	var data: Dictionary = b.capture()
	Sm2CombatFixtures.item(Sm2CombatFixtures.actor(data,3),"weapon").ammo = 0
	_restore(t,b,data)

static func _poison(t: Sm2TestHarness,b: Sm2TacticalBattle,target: int,hp: int) -> void:
	var data: Dictionary = b.capture()
	data.revision = "1"
	data.next_effect_id = "2"
	data.effects = [{"effect_id":"1","definition_id":"m4:effect.poison","source_actor_id":"4","target_actor_id":str(target),"remaining":3,"applied_revision":"1"}]
	Sm2CombatFixtures.actor(data,target).combat.hp = hp
	_restore(t,b,data)

static func _profile(t: Sm2TestHarness,p: Sm2AiProfile) -> void:
	var original: String = p.fingerprint()
	for defect: String in ["policy","horizon","discount","weight","reserve","missing"]:
		var raw: Dictionary = p.to_data()
		match defect:
			"policy": raw.policy = "unknown"
			"horizon": raw.effect_horizon = 4
			"discount": raw.future_tick_percent = 101
			"weight": raw.mana_weight = -1
			"reserve": raw.mana_reserve = true
			"missing": raw.erase("defense_weight")
		t.expect(not p.build(raw).is_empty(),"invalid ability profile "+defect)
		t.equal(p.fingerprint(),original,"profile build atomic")
	t.expect(Sm2AiContentLoader.load_saved_profile(original).ok,"new saved profile recognized")
	var legacy: Sm2AiProfile = Sm2AiContentLoader.load_profile().profile
	t.equal(Sm2AiContentLoader.load_saved_profile(legacy.fingerprint()).profile.to_data(),legacy.to_data(),"old saved profile selected unchanged")
	t.expect(not Sm2AiContentLoader.load_saved_profile("unknown").ok,"unknown saved policy rejected")
	for path: String in ["sm2_ability_ai.gd","sm2_ai_effect_assessment.gd"]:
		var source: String = FileAccess.get_file_as_string("res://src/domain/ai/"+path)
		for forbidden: String in [".execute(",".capture(",".rng","Sm2BattleDice"]:
			t.expect(not source.contains(forbidden),"new policy does not use "+forbidden)

static func _choices(t: Sm2TestHarness,c: Dictionary,p: Sm2AiProfile) -> void:
	var limited: Dictionary = _limited(c,[],24)
	var b: Sm2TacticalBattle = _battle(t,limited)
	_empty_bow(t,b)
	var decision: Dictionary = _decide(t,b,p)
	t.equal([decision.choice,decision.command.ability_id],["spell",BOLT],"empty bow with mana casts instead of retreating")
	var expected: Dictionary = b.preview(decision.command)
	t.equal(decision.score,(int(expected.hp_loss)*400-int(expected.mana_cost)*25)/int(expected.ap_cost),"spell score uses shared HP forecast and explicit mana price")
	var data: Dictionary = b.capture()
	data.rng.state = "76"
	data.rng.draws = "999"
	_restore(t,b,data)
	t.equal(Sm2TacticalAi.command_data(_decide(t,b,p).command),Sm2TacticalAi.command_data(decision.command),"actual future RNG not consulted")
	# A clear, unarmored melee target makes the ordinary weapon the better option.
	b = _battle(t,limited,[2,4])
	data = b.capture()
	for item: Dictionary in Sm2CombatFixtures.actor(data,4).combat.items:
		if item.slot in ["head","body","shield"]: item.current = 0
	_restore(t,b,data)
	decision = _decide(t,b,p)
	t.equal(decision.choice,"attack","use efficient weapon rather than always spend mana")
	# Only three AP: poison is available, the spell and weapon are not.
	b = _battle(t,_limited(c,["poison"],24))
	data = b.capture()
	Sm2CombatFixtures.actor(data,3).ap = 3
	_restore(t,b,data)
	decision = _decide(t,b,p)
	t.equal(decision.command.ability_id,"m4:ability.poison","poison uses remaining AP")
	t.expect(b.execute(decision.command).accepted,"AI applies poison")
	# A fully active effect is never redundantly reapplied.
	b = _battle(t,_limited(c,["poison"]))
	_empty_bow(t,b)
	decision = _decide(t,b,p)
	t.equal(decision.command.ability_id,"m4:ability.poison","poison selected without magic")
	t.expect(b.execute(decision.command).accepted,"poison command accepted")
	decision = _decide(t,b,p)
	t.expect(decision.command.ability_id != "m4:ability.poison","full poison not reapplied")
	# Shared resistance/LOS legality: no HP benefit at 100 percent resistance.
	limited = _limited(c,[],24)
	var raw: Dictionary = limited.magic.to_data()
	for profile: Dictionary in raw.profiles: profile.arcane_resistance = 100
	limited.magic.build(raw,c.combat,limited.effects)
	b = _battle(t,limited)
	_empty_bow(t,b)
	t.expect(_decide(t,b,p).command.ability_id != BOLT,"zero-damage spell not cast")
	b = _battle(t,_limited(c,[],24),[3,5,4])
	_empty_bow(t,b)
	data = b.capture()
	Sm2CombatFixtures.actor(data,4).q = 1
	Sm2CombatFixtures.actor(data,4).r = 3
	_restore(t,b,data)
	var ray: Sm2Command = Sm2CombatFixtures.command(b,"unused",4)
	ray.ability_id = BOLT
	t.expect(b.preview(ray).allowed,"lower-resistance target has clear ray")
	decision = _decide(t,b,p)
	t.equal(decision.command.target_actor_id,4,"lower-resistance target selected on clear ray")

static func _support(t: Sm2TestHarness,c: Dictionary,p: Sm2AiProfile) -> void:
	var reservation: Sm2TacticalBattle = _battle(t,_limited(c,["weakness"]))
	var reserved: Dictionary = reservation.capture()
	Sm2CombatFixtures.actor(reserved,3).ap = 6
	# Bow cannot fire in an adjacent enemy's control zone.
	Sm2CombatFixtures.actor(reserved,4).q = 3
	_restore(t,reservation,reserved)
	t.expect(reservation.preview(Sm2CombatFixtures.command(reservation,"bow_shot",4)).allowed,"reserved direct attack is actually available")
	t.equal(_decide(t,reservation,p).choice,"attack","non-urgent effect leaves room for direct attack")
	for effect: String in ["weakness","cover"]:
		var b: Sm2TacticalBattle = _battle(t,_limited(c,[effect]))
		_empty_bow(t,b)
		var decision: Dictionary = _decide(t,b,p)
		t.equal(decision.command.ability_id,"m4:ability."+effect,"useful flat effect "+effect)
		t.expect(b.execute(decision.command).accepted,"flat effect accepted")
		if effect == "weakness":
			t.expect(_decide(t,b,p).command.ability_id != "m4:ability.weakness","full weakness not refreshed")
			var weakened: Dictionary = b.capture()
			weakened.effects[0].remaining = 1
			_restore(t,b,weakened)
			t.equal(_decide(t,b,p).command.ability_id,"m4:ability.weakness","refresh values extra useful lifetime")
	var b: Sm2TacticalBattle = _battle(t,c)
	_poison(t,b,3,3)
	var decision: Dictionary = _decide(t,b,p)
	t.equal([decision.choice,decision.command.target_actor_id],["cleanse",3],"lethal self poison is cleansed before attack")
	t.expect(b.execute(decision.command).accepted,"self cleanse accepted")
	t.expect(b.capture().effects.is_empty(),"AI actually removed poison")
	b = _battle(t,c,[3,2,4])
	_poison(t,b,2,2)
	decision = _decide(t,b,p)
	t.equal([decision.choice,decision.command.target_actor_id],["cleanse",2],"AI rescues poisoned ally")
	b = _battle(t,c)
	_poison(t,b,3,3)
	var data: Dictionary = b.capture()
	Sm2CombatFixtures.actor(data,4).combat.hp = 18
	_restore(t,b,data)
	decision = _decide(t,b,p)
	t.equal(decision.choice,"spell","winning spell outranks cleanse")
	t.expect(b.execute(decision.command).accepted and b.view().finished,"winning spell finishes before poison")
	# Cover that expires on the same last-AP action provides no future protection.
	var limited: Dictionary = _limited(c,["cover"])
	var raw: Dictionary = limited.effects.to_data()
	for effect: Dictionary in raw.effects:
		if effect.id == "m4:effect.cover": effect.duration = 1
	limited.effects.build(raw,c.combat)
	limited.magic.build(limited.magic.to_data(),c.combat,limited.effects)
	b = _battle(t,limited)
	_empty_bow(t,b)
	data = b.capture()
	Sm2CombatFixtures.actor(data,3).ap = 3
	_restore(t,b,data)
	t.expect(_decide(t,b,p).command.ability_id != "m4:ability.cover","instant-expiring self cover is skipped")

static func _guards(t: Sm2TestHarness,c: Dictionary,p: Sm2AiProfile) -> void:
	var b: Sm2TacticalBattle = _battle(t,_limited(c,[],24))
	_empty_bow(t,b)
	var data: Dictionary = b.capture()
	Sm2CombatFixtures.actor(data,4).q = 6
	_restore(t,b,data)
	var decision: Dictionary = _decide(t,b,p)
	t.equal(decision.command.kind,"move","caster approaches a valid spell position")
	t.expect(b.execute(decision.command).accepted,"caster route step legal")
	var raw: Dictionary = p.to_data()
	raw.query_limit = 1
	var tiny: Sm2AiProfile = Sm2AiProfile.new()
	t.expect(tiny.build(raw).is_empty(),"small work budget is valid")
	var before: String = b.state_hash()
	t.equal(b.ai_decision(tiny).reason,"ai_query_limit","budget limit is explicit error")
	t.equal(b.state_hash(),before,"budget failure inert")
	# Renaming authored data does not require adding a policy branch.
	var renamed: Dictionary = _limited(c,[],24)
	var spells: Dictionary = renamed.magic.to_data()
	for spell: Dictionary in spells.spells:
		if spell.id == BOLT: spell.id = "m4:spell.other_bolt"
	for profile: Dictionary in spells.profiles: profile.spells = ["m4:spell.other_bolt"]
	t.expect(renamed.magic.build(spells,c.combat,renamed.effects).is_empty(),"renamed spell catalog valid")
	b = _battle(t,renamed)
	_empty_bow(t,b)
	t.equal(_decide(t,b,p).command.ability_id,"m4:spell.other_bolt","policy dispatches by operation not authored ID")
	b = _battle(t,_limited(c,["poison"]))
	_empty_bow(t,b)
	data = b.capture()
	data.next_effect_id = "9223372036854775806"
	_restore(t,b,data)
	t.expect(_decide(t,b,p).command.ability_id != "m4:ability.poison","exhausted effect allocator is honored without actual ID access")
	b = _battle(t,c)
	data = b.capture()
	Sm2CombatFixtures.actor(data,3).morale = "fleeing"
	_restore(t,b,data)
	t.equal(_decide(t,b,p).choice,"retreat","fleeing still uses old retreat policy")

static func _full(t: Sm2TestHarness,c: Dictionary,p: Sm2AiProfile) -> void:
	for seed_value: int in [20260909,1,76]:
		var setup: Dictionary = c.setup.duplicate(true)
		setup.seed = seed_value
		var mode: String = "magic" if c.magic != null else "effects"
		var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/m4_ability_ai/"+mode+"/"+str(seed_value))
		var runner: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,p,store,true,c.effects,c.magic)
		t.expect(runner.new_battle(setup).ok,"full ability battle starts")
		var initial: Dictionary = runner.capture().session
		var history: Array[Dictionary] = []
		for i: int in 6:
			var action: Dictionary = runner.step()
			t.expect(action.ok,"opening AI command accepted")
			if action.has("command"): history.append({"command":action.command,"events":action.events,"code":action.code})
		t.expect(not runner.view().finished,"checkpoint remains mid-battle")
		t.expect(runner.save_game().ok,"modern AI saves active battle")
		var restored: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,p,store,true,c.effects,c.magic)
		t.expect(restored.load_game().ok,"modern AI loads active battle")
		var played: Dictionary = runner.run_to_end(2000)
		var continued: Dictionary = restored.run_to_end(2000)
		t.expect(played.ok and played.status == "finished","modern AI completes battle "+str(seed_value))
		t.expect(int(runner.view().round) < 100,"authored battle resolves before round-limit stalemate "+mode+" "+str(seed_value))
		t.equal(continued,played,"loaded AI decisions and events exactly match")
		var choices: Dictionary = {}
		var retries: int = 0
		for entry: Dictionary in played.history:
			history.append({"command":entry.command,"events":entry.events,"code":entry.code})
			choices[entry.choice] = int(choices.get(entry.choice,0))+1
			retries += int(entry.retries)
		t.equal(retries,0,"no command rejection retries")
		t.expect(int(choices.get("effect",0)) > 0,"full battle uses effects "+mode)
		if c.magic != null: t.expect(int(choices.get("spell",0)) > 0,"full battle uses spells")
		var replay: Dictionary = Sm2BattleReplay.replay(c.catalog,c.combat,initial,history,c.effects,c.magic)
		t.expect(replay.ok,"modern battle replay without AI succeeds")
		t.equal(replay.session,runner.capture().session,"replay final state equals modern AI")
		t.expect(store.save_slot({"seed":seed_value,"initial":initial,"history":history,"choices":choices,"final":runner.capture()},"trace").ok,"modern battle trace written")
