extends RefCounted
const IMPLANTS=preload("res://tests/scenarios/test_p5_implants.gd")
const PSI=preload("res://tests/scenarios/test_p5_psionics.gd")
const CROSS=preload("res://tests/scenarios/test_p5_cross_nodes.gd")
const ID: String="p5:ability.psionic_strike"
const NODE: String="p5:node.psionic_strike"
const SWORD: String="m2:ability.sword_strike"
const MELEE: String="p1:skill.melee"
const TRACK: String="p1:skill.psionics"

static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2HybridContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)

static func fixture(t: Sm2TestHarness,seed_value: int=1,enhanced: bool=false,learned: bool=true,capped: bool=false) -> Sm2TacticalBattle:
	var session: Sm2JourneySession=make(); session.world.start("hybrid-oracle")
	var body: Sm2ProgressBodyState=session.world.bodies[2].progress
	body.tracks[MELEE].earned=100; body.tracks[TRACK].earned=250
	if learned: Sm2ProgressRules.purchase(body,session._content.development.progression().node(NODE))
	if capped: body.tracks[TRACK].earned=Sm2ProgressCatalog.XP_LIMIT
	if enhanced:
		for id: String in [IMPLANTS.ID,IMPLANTS.UPGRADES.ID]:
			session.world.apply(session.command("collect_upgrade",0,id)); session.world.apply(session.command("apply_upgrade",2,id))
	var content: Dictionary=Sm2EncounterFactory.build(session._content,session.journey()); t.expect(content.ok,"hybrid encounter compiles")
	if not content.ok: return null
	content.setup.seed=seed_value; content.setup.actors[2].q=2; content.setup.actors[2].r=1
	var battle: Sm2TacticalBattle=Sm2TacticalBattle.new(content.catalog,content.combat,true,content.effects,content.magic,content.development,content.origin)
	t.expect(battle.start(content.setup).ok,"hybrid battle starts")
	return battle

static func command(b: Sm2TacticalBattle,id: String=ID) -> Sm2Command: return PSI.bc(b,"use_ability",id,3)

