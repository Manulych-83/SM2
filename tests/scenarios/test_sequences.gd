extends RefCounted
const F = preload("res://tests/scenarios/test_m4_effects.gd")
const ATTACK: String = "sequences:ability.exhaustion"
const SUPPORT: String = "sequences:ability.protection"

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary = Sm2EffectSequenceContentLoader.load_scenario()
	t.expect(c.ok,"authored JSON sequences load: "+str(c.get("errors",[])))
	if not c.ok: return
	_catalog(t,c)
	_execution(t,c)
	_limits(t,c)
	_order(t,c)
	_storage(t,c)
	_ai(t,c)
	_large_catalog(t,c)
	_full(t,c)
	t.complete_suite("sequences")

static func _variant(t: Sm2TestHarness,c: Dictionary,raw: Dictionary) -> Dictionary:
	var result: Dictionary = c.duplicate()
	result.effects = Sm2EffectCatalog.new()
	t.expect(result.effects.build(raw,c.combat).is_empty(),"variant validates")
	return result

static func _authored(raw: Dictionary,id: String = ATTACK) -> Dictionary:
	for action: Dictionary in raw.actions:
		if action.id == id: return action
	return {}

static func _catalog(t: Sm2TestHarness,c: Dictionary) -> void:
	var original: String = c.effects.fingerprint()
	for defect: String in ["legacy","empty","too_many","reference","recursive","fields","policy","fact","type","tree","dispel_reference","root_reference"]:
		var raw: Dictionary = c.effects.to_data()
		var action: Dictionary = _authored(raw)
		match defect:
			"legacy": raw.version = "sm2.m4.effects.1"
			"empty": action.steps = []
			"too_many":
				while action.steps.size() < 17: action.steps.append(action.steps[0].duplicate(true))
			"reference": action.steps[0].effect_id = "unknown"
			"recursive": action.steps[0].operation = "invoke_ability"
			"fields": action.steps[0].callback = "run"
			"policy": action.steps[0].on_unavailable = "ignore_everything"
			"fact": action.steps[1].when.fact = "world.secret"
			"type": action.steps[1].when.value = false
			"tree": action.steps[1].when = {"kind":"all","children":[]}
			"dispel_reference": action.steps[0].operation = "dispel_effects"
			"root_reference": action.effect_id = "m4:effect.poison"
		t.expect(not c.effects.build(raw,c.combat).is_empty(),"reject invalid sequence "+defect)
		t.equal(c.effects.fingerprint(),original,"failed sequence build is atomic")
	var copy: Sm2EffectAction = c.effects.action(ATTACK)
	copy.steps[0].effect_id = "changed"
	t.equal(c.effects.action(ATTACK).steps[0].effect_id,"m4:effect.weakness","nested action data detached")
	var old: Dictionary = Sm2EffectContentLoader.load_scenario()
	var rebuilt: Sm2EffectCatalog = Sm2EffectCatalog.new()
	t.expect(rebuilt.build(old.effects.to_data(),old.combat).is_empty(),"old catalog rebuild")
	t.equal(rebuilt.fingerprint(),old.effects.fingerprint(),"legacy hash remains exact")
	t.expect(not old.effects.action("m4:ability.poison").to_data().has("steps"),"old action shape unchanged")
	t.expect(original != old.effects.fingerprint(),"new behavior requires distinct catalog fingerprint")

