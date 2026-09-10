extends RefCounted
static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary = Sm2EffectContentLoader.load_scenario()
	t.expect(c.ok,"M4 authored content loads")
	if not c.ok: return
	_catalog(t,c)
	_lifetime(t,c)
	_stats(t,c)
	_damage(t,c)
	_storage(t,c)
	_edges(t,c)
	t.complete_suite("m4_effects")

static func _battle(t: Sm2TestHarness,c: Dictionary,ids: Array[int] = [2,4]) -> Sm2TacticalBattle:
	var b: Sm2TacticalBattle = Sm2TacticalBattle.new(c.catalog,c.combat,true,c.effects)
	t.expect(b.start(Sm2CombatFixtures.setup(c,ids,1231)).ok,"M4 fixture starts")
	return b

static func _command(b: Sm2TacticalBattle,kind: String,ability: String = "",target: int = 0) -> Sm2Command:
	var cmd: Sm2Command = Sm2Command.new()
	cmd.kind = kind
	cmd.actor_id = b.view().active_actor_id
	cmd.expected_revision = b.view().revision
	cmd.ability_id = ability
	cmd.target_actor_id = target
	return cmd

static func _act(t: Sm2TestHarness,b: Sm2TacticalBattle,kind: String,ability: String = "",target: int = 0) -> Sm2CommandResult:
	var before: int = b.view().revision
	var result: Sm2CommandResult = b.execute(_command(b,kind,ability,target))
	t.expect(result.accepted,"M4 accepts "+kind+" "+ability+": "+result.code)
	t.equal(result.revision,before+1,"one revision for whole command including effects")
	return result

static func _inject(t: Sm2TestHarness,b: Sm2TacticalBattle,effects: Array[Dictionary]) -> void:
	var data: Dictionary = b.capture()
	data.revision = "10"
	data.effects = effects
	data.next_effect_id = str(effects.size()+1)
	t.expect(b.restore(data).ok,"explicit effect fixture validates")

static func _effect(id: int,name: String,target: int,source: int,remaining: int = 2) -> Dictionary:
	return {"effect_id":str(id),"definition_id":"m4:effect."+name,"target_actor_id":str(target),"source_actor_id":str(source),"remaining":remaining,"applied_revision":"1"}

static func _catalog(t: Sm2TestHarness,c: Dictionary) -> void:
	var original: String = c.effects.fingerprint()
	for defect: String in ["operation","clock","stack","duration","resistance","reference","duplicate","channel"]:
		var raw: Dictionary = c.effects.to_data()
		match defect:
			"operation": raw.effects[0].operations[0].kind = "unknown"
			"clock": raw.effects[0].clock = "frame"
			"stack": raw.effects[0].stacking = "infinite"
			"duration": raw.effects[0].duration = 0
			"resistance": raw.profiles[0].resistances.poison = 101
			"reference": raw.actions[0].effect_id = "missing"
			"duplicate": raw.effects.append(raw.effects[0])
			"channel": raw.effects[1].operations[0].channel = "not_implemented"
		t.expect(not c.effects.build(raw,c.combat).is_empty(),"bad catalog rejected: "+defect)
		t.equal(c.effects.fingerprint(),original,"catalog failure atomic")
	c.effects.definition("m4:effect.poison").duration = 999
	t.equal(c.effects.definition("m4:effect.poison").duration,3,"definition returns detached copy")
	var raw: Dictionary = c.effects.to_data()
	var extra: Dictionary = c.effects.definition("m4:effect.poison").to_data()
	extra.id = "m4:effect.strong_poison"
	extra.operations[0].amount = 7
	raw.effects.append(extra)
	var action: Dictionary = c.effects.action("m4:ability.poison").to_data()
	action.id = "m4:ability.strong_poison"
	action.effect_id = extra.id
	raw.actions.append(action)
	for p: Dictionary in raw.profiles: p.actions.append(action.id)
	var extra_catalog: Sm2EffectCatalog = Sm2EffectCatalog.new()
	t.expect(extra_catalog.build(raw,c.combat).is_empty(),"new effect uses data only")
	var expanded: Dictionary = c.duplicate()
	expanded.effects = extra_catalog
	var b: Sm2TacticalBattle = _battle(t,expanded)
	_act(t,b,"use_ability",action.id,4)
	_act(t,b,"end_turn")
	_act(t,b,"end_turn")
	t.equal(Sm2CombatFixtures.actor(b.view(),4).combat.hp,53,"new authored poison variant ticks7 without new code")

