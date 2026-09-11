extends RefCounted
const GROWTH=preload("res://tests/scenarios/test_p5_growth.gd")
const PSI=preload("res://tests/scenarios/test_p5_psionics.gd")
const TRACK: String="p1:skill.psionics"
const RESONANCE: String="p4a:stat.resonance"
const NODE: String="p5:node.shield"
const ABILITY: String="p5:ability.shield"

static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2PsionicShieldContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)

static func learn(s: Sm2JourneySession,t: Sm2TestHarness) -> void:
	for i: int in 8: t.expect(s.act(s.command("practice",s.world.hero_id(),PSI.PRACTICE)).ok,"practice for both independent nodes")
	for node: String in [PSI.NODE,NODE]: t.expect(s.act(s.command("buy_node",s.world.hero_id(),node)).ok,"learn "+node)

static func fixture(t: Sm2TestHarness,xp: int=200,res_xp: int=0) -> Sm2TacticalBattle:
	var s: Sm2JourneySession=make(); s.world.start("p5:shield-fixture")
	var body: Sm2ProgressBodyState=s.world.bodies[2].progress
	body.tracks[TRACK].earned=xp; body.tracks[TRACK].spent=200; body.tracks[TRACK].nodes.assign([PSI.NODE,NODE]); body.tracks[RESONANCE].earned=res_xp
	s.world.apply(s.command("start_battle"))
	var c: Dictionary=Sm2EncounterFactory.build(s._content,s.journey()); t.expect(c.ok,"shield encounter compiles")
	c.setup.actors[2].q=2; c.setup.actors[2].r=1
	var b: Sm2TacticalBattle=Sm2TacticalBattle.new(c.catalog,c.combat,true,c.effects,c.magic,c.development,c.origin)
	var started: Dictionary=b.start(c.setup); t.expect(started.ok,"shield battle starts "+str(started.get("errors",[]))); return b

