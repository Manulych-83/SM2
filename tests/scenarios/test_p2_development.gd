extends RefCounted
const STRIKE: String = "m2:ability.sword_strike"
const STRENGTH: String = "p1:stat.strength"
const MELEE: String = "p1:skill.melee"

static func command(b: Sm2TacticalBattle, kind: String = "use_ability", target: int = 3) -> Sm2Command:
	var value: Sm2Command = Sm2Command.new()
	value.battle_id=b.view().battle_id
	value.kind=kind; value.actor_id=b.view().active_actor_id; value.expected_revision=b.view().revision
	value.ability_id=STRIKE if kind == "use_ability" else ""; value.target_actor_id=target
	return value

static func actor(b: Sm2TacticalBattle, id: int) -> Dictionary:
	for entry: Dictionary in b.view().actors:
		if entry.actor_id == id: return entry
	return {}

static func track(b: Sm2TacticalBattle, id: int, key: String) -> Dictionary:
	for entry: Dictionary in actor(b,id).development.tracks:
		if entry.id == key: return entry
	return {}

static func make(c: Dictionary, setup: Dictionary) -> Sm2TacticalBattle:
	var b: Sm2TacticalBattle = Sm2TacticalBattle.new(c.catalog,c.combat,true,null,null,c.development)
	b.start(setup)
	return b

static func adjacent_setup(c: Dictionary) -> Dictionary:
	var setup: Dictionary=c.setup.duplicate(true)
	setup.actors[2].q=2; setup.actors[2].r=1
	return setup

static func practice_fixture(c: Dictionary) -> Dictionary:
	var raw: Dictionary=c.combat.to_data()
	for ability: Dictionary in raw.abilities:
		if ability.operation == "damage": ability.damage_min=1; ability.damage_max=1
	var combat: Sm2CombatCatalog=Sm2CombatCatalog.new()
	combat.build(raw,c.catalog)
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	development.build(c.development.to_data(),c.development.progression(),combat)
	return {"catalog":c.catalog,"combat":combat,"development":development,"setup":c.setup}

