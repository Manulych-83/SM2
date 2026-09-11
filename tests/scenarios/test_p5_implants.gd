extends RefCounted
const UPGRADES=preload("res://tests/scenarios/test_p5_upgrades.gd")
const PSI=preload("res://tests/scenarios/test_p5_psionics.gd")
const SHIELD=preload("res://tests/scenarios/test_p5_shield.gd")
const ID: String="p5:upgrade.psi_amplifier"
const RES: String="p4a:stat.resonance"
static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2ImplantContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)
static func install(s: Sm2JourneySession,t: Sm2TestHarness) -> void:
	UPGRADES.install(s,t)
	t.expect(s.act(s.command("collect_upgrade",0,ID)).ok,"collect implant kit")
	t.expect(s.act(s.command("apply_upgrade",s.world.hero_id(),ID)).ok,"install amplifier")
static func fixture(t: Sm2TestHarness,enhanced: bool=true,earned: int=200,capped: bool=false) -> Sm2TacticalBattle:
	var s: Sm2JourneySession=make(); s.world.start("p5:implant-fixture")
	if enhanced:
		for id: String in [UPGRADES.ID,ID]:
			s.world.apply(s.command("collect_upgrade",0,id)); s.world.apply(s.command("apply_upgrade",2,id))
	var body: Sm2ProgressBodyState=s.world.bodies[2].progress
	body.tracks[PSI.TRACK].earned=earned; body.tracks[PSI.TRACK].spent=200; body.tracks[PSI.TRACK].nodes.assign([PSI.NODE,SHIELD.NODE])
	if capped: body.tracks[RES].earned=Sm2ProgressCatalog.XP_LIMIT
	s.world.apply(s.command("start_battle"))
	var content: Dictionary=Sm2EncounterFactory.build(s._content,s.journey()); t.expect(content.ok,"implant encounter compiles")
	content.setup.actors[2].q=2; content.setup.actors[2].r=1
	var battle: Sm2TacticalBattle=Sm2TacticalBattle.new(content.catalog,content.combat,true,content.effects,content.magic,content.development,content.origin)
	t.expect(battle.start(content.setup).ok,"implant battle starts"); return battle
static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2ImplantContentLoader.load_scenario(); t.expect(c.ok,"implant content loads")
	if not c.ok: t.complete_suite("p5_implants"); return
	_catalog(t,c); _camp(t); _battle(t); _life(t)
	t.complete_suite("p5_implants")
static func _catalog(t: Sm2TestHarness,c: Dictionary) -> void:
	var raw: Dictionary=c.development.upgrades().to_data(); var progress: Sm2ProgressCatalog=c.development.progression()
	for defect: String in ["old","negative","huge","unknown","duplicate"]:
		var bad: Dictionary=raw.duplicate(true)
		match defect:
			"old": bad.version=Sm2BodyUpgradeCatalog.VERSION
			"negative": bad.upgrades[1].modifiers[1].amount=-1
			"huge": bad.upgrades[1].modifiers[1].amount=101
			"unknown": bad.upgrades[1].modifiers[1].kind="execute_script"
			"duplicate": bad.upgrades[1].modifiers.append(bad.upgrades[1].modifiers[1].duplicate(true))
		t.expect(not Sm2BodyUpgradeCatalog.new().build(bad,progress).is_empty(),"reject focus operation "+defect)
	var rules: Dictionary=c.development.to_data(); rules.version=Sm2DevelopmentCatalog.UPGRADE_VERSION
	t.expect(not Sm2DevelopmentCatalog.new().build(rules,progress,c.combat).is_empty(),"old development rejects new operations")
	var data: Sm2BodyUpgradeState=Sm2BodyUpgradeState.new(); data.installed.assign([ID,UPGRADES.ID]); data.installed.sort()
	var price: Dictionary=Sm2PsionicCostQuery.resolve(6,c.development.upgrades(),data)
	t.equal(price.total,7,"one focus penalty despite two paths")
	t.equal(price.sources[0].name,"Пси-усилитель","named cost source")
	price.sources[0].amount=999
	t.equal(Sm2PsionicCostQuery.resolve(6,c.development.upgrades(),data).total,7,"price projection detached")
	t.equal(Sm2PsionicCostQuery.resolve(6).total,6,"no upgrades preserves old price")