static func prepared(t: Sm2TestHarness,store: Sm2SaveStore=null) -> Sm2JourneySession:
	var s: Sm2JourneySession=make(store)
	t.expect(s.new_game().ok,"production hybrid game starts")
	IMPLANTS.install(s,t)
	t.expect(s.act(s.command("start_battle")).ok,"production first encounter")
	PSI.JOURNEY.finish(s,t)
	if s.world.hero_id()==0:
		t.expect(s.act(s.command("incarnate",8)).ok,"production new body after defeat")
		for item: Dictionary in s.journey().items:
			if item.definition_id=="m2:equipment.sword" and item.owner_id=="2":
				t.expect(s.act(s.command("transfer",8,item.id)).ok,"retrieve former sword")
				t.expect(s.act(s.command("equip",0,item.id)).ok,"equip recovered sword"); break
	var hero: int=s.world.hero_id()
	t.expect(hero>0,"living hero for training")
	for i: int in 3: t.expect(s.act(s.command("practice",hero)).ok,"real sword exercise after encounter")
	for i: int in 10: t.expect(s.act(s.command("practice",hero,PSI.PRACTICE)).ok,"real psi exercise")
	return s

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2HybridContentLoader.load_scenario()
	t.expect(c.ok,"hybrid content loads "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("p5_hybrids"); return
	_catalog(t,c); _combat(t); _boundaries(t); _journey(t); _shield(t)
	t.complete_suite("p5_hybrids")

static func _catalog(t: Sm2TestHarness,c: Dictionary) -> void:
	t.equal(c.development.hybrids().ids(),[ID],"one authored hybrid")
	t.equal(c.development.awards(ID),{MELEE:20,"p1:stat.strength":5,TRACK:20,"p4a:stat.resonance":5},"one combined practice award")
	t.expect(not c.combat.gear("m2:equipment.sword").abilities.has(ID),"equipment does not grant learned ability")
	for defect: String in ["unknown_base","ranged","same","unknown_node","zero_cost","negative_damage","growth","award","missing_direction","extra_field"]:
		var raw: Dictionary=c.development.hybrids().to_data(); var entry: Dictionary=raw.abilities[0]
		match defect:
			"unknown_base": entry.base_attack="missing"
			"ranged": entry.base_attack="m2:ability.bow_shot"
			"same": entry.base_attack=ID
			"unknown_node": entry.required_node="missing"
			"zero_cost": entry.concentration_cost=0
			"negative_damage": entry.damage=-1
			"growth": entry.damage_scaling.terms[0].track_id="missing"
			"award": entry.awards[TRACK]=true
			"missing_direction": entry.awards.erase(MELEE)
			"extra_field": entry.script="forbidden"
		t.expect(not Sm2HybridCatalog.new().build(raw,c.development.progression(),c.combat).is_empty(),"invalid hybrid "+defect)
	var rules: Dictionary=c.development.to_data(); rules.version=Sm2DevelopmentCatalog.IMPLANT_VERSION
	t.expect(not Sm2DevelopmentCatalog.new().build(rules,c.development.progression(),c.combat).is_empty(),"old profile rejects hybrid layer")

static func _combat(t: Sm2TestHarness) -> void:
	var hit_seen: bool=false; var miss_seen: bool=false
	for seed_value: int in range(1,13):
		var b: Sm2TacticalBattle=fixture(t,seed_value); var ordinary: Sm2TacticalBattle=fixture(t,seed_value)
		if b==null or ordinary==null: return
		var before: String=b.state_hash(); var p: Dictionary=b.preview(command(b))
		t.expect(p.allowed,"learned sword action available")
		t.equal(p.hybrid.psionic_damage,8,"own psi2 adds two above base6")
		t.equal(p.mana_cost,6,"base focus price6")
		t.equal(b.state_hash(),before,"forecast inert")
		var ai: Sm2AiQueries=Sm2AiQueries.new(b._state,b._combat)
		t.equal(ai.action(command(b),b._state.actor(1).spatial.position),p,"AI query uses same combined forecast")
		t.equal(ai.action_info(ID).mana_cost,6,"AI metadata shares focus price")
		var old_hp: int=b._state.actor(3).combat.hp
		var result: Sm2CommandResult=b.execute(command(b)); var physical: Sm2CommandResult=ordinary.execute(command(ordinary,SWORD))
		t.expect(result.accepted and physical.accepted,"real paired attacks")
		var hit: bool=false
		for event: Dictionary in result.events:
			if event.type=="attack_hit": hit=true
		if hit:
			hit_seen=true
			t.equal(b._state.actor(3).combat.hp,maxi(0,ordinary._state.actor(3).combat.hp-8),"physical HP plus8 psi on hit")
			for slot: String in ["head","body"]:
				t.equal(b._state.actor(3).combat.item(slot).current,ordinary._state.actor(3).combat.item(slot).current,"psi does not damage armor")
			var delta: int=old_hp-b._state.actor(3).combat.hp
			var in_range: bool=false
			for zone: Dictionary in p.zones: in_range=in_range or (delta>=zone.hp_min and delta<=zone.hp_max)
			t.expect(in_range,"actual combined loss within forecast")
		else:
			miss_seen=true; t.equal(b._state.actor(3).combat.hp,old_hp,"miss causes no physical or psi HP loss")
		t.equal(b._state.mana[1].current,6,"hit and miss both spend concentration once")
		t.equal(b._state.development.bodies[1].tracks[MELEE].earned,120,"melee practice exactly once")
		t.equal(b._state.development.bodies[1].tracks[TRACK].earned,270,"psi practice exactly once")
		t.equal(b._state.development.counts[1][ID],1,"one hybrid activity")
		t.equal(b._state.development.counts[1][SWORD],0,"no second ordinary activity")
		var restored: Sm2TacticalBattle=fixture(t,seed_value)
		t.expect(restored.restore(b.capture()).ok,"combined attack snapshot restores")
		t.equal(restored.state_hash(),b.state_hash(),"reloaded state exact")
	t.expect(hit_seen and miss_seen,"deterministic seeds exercise hit and miss")

static func _boundaries(t: Sm2TestHarness) -> void:
	var b: Sm2TacticalBattle=fixture(t,1,true)
	t.equal(b.capture().schema_version,18,"explicit schema18")
	var p: Dictionary=b.preview(command(b))
	t.equal([p.hybrid.psionic_damage,p.mana_cost,p.fatigue_cost],[10,7,12],"genetics and implant stack with own practice")
	t.expect(not Sm2AttackResolver.preview(b._state,b._combat,command(b),true).allowed,"hybrid never automatic reaction")
	var unlearned: Sm2TacticalBattle=fixture(t,1,false,false)
	var before: String=unlearned.state_hash()
	t.expect(not unlearned.execute(command(unlearned)).accepted,"unlearned hybrid refused")
	t.equal(unlearned.state_hash(),before,"unlearned refusal atomic")
	b=fixture(t,1,false,true,true); before=b.state_hash()
	t.expect(not b.execute(command(b)).accepted,"late practice limit rejects complete attack")
	t.equal(b.state_hash(),before,"late refusal rolls back focus HP armor RNG and XP")
	b=fixture(t); b._state.mana[1].current=5; before=b.state_hash()
	t.equal(b.preview(command(b)).reason,"insufficient_concentration","insufficient focus explained")
	t.expect(not b.execute(command(b)).accepted,"insufficient focus refuses")
	t.equal(b.state_hash(),before,"insufficient focus changes nothing")
	b=fixture(t,2); b._state.rng.draws=Sm2AttackResolver.MAX_COUNTER-1; before=b.state_hash()
	t.expect(not b.execute(command(b)).accepted,"late RNG exhaustion after resource debit refuses")
	t.equal(b.state_hash(),before,"late RNG refusal restores focus AP fatigue and all state")
	b=fixture(t); before=b.state_hash()
	for target: int in [1,2,4]:
		var bad: Sm2Command=command(b); bad.target_actor_id=target
		t.expect(not b.execute(bad).accepted,"invalid hybrid target "+str(target))
		t.equal(b.state_hash(),before,"invalid target has no costs")
	var state: Sm2TacticalState=fixture(t)._state.copy()
	state.actor(1).body_functions.working.right_hand=false
	t.expect(not Sm2AttackResolver.available_abilities(state.actor(1),b._combat,state).has(ID),"disabled weapon hand removes hybrid")
	t.expect(not Sm2AttackResolver.available_abilities(state.actor(2),b._combat,state).has(ID),"companion cannot use hero hybrid")
	state=fixture(t)._state.copy()
	state.actor(1).combat.items.erase("weapon")
	t.expect(not Sm2AttackResolver.available_abilities(state.actor(1),b._combat,state).has(ID),"learned node alone cannot replace sword")
	var legacy: Sm2JourneySession=IMPLANTS.make(); legacy.new_game()
	var current: Sm2JourneySession=make(); t.expect(current.new_game().ok,"new hybrid journey")
	t.expect(not current.restore(legacy.capture()).ok and not legacy.restore(current.capture()).ok,"old and new saves reject crossload")

static func _journey(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=prepared(t,Sm2SaveStore.new("user://hybrid-production-core"))
	var hero: int=s.world.hero_id()
	var before: String=s.state_hash()
	var model: Dictionary=Sm2HeroDevelopmentView.build(s,MELEE)
	var shown: bool=false
	for node: Dictionary in model.nodes:
		if node.id==NODE: shown=node.allowed and str(node.effects).contains("промахе")
	t.expect(shown,"hero card describes learned action and miss rule")
	t.equal(s.state_hash(),before,"hero description inert")
	t.expect(s.act(s.command("buy_node",hero,NODE)).ok,"real dual-wallet learn in production game")
	t.equal([s.world.bodies[hero].progress.tracks[MELEE].spent,s.world.bodies[hero].progress.tracks[TRACK].spent],[70,90],"production dual price")
	t.expect(s.save_game().ok and s.load_game().ok,"production camp roundtrip")
	t.expect(s.act(s.command("start_battle")).ok,"next encounter carries node")
	var battle: Sm2TacticalBattle=s.runner._session._battle
	t.expect(battle.view().actors[0].abilities.has(ID),"next encounter exposes learned action")
	var blocked: String=s.state_hash()
	t.expect(not s.act(s.command("buy_node",hero,NODE)).ok,"learning unavailable during combat")
	t.equal(s.state_hash(),blocked,"combat purchase refusal atomic")
	var cast: bool=false
	for i: int in 40:
		if not s.world.busy(): break
		if int(s.runner.view().active_actor_id)==1:
			for victim: int in [3,4]:
				var action: Sm2Command=PSI.command(s,"use_ability",ID,victim)
				if s.runner.preview(action).allowed:
					t.expect(s.attack(action).accepted,"real learned hybrid in production encounter"); cast=true; break
		if cast: break
		t.expect(PSI.JOURNEY.advance(s).ok,"approach through actual turn commands")
	t.expect(cast,"production hybrid reaches valid target")
	before=s.state_hash(); t.expect(s.save_game().ok and s.load_game().ok,"active production save with hybrid count")
	t.equal(s.state_hash(),before,"production active reload exact")
	if s.world.busy(): PSI.JOURNEY.finish(s,t)
	t.expect(not s.world.busy(),"production outcome completes")
	var survivor: int=s.world.hero_id()
	if survivor>0: t.expect(s.act(s.command("end_life")).ok,"end developed body")
	var next_body: int=8 if hero!=8 else 9
	t.expect(s.act(s.command("incarnate",next_body)).ok,"new embodiment after hybrid history")
	t.expect(not NODE in s.world.bodies[next_body].progress.tracks[MELEE].nodes,"new body does not inherit hybrid")
	t.equal(s.world.bodies[next_body].progress.tracks[TRACK].earned,0,"new body has zero psi practice")
	t.expect(s.save_game().ok and s.load_game().ok,"closed encounters and new body history roundtrip")

static func _shield(t: Sm2TestHarness) -> void:
	# Detached diagnostic shields on the victim exercise shared absorption without
	# granting enemy shield learning. This fixture is not a serializable journey.
	for capacity: int in [1,20,1000]:
		var b: Sm2TacticalBattle=fixture(t,2)
		var state: Sm2TacticalState=b._state.copy(); var victim: Sm2TacticalActor=state.actor(3)
		victim.barrier.remaining=capacity; victim.barrier.capacity=capacity
		var cmd: Sm2Command=command(b)
		var p: Dictionary=Sm2AttackResolver.preview(state,b._combat,cmd)
		var result: Dictionary=Sm2AttackResolver.resolve(state,b._combat,cmd)
		t.expect(result.accepted,"diagnostic shield target attacked")
		var incoming: int=0; var absorbed: int=0; var hit: bool=false
		for event: Dictionary in result.events:
			if event.type=="hybrid_damage": incoming=int(event.physical)+int(event.psionic); hit=true
			if event.type=="barrier_absorbed": absorbed+=int(event.amount)
		t.expect(hit,"shield oracle seed hits")
		t.equal(absorbed,mini(capacity,incoming),"shield absorbs combined components once")
		t.equal(victim.combat.hp,60-mini(60,maxi(0,incoming-capacity)),"HP cap applied after shield and combined input")
		var fits: bool=false
		for zone: Dictionary in p.zones: fits=fits or (60-victim.combat.hp>=zone.hp_min and 60-victim.combat.hp<=zone.hp_max)
		t.expect(fits,"shield forecast and actual HP agree")