static func _execution(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle = F._battle(t,c)
	var cmd: Sm2Command = F._command(b,"use_ability",ATTACK,4)
	var before: Dictionary = b.capture()
	var check: Dictionary = b.preview(cmd)
	t.expect(check.allowed,"compound available")
	t.equal(check.sequence.size(),2,"two preview steps")
	t.expect(check.sequence[1].applied,"condition sees first step harmful effect")
	t.equal(b.capture(),before,"preview leaves all state including RNG allocator unchanged")
	var result: Sm2CommandResult = b.execute(cmd)
	t.expect(result.accepted,"compound executes")
	t.equal(b.view().revision,int(before.revision)+1,"one revision")
	t.equal(Sm2CombatFixtures.actor(b.view(),2).ap,6,"one 3AP payment")
	t.equal(b.capture().effects.size(),2,"two actual effects")
	t.equal(b.capture().next_effect_id,"3","two IDs allocated once")
	t.equal(b.capture().rng,before.rng,"no dice in deterministic effects")
	t.equal(result.events[0].type,"resources_spent","resources first")
	t.equal(result.events[1].definition_id,"m4:effect.weakness","weakness first")
	t.equal(result.events[2].definition_id,"m4:effect.poison","poison second")
	var unchanged: String = b.state_hash()
	cmd.expected_revision = b.view().revision
	t.equal(b.preview(cmd).reason,"effect_sequence_no_change","all full is no-op")
	t.expect(not b.execute(cmd).accepted,"no-op rejected")
	t.equal(b.state_hash(),unchanged,"no-op no payment or revision")
	# Immunity is a normal unavailable step; require policy rolls back whole action.
	for policy: String in ["skip","reject"]:
		var raw: Dictionary = c.effects.to_data()
		_authored(raw).steps[1].on_unavailable = policy
		var v: Dictionary = _variant(t,c,raw)
		b = F._battle(t,v,[2,5])
		before = b.capture()
		cmd = F._command(b,"use_ability",ATTACK,5)
		result = b.execute(cmd)
		t.equal(result.accepted,policy == "skip","immunity policy "+policy)
		if policy == "skip":
			t.equal(b.capture().effects.size(),1,"weakness survives skipped poison")
			t.equal(result.events[2].type,"effect_step_skipped","explicit skipped event")
			t.equal(result.events[2].reason,"effect_immune","immunity explained")
		else: t.equal(b.capture(),before,"required immune step leaves no partial effect")
	# False predicate skips poison, even though its effect could otherwise apply.
	var raw: Dictionary = c.effects.to_data()
	_authored(raw).steps[1].when.value = 2
	b = F._battle(t,_variant(t,c,raw))
	check = b.preview(F._command(b,"use_ability",ATTACK,4))
	t.equal(check.sequence[1].reason,"effect_condition_unmet","predicate evaluated against projected count1")
	t.expect(Sm2BattleText.sequence_description(check.sequence).contains("Условие шага"),"UI reason comes from forecast")
	F._act(t,b,"use_ability",ATTACK,4)
	t.equal(b.capture().effects.size(),1,"false predicate prevents poison")
	_authored(raw).steps[1].on_unavailable = "reject"
	b = F._battle(t,_variant(t,c,raw))
	before = b.capture()
	t.equal(b.execute(F._command(b,"use_ability",ATTACK,4)).code,"effect_condition_unmet","required false predicate denies root")
	t.equal(b.capture(),before,"false required predicate leaves no first step")
	b = F._battle(t,c)
	F._inject(t,b,[F._effect(1,"weakness",4,2,1),F._effect(2,"poison",4,2,1)])
	result = F._act(t,b,"use_ability",ATTACK,4)
	t.equal(result.events[1].type,"effect_refreshed","existing step refreshes")
	t.equal(result.events[2].type,"effect_refreshed","both refresh")
	t.equal(b.capture().next_effect_id,"3","refresh allocates nothing")
	# Shared range/side/resource restrictions also guard compound roots.
	for defect: String in ["side","ap","fatigue"]:
		b = F._battle(t,c)
		var data: Dictionary = b.capture()
		if defect == "ap": Sm2CombatFixtures.actor(data,2).ap = 2
		if defect == "fatigue": Sm2CombatFixtures.actor(data,2).fatigue = Sm2CombatFixtures.actor(b.view(),2).fatigue_max
		t.expect(b.restore(data).ok,"resource fixture")
		cmd = F._command(b,"use_ability",ATTACK,2 if defect == "side" else 4)
		before = b.capture()
		t.expect(not b.execute(cmd).accepted,"root guard "+defect)
		t.equal(b.capture(),before,"root guard atomic "+defect)

static func _limits(t: Sm2TestHarness,c: Dictionary) -> void:
	for available: int in [0,1,2]:
		var b: Sm2TacticalBattle = F._battle(t,c)
		var data: Dictionary = b.capture()
		data.next_effect_id = str(Sm2EffectSequence.MAX_ID-available)
		t.expect(b.restore(data).ok,"allocator boundary fixture")
		var before: Dictionary = b.capture()
		var cmd: Sm2Command = F._command(b,"use_ability",ATTACK,4)
		var checked: Dictionary = b.preview(cmd)
		t.equal(checked.allowed,available == 2,"allocator counts all steps")
		var decoded: Dictionary = Sm2EffectSnapshot.decode(data,c.catalog,c.combat,c.effects)
		var query: Sm2AiQueries = Sm2AiQueries.new(decoded.state,c.combat)
		t.equal(query.action(cmd,decoded.state.actor(2).spatial.position).allowed,checked.allowed,"AI same remaining allocation capacity")
		t.equal(b.execute(cmd).accepted,available == 2,"allocator execute agrees")
		if available < 2: t.equal(b.capture(),before,"technical limit never silently skips step")
	# Full target: 63 existing + two new must reject; 62 + two exactly fits.
	var raw: Dictionary = c.effects.to_data()
	for i: int in 63:
		var definition: Dictionary = c.effects.definition("m4:effect.cover").to_data()
		definition.id = "sequences:effect.filler_%s" % i
		raw.effects.append(definition)
	var v: Dictionary = _variant(t,c,raw)
	for count: int in [62,63]:
		var b: Sm2TacticalBattle = F._battle(t,v)
		var effects: Array[Dictionary] = []
		for i: int in count:
			var effect: Dictionary = F._effect(i+1,"cover",4,2)
			effect.definition_id = "sequences:effect.filler_%s" % i
			effects.append(effect)
		F._inject(t,b,effects)
		var before: Dictionary = b.capture()
		t.equal(b.execute(F._command(b,"use_ability",ATTACK,4)).accepted,count == 62,"target cap reserves every step")
		if count == 63: t.equal(b.capture(),before,"second effect cap rolls back first")

static func _order(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle = F._battle(t,c)
	F._inject(t,b,[F._effect(1,"poison",2,4,3)])
	var check: Dictionary = b.preview(F._command(b,"use_ability",SUPPORT,2))
	t.expect(check.allowed and check.sequence[0].applied and check.sequence[1].applied,"cleanse then cover preview")
	var result: Sm2CommandResult = F._act(t,b,"use_ability",SUPPORT,2)
	t.equal(result.events[1].type,"effect_removed","remove first")
	t.equal(result.events[2].definition_id,"m4:effect.cover","cover after removal")
	t.equal(b.capture().effects.size(),1,"only cover left")
	# Rename and change composition solely in data; apply/remove/reapply consumes two IDs.
	var raw: Dictionary = c.effects.to_data()
	var action: Dictionary = _authored(raw)
	var first: Dictionary = action.steps[0].duplicate(true)
	action.id = "sequences:ability.renamed"
	action.steps = [first,{"operation":"dispel_effects","effect_id":"","on_unavailable":"reject"},first.duplicate(true)]
	for profile: Dictionary in raw.profiles:
		profile.actions.erase(ATTACK)
		profile.actions.append(action.id)
	b = F._battle(t,_variant(t,c,raw))
	F._act(t,b,"use_ability",action.id,4)
	t.equal(b.capture().effects.size(),1,"newly applied effect can be removed by later leaf")
	t.equal(b.capture().effects[0].effect_id,"2","reapplication gets fresh ID")
	t.equal(b.capture().next_effect_id,"3","no recycling IDs")
	# Max-length finite chain with no new behaviors or recursion.
	action.steps.clear()
	for i: int in 8:
		action.steps.append(first.duplicate(true))
		action.steps.append({"operation":"dispel_effects","effect_id":"","on_unavailable":"reject"})
	b = F._battle(t,_variant(t,c,raw))
	F._act(t,b,"use_ability",action.id,4)
	t.expect(b.capture().effects.is_empty(),"16 leaves finish in declared order")
	t.equal(b.capture().next_effect_id,"9","16 leaves bounded to8 allocations")

static func _storage(t: Sm2TestHarness,c: Dictionary) -> void:
	var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/sequences")
	var ai: Sm2AiProfile = Sm2AiContentLoader.load_profile(Sm2AiContentLoader.ABILITY_PATH).profile
	var runner: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,ai,store,false,c.effects)
	t.expect(runner.new_battle(Sm2CombatFixtures.setup(c,[2,4],1231)).ok,"runner starts")
	var initial: Dictionary = runner.capture().session
	var cmd: Sm2Command = Sm2Command.new()
	cmd.kind = "use_ability"; cmd.actor_id = 2; cmd.target_actor_id = 4; cmd.ability_id = ATTACK
	var result: Sm2CommandResult = runner.execute_player(cmd)
	t.expect(result.accepted,"root through application")
	var history: Array[Dictionary] = [{"command":Sm2TacticalAi.command_data(cmd),"events":result.events,"code":result.code}]
	t.expect(runner.save_game().ok,"compound writes real slot")
	var restored: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,ai,store,false,c.effects)
	t.expect(restored.load_game().ok,"compound loads fresh runner")
	t.equal(restored.capture(),runner.capture(),"no duplicate charge or steps on load")
	cmd.kind = "end_turn"; cmd.ability_id = ""; cmd.target_actor_id = 0
	cmd.expected_revision = runner.view().revision
	result = runner.execute_player(cmd)
	t.equal(restored.execute_player(cmd).events,result.events,"next command exact after load")
	history.append({"command":Sm2TacticalAi.command_data(cmd),"events":result.events,"code":result.code})
	var replay: Dictionary = Sm2BattleReplay.replay(c.catalog,c.combat,initial,history,c.effects)
	t.expect(replay.ok,"root command replay")
	t.equal(replay.session,runner.capture().session,"replay does not need steps serialized")
	var legacy: Dictionary = Sm2EffectContentLoader.load_scenario()
	var old: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,ai,store,false,legacy.effects)
	t.expect(not old.load_game().ok,"old catalog rejects changed fingerprint")