static func _lifetime(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle = _battle(t,c)
	var cmd: Sm2Command = _command(b,"use_ability","m4:ability.poison",4)
	var before: String = b.state_hash()
	t.expect(b.preview(cmd).allowed,"poison prediction legal")
	t.equal(b.state_hash(),before,"effect preview inert")
	_act(t,b,"use_ability","m4:ability.poison",4)
	t.equal(b.capture().effects[0].remaining,3,"apply starts at3 without tick")
	before = b.state_hash()
	t.equal(b.execute(_command(b,"use_ability","m4:ability.poison",4)).code,"effect_already_full","full duration rejected")
	t.equal(b.state_hash(),before,"duplicate spends no RNG resources IDs revision")
	_act(t,b,"end_turn")
	_act(t,b,"wait")
	t.equal(b.capture().effects[0].remaining,3,"Wait and resume do not tick")
	_act(t,b,"end_turn")
	t.equal(Sm2CombatFixtures.actor(b.view(),4).combat.hp,55,"first target completion ticks5")
	t.equal(b.capture().effects[0].remaining,2,"remaining after first tick2")
	var next_id: String = b.capture().next_effect_id
	_act(t,b,"use_ability","m4:ability.poison",4)
	t.equal(b.capture().next_effect_id,next_id,"refresh reuses ID")
	t.equal(b.capture().effects[0].remaining,3,"refresh restores3")
	for round_index: int in 3:
		_act(t,b,"end_turn")
		_act(t,b,"end_turn")
	t.equal(Sm2CombatFixtures.actor(b.view(),4).combat.hp,40,"four completed ticks including before refresh")
	t.expect(b.capture().effects.is_empty(),"expires after final tick")
	b = _battle(t,c)
	_act(t,b,"use_ability","m4:ability.poison",4)
	_act(t,b,"use_ability","m4:ability.weakness",4)
	_act(t,b,"use_ability","m4:ability.cover",2)
	t.equal(b.view().active_actor_id,4,"AP0 automatically advances")
	t.equal(b.capture().effects[2].remaining,1,"self effect ticks exactly once at AP0")
	_act(t,b,"use_ability","m4:ability.cleanse",4)
	t.equal(b.capture().effects.size(),1,"cleanse removes both harmful but keeps helpful")
	before = b.state_hash()
	t.equal(b.execute(_command(b,"use_ability","m4:ability.cleanse",4)).code,"no_dispellable_effects","empty cleanse rejected")
	t.equal(b.state_hash(),before,"empty cleanse inert")
	b = _battle(t,c,[2,5])
	before = b.state_hash()
	t.equal(b.execute(_command(b,"use_ability","m4:ability.poison",5)).code,"effect_immune","immune target denies application")
	t.equal(b.state_hash(),before,"immune application fully inert")

static func _stats(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle = _battle(t,c)
	var data: Dictionary = b.capture()
	Sm2CombatFixtures.actor(data,2).morale = "wavering"
	t.expect(b.restore(data).ok,"morale fixture")
	_inject(t,b,[_effect(1,"weakness",2,4)])
	var actor: Dictionary = Sm2CombatFixtures.actor(b.view(),2)
	t.equal(actor.stats.melee_skill.value,54,"70 minus10 at90 percent equals54")
	var attack: Sm2Command = _command(b,"use_ability","m2:ability.sword_strike",4)
	t.equal(b.preview(attack).modifiers.skill,54,"weapon preview uses effect stats")
	var before: String = b.state_hash()
	var decision: Dictionary = b.ai_decision(Sm2AiContentLoader.load_profile().profile)
	t.expect(decision.ok and b.preview(decision.command).allowed,"AI handles extended action list")
	t.equal(b.state_hash(),before,"AI with effects does not mutate battle")
	_act(t,b,"use_ability","m4:ability.cleanse",2)
	t.equal(Sm2CombatFixtures.actor(b.view(),2).stats.melee_skill.value,63,"cleanse restores unmodified morale-adjusted skill")
	b = _battle(t,c)
	_inject(t,b,[_effect(1,"weakness",4,2)])
	var move: Sm2Command = _command(b,"move")
	move.target = Vector2i(0,2)
	var result: Sm2CommandResult = b.execute(move)
	t.expect(result.accepted,"reaction fixture moves")
	for event: Dictionary in result.events:
		if event.type == "attack_attempted":
			# Authored fighter skill70, weakness-10, axe bonus0, defender5+shield15.
			t.equal(event.hit_chance,40,"reaction oracle (70-10)+0-(5+15)=40")

static func _damage(t: Sm2TestHarness,c: Dictionary) -> void:
	for resistance: int in [0,50,100]:
		var raw: Dictionary = c.effects.to_data()
		for p: Dictionary in raw.profiles:
			if p.id == "m2:loadout.sword_fighter": p.resistances.poison = resistance
		var catalog: Sm2EffectCatalog = Sm2EffectCatalog.new()
		t.expect(catalog.build(raw,c.combat).is_empty(),"resistance content")
		var variant: Dictionary = c.duplicate()
		variant.effects = catalog
		var b: Sm2TacticalBattle = _battle(t,variant)
		_inject(t,b,[_effect(1,"poison",2,4)])
		_act(t,b,"end_turn")
		t.equal(Sm2CombatFixtures.actor(b.view(),2).combat.hp,60-[5,2,0][[0,50,100].find(resistance)],"resistance oracle "+str(resistance))
		t.equal(b.capture().effects[0].remaining,1,"zero loss still consumes duration")
		t.equal(b.capture().rng.draws,"0","periodic damage on survivor has no hit/morale RNG")
	var b: Sm2TacticalBattle = _battle(t,c)
	_inject(t,b,[_effect(1,"poison",2,4),_effect(2,"cover",2,2)])
	var data: Dictionary = b.capture()
	Sm2CombatFixtures.actor(data,2).combat.hp = 1
	t.expect(b.restore(data).ok,"lethal poison fixture")
	var result: Sm2CommandResult = _act(t,b,"end_turn")
	t.expect(b.view().finished and b.view().winner == "opposition","poison death resolves victory before next turn")
	t.equal(b.view().round,1,"no extra round after lethal tick")
	t.expect(b.capture().effects.is_empty(),"death and outcome remove effects")
	var death_count: int = 0
	for event: Dictionary in result.events:
		if event.type == "actor_died": death_count += 1
		t.expect(event.type != "activation_started","no activation after lethal tick")
	t.equal(death_count,1,"one death event")
	# A dead source does not cancel a surviving target's effect.
	b = _battle(t,c,[2,4,6])
	_inject(t,b,[_effect(1,"poison",2,4)])
	data = b.capture()
	# Source death is produced through ordinary HP application in a decoded candidate.
	var decoded: Dictionary = Sm2EffectSnapshot.decode(data,c.catalog,c.combat,c.effects)
	var events: Array[Dictionary] = []
	Sm2HpApplication.apply(decoded.state,decoded.state.actor(4),2,60,events)
	t.expect(b.restore(decoded.state.to_data(c.catalog.fingerprint())).ok,"historical dead source remains a valid reference")
	t.equal(b.capture().effects.size(),1,"source death preserves target effect")

static func _storage(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle = _battle(t,c)
	_act(t,b,"use_ability","m4:ability.poison",4)
	var saved: Dictionary = b.capture()
	for defect: String in ["unknown","duration","duplicate","counter","target","extra","future_revision","zero_id"]:
		var data: Dictionary = saved.duplicate(true)
		match defect:
			"unknown": data.effects[0].definition_id = "unknown"
			"duration": data.effects[0].remaining = 4
			"duplicate": data.effects.append(data.effects[0])
			"counter": data.next_effect_id = "1"
			"target": data.effects[0].target_actor_id = "99"
			"extra": data.unexpected = true
			"future_revision": data.effects[0].applied_revision = "999"
			"zero_id": data.effects[0].effect_id = "0"
		t.expect(not b.restore(data).ok,"bad M4 snapshot rejected "+defect)
		t.equal(b.capture(),saved,"bad restore inert")
	var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/m4_effects")
	var runner: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,Sm2AiContentLoader.load_profile().profile,store,false,c.effects)
	t.expect(runner.new_battle(Sm2CombatFixtures.setup(c,[2,4],1231)).ok,"runner starts")
	var initial: Dictionary = runner.capture().session
	var history: Array[Dictionary] = []
	var cmd: Sm2Command = Sm2Command.new()
	cmd.kind = "use_ability"
	cmd.actor_id = 2
	cmd.ability_id = "m4:ability.poison"
	cmd.target_actor_id = 4
	var result: Sm2CommandResult = runner.execute_player(cmd)
	t.expect(result.accepted,"player effect through runner")
	history.append({"command":Sm2TacticalAi.command_data(cmd),"events":result.events,"code":result.code})
	t.expect(runner.save_game().ok,"M4 save writes")
	var snapshot: Dictionary = runner.capture()
	var restored: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,Sm2AiContentLoader.load_profile().profile,store,false,c.effects)
	t.expect(restored.load_game().ok,"fresh runner loads M4")
	t.equal(restored.capture(),snapshot,"exact M4 restore no tick")
	cmd.kind = "end_turn"
	cmd.ability_id = ""
	cmd.target_actor_id = 0
	cmd.expected_revision = runner.view().revision
	result = runner.execute_player(cmd)
	t.equal(restored.execute_player(cmd).events,result.events,"player continuation equal")
	history.append({"command":Sm2TacticalAi.command_data(cmd),"events":result.events,"code":result.code})
	for step_index: int in 30:
		if runner.view().finished or runner.view().active_actor_id == 2: break
		var a: Dictionary = runner.step()
		var z: Dictionary = restored.step()
		t.expect(a.ok and z.ok,"AI continues effect save")
		t.equal(a,z,"AI continuation including effects identical")
		if a.has("command"): history.append(a)
	t.equal(runner.capture(),restored.capture(),"future state identical")
	var replay: Dictionary = Sm2BattleReplay.replay(c.catalog,c.combat,initial,history,c.effects)
	t.expect(replay.ok,"M4 command replay works")
	t.equal(replay.session,runner.capture().session,"replay without AI matches")
	var legacy: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,Sm2AiContentLoader.load_profile().profile,store)
	t.expect(not legacy.restore(snapshot).ok,"legacy runner rejects M4 payload")
	t.expect(not store.has_slot(Sm2BattleRunner.SLOT),"M4 save did not overwrite M3 slot")
	var session: Sm2TacticalSession = Sm2TacticalSession.new(c.catalog,store,c.combat,true,c.effects)
	t.expect(session.restore_payload(snapshot.session).ok,"M4 session restores runner session")
	t.expect(session.save_game().ok and session.has_save(),"M4 standalone session reports its own saved slot")
	var loaded_session: Sm2TacticalSession = Sm2TacticalSession.new(c.catalog,store,c.combat,true,c.effects)
	t.expect(loaded_session.load_game().ok,"standalone M4 session loads same slot")
	t.equal(loaded_session.capture(),session.capture(),"standalone session save remains exact")
	t.expect(not store.has_slot(Sm2TacticalSession.SLOT),"standalone M4 save leaves M2 slot absent")