static func cast(b: Sm2TacticalBattle) -> Sm2Command: return PSI.bc(b,"use_ability",ABILITY,1)

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2PsionicShieldContentLoader.load_scenario(); t.expect(c.ok,"shield content "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("p5_shield"); return
	_catalog(t,c)
	var b: Sm2TacticalBattle=fixture(t)
	if b._state==null: t.complete_suite("p5_shield"); return
	_transactions(t)
	_damage(t)
	_other_damage(t)
	_partial_save(t)
	_lives(t)
	t.complete_suite("p5_shield")

static func _catalog(t: Sm2TestHarness,c: Dictionary) -> void:
	var progress: Sm2ProgressCatalog=c.development.progression(); var psi: Sm2PsionicCatalog=c.development.psionics()
	var body: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(2,progress)
	t.equal(Sm2ProgressRules.purchase_error(body,progress,NODE),"level_required","natural resonance does not teach shield")
	for data: Array in [[100,0,18],[250,0,20],[100,250,20],[250,250,22]]:
		body.tracks[TRACK].earned=data[0]; body.tracks[RESONANCE].earned=data[1]
		t.equal(psi.capacity(ABILITY,body,progress).total,data[2],"shield skill/resonance formula "+str(data))
	var raw: Dictionary=psi.to_data()
	for value: Variant in [-1,0,10001,"18"]:
		var bad: Dictionary=raw.duplicate(true); bad.abilities[1].capacity=value
		t.expect(not Sm2PsionicCatalog.new().build(bad,progress,c.combat).is_empty(),"invalid capacity "+str(value))
	var bad: Dictionary=raw.duplicate(true); bad.version=Sm2PsionicCatalog.GROWTH_VERSION
	t.expect(not Sm2PsionicCatalog.new().build(bad,progress,c.combat).is_empty(),"old catalog rejects shield")
	bad=raw.duplicate(true); bad.abilities[1].operation="execute_script"
	t.expect(not Sm2PsionicCatalog.new().build(bad,progress,c.combat).is_empty(),"unknown operation rejected")
	bad=c.development.to_data(); bad.version=Sm2DevelopmentCatalog.PSIONIC_GROWTH_VERSION
	t.expect(not Sm2DevelopmentCatalog.new().build(bad,progress,c.combat).is_empty(),"profile agreement strict")

static func _transactions(t: Sm2TestHarness) -> void:
	var b: Sm2TacticalBattle=fixture(t,240,245); var twin: Sm2TacticalBattle=fixture(t,240,245)
	t.equal(b.capture().schema_version,15,"schema15 explicit")
	var before: String=b.state_hash(); var check: Dictionary=b.preview(cast(b))
	t.equal(check.capacity,18,"capacity before new levels")
	var ai: Sm2AiQueries=Sm2AiQueries.new(b._state,b._combat)
	t.equal(ai.action(cast(b),b._state.actor(1).spatial.position),check,"AI reads same capacity")
	var ai_result: Dictionary=b.ai_decision(Sm2AiContentLoader.load_profile(Sm2AiContentLoader.ABILITY_PATH).profile)
	t.expect(ai_result.ok,"existing ability AI safely handles new player ability")
	t.equal(b.state_hash(),before,"queries detached")
	var bad: Sm2Command=cast(b); bad.target_actor_id=2
	t.equal(b.execute(bad).code,"self_target_required","cannot shield ally")
	t.equal(b.state_hash(),before,"invalid target atomic")
	var result: Sm2CommandResult=b.execute(cast(b)); var other: Sm2CommandResult=twin.execute(cast(twin))
	t.expect(result.accepted and other.accepted,"shield cast on both deterministic runs")
	t.equal(result.events,other.events,"identical cast and awards")
	t.equal(b._state.actor(1).barrier.remaining,18,"current cast uses pre-XP capacity")
	t.equal(b._state.mana[1].current,6,"focus paid once")
	t.equal(b._state.actor(1).spatial.ap,b._state.actor(1).spatial.ap_max-4,"exactly four AP paid from nine")
	t.equal(b._state.development.bodies[1].tracks[TRACK].earned,260,"own skill award")
	t.equal(b._state.development.bodies[1].tracks[RESONANCE].earned,250,"own resonance award")
	t.equal(b.preview(cast(b)).capacity,22,"next cast sees both new levels")
	var snapshot: Dictionary=b.capture(); before=b.state_hash()
	t.expect(twin.restore(snapshot).ok,"active shield restores")
	t.equal(twin.state_hash(),before,"load no ticking or recovery")
	for field: String in ["remaining","capacity","expires_round","ability_id"]:
		var forged: Dictionary=snapshot.duplicate(true)
		forged.actors[0].barrier[field]="unknown" if field=="ability_id" else 99999
		t.expect(not twin.restore(forged).ok,"reject corrupt barrier "+field)
		t.equal(twin.state_hash(),before,"bad snapshot atomic")
	var forged: Dictionary=snapshot.duplicate(true); forged.schema_version=14
	t.expect(not twin.restore(forged).ok,"old schema cannot hide barrier")
	result=b.execute(cast(b)); other=twin.execute(cast(twin))
	t.expect(result.accepted and other.accepted,"recast accepted")
	t.equal(b._state.actor(1).barrier.remaining,22,"recast replaces rather than stacks")
	t.equal(b.state_hash(),twin.state_hash(),"loaded continuation identical")
	# Scheduler lifecycle: wait/resume within this activation preserves the pool.
	b=fixture(t); t.expect(b.execute(cast(b)).accepted,"shield before waiting")
	t.expect(b.execute(PSI.bc(b,"wait")).accepted,"wait with barrier")
	for i: int in 12:
		if b._state.active_id()==1: break
		t.expect(b.execute(PSI.bc(b,"end_turn")).accepted,"finish other actors before resumed hero")
	t.equal(b._state.phase,"deferred","hero deferred activation resumes")
	t.equal(b._state.actor(1).barrier.remaining,18,"wait is not another turn")
	t.expect(b.execute(PSI.bc(b,"end_turn")).accepted,"finish resumed hero")
	for i: int in 12:
		if b._state.active_id()==1: break
		t.expect(b.execute(PSI.bc(b,"end_turn")).accepted,"advance next round")
	t.equal(b._state.actor(1).barrier.remaining,0,"expires exactly at next hero activation")
	b=fixture(t,200,Sm2ProgressCatalog.XP_LIMIT-2); before=b.state_hash()
	result=b.execute(cast(b)); t.equal(result.code,"experience_limit","late resonance failure")
	t.equal(b.state_hash(),before,"late failure rolls back shield costs both XP RNG revision")
	t.expect(result.events.is_empty(),"no rejected events")
	var old: Sm2TacticalBattle=GROWTH.fixture(t)
	t.expect(not old.capture().actors[0].has("barrier"),"P5.2 retains original actor fields")
	t.equal(old.preview(PSI.bc(old)).damage,12,"P5.2 original damage remains")

static func _damage(t: Sm2TestHarness) -> void:
	var b: Sm2TacticalBattle=fixture(t); t.expect(b.execute(cast(b)).accepted,"damage fixture shield")
	var state: Sm2TacticalState=b._state.copy(); var hero: Sm2TacticalActor=state.actor(1)
	hero.combat.hp=5
	t.equal(Sm2BarrierRules.loss(hero,20),{"absorbed":18,"hp_loss":2},"overkill clamped after barrier, not before")
	var events: Array[Dictionary]=[]
	t.equal(Sm2BarrierRules.absorb(hero,7,events),0,"first hit fully absorbed")
	t.equal(hero.barrier.remaining,11,"finite remaining capacity")
	t.equal(Sm2BarrierRules.absorb(hero,20,events),5,"second hit exhausts shield and caps HP loss")
	t.equal(hero.barrier.to_data(),{},"exhausted pool canonical empty")
	# Real physical resolver; compare raw oracle and armor before barrier.
	var hit_found: bool=false
	for seed_value: int in range(1,30):
		state=b._state.copy(); hero=state.actor(1); hero.barrier.capacity=1000; hero.barrier.remaining=1000
		state.rng=Sm2DeterministicRng.new(seed_value)
		var attack: Sm2Command=PSI.bc(b,"use_ability","m2:ability.sword_strike",1); attack.actor_id=3
		var preview: Dictionary=Sm2AttackResolver.preview(state,b._combat,attack)
		if not preview.allowed: t.expect(false,"physical fixture available "+str(preview)); break
		for zone: Dictionary in preview.zones: t.equal(zone.hp_max,0,"physical preview respects full barrier")
		var resolved: Dictionary=Sm2AttackResolver.resolve(state,b._combat,attack,false,Sm2ConsequenceContext.new())
		t.expect(resolved.accepted,"physical strike resolves")
		for event: Dictionary in resolved.events:
			if event.type=="attack_hit": hit_found=true
		if hit_found:
			t.equal(hero.combat.hp,b._state.actor(1).combat.hp,"actual hit completely absorbed")
			t.expect(hero.barrier.remaining<1000,"physical hit consumes barrier")
			break
	t.expect(hit_found,"physical absorption tested on actual hit")
	# Direct psionic resolver uses target barrier in forecast and actual damage.
	state=b._state.copy(); var enemy: Sm2TacticalActor=state.actor(3)
	enemy.barrier.capacity=10; enemy.barrier.remaining=10
	var impulse: Sm2Command=PSI.bc(b)
	var preview: Dictionary=Sm2SpellResolver.preview(state,impulse)
	t.equal(preview.hp_loss,2,"12 impulse minus 10 barrier")
	t.equal(preview.absorbed,10,"forecast absorption visible")
	var resolved: Dictionary=Sm2SpellResolver.resolve(state,b._combat,impulse,Sm2ConsequenceContext.new())
	t.expect(resolved.accepted,"psi hit resolves")
	t.equal(enemy.combat.hp,58,"psi actual damage matches forecast")
	t.equal(enemy.barrier.remaining,0,"psi exhausts barrier")
	# Internal damage enters the common HP sink without attack absorption.
	state=b._state.copy(); hero=state.actor(1); events=[]
	Sm2HpApplication.apply(state,hero,3,4,events)
	t.equal(hero.combat.hp,56,"internal damage bypasses shield")
	t.equal(hero.barrier.remaining,18,"internal damage does not spend barrier")
	Sm2HpApplication.apply(state,hero,3,1000,events)
	t.expect(not hero.spatial.alive and hero.barrier.remaining==0,"death clears shield")

static func life_content() -> Dictionary:
	var c: Dictionary=Sm2PsionicShieldContentLoader.load_scenario(); var injury: Dictionary=GROWTH.life_content()
	var dev: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new(); var errors: PackedStringArray=dev.build(c.development.to_data(),c.development.progression(),injury.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	c.combat=injury.combat; c.development=dev; c.setup=injury.setup
	c.journey_fingerprint=Sm2Canonical.hash([c.journey_fingerprint,injury.journey_fingerprint]); return c

static func _other_damage(t: Sm2TestHarness) -> void:
	# Diagnostic compositions exercise shared channels without changing old authored profiles.
	var effects_test: GDScript=load("res://tests/scenarios/test_m4_effects.gd")
	var c: Dictionary=Sm2EffectContentLoader.load_scenario()
	var effect_data: Dictionary=c.effects.to_data()
	for profile: Dictionary in effect_data.profiles: profile.resistances.poison=0
	t.expect(c.effects.build(effect_data,c.combat).is_empty(),"diagnostic zero poison resistance")
	var b: Sm2TacticalBattle=effects_test._battle(t,c)
	var injected: Array[Dictionary]=[effects_test._effect(1,"poison",2,4)]
	effects_test._inject(t,b,injected)
	var state: Sm2TacticalState=b._state.copy(); var target: Sm2TacticalActor=state.actor(2)
	target.barrier=Sm2BarrierState.new(); target.barrier.remaining=18; target.barrier.capacity=18
	var events: Array[Dictionary]=[]
	t.equal(Sm2EffectResolver.end_activation(state,2,c.combat,Sm2ConsequenceContext.new(),events),"","real poison tick")
	t.equal(target.combat.hp,55,"poison bypasses all 18 protection")
	t.equal(target.barrier.remaining,18,"poison preserves shield capacity")
	var area_test: GDScript=load("res://tests/scenarios/test_m4_areas.gd")
	c=Sm2AreaContentLoader.load_scenario(); b=area_test.battle(t,c); state=b._state.copy()
	var command: Sm2Command=area_test.command(b)
	var before: Dictionary=Sm2AreaSpellResolver.preview(state,command)
	t.expect(before.allowed and not before.targets.is_empty(),"area diagnostic valid")
	if before.allowed and not before.targets.is_empty():
		target=state.actor(int(before.targets[0].actor_id)); var hp: int=target.combat.hp
		target.barrier=Sm2BarrierState.new(); target.barrier.remaining=7; target.barrier.capacity=7
		var preview: Dictionary=Sm2AreaSpellResolver.preview(state,command)
		t.equal(preview.targets[0].hp_loss,maxi(0,int(before.targets[0].hp_loss)-7),"area shared preview accounts for barrier")
		var result: Dictionary=Sm2AreaSpellResolver.resolve(state,c.combat,command,Sm2ConsequenceContext.new())
		t.expect(result.accepted,"actual area resolves")
		t.equal(target.combat.hp,hp-int(preview.targets[0].hp_loss),"area damage equals forecast")
		t.equal(target.barrier.remaining,0,"area consumes finite protection")
	b=fixture(t); t.expect(b.execute(cast(b)).accepted,"reaction source shield")
	var hit_found: bool=false; var miss_found: bool=false
	for seed_value: int in range(1,40):
		state=b._state.copy(); target=state.actor(1); target.barrier.capacity=1000; target.barrier.remaining=1000
		state.rng=Sm2DeterministicRng.new(seed_value)
		command=PSI.bc(b,"use_ability","m2:ability.sword_strike",1); command.actor_id=3
		var result: Dictionary=Sm2AttackResolver.resolve(state,b._combat,command,true,Sm2ConsequenceContext.new())
		t.expect(result.accepted,"real reaction resolves")
		for event: Dictionary in result.events:
			if event.type=="attack_hit": hit_found=true; t.expect(target.barrier.remaining<1000,"reaction hit uses barrier")
			if event.type=="attack_missed": miss_found=true; t.equal(target.barrier.remaining,1000,"miss does not spend barrier")
		t.equal(target.combat.hp,60,"reaction absorbed without health loss")
		if hit_found and miss_found: break
	t.expect(hit_found and miss_found,"both hit and miss reaction paths exercised")
	# Aimed strike at an independently shielded target: no actual HP loss, no severing.
	hit_found=false
	for seed_value: int in range(1,40):
		state=b._state.copy(); target=state.actor(3); state.actor(1).spatial.ap=9
		target.barrier.capacity=1000; target.barrier.remaining=1000; state.rng=Sm2DeterministicRng.new(seed_value)
		command=PSI.bc(b,"use_ability","p4:ability.sever_right",3)
		var result: Dictionary=Sm2AttackResolver.resolve(state,b._combat,command,false,Sm2ConsequenceContext.new())
		t.expect(result.accepted,"aimed strike resolves")
		for event: Dictionary in result.events:
			if event.type=="attack_hit": hit_found=true
		if hit_found:
			t.equal(target.combat.hp,60,"aimed hit fully absorbed")
			t.expect(state.body_changes.is_empty(),"fully shielded hit cannot sever arm")
			break
	t.expect(hit_found,"aimed hit path exercised")

static func _lives(t: Sm2TestHarness) -> void:
	var store: Sm2SaveStore=Sm2SaveStore.new("user://shield-lives")
	var c: Dictionary=life_content(); var s: Sm2JourneySession=Sm2JourneySession.new(c,Sm2AiContentLoader.load_profile().profile,store)
	t.expect(s.new_game().ok,"shield journey new game"); learn(s,t)
	t.expect(s.act(s.command("start_battle")).ok,"shield journey battle")
	t.expect(s.attack(PSI.command(s,"use_ability",ABILITY,1)).accepted,"journey real shield")
	t.expect(s.save_game().ok,"save active shield")
	var loaded: Sm2JourneySession=Sm2JourneySession.new(c,s._profile,store)
	t.expect(loaded.load_game().ok,"load active shield journey")
	t.equal(loaded.state_hash(),s.state_hash(),"journey exact shield resume")
	PSI.PROSTHESIS.finish_retreat(s,t)
	t.expect(not s.world.busy() and s.world.hero_id()==2,"hero survives for next incarnation")
	t.expect(NODE in s.world.bodies[2].progress.tracks[TRACK].nodes,"learned shield persists outside battle")
	var camp: Dictionary=s.capture()
	t.expect(s.act(s.command("start_battle")).ok,"next battle keeps learned shield")
	t.equal(s.runner._session._battle._state.actor(1).barrier.remaining,0,"next battle has no old protection pool")
	t.expect(s.runner.preview(PSI.command(s,"use_ability",ABILITY,1)).allowed,"next battle can cast learned shield")
	t.expect(s.restore(camp).ok,"camp restored for incarnation branch")
	var companion: Dictionary=s.world.bodies[4].to_data(); var knowledge: Array=s.world.soul.knowledge.duplicate(); var items: Array=s.journey().items.duplicate(true)
	t.expect(s.act(s.command("end_life")).ok,"end wounded body life")
	t.expect(s.act(s.command("incarnate",8)).ok,"new clean incarnation")
	t.equal(s.world.bodies[8].progress.tracks[TRACK].earned,0,"new body own practice reset")
	t.expect(s.world.bodies[8].progress.tracks[TRACK].nodes.is_empty(),"new body shield and impulse reset")
	t.equal(s.world.bodies[8].progress.tracks[RESONANCE].earned,0,"new body resonance reset")
	t.expect(s.save_game().ok,"save reincarnation without shield")
	t.expect(loaded.load_game().ok,"reload new body")
	t.equal(loaded.state_hash(),s.state_hash(),"new body exact reload")
	t.equal(s.world.bodies[4].to_data(),companion,"companion retained")
	t.equal(s.world.soul.knowledge,knowledge,"Soul knowledge retained")
	t.equal(s.journey().items,items,"world equipment retained")
	learn(s,t); t.expect(s.act(s.command("start_battle")).ok,"retrained new body enters next encounter")
	t.equal(s.runner.preview(PSI.command(s,"use_ability",ABILITY,1)).capacity,18,"new body's relearned shield returns to baseline")
	t.expect(s.attack(PSI.command(s,"use_ability",ABILITY,1)).accepted,"new incarnation actually casts shield")

static func _partial_save(t: Sm2TestHarness) -> void:
	var b: Sm2TacticalBattle=fixture(t)
	t.expect(b.execute(cast(b)).accepted,"shield for real incoming enemy turn")
	for i: int in 4:
		if b._state.active_id()==3: break
		t.expect(b.execute(PSI.bc(b,"end_turn")).accepted,"advance to enemy")
	var start: Dictionary=b.capture(); var found: bool=false
	for seed_value: int in range(1,40):
		var trial: Dictionary=start.duplicate(true); trial.rng.state=str(seed_value)
		t.expect(b.restore(trial).ok,"explicit RNG fixture validates")
		var result: Sm2CommandResult=b.execute(PSI.bc(b,"use_ability","m2:ability.sword_strike",1))
		t.expect(result.accepted,"real enemy command against shield")
		var left: int=b._state.actor(1).barrier.remaining
		if left>0 and left<18:
			found=true
			var snapshot: Dictionary=b.capture(); var twin: Sm2TacticalBattle=fixture(t)
			t.expect(twin.restore(snapshot).ok,"partially depleted shield snapshot accepted")
			t.equal(twin._state.actor(1).barrier.remaining,left,"exact partial capacity restored")
			t.equal(twin.state_hash(),b.state_hash(),"partial shield reload exact")
			var a: Sm2CommandResult=b.execute(PSI.bc(b,"end_turn")); var z: Sm2CommandResult=twin.execute(PSI.bc(twin,"end_turn"))
			t.expect(a.accepted and z.accepted,"loaded partial shield continues")
			t.equal(a.events,z.events,"loaded continuation same events")
			t.equal(b.state_hash(),twin.state_hash(),"loaded continuation same state")
			break
	t.expect(found,"a real enemy hit partially depleted the shield")