static func four_attacks(t: Sm2TestHarness,c: Dictionary) -> Sm2TacticalBattle:
	var b: Sm2TacticalBattle=make(c,adjacent_setup(c))
	t.expect(not b.view().is_empty(),"P2 real battle fixture starts")
	for index: int in 4:
		for skipped: int in 12:
			if b.view().active_actor_id == 1 and b.preview(command(b)).allowed: break
			t.expect(b.execute(command(b,"end_turn",0)).accepted,"P2 pass other activations")
		var before: String=b.state_hash()
		var cmd: Sm2Command=command(b)
		var forecast: Dictionary=b.preview(cmd)
		t.expect(forecast.allowed,"P2 sword forecast allowed")
		t.equal(b.state_hash(),before,"P2 preview does not train")
		var result: Sm2CommandResult=b.execute(cmd)
		t.expect(result.accepted,"P2 real attack accepted "+result.code)
		for event: Dictionary in result.events:
			if event.type == "attack_attempted": t.equal(event.hit_chance,forecast.hit_chance,"P2 executed chance matches current preview")
		t.equal(track(b,1,MELEE).earned,(index+1)*40,"P2 own attack gives own melee XP")
		t.equal(track(b,2,MELEE).earned,0,"P2 companion not trained by hero")
		t.equal(track(b,1,"p1:skill.psionics").earned,0,"P2 sword does not train psionics")
		var saved: String=b.state_hash()
		t.expect(not b.execute(cmd).accepted,"P2 repeated command rejected")
		t.equal(b.state_hash(),saved,"P2 repeat inert including XP and RNG")
	return b

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2DevelopmentContentLoader.load_scenario()
	t.expect(c.ok,"P2 authored content loads "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("p2_development"); return
	_catalog(t,c)
	var fixture: Dictionary=practice_fixture(c)
	var b: Sm2TacticalBattle=four_attacks(t,fixture)
	t.equal([track(b,1,STRENGTH).earned,track(b,1,STRENGTH).level,track(b,1,STRENGTH).progress,track(b,1,MELEE).earned,track(b,1,MELEE).level,track(b,1,MELEE).progress],[120,11,20,160,2,60],"P2 four attacks independent numeric oracle")
	t.equal(actor(b,1).melee_stat.value,72,"P2 individual melee 70 + 2 after growth")
	t.equal(actor(b,2).melee_stat.value,70,"P2 same template companion stays at baseline")
	var buy: Sm2Command=command(b,"buy_node",1); buy.actor_id=1; buy.ability_id="p1:node.strength_1"
	var before: String=b.state_hash()
	t.equal(b.execute(buy).code,"nodes_after_battle","P2 nodes cannot be bought during battle")
	t.equal(b.state_hash(),before,"P2 early purchase inert")
	var wrong_world: Sm2Command=command(b,"end_turn",0); wrong_world.battle_id="other-world"
	t.equal(b.execute(wrong_world).code,"wrong_battle","P2 rejects command from another world with same revision")
	t.equal(b.state_hash(),before,"P2 wrong-world command inert")
	var restored: Sm2TacticalBattle=make(fixture,adjacent_setup(fixture))
	t.expect(restored.restore(JSON.parse_string(JSON.stringify(b.capture()))).ok,"P2 JSON restores combined state")
	t.equal(restored.state_hash(),b.state_hash(),"P2 same battle and progression after reload")
	var next: Sm2Command=command(b,"end_turn",0)
	t.equal(Sm2Canonical.hash(b.execute(next).events),Sm2Canonical.hash(restored.execute(next).events),"P2 following command same events")
	t.equal(b.state_hash(),restored.state_hash(),"P2 following command same state")
	_negative(t,fixture,b)
	_hit_miss_and_reaction(t,c)
	_atomic(t,c)
	_ai_queries(t,fixture)
	_unrelated(t,c)
	_full(t,c)
	t.complete_suite("p2_development")

static func _catalog(t: Sm2TestHarness,c: Dictionary) -> void:
	var original: String=c.development.fingerprint()
	for defect: String in ["version","actor","track","negative","operation","duplicate_mapping","max_stat"]:
		var raw: Dictionary=c.development.to_data()
		match defect:
			"version": raw.version="unknown"
			"actor": raw.companion_actor_id=raw.hero_actor_id
			"track": raw.awards[STRIKE]={"missing":40}
			"negative": raw.awards[STRIKE][MELEE]=-1
			"operation": raw.awards={"m2:ability.shieldwall":{MELEE:40}}
			"duplicate_mapping": raw.mappings.append(raw.mappings[0].duplicate(true))
			"max_stat": raw.mappings[0].stat="hp_max"
		t.expect(not c.development.build(raw,c.development.progression(),c.combat).is_empty(),"P2 rejects catalog "+defect)
		t.equal(c.development.fingerprint(),original,"P2 catalog failure atomic")
	var detached: Dictionary=c.development.to_data(); detached.awards.clear()
	t.equal(c.development.fingerprint(),original,"P2 catalog reads detached")
	var old: Sm2TacticalBattle=Sm2TacticalBattle.new(c.catalog,c.combat,true)
	t.expect(old.start(c.setup).ok,"P2 source setup valid in legacy engine")
	t.expect(not old.capture().has("development"),"P2 opt in leaves legacy schema untouched")

static func _negative(t: Sm2TestHarness,c: Dictionary,b: Sm2TacticalBattle) -> void:
	var expected: String=b.state_hash()
	for defect: String in ["version","fingerprint","world","body_id","binding","xp","spent","counts","sequence","soul","extra","nodes_during_battle"]:
		var data: Dictionary=b.capture()
		match defect:
			"version": data.schema_version=7
			"fingerprint": data.development.fingerprint="wrong"
			"world": data.development.world_id="another"
			"body_id": data.development.members[1].body.id="2"
			"binding": data.development.members[1].actor_id="1"
			"xp": data.development.members[0].body.tracks[0].earned_total+=1
			"spent": data.development.members[0].body.tracks[0].spent_total=1
			"counts": data.development.members[0].attacks[0].count+=1
			"sequence": data.development.sequence="100"
			"soul": data.development.soul.incarnation_id="4"
			"extra": data["made_up"]=true
			"nodes_during_battle":
				data.development.members[0].body.tracks[0].owned_nodes=["p1:node.melee_1"]
				data.development.members[0].body.tracks[0].spent_total=60
		t.expect(not b.restore(data).ok,"P2 rejects snapshot "+defect)
		t.equal(b.state_hash(),expected,"P2 bad load leaves active battle intact")
	var legacy: Sm2TacticalBattle=Sm2TacticalBattle.new(c.catalog,c.combat,true)
	legacy.start(c.setup)
	t.expect(not legacy.restore(b.capture()).ok,"P2 snapshot not loaded into legacy")
	t.expect(not b.restore(legacy.capture()).ok,"P2 no automatic legacy migration")

static func _hit_miss_and_reaction(t: Sm2TestHarness,c: Dictionary) -> void:
	var outcomes: Dictionary={}
	for seed_value: int in range(1,40):
		var setup: Dictionary=adjacent_setup(c); setup.seed=seed_value
		var b: Sm2TacticalBattle=make(c,setup)
		var result: Sm2CommandResult=b.execute(command(b))
		for event: Dictionary in result.events:
			if event.type in ["attack_hit","attack_missed"]: outcomes[event.type]=true
		t.equal(track(b,1,MELEE).earned,40,"P2 completed hit or miss awards exactly once")
		if outcomes.size() == 2: break
	t.equal(outcomes.size(),2,"P2 both hit and miss actually observed")
	var b: Sm2TacticalBattle=make(c,adjacent_setup(c))
	for index: int in 2: t.expect(b.execute(command(b,"end_turn",0)).accepted,"P2 reach enemy activation")
	t.equal(b.view().active_actor_id,3,"P2 enemy moves under hero control zone")
	var move: Sm2Command=command(b,"move",0); move.target=Vector2i(3,1)
	var result: Sm2CommandResult=b.execute(move)
	t.expect(result.accepted,"P2 reaction departure accepted "+result.code)
	t.equal(track(b,1,MELEE).earned,40,"P2 reacting hero earns own XP")
	t.equal(track(b,2,MELEE).earned,0,"P2 reaction does not train companion")
	var reaction: bool=false
	for event: Dictionary in result.events:
		if event.type == "reaction_spent" and event.actor_id == "1": reaction=true
	t.expect(reaction,"P2 actual reaction executed")

static func _atomic(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle=make(c,adjacent_setup(c))
	var raw: Dictionary=b.capture(); raw.rng.draws="9223372036854775806"
	t.expect(b.restore(raw).ok,"P2 RNG ceiling fixture valid")
	var before: String=b.state_hash()
	t.expect(not b.execute(command(b)).accepted,"P2 late RNG refusal")
	t.equal(b.state_hash(),before,"P2 late RNG refusal retains battle and experience")
	# Coherent near-cap history: next real attempt must roll back its resources and RNG.
	b=make(c,adjacent_setup(c)); raw=b.capture(); raw.revision="25000"
	raw.development.sequence="25000"; raw.development.members[0].attacks[0].count=25000
	for row: Dictionary in raw.development.members[0].body.tracks:
		row.earned_total=1000000 if row.track_id == MELEE else 750000 if row.track_id == STRENGTH else 0
	t.expect(b.restore(raw).ok,"P2 coherent XP cap fixture valid")
	before=b.state_hash()
	var result: Sm2CommandResult=b.execute(command(b))
	t.equal(result.code,"experience_limit","P2 late XP cap rejected")
	t.equal(b.state_hash(),before,"P2 XP refusal rolls back attack HP armor RNG resources and counters")
	t.equal(result.events.size(),0,"P2 refused events not published")
	b=make(c,adjacent_setup(c))
	for i: int in 2: b.execute(command(b,"end_turn",0))
	raw=b.capture(); raw.revision="25002"; raw.development.sequence="25000"; raw.development.members[0].attacks[0].count=25000
	for row: Dictionary in raw.development.members[0].body.tracks: row.earned_total=1000000 if row.track_id == MELEE else 750000 if row.track_id == STRENGTH else 0
	t.expect(b.restore(raw).ok,"P2 capped reaction fixture restores")
	before=b.state_hash()
	var departure: Sm2Command=command(b,"move",0); departure.target=Vector2i(3,1)
	t.equal(b.execute(departure).code,"experience_limit","P2 reaction late refusal propagated")
	t.equal(b.state_hash(),before,"P2 reaction refusal rolls back enemy move and all participants")

static func _ai_queries(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle=four_attacks(t,c)
	var decoded: Dictionary=Sm2DevelopmentSnapshot.decode(b.capture(),c.catalog,c.combat,null,null,c.development)
	t.expect(decoded.ok,"P2 AI test state decodes")
	decoded.state.actor(1).spatial.ap=decoded.state.actor(1).spatial.ap_max
	decoded.state.actor(1).spatial.fatigue=0
	var query: Sm2AiQueries=Sm2AiQueries.new(decoded.state,c.combat)
	var cmd: Sm2Command=command(b); cmd.actor_id=1
	var source: Sm2TacticalActor=decoded.state.actor(1)
	var expected: Dictionary=Sm2AttackResolver.preview(decoded.state,c.combat,cmd)
	var predicted: Dictionary=query.attack(cmd,source.spatial.position)
	t.expect(predicted.allowed and expected.allowed,"P2 AI numeric forecast is a complete affordable attack")
	t.equal(predicted.hit_chance,expected.hit_chance,"P2 AI and resolver share developed skill")
	t.equal(predicted.modifiers.skill,72,"P2 AI uses numeric developed skill rather than old profile")
	decoded.state.development.bodies[1].tracks[MELEE].earned=0
	t.equal(query.attack(cmd,source.spatial.position).hit_chance,predicted.hit_chance,"P2 AI projection detached from later live mutations")

static func _unrelated(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle=make(c,adjacent_setup(c))
	var wall: Sm2Command=command(b,"use_ability",1); wall.ability_id="m2:ability.shieldwall"
	t.expect(b.execute(wall).accepted,"P2 shield stance is real accepted action")
	t.equal(track(b,1,MELEE).earned,0,"P2 stance gives no melee XP")
	t.expect(b.execute(command(b,"wait",0)).accepted,"P2 wait accepted")
	t.equal(track(b,1,STRENGTH).earned,0,"P2 wait gives no strength XP")
	var effects: Dictionary=Sm2EffectContentLoader.load_scenario()
	var layered: Sm2TacticalBattle=Sm2TacticalBattle.new(c.catalog,c.combat,true,effects.effects,null,c.development)
	t.expect(layered.start(adjacent_setup(c)).ok,"P2 development can preserve effect layer")
	t.expect(layered.execute(command(layered)).accepted,"P2 ordinary strike with effect layer")
	var clone: Sm2TacticalBattle=Sm2TacticalBattle.new(c.catalog,c.combat,true,effects.effects,null,c.development)
	t.expect(clone.restore(layered.capture()).ok,"P2 layered snapshot restores")
	t.equal(clone.state_hash(),layered.state_hash(),"P2 layered snapshot exact")

static func _full(t: Sm2TestHarness,c: Dictionary) -> void:
	var ai: Sm2AiProfile=Sm2AiContentLoader.load_profile().profile
	var player: Sm2BattleRunner=Sm2BattleRunner.new(c.catalog,c.combat,ai,null,false,null,null,c.development)
	t.expect(player.new_battle(c.setup).ok,"P2 player runner starts")
	t.equal(player.step().status,"player_turn","P2 waits for player")
	for seed_value: int in [20260910,1,76]:
		var setup: Dictionary=c.setup.duplicate(true); setup.seed=seed_value
		var store: Sm2SaveStore=Sm2SaveStore.new("user://p2-tests/"+str(seed_value))
		var runner: Sm2BattleRunner=Sm2BattleRunner.new(c.catalog,c.combat,ai,store,true,null,null,c.development)
		t.expect(runner.new_battle(setup).ok,"P2 full battle starts")
		var initial: Dictionary=runner.capture().session
		var history: Array=[]
		for step_index: int in 1000:
			var step: Dictionary=runner.step()
			t.expect(step.ok,"P2 full battle step "+str(step.get("reason","")))
			if not step.ok: break
			if step.has("command"): history.append(step)
			if step_index == 9:
				t.expect(runner.save_game().ok,"P2 save mid battle")
				var clone: Sm2BattleRunner=Sm2BattleRunner.new(c.catalog,c.combat,ai,store,true,null,null,c.development)
				t.expect(clone.load_game().ok,"P2 load mid battle")
				t.equal(clone.state_hash(),runner.state_hash(),"P2 disk preserves combined state")
				runner=clone
			if step.status == "finished": break
		t.expect(runner.view().finished,"P2 real full battle reaches outcome")
		for member: Dictionary in runner.view().actors:
			if not member.has("development"): continue
			for node_id: String in ["p1:node.strength_1","p1:node.melee_1"]:
				var purchase: Sm2Command=Sm2Command.new()
				purchase.kind="buy_node"; purchase.battle_id=runner.view().battle_id; purchase.actor_id=member.actor_id; purchase.target_actor_id=member.actor_id; purchase.ability_id=node_id; purchase.expected_revision=runner.view().revision
				var check: Dictionary=runner.preview(purchase)
				if not check.allowed: continue
				var purchased: Sm2CommandResult=runner.execute_player(purchase)
				t.expect(purchased.accepted,"P2 earned node purchased after real full battle")
				history.append({"command":Sm2TacticalAi.command_data(purchase),"code":purchased.code,"events":purchased.events})
		var replay: Dictionary=Sm2BattleReplay.replay(c.catalog,c.combat,initial,history,null,null,c.development)
		t.expect(replay.ok,"P2 full replay "+str(replay.get("reason","")))
		if replay.ok: t.equal(replay.hash,Sm2Canonical.hash(runner.capture().session),"P2 replay same battle and progression")
		var hash: String=runner.state_hash()
		t.equal(runner.step().record.code,"already_recorded","P2 outcome recorded once")
		t.equal(runner.state_hash(),hash,"P2 repeated completion does not train")
		t.expect(runner.save_game().ok,"P2 save finished state")
		var loaded: Sm2BattleRunner=Sm2BattleRunner.new(c.catalog,c.combat,ai,store,true,null,null,c.development)
		t.expect(loaded.load_game().ok,"P2 reload real post-combat purchases")
		t.equal(loaded.state_hash(),runner.state_hash(),"P2 final save persists purchased nodes")
		var saved_hash: String=runner.state_hash()
		Sm2BattleReplay.replay(c.catalog,c.combat,initial,history,null,null,c.development)
		t.equal(runner.state_hash(),saved_hash,"P2 isolated replay cannot award live session twice")
		var summary: Array[Dictionary] = []
		for member: Dictionary in runner.view().actors:
			if member.has("development"): summary.append({"actor":member.actor_id,"alive":member.alive,"practice":member.development.attacks})
		print("P2_FULL ",seed_value," ",JSON.stringify({"winner":runner.view().winner,"commands":history.size(),"members":summary}))
	# Controlled post-combat purchase fixture; full histories are exercised above.
	var setup: Dictionary=c.setup.duplicate(true)
	setup.actors[2].on_field=false; setup.actors[3].on_field=false
	var b: Sm2TacticalBattle=make(c,setup)
	var raw: Dictionary=b.capture(); raw.revision="4"; raw.development.sequence="4"
	raw.development.members[0].attacks[0].count=4
	for row: Dictionary in raw.development.members[0].body.tracks: row.earned_total=160 if row.track_id == MELEE else 120 if row.track_id == STRENGTH else 0
	t.expect(b.restore(raw).ok,"P2 controlled finished progression fixture")
	for id: String in ["p1:node.strength_1","p1:node.melee_1"]:
		var buy: Sm2Command=command(b,"buy_node",1); buy.actor_id=1; buy.ability_id=id
		t.expect(b.execute(buy).accepted,"P2 purchase after battle")
	t.equal([track(b,1,STRENGTH).available,track(b,1,MELEE).available,track(b,1,STRENGTH).level,track(b,1,MELEE).level,actor(b,1).melee_stat.value],[50,100,11,2,78],"P2 purchase numeric oracle and unchanged levels")
	t.equal(track(b,2,MELEE).spent,0,"P2 purchase never spends companion XP")
	var original: String=b.state_hash()
	var duplicate: Sm2Command=command(b,"buy_node",1); duplicate.actor_id=1; duplicate.ability_id="p1:node.melee_1"
	t.equal(b.execute(duplicate).code,"node_owned","P2 duplicate node refused")
	t.equal(b.state_hash(),original,"P2 duplicate node cannot spend twice")
	duplicate.actor_id=3; duplicate.target_actor_id=3
	t.equal(b.execute(duplicate).code,"development_owner","P2 cannot purchase for enemy")
	t.equal(b.state_hash(),original,"P2 enemy purchase inert")