static func _edges(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle = _battle(t,c,[2,4,3])
	_act(t,b,"use_ability","m4:ability.poison",4)
	_act(t,b,"end_turn")
	_act(t,b,"end_turn")
	_act(t,b,"end_turn")
	_act(t,b,"end_turn")
	_act(t,b,"use_ability","m4:ability.poison",4)
	t.equal([b.capture().effects.size(),b.capture().effects[0].effect_id,b.capture().effects[0].source_actor_id,b.capture().effects[0].remaining],[1,"1","2",3],"second source refreshes same ID without stacking")
	b = _battle(t,c,[2,4,3])
	_inject(t,b,[_effect(1,"poison",3,4),_effect(2,"cover",3,3)])
	var data: Dictionary = b.capture()
	Sm2CombatFixtures.actor(data,3).combat.hp = 1
	data.rng.draws = "9223372036854775806"
	t.expect(b.restore(data).ok,"RNG ceiling fixture accepted")
	var before: String = b.state_hash()
	var result: Sm2CommandResult = b.execute(_command(b,"end_turn"))
	t.equal(result.code,"rng_counter_limit","morale failure after lethal tick is surfaced")
	t.expect(not result.accepted,"technical failure rejects root command")
	t.equal(b.state_hash(),before,"rollback restores ending flags HP effects IDs RNG and revision")
	b = _battle(t,c)
	data = b.capture()
	data.next_effect_id = "9223372036854775806"
	t.expect(b.restore(data).ok,"exhausted effect allocator can be saved")
	before = b.state_hash()
	t.equal(b.execute(_command(b,"use_ability","m4:ability.poison",4)).code,"effect_id_limit","allocator exhaustion denies before payment")
	t.equal(b.state_hash(),before,"allocator error inert")
	b = _battle(t,c)
	_inject(t,b,[_effect(1,"poison",2,4)])
	data = b.capture()
	Sm2CombatFixtures.actor(data,2).q = 0
	t.expect(b.restore(data).ok,"boundary fixture")
	var hp: int = Sm2CombatFixtures.actor(b.view(),2).combat.hp
	result = _act(t,b,"escape")
	t.equal(Sm2CombatFixtures.actor(b.view(),2).combat.hp,hp,"escape has no final poison tick")
	t.expect(b.capture().effects.is_empty(),"escape clears effects")
	for event: Dictionary in result.events: t.expect(event.type != "effect_ticked","no tick on successful exit")
	var raw: Dictionary = c.effects.to_data()
	var instances: Array[Dictionary] = []
	for index: int in 64:
		var definition: Dictionary = c.effects.definition("m4:effect.cover").to_data()
		definition.id = "limit:effect."+str(index)
		raw.effects.append(definition)
		var instance: Dictionary = _effect(index+1,"cover",2,2)
		instance.definition_id = definition.id
		instances.append(instance)
	var catalog: Sm2EffectCatalog = Sm2EffectCatalog.new()
	t.expect(catalog.build(raw,c.combat).is_empty(),"64 distinct definitions valid")
	var expanded: Dictionary = c.duplicate()
	expanded.effects = catalog
	b = _battle(t,expanded)
	_inject(t,b,instances)
	before = b.state_hash()
	t.equal(b.execute(_command(b,"use_ability","m4:ability.cover",2)).code,"effect_limit","65th effect denied")
	t.equal(b.state_hash(),before,"effect limit inert")