static func _camp(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=make(Sm2SaveStore.new("user://implant-core")); t.expect(s.new_game().ok,"implant world starts")
	var before: String=s.state_hash()
	t.expect(not s.act(s.command("apply_upgrade",2,ID)).ok,"requires kit"); t.equal(s.state_hash(),before,"missing kit atomic")
	var own: Dictionary=s.world.bodies[2].progress.to_data(); install(s,t)
	t.equal(s.world.bodies[2].progress.to_data(),own,"neither path grants practice or nodes")
	var view: Dictionary=Sm2HeroDevelopmentView.build(s,RES)
	t.equal(view.selected.level,10,"own Resonance10"); t.equal(view.selected.effective,12,"effective Resonance12")
	t.equal(view.selected.upgrade_sources[0].name,"Пси-усилитель","Resonance source named")
	t.equal(Sm2HeroDevelopmentView.build(s,UPGRADES.POWER).selected.effective,12,"genetic Power persists alongside implant")
	t.equal(s.journey().upgrade_supply.remaining[ID],0,"kit consumed")
	before=s.state_hash()
	for command: Sm2WorldCommand in [s.command("apply_upgrade",2,ID),s.command("apply_upgrade",4,ID),s.command("collect_upgrade",0,ID)]:
		t.expect(not s.act(command).ok,"repeat or wrong body denied"); t.equal(s.state_hash(),before,"invalid world command atomic")
	t.expect(s.save_game().ok and s.load_game().ok,"two installed paths save/load"); t.equal(s.state_hash(),before,"camp reload exact")
	var forged: Dictionary=s.capture(); forged.world.upgrade_supply.remaining[ID]=1
	t.expect(not s.restore(forged).ok,"forged kit count rejected"); t.equal(s.state_hash(),before,"forged load atomic")
	SHIELD.learn(s,t)
	view=Sm2HeroDevelopmentView.build(s,PSI.TRACK)
	for node: Dictionary in view.nodes:
		if node.id in [PSI.NODE,SHIELD.NODE]: t.expect(str(node.effects).contains("Пси-усилитель: +1") and str(node.effects).contains("7 концентрации"),"node explains derived price")
static func _battle(t: Sm2TestHarness) -> void:
	var b: Sm2TacticalBattle=fixture(t); var normal: Sm2TacticalBattle=fixture(t,false)
	t.equal(b.capture().schema_version,17,"schema17")
	var impulse: Sm2Command=PSI.bc(b); var shield: Sm2Command=SHIELD.cast(b)
	var p: Dictionary=b.preview(impulse); var q: Dictionary=b.preview(shield)
	t.expect(p.allowed and q.allowed,"both learned abilities available")
	t.equal(p.damage,14,"amplified impulse14"); t.equal(q.capacity,20,"amplified shield20")
	t.equal(p.mana_cost,7,"impulse price7"); t.equal(q.mana_cost,7,"shield price7")
	t.equal(p.cost_calculation.base,6,"base price explained"); t.equal(p.cost_calculation.bonus,1,"penalty explained")
	t.equal(normal.preview(PSI.bc(normal)).damage,12,"plain impulse12"); t.equal(normal.preview(SHIELD.cast(normal)).capacity,18,"plain shield18")
	var before: String=b.state_hash(); var ai: Sm2AiQueries=Sm2AiQueries.new(b._state,b._combat)
	t.equal(ai.action(impulse,b._state.actor(1).spatial.position),p,"AI shares forecast")
	t.equal(ai.action_info(PSI.ABILITY).mana_cost,7,"AI shares cost metadata"); t.equal(b.state_hash(),before,"queries read only")
	t.equal(b.preview(PSI.bc(b,"use_ability","m2:ability.sword_strike",3)).fatigue_cost,12,"genetic fatigue still applies to physical attack")
	t.expect(b.execute(shield).accepted,"real enhanced shield")
	t.equal(b._state.actor(1).barrier.remaining,20,"actual protection20"); t.equal(b._state.mana[1].current,5,"actual focus12-7")
	t.equal(b._state.actor(1).spatial.fatigue,0,"implant does not add physical fatigue to psi")
	t.equal(b._state.development.bodies[1].tracks[RES].earned,5,"own Resonance gains only cast practice")
	before=b.state_hash(); t.equal(b.preview(PSI.bc(b)).reason,"insufficient_concentration","five cannot pay seven")
	t.expect(not b.execute(PSI.bc(b)).accepted,"second cast denied"); t.equal(b.state_hash(),before,"denied cast changes nothing")
	var twin: Sm2TacticalBattle=fixture(t); t.expect(twin.restore(b.capture()).ok,"active implanted shield reload")
	t.equal(twin.state_hash(),before,"focus and barrier restored exactly")
	var candidate: Sm2TacticalState=b._state.copy(); var events: Array[Dictionary]=[]
	Sm2ManaResolver.recover_round(candidate,1,events); t.equal(candidate.mana[1].current,8,"round recovery remains3")
	t.expect(Sm2SpellResolver.preview(candidate,PSI.bc(b)).allowed,"recovery makes enhanced spell affordable")
	b=fixture(t); t.expect(b.execute(PSI.bc(b)).accepted,"real amplified impulse")
	t.equal(b._state.actor(3).combat.hp,46,"actual impulse14"); t.equal(b._state.mana[1].current,5,"impulse spends7")
	b=fixture(t,true,250); t.equal(b.preview(PSI.bc(b)).damage,16,"own skill growth stacks with implant"); t.equal(b.preview(SHIELD.cast(b)).capacity,22,"own growth and implant shield22")
	for ability: String in [PSI.ABILITY,SHIELD.ABILITY]:
		b=fixture(t,true,200,true); before=b.state_hash()
		var failed: Sm2CommandResult=b.execute(PSI.bc(b,"use_ability",ability,1 if ability==SHIELD.ABILITY else 3))
		t.equal(failed.code,"experience_limit","late Resonance cap rejects cast")
		t.equal(b.state_hash(),before,"late failure rolls back focus protection HP XP and RNG"); t.expect(failed.events.is_empty(),"no partial events")
static func life_content() -> Dictionary:
	var c: Dictionary=Sm2ImplantContentLoader.load_scenario(); var injury: Dictionary=SHIELD.life_content()
	var dev: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new(); var errors: PackedStringArray=dev.build(c.development.to_data(),c.development.progression(),injury.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	c.combat=injury.combat; c.development=dev; c.setup=injury.setup; c.journey_fingerprint=Sm2Canonical.hash([c.journey_fingerprint,injury.journey_fingerprint]); return c
static func _life(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=Sm2JourneySession.new(life_content(),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://implant-lives"))
	t.expect(s.new_game().ok,"lives starts"); install(s,t); SHIELD.learn(s,t)
	t.expect(s.act(s.command("start_battle")).ok,"start with three paths")
	var before: String=s.state_hash(); t.expect(not s.act(s.command("apply_upgrade",2,ID)).ok,"no surgery in battle"); t.equal(s.state_hash(),before,"busy denial atomic")
	t.expect(s.attack(PSI.command(s,"use_ability",SHIELD.ABILITY,1)).accepted,"implanted life casts shield")
	before=s.state_hash(); t.expect(s.save_game().ok and s.load_game().ok,"combined active game saves"); t.equal(s.state_hash(),before,"active Journey exact")
	PSI.PROSTHESIS.finish_retreat(s,t)
	t.equal(s.world.bodies[2].upgrades.installed.size(),2,"both modifications survive retreat")
	var camp: Dictionary=s.capture(); t.expect(s.act(s.command("start_battle")).ok,"next encounter begins")
	t.equal(s.runner._session._battle._state.development.upgrades[1].installed.size(),2,"next encounter inherits both upgrades")
	t.expect(s.restore(camp).ok,"camp branch restores")
	var companion: Dictionary=s.world.bodies[4].to_data(); var knowledge: Array=s.world.soul.knowledge.duplicate(); var items: Array=s.journey().items.duplicate(true)
	t.expect(s.act(s.command("end_life")).ok,"end modified life"); t.expect(s.act(s.command("incarnate",8)).ok,"enter clean body")
	t.expect(s.world.bodies[8].upgrades.installed.is_empty(),"new body has neither modification")
	t.equal(s.world.bodies[2].upgrades.installed.size(),2,"old body retains both")
	t.equal(Sm2HeroDevelopmentView.build(s,RES).selected.effective,10,"new Resonance natural")
	t.equal(Sm2HeroDevelopmentView.build(s,UPGRADES.POWER).selected.effective,10,"new Power natural")
	for id: String in [UPGRADES.ID,ID]:
		t.expect(not s.act(s.command("collect_upgrade",0,id)).ok,"no stash respawn"); t.expect(not s.act(s.command("apply_upgrade",8,id)).ok,"no returned supplies")
	t.equal(s.world.bodies[4].to_data(),companion,"companion retained"); t.equal(s.world.soul.knowledge,knowledge,"knowledge retained"); t.equal(s.journey().items,items,"equipment retained")
	t.expect(s.save_game().ok and s.load_game().ok,"history old body and empty new body save")