static func _ai(t: Sm2TestHarness,c: Dictionary) -> void:
	var p: Sm2AiProfile = Sm2AiContentLoader.load_profile(Sm2AiContentLoader.ABILITY_PATH).profile
	var b: Sm2TacticalBattle = F._battle(t,c,[3,4])
	var data: Dictionary = b.capture()
	Sm2CombatFixtures.item(Sm2CombatFixtures.actor(data,3),"weapon").ammo = 0
	t.expect(b.restore(data).ok,"empty bow AI fixture")
	var before: Dictionary = b.capture()
	var decision: Dictionary = b.ai_decision(p)
	t.expect(decision.ok,"AI evaluates sequences")
	if decision.ok:
		t.expect(b.preview(decision.command).allowed,"chosen AI command legal")
		t.equal(decision.command.ability_id,ATTACK,"AI prefers compound weakness+poison to poison alone")
		t.equal(Sm2TacticalAi.command_data(b.ai_decision(p).command),Sm2TacticalAi.command_data(decision.command),"AI repeatable")
	t.equal(b.capture(),before,"AI projection leaves battle untouched")

static func _large_catalog(t: Sm2TestHarness,c: Dictionary) -> void:
	var raw: Dictionary = c.effects.to_data()
	while raw.effects.size() < 2000:
		var definition: Dictionary = c.effects.definition("m4:effect.cover").to_data()
		definition.id = "sequences:effect.generated_%s" % raw.effects.size()
		raw.effects.append(definition)
	var v: Dictionary = _variant(t,c,raw)
	var small: Sm2TacticalBattle = F._battle(t,c)
	var large: Sm2TacticalBattle = F._battle(t,v)
	var cmd: Sm2Command = F._command(small,"use_ability",ATTACK,4)
	t.equal(large.preview(cmd),small.preview(cmd),"2000 definitions preserve same bounded preview")
	t.equal(large.execute(cmd).events,small.execute(cmd).events,"2000 definitions same actual effects")
	t.equal(large.capture().effects.size(),2,"catalog entries do not become runtime instances")
	var restored: Sm2TacticalBattle = F._battle(t,v)
	t.expect(restored.restore(large.capture()).ok,"large catalog snapshot restores")
	t.equal(restored.capture(),large.capture(),"large catalog roundtrip exact")

