extends RefCounted
const PSI=preload("res://tests/scenarios/test_p5_psionics.gd")
const TRACK: String="p1:skill.psionics"
const RESONANCE: String="p4a:stat.resonance"
const NODE: String="p5:node.impulse"
const ABILITY: String="p5:ability.impulse"

static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2PsionicGrowthContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)

static func fixture(t: Sm2TestHarness,psi_xp: int=100,res_xp: int=0) -> Sm2TacticalBattle:
	var s: Sm2JourneySession=make(); s.world.start("p5:growth-fixture")
	var body: Sm2ProgressBodyState=s.world.bodies[2].progress
	body.tracks[TRACK].earned=psi_xp; body.tracks[TRACK].spent=100; body.tracks[TRACK].nodes.append(NODE); body.tracks[RESONANCE].earned=res_xp
	s.world.apply(s.command("start_battle"))
	var c: Dictionary=Sm2EncounterFactory.build(s._content,s.journey()); t.expect(c.ok,"growth factory compiles")
	c.setup.actors[2].q=2; c.setup.actors[2].r=1
	var b: Sm2TacticalBattle=Sm2TacticalBattle.new(c.catalog,c.combat,true,c.effects,c.magic,c.development,c.origin)
	t.expect(b.start(c.setup).ok,"growth fixture battle starts"); return b

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2PsionicGrowthContentLoader.load_scenario(); t.expect(c.ok,"growth content "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("p5_growth"); return
	_math(t,c)
	_battle(t)
	_lives(t)
	t.complete_suite("p5_growth")

static func _math(t: Sm2TestHarness,c: Dictionary) -> void:
	var progress: Sm2ProgressCatalog=c.development.progression(); var psi: Sm2PsionicCatalog=c.development.psionics()
	for values: Array in [[100,0,12],[250,0,14],[100,100,12],[100,250,14],[250,250,16]]:
		var body: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(2,progress); body.tracks[TRACK].earned=values[0]; body.tracks[RESONANCE].earned=values[1]
		var before: String=Sm2Canonical.hash(body.to_data()); var result: Dictionary=psi.damage(ABILITY,body,progress)
		t.equal(result.total,values[2],"known skill/resonance formula "+str(values))
		t.equal(Sm2Canonical.hash(body.to_data()),before,"parameter query leaves XP and nodes intact")
		result.terms[0].sources[0].amount=999
		t.equal(psi.damage(ABILITY,body,progress).total,values[2],"calculation detached")
	var body: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(2,progress)
	body.tracks[TRACK].earned=100; body.tracks[RESONANCE].earned=100
	body.tracks[RESONANCE].spent=70; body.tracks[RESONANCE].nodes.append("p4a:node.resonance")
	t.equal(psi.damage(ABILITY,body,progress).total,14,"source's own node contributes to effective skill")
	body.tracks[TRACK].earned=0
	t.equal(Sm2ProgressRules.purchase_error(body,progress,NODE),"level_required","effective skill cannot replace own learning")
	body.tracks[TRACK].earned=250
	var rule: Dictionary=psi.ability(ABILITY).damage_scaling; rule.maximum=15
	t.equal(Sm2AbilityParameterQuery.resolve(12,rule,body,progress).total,15,"authored upper bound")
	rule.maximum=10000; rule.terms[0].numerator=5; rule.terms[0].denominator=3
	t.equal(Sm2AbilityParameterQuery.resolve(12,rule,body,progress).total,15,"fractional positive contribution rounded down")
	var original: Dictionary=psi.to_data()
	for key: String in ["track_id","denominator","numerator","baseline"]:
		var raw: Dictionary=original.duplicate(true)
		raw.abilities[0].damage_scaling.terms[0][key]="unknown" if key=="track_id" else -1
		t.expect(not Sm2PsionicCatalog.new().build(raw,progress,c.combat).is_empty(),"invalid growth term "+key)
	var raw: Dictionary=original.duplicate(true); raw.abilities[0].damage_scaling.maximum=1
	t.expect(not Sm2PsionicCatalog.new().build(raw,progress,c.combat).is_empty(),"cap below base rejected")
	raw=original.duplicate(true); raw.abilities[0].damage_scaling.terms.append(raw.abilities[0].damage_scaling.terms[0].duplicate(true))
	t.expect(not Sm2PsionicCatalog.new().build(raw,progress,c.combat).is_empty(),"duplicate contribution rejected")
	raw=original.duplicate(true); raw.abilities[0].additional_awards={TRACK:5}
	t.expect(not Sm2PsionicCatalog.new().build(raw,progress,c.combat).is_empty(),"extra award cannot overwrite own skill XP")
	raw=original.duplicate(true); raw.version=Sm2PsionicCatalog.VERSION
	t.expect(not Sm2PsionicCatalog.new().build(raw,progress,c.combat).is_empty(),"old psi profile rejects scaling fields")
	raw=c.development.to_data(); raw.version=Sm2DevelopmentCatalog.PSIONIC_VERSION
	t.expect(not Sm2DevelopmentCatalog.new().build(raw,progress,c.combat).is_empty(),"development and psi versions must agree")
	var s: Sm2JourneySession=make(); t.expect(s.new_game().ok,"growth camp starts")
	var before: String=s.state_hash(); var v: Dictionary=Sm2HeroDevelopmentView.build(s,TRACK)
	t.equal(v.selected.level,0,"own skill begins at zero")
	t.equal(v.selected.effective,5,"natural resonance contribution is visible")
	t.expect(not s.act(s.command("buy_node",2,NODE)).ok,"natural affinity does not teach impulse")
	t.equal(s.state_hash(),before,"own-level denial atomic")

static func _battle(t: Sm2TestHarness) -> void:
	var b: Sm2TacticalBattle=fixture(t,240,245); var twin: Sm2TacticalBattle=fixture(t,240,245)
	t.equal(b.capture().schema_version,14,"new explicit schema14")
	var initial: Dictionary=b.capture(); var before: String=b.state_hash(); var cast: Sm2Command=PSI.bc(b)
	var preview: Dictionary=b.preview(cast)
	t.equal(preview.damage,12,"before threshold current action remains 12")
	var queries: Sm2AiQueries=Sm2AiQueries.new(b._state,b._combat)
	t.equal(queries.action(cast,b._state.actor(1).spatial.position).damage_calculation,preview.damage_calculation,"AI projection uses same detached calculation")
	t.equal(b.state_hash(),before,"preview and AI leave RNG and development intact")
	var result: Sm2CommandResult=b.execute(cast); var replay: Sm2CommandResult=twin.execute(cast)
	t.expect(result.accepted and replay.accepted,"real threshold cast")
	t.equal(result.events,replay.events,"deterministic awards and calculation event")
	t.equal(b._state.actor(3).combat.hp,48,"current attack uses pre-award strength")
	t.equal(b._state.development.bodies[1].tracks[TRACK].earned,260,"own skill XP increment")
	t.equal(b._state.development.bodies[1].tracks[RESONANCE].earned,250,"own resonance XP increment")
	t.equal(b.preview(PSI.bc(b)).damage,16,"both level changes affect next action in same activation")
	t.equal(b._magic.spell(ABILITY).damage,12,"authored spell definition not mutated")
	t.equal(b._state.mana[1].current,6,"focus unchanged by development formula")
	var snapshot: Dictionary=b.capture(); var after: String=b.state_hash()
	t.expect(twin.restore(snapshot).ok,"growth snapshot reload")
	t.equal(twin.state_hash(),after,"snapshot exact without growth applied twice")
	t.equal(twin.preview(PSI.bc(twin)).damage,16,"derived damage reconstructed after load")
	result=b.execute(PSI.bc(b)); replay=twin.execute(PSI.bc(twin))
	t.expect(result.accepted and replay.accepted,"second stronger action accepted")
	t.equal(b._state.actor(3).combat.hp,32,"second actual damage equals forecast")
	t.equal(b.state_hash(),twin.state_hash(),"loaded continuation deterministic")
	var forged: Dictionary=snapshot.duplicate(true)
	for track: Dictionary in forged.development.members[0].body.tracks:
		if track.track_id==RESONANCE: track.earned_total+=1
	before=b.state_hash(); t.expect(not b.restore(forged).ok,"unearned resonance snapshot rejected"); t.equal(b.state_hash(),before,"forged growth load atomic")
	forged=initial.duplicate(true); forged.schema_version=13
	t.expect(not b.restore(forged).ok,"schema13 cannot disguise growth")
	b=fixture(t,100,Sm2ProgressCatalog.XP_LIMIT-2); before=b.state_hash()
	result=b.execute(PSI.bc(b)); t.equal(result.code,"experience_limit","late secondary attribute XP cap")
	t.equal(b.state_hash(),before,"failed extra award rolls back both XP pools damage RNG focus revision")
	t.expect(result.events.is_empty(),"no events from rejected growth command")
	b=fixture(t); result=b.execute(PSI.bc(b,"use_ability","m2:ability.sword_strike")); t.expect(result.accepted,"physical attack valid in same profile")
	t.equal(b._state.development.bodies[1].tracks[RESONANCE].earned,0,"sword does not train resonance")
	t.equal(b._state.development.bodies[1].tracks[TRACK].earned,100,"sword does not train psi")
	b=PSI.battle(t,250,true); t.equal(b.preview(PSI.bc(b)).damage,12,"old P5.1 retains fixed damage despite skill level")
	result=b.execute(PSI.bc(b)); t.expect(result.accepted,"old P5.1 still casts")
	t.equal(b._state.development.bodies[1].tracks[RESONANCE].earned,0,"old P5.1 retains old award contract")

static func life_content() -> Dictionary:
	var c: Dictionary=Sm2PsionicGrowthContentLoader.load_scenario(); var injury: Dictionary=PSI.life_content()
	var dev: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new(); var errors: PackedStringArray=dev.build(c.development.to_data(),c.development.progression(),injury.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	c.combat=injury.combat; c.development=dev; c.setup=injury.setup
	c.journey_fingerprint=Sm2Canonical.hash([c.journey_fingerprint,injury.journey_fingerprint]); return c

static func _lives(t: Sm2TestHarness) -> void:
	var c: Dictionary=life_content(); var store: Sm2SaveStore=Sm2SaveStore.new("user://growth-lives")
	var s: Sm2JourneySession=Sm2JourneySession.new(c,Sm2AiContentLoader.load_profile().profile,store)
	t.expect(s.new_game().ok,"growth journey starts"); PSI.learn(s,t)
	for i: int in 6: t.expect(s.act(s.command("practice",2,PSI.PRACTICE)).ok,"additional own training to skill 2")
	t.equal(Sm2HeroDevelopmentView.build(s,TRACK).selected.effective,7,"own level plus resonance contribution")
	t.expect(s.act(s.command("start_battle")).ok,"growth journey battle")
	var target_id: int=PSI.target(s); t.expect(target_id>0,"growth journey target")
	var cast: Sm2Command=PSI.command(s,"use_ability",ABILITY,target_id)
	t.equal(s.runner.preview(cast).damage,14,"trained journey forecast")
	t.expect(s.attack(cast).accepted,"trained journey cast")
	t.expect(s.save_game().ok,"save growing battle")
	var loaded: Sm2JourneySession=Sm2JourneySession.new(c,s._profile,store); t.expect(loaded.load_game().ok,"load growing battle")
	t.equal(loaded.state_hash(),s.state_hash(),"growing battle exact reload")
	PSI.PROSTHESIS.finish_retreat(s,t)
	t.equal(s.world.hero_id(),2,"growth hero survives retreat")
	t.equal(s.world.bodies[2].progress.tracks[TRACK].earned,270,"closed outcome transfers skill")
	t.equal(s.world.bodies[2].progress.tracks[RESONANCE].earned,5,"closed outcome transfers resonance once")
	t.expect(s.save_game().ok and s.load_game().ok,"closed history persists both tracks")
	var camp: Dictionary=s.capture(); t.expect(s.act(s.command("start_battle")).ok,"next encounter")
	t.equal(s.runner.preview(PSI.command(s,"use_ability",ABILITY,3)).damage,14,"next encounter uses current growth")
	t.expect(s.restore(camp).ok,"restore camp for incarnation branch")
	var companion: Dictionary=s.world.bodies[4].to_data(); var items: Array=s.journey().items.duplicate(true); var knowledge: Array=s.world.soul.knowledge.duplicate()
	t.expect(s.act(s.command("end_life")).ok and s.act(s.command("incarnate",8)).ok,"new body")
	for id: String in [TRACK,RESONANCE]: t.equal(s.world.bodies[8].progress.tracks[id].earned,0,"own growth resets "+id)
	t.expect(s.world.bodies[8].progress.tracks[TRACK].nodes.is_empty(),"new body no inherited impulse")
	t.equal(s.world.bodies[4].to_data(),companion,"companion preserved")
	t.equal(s.journey().items,items,"equipment preserved in world")
	t.equal(s.world.soul.knowledge,knowledge,"knowledge preserved")
	PSI.learn(s,t); t.expect(s.save_game().ok,"save new body's own learning")
	t.expect(loaded.load_game().ok,"reload new incarnation")
	t.equal(loaded.state_hash(),s.state_hash(),"new incarnation exact history")
	t.expect(s.act(s.command("start_battle")).ok,"new body battle")
	t.equal(s.runner.preview(PSI.command(s,"use_ability",ABILITY,3)).damage,12,"new body's freshly learned impulse back to baseline")
