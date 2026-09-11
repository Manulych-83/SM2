extends RefCounted
const SHIELD=preload("res://tests/scenarios/test_p5_shield.gd")
const PSI=preload("res://tests/scenarios/test_p5_psionics.gd")
const ID: String="p5:upgrade.muscles"
const POWER: String="p1:stat.strength"

static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2BodyUpgradeContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)
static func install(s: Sm2JourneySession,t: Sm2TestHarness) -> void:
	t.expect(s.act(s.command("collect_upgrade",0,ID)).ok,"collect finite drug")
	t.expect(s.act(s.command("apply_upgrade",s.world.hero_id(),ID)).ok,"install muscles")
static func fixture(t: Sm2TestHarness,enhanced: bool=true,capped: bool=false) -> Sm2TacticalBattle:
	var s: Sm2JourneySession=make(); s.world.start("p5:upgrade-fixture")
	if enhanced:
		s.world.apply(s.command("collect_upgrade",0,ID)); s.world.apply(s.command("apply_upgrade",2,ID))
	var body: Sm2ProgressBodyState=s.world.bodies[2].progress
	body.tracks[PSI.TRACK].earned=200; body.tracks[PSI.TRACK].spent=200; body.tracks[PSI.TRACK].nodes.assign([PSI.NODE,SHIELD.NODE])
	if capped: body.tracks[POWER].earned=Sm2ProgressCatalog.XP_LIMIT
	s.world.apply(s.command("start_battle"))
	var c: Dictionary=Sm2EncounterFactory.build(s._content,s.journey()); t.expect(c.ok,"upgraded encounter compiles")
	c.setup.actors[2].q=2; c.setup.actors[2].r=1
	var b: Sm2TacticalBattle=Sm2TacticalBattle.new(c.catalog,c.combat,true,c.effects,c.magic,c.development,c.origin)
	var started: Dictionary=b.start(c.setup); t.expect(started.ok,"upgraded battle starts "+str(started.get("errors",[]))); return b

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2BodyUpgradeContentLoader.load_scenario(); t.expect(c.ok,"upgrade content "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("p5_upgrades"); return
	_catalog(t,c)
	_camp(t)
	var b: Sm2TacticalBattle=fixture(t)
	if b._state!=null: _battle(t); _life(t)
	t.complete_suite("p5_upgrades")

static func _catalog(t: Sm2TestHarness,c: Dictionary) -> void:
	var raw: Dictionary=c.development.upgrades().to_data(); var progress: Sm2ProgressCatalog=c.development.progression()
	for defect: String in ["operation","track","amount","duplicate","path","doses"]:
		var bad: Dictionary=raw.duplicate(true)
		match defect:
			"operation": bad.upgrades[0].modifiers[0].kind="script"
			"track": bad.upgrades[0].modifiers[0].track_id="p1:skill.psionics"
			"amount": bad.upgrades[0].modifiers[0].amount=-2
			"duplicate": bad.upgrades.append(bad.upgrades[0].duplicate(true))
			"path": bad.upgrades[0].path="unknown"
			"doses": bad.upgrades[0].doses=0
		t.expect(not Sm2BodyUpgradeCatalog.new().build(bad,progress).is_empty(),"invalid authored upgrade "+defect)
	var bad: Dictionary=c.development.to_data(); bad.version=Sm2DevelopmentCatalog.PSIONIC_SHIELD_VERSION
	t.expect(not Sm2DevelopmentCatalog.new().build(bad,progress,c.combat).is_empty(),"old development rejects upgrades")
	t.expect(not Sm2BodyUpgradeState.decode({"installed":[ID,ID]},c.development.upgrades()).ok,"duplicates cannot stack")
	# A second diagnostic enhancement composes without a combination-specific class.
	var raw2: Dictionary=raw.upgrades[0].duplicate(true); raw2.id="test:upgrade.implant"; raw2.path="cybernetics"; raw2.modifiers=[{"kind":"track_bonus","track_id":POWER,"amount":3}]
	raw.upgrades.append(raw2)
	var catalog: Sm2BodyUpgradeCatalog=Sm2BodyUpgradeCatalog.new(); t.expect(catalog.build(raw,progress).is_empty(),"second path uses same validated operations")
	var installed: Sm2BodyUpgradeState=Sm2BodyUpgradeState.new(); installed.installed.assign([ID,"test:upgrade.implant"])
	var body: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(2,progress)
	for row: Dictionary in Sm2ProgressRules.tracks(body,progress,catalog.track_modifiers(installed)):
		if row.id==POWER: t.equal(row.effective,15,"two independently authored bonuses add 2 and 3")
	t.equal(catalog.attack_fatigue(installed),2,"penalty appears once")
	t.equal(body.tracks[POWER].earned,0,"composition grants no XP")
	t.equal(Sm2ProgressRules.purchase_error(body,progress,"p1:node.strength_1"),"level_required","effective 15 is not own level 11")

static func _camp(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=make(Sm2SaveStore.new("user://upgrade-camp")); t.expect(s.new_game().ok,"upgrade camp starts")
	var before: String=s.state_hash()
	t.expect(not s.act(s.command("apply_upgrade",2,ID)).ok,"drug required before applying")
	t.equal(s.state_hash(),before,"missing drug rejection atomic")
	t.expect(s.act(s.command("collect_upgrade",0,ID)).ok,"collect once")
	before=s.state_hash(); t.expect(not s.act(s.command("collect_upgrade",0,ID)).ok,"cannot duplicate cache"); t.equal(s.state_hash(),before,"duplicate collect atomic")
	t.expect(not s.act(s.command("apply_upgrade",4,ID)).ok,"companion not upgraded")
	t.equal(s.state_hash(),before,"wrong target retains dose")
	var own: Dictionary=s.world.bodies[2].progress.to_data(); var stale: Sm2WorldCommand=s.command("apply_upgrade",2,ID)
	t.expect(s.act(stale).ok,"apply consumes drug")
	t.equal(s.world.bodies[2].progress.to_data(),own,"installation changes no XP, nodes or spent practice")
	t.equal(s.journey().upgrade_supply.remaining[ID],0,"exactly one dose consumed")
	var view: Dictionary=Sm2HeroDevelopmentView.build(s,POWER)
	t.equal(view.selected.level,10,"own power remains 10"); t.equal(view.selected.effective,12,"effective power 12")
	t.equal(view.selected.upgrade_bonus,2,"UI distinguishes improvement")
	t.equal(view.selected.upgrade_sources[0].name,"Усиленные мышцы","named source shown")
	before=s.state_hash(); t.expect(not s.act(stale).ok,"stale apply denied"); t.equal(s.state_hash(),before,"stale apply atomic")
	t.expect(not s.act(s.command("apply_upgrade",2,ID)).ok,"no repeat stacking")
	t.expect(not s.act(s.command("buy_node",2,"p1:node.strength_1")).ok,"upgrade cannot learn an own-level node")
	t.expect(s.save_game().ok and s.load_game().ok,"enhancement and finite supply survive load")
	t.equal(s.state_hash(),before,"no duplicate dose or bonus on load")
	var forged: Dictionary=s.capture(); forged.world.upgrade_supply.remaining[ID]=1
	t.expect(not s.restore(forged).ok,"fabricated supply rejected by history")
	t.equal(s.state_hash(),before,"forged world rejection atomic")
	var copy: Sm2JourneyWorld=s.journey().copy_world(); copy.bodies[2].upgrades.installed.clear()
	t.equal(s.world.bodies[2].upgrades.installed,[ID],"body state copy detached")
	t.equal(copy.validate(),"upgrade_supply_conservation","deleted installed dose violates conservation")

static func _battle(t: Sm2TestHarness) -> void:
	var b: Sm2TacticalBattle=fixture(t); var normal: Sm2TacticalBattle=fixture(t,false)
	t.equal(b.capture().schema_version,16,"explicit schema16")
	var command: Sm2Command=PSI.bc(b,"use_ability","m2:ability.sword_strike",3)
	var preview: Dictionary=b.preview(command); var ordinary: Dictionary=normal.preview(PSI.bc(normal,"use_ability","m2:ability.sword_strike",3))
	t.expect(preview.allowed and ordinary.allowed,"same physical attack available")
	t.equal(preview.fatigue_cost,int(ordinary.fatigue_cost)+2,"physical cost includes penalty")
	t.equal(preview.hit_chance,int(ordinary.hit_chance)+2,"Power 12 contributes one effective melee level, mapping +2")
	var ai: Sm2AiQueries=Sm2AiQueries.new(b._state,b._combat); var before: String=b.state_hash()
	t.equal(ai.action(command,b._state.actor(1).spatial.position),preview,"AI uses same bonus and cost")
	t.equal(ai.action_info(command.ability_id).fatigue_cost,preview.fatigue_cost,"AI metadata agrees with cost")
	t.equal(b.state_hash(),before,"queries read only")
	var fatigue: int=b._state.actor(1).spatial.fatigue
	t.expect(b.execute(command).accepted,"real enhanced attack")
	t.equal(b._state.actor(1).spatial.fatigue,fatigue+int(preview.fatigue_cost),"actual physical cost equals forecast")
	var twin: Sm2TacticalBattle=fixture(t); t.expect(twin.restore(b.capture()).ok,"upgraded battle reload")
	t.equal(twin.state_hash(),b.state_hash(),"snapshot exact")
	var forged: Dictionary=b.capture(); forged.development.origin.actors[0].upgrades.installed=[]
	before=b.state_hash(); t.expect(not b.restore(forged).ok,"battle origin upgrade tamper rejected"); t.equal(b.state_hash(),before,"bad battle reload atomic")
	b=fixture(t); var impulse: Dictionary=b.preview(PSI.bc(b)); var shield: Dictionary=b.preview(SHIELD.cast(b))
	t.equal(impulse.damage,12,"muscles do not increase psionic damage")
	t.equal(shield.capacity,18,"muscles do not increase psionic shield")
	t.equal(impulse.fatigue_cost,0,"psi has no physical penalty")
	t.expect(b.execute(SHIELD.cast(b)).accepted and b.execute(PSI.bc(b)).accepted,"genetics and both psionic abilities work together")
	t.equal(b._state.actor(1).spatial.fatigue,0,"casting either ability adds no physical fatigue")
	# Reaction query, affordability and actual failed-command rollback use the same cost.
	b=fixture(t); var state: Sm2TacticalState=b._state.copy(); command=PSI.bc(b,"use_ability","m2:ability.sword_strike",3)
	t.equal(Sm2AttackResolver.preview(state,b._combat,command,true).fatigue_cost,7,"reaction base5 plus2")
	state.actor(1).spatial.fatigue=state.actor(1).spatial.fatigue_max-6
	t.expect(not Sm2AttackResolver.preview(state,b._combat,command,true).allowed,"six remaining fatigue cannot pay seven")
	t.expect(not Sm2AttackResolver.neighbors_threatening(state,state.actor(3),b._combat,true).has(1),"unaffordable reaction not advertised")
	b=fixture(t,true,true); before=b.state_hash()
	var rejected: Sm2CommandResult=b.execute(PSI.bc(b,"use_ability","m2:ability.sword_strike",3))
	t.equal(rejected.code,"experience_limit","late own practice limit rejects attack")
	t.equal(b.state_hash(),before,"late rejection rolls back RNG HP fatigue and own XP")
	t.expect(rejected.events.is_empty(),"no events for rejected attack")

static func life_content() -> Dictionary:
	var c: Dictionary=Sm2BodyUpgradeContentLoader.load_scenario(); var injury: Dictionary=SHIELD.life_content()
	var dev: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new(); var errors: PackedStringArray=dev.build(c.development.to_data(),c.development.progression(),injury.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	c.combat=injury.combat; c.development=dev; c.setup=injury.setup; c.journey_fingerprint=Sm2Canonical.hash([c.journey_fingerprint,injury.journey_fingerprint]); return c
static func _life(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=Sm2JourneySession.new(life_content(),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://upgrade-lives"))
	t.expect(s.new_game().ok,"lives fixture starts"); install(s,t); SHIELD.learn(s,t)
	t.expect(s.act(s.command("start_battle")).ok,"modified hero enters battle")
	var before: String=s.state_hash(); t.expect(not s.act(s.command("apply_upgrade",2,ID)).ok,"cannot apply in battle"); t.equal(s.state_hash(),before,"in-battle denial atomic")
	t.expect(s.attack(PSI.command(s,"use_ability",SHIELD.ABILITY,1)).accepted,"enhanced body casts shield")
	t.expect(s.save_game().ok and s.load_game().ok,"combined state saves")
	PSI.PROSTHESIS.finish_retreat(s,t)
	t.expect(s.world.hero_id()==2 and not s.world.busy(),"enhanced hero survives retreat")
	t.equal(s.world.bodies[2].upgrades.installed,[ID],"enhancement persists after battle")
	var camp: Dictionary=s.capture()
	t.expect(s.act(s.command("start_battle")).ok,"next encounter starts")
	t.equal(s.runner._session._battle._state.development.extra_attack_fatigue(1),2,"next encounter retains enhancement")
	t.expect(s.restore(camp).ok,"return camp for reincarnation branch")
	var companion: Dictionary=s.world.bodies[4].to_data(); var knowledge: Array=s.world.soul.knowledge.duplicate(); var items: Array=s.journey().items.duplicate(true)
	t.expect(s.act(s.command("end_life")).ok,"end enhanced life")
	t.expect(not s.world.eligible(2).is_empty(),"enhanced corpse not eligible")
	t.expect(s.act(s.command("incarnate",8)).ok,"incarnate pure prepared human")
	t.expect(s.world.bodies[8].upgrades.installed.is_empty(),"new body has no old enhancement")
	t.equal(s.world.bodies[2].upgrades.installed,[ID],"modification stays with prior body")
	t.equal(Sm2HeroDevelopmentView.build(s,POWER).selected.effective,10,"new body's effective power is natural")
	t.expect(not s.act(s.command("collect_upgrade",0,ID)).ok,"world cache does not respawn")
	t.expect(not s.act(s.command("apply_upgrade",8,ID)).ok,"consumed drug not returned by death")
	t.equal(s.world.bodies[4].to_data(),companion,"companion unchanged")
	t.equal(s.world.soul.knowledge,knowledge,"Soul knowledge unchanged")
	t.equal(s.journey().items,items,"equipment remains in world")
	t.expect(s.save_game().ok and s.load_game().ok,"both bodies and consumed dose restore")