static func _full(t: Sm2TestHarness,c: Dictionary) -> void:
	var p: Sm2AiProfile = Sm2AiContentLoader.load_profile(Sm2AiContentLoader.ABILITY_PATH).profile
	var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/sequences_full")
	var runner: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,p,store,true,c.effects)
	t.expect(runner.new_battle(c.setup).ok,"full six-actor compound battle starts")
	var initial: Dictionary = runner.capture().session
	var history: Array[Dictionary] = []
	for i: int in 6:
		var entry: Dictionary = runner.step()
		t.expect(entry.ok,"opening compound AI command")
		if entry.has("command"): history.append({"command":entry.command,"events":entry.events,"code":entry.code})
	t.expect(runner.save_game().ok,"full active battle saved")
	var restored: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,p,store,true,c.effects)
	t.expect(restored.load_game().ok,"full active battle restored")
	var played: Dictionary = runner.run_to_end(2000)
	var continued: Dictionary = restored.run_to_end(2000)
	t.expect(played.ok and played.status == "finished","full compound battle completes")
	t.expect(int(runner.view().round) < 100,"no round-limit stalemate")
	t.equal(continued,played,"full saved continuation commands/events match")
	var compound: int = 0
	var retries: int = 0
	for entry: Dictionary in played.history:
		history.append({"command":entry.command,"events":entry.events,"code":entry.code})
		if entry.command.get("ability_id","") in [ATTACK,SUPPORT]: compound += 1
		retries += int(entry.retries)
	t.expect(compound > 0,"full battle actually uses compound actions")
	t.equal(retries,0,"no rejected AI command retries")
	var replay: Dictionary = Sm2BattleReplay.replay(c.catalog,c.combat,initial,history,c.effects)
	t.expect(replay.ok,"full compound command replay succeeds")
	t.equal(replay.session,runner.capture().session,"full replay reproduces final state")
