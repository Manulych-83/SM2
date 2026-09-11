extends RefCounted
const TRACK: String="p1:skill.psionics"
const NODE: String="p5:node.impulse"
const ABILITY: String="p5:ability.impulse"
const PRACTICE: String="p5:activity.psionics"
const JOURNEY=preload("res://tests/scenarios/test_p4_journey.gd")
const PROSTHESIS=preload("res://tests/scenarios/test_p4_prosthesis.gd")

static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2PsionicContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)

static func learn(s: Sm2JourneySession,t: Sm2TestHarness) -> void:
	for i: int in 4: t.expect(s.act(s.command("practice",s.world.hero_id(),PRACTICE)).ok,"own psi exercise")
	t.expect(s.act(s.command("buy_node",s.world.hero_id(),NODE)).ok,"learn impulse with own XP")

static func command(s: Sm2JourneySession,kind: String="use_ability",ability: String=ABILITY,target: int=3) -> Sm2Command:
	var v: Dictionary=s.runner.view(); var c: Sm2Command=Sm2Command.new()
	c.kind=kind; c.actor_id=v.active_actor_id; c.expected_revision=int(v.revision); c.battle_id=v.battle_id; c.ability_id=ability; c.target_actor_id=target
	return c

static func hero_turn(s: Sm2JourneySession,t: Sm2TestHarness) -> bool:
	for i: int in 60:
		if not s.world.busy(): return false
		if int(s.runner.view().active_actor_id)==s._content.development.hero(): return true
		var r: Dictionary=JOURNEY.advance(s); t.expect(r.ok,"advance to hero "+str(r))
		if not r.ok: return false
	return false

static func target(s: Sm2JourneySession) -> int:
	for row: Dictionary in s.runner.view().actors:
		if s.runner.preview(command(s,"use_ability",ABILITY,int(row.actor_id))).allowed: return int(row.actor_id)
	return 0

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2PsionicContentLoader.load_scenario()
	t.expect(c.ok,"P5 content "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("p5_psionics"); return
	_catalog(t,c)
	_battle_edges(t)
	_lives(t)
	var s: Sm2JourneySession=make(Sm2SaveStore.new("user://p5-tests"))
	t.expect(s.new_game().ok,"P5 starts")
	t.equal(s.slot_name(),"p5_psionic_journey","separate slot")
	t.equal(s.world.capture().format,"sm2.world.p5.psionic.1","separate world")
	var before: String=s.state_hash()
	t.expect(not s.act(s.command("buy_node",2,NODE)).ok,"no unlock without own practice")
	t.equal(s.state_hash(),before,"failed unlock unchanged")
	learn(s,t)
	t.equal(s.world.bodies[2].progress.tracks[TRACK].earned,100,"own earned practice")
	t.equal(s.world.bodies[2].progress.tracks[TRACK].spent,100,"own spent practice")
	t.equal(Sm2HeroDevelopmentView.build(s,TRACK).selected.level,1,"purchase retains level")
	t.expect(s.save_game().ok,"learned camp saves")
	t.expect(s.act(s.command("start_battle")).ok,"psionic encounter starts")
	t.equal(s.runner.capture().session.battle.schema_version,13,"explicit schema13")
	t.expect(hero_turn(s,t),"hero activation available")
	var victim: int=target(s)
	t.expect(victim!=0,"enemy in impulse range")
	if victim==0: print(s.runner.view()); t.complete_suite("p5_psionics"); return
	var cast: Sm2Command=command(s,"use_ability",ABILITY,victim)
	var check: Dictionary=s.runner.preview(cast); before=s.state_hash()
	t.equal(check.hp_loss,12,"prototype impulse damage")
	t.equal(check.mana_cost,6,"prototype concentration price")
	t.equal(s.state_hash(),before,"preview is read-only")
	var r: Sm2CommandResult=s.attack(cast)
	t.expect(r.accepted,"real impulse accepted "+r.code)
	t.equal(s.runner._session._battle._state.mana[c.development.hero()].current,6,"concentration spent")
	t.equal(s.runner._session._battle._state.development.bodies[c.development.hero()].tracks[TRACK].earned,120,"impulse awards only psi")
	t.expect(not s.attack(cast).accepted,"duplicate cast rejected")
	t.expect(s.save_game().ok,"mid-battle save")
	var loaded: Sm2JourneySession=make(Sm2SaveStore.new("user://p5-tests")); t.expect(loaded.load_game().ok,"mid-battle load")
	t.equal(loaded.state_hash(),s.state_hash(),"load restores exact world battle and concentration")
	JOURNEY.finish(s,t)
	t.expect(not s.world.busy(),"fight settles")
	t.expect(s.save_game().ok,"settled save")
	t.expect(loaded.load_game().ok,"settled history loads")
	t.equal(loaded.state_hash(),s.state_hash(),"settled history agrees")
	t.complete_suite("p5_psionics")

static func _catalog(t: Sm2TestHarness,c: Dictionary) -> void:
	var source: Dictionary=c.development.psionics().to_data()
	for field: String in ["required_node","practice_xp","concentration_cost","range_min","id"]:
		var raw: Dictionary=source.duplicate(true)
		raw.abilities[0][field]="missing" if field=="required_node" else "m2:ability.sword_strike" if field=="id" else -1
		var catalog: Sm2PsionicCatalog=Sm2PsionicCatalog.new()
		t.expect(not catalog.build(raw,c.development.progression(),c.combat).is_empty(),"reject invalid psi "+field)
	var raw: Dictionary=source.duplicate(true); raw.abilities.append(raw.abilities[0].duplicate(true))
	t.expect(not Sm2PsionicCatalog.new().build(raw,c.development.progression(),c.combat).is_empty(),"duplicate psi rejected")
	raw=source.duplicate(true); raw.track_id="p1:stat.strength"
	t.expect(not Sm2PsionicCatalog.new().build(raw,c.development.progression(),c.combat).is_empty(),"attribute cannot become psi skill")
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new(); raw=c.development.to_data(); raw.version=Sm2DevelopmentCatalog.PROSTHESIS_VERSION
	t.expect(not development.build(raw,c.development.progression(),c.combat).is_empty(),"old development version rejects psi fields")
	raw=source.duplicate(true); raw.abilities[0].damage=999
	t.equal(c.development.psionics().ability(ABILITY).damage,12,"authored values are detached")
	var old: Sm2JourneySession=Sm2JourneySession.new(Sm2DiscoveryContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile)
	t.expect(old.new_game().ok,"old discovery still starts")
	t.expect(not old.act(old.command("practice",2,PRACTICE)).ok,"old world cannot train new action")
	t.expect(old.act(old.command("start_battle")).ok,"old encounter starts")
	t.equal(old.runner.capture().session.battle.schema_version,12,"old schema unchanged")
	t.expect(not old.runner.view().actors[0].has("mana"),"old body encounter has no invented resource")
	var fresh: Sm2JourneySession=make(); t.expect(fresh.new_game().ok,"new profile starts for compatibility")
	var before: String=fresh.state_hash(); t.expect(not fresh.restore(old.capture()).ok,"old slot rejected without migration"); t.equal(fresh.state_hash(),before,"wrong profile load atomic")

static func battle(t: Sm2TestHarness,earned: int=100,owned: bool=true,final_enemy: bool=false) -> Sm2TacticalBattle:
	var s: Sm2JourneySession=make(); s.world.start("p5:deterministic-fixture"); t.equal(s.journey().validate(),"","fixture world starts")
	# Explicit domain fixture: valid authored body baseline, independent of history tests.
	var track: Sm2ProgressTrackState=s.world.bodies[2].progress.tracks[TRACK]
	track.earned=earned
	if owned: track.spent=100; track.nodes.append(NODE)
	s.world.apply(s.command("start_battle"))
	var c: Dictionary=Sm2EncounterFactory.build(s._content,s.journey())
	t.expect(c.ok,"fixture factory compiles")
	c.setup.actors[2].q=2; c.setup.actors[2].r=1
	if final_enemy:
		c.origin.actors[2].hp=12; c.origin.actors[3].hp=0
		c.setup.actors[3].alive=false; c.setup.actors[3].on_field=false
	var b: Sm2TacticalBattle=Sm2TacticalBattle.new(c.catalog,c.combat,true,c.effects,c.magic,c.development,c.origin)
	t.expect(b.start(c.setup).ok,"fixture battle starts")
	return b

static func bc(b: Sm2TacticalBattle,kind: String="use_ability",ability: String=ABILITY,target_id: int=3) -> Sm2Command:
	var c: Sm2Command=Sm2Command.new(); c.kind=kind; c.actor_id=b.view().active_actor_id; c.battle_id=b.view().battle_id; c.expected_revision=int(b.view().revision); c.ability_id=ability; c.target_actor_id=target_id; return c

static func _battle_edges(t: Sm2TestHarness) -> void:
	var b: Sm2TacticalBattle=battle(t,0,false)
	var before: String=b.state_hash(); t.expect(not b.execute(bc(b)).accepted,"no node no cast"); t.equal(b.state_hash(),before,"locked cast changes nothing")
	b=battle(t)
	var physical: Sm2CommandResult=b.execute(bc(b,"use_ability","m2:ability.sword_strike"))
	t.expect(physical.accepted,"real sword attack accepted")
	t.equal(b._state.development.bodies[1].tracks[TRACK].earned,100,"sword does not teach psionics")
	b=battle(t)
	for target_id: int in [1,2,999]:
		before=b.state_hash(); t.expect(not b.execute(bc(b,"use_ability",ABILITY,target_id)).accepted,"invalid psi target rejected "+str(target_id)); t.equal(b.state_hash(),before,"invalid target inert")
	# Detached spatial query fixtures; these changed positions are never saved or published.
	var state: Sm2TacticalState=b._state.copy(); state.actor(3).spatial.position=Vector2i(8,5)
	t.equal(Sm2SpellResolver.preview(state,bc(b)).reason,"attack_range","out of range denied")
	state=b._state.copy(); state.actor(3).spatial.position=Vector2i(4,1); state.actor(2).spatial.position=Vector2i(2,1)
	t.equal(Sm2SpellResolver.preview(state,bc(b)).reason,"line_of_sight_blocked","intervening actor blocks LOS")
	state=b._state.copy(); var cc: Sm2Command=bc(b); cc.actor_id=2
	t.equal(Sm2SpellResolver.preview(state,cc).reason,"ability_unavailable","companion not granted hero psionics")
	# Missing arms do not prevent a non-manual ability.
	state=b._state.copy(); state.actor(1).body_functions.working.right_hand=false; state.actor(1).body_functions.working.left_hand=false
	t.expect(Sm2SpellResolver.preview(state,bc(b)).allowed,"psi requires no hand function")
	var first: Dictionary=b.capture(); var copy: Sm2TacticalBattle=battle(t)
	var cast: Sm2Command=bc(b); var hp: int=b._state.actor(3).combat.hp; var armor: Array=b._state.actor(3).combat.to_data().items.duplicate(true)
	var result: Sm2CommandResult=b.execute(cast); var repeated: Sm2CommandResult=copy.execute(cast)
	t.expect(result.accepted and repeated.accepted,"matching real commands accepted")
	t.equal(result.events,repeated.events,"deterministic events including own XP")
	t.equal(b.state_hash(),copy.state_hash(),"deterministic resulting state")
	t.equal(b._state.actor(3).combat.hp,hp-12,"exact direct HP loss")
	t.equal(b._state.actor(3).combat.to_data().items,armor,"armor and shield untouched")
	for id: String in b._state.development.progress.track_ids():
		if id!=TRACK: t.equal(b._state.development.bodies[1].tracks[id].earned,0,"no unrelated XP "+id)
	t.expect(b.execute(bc(b)).accepted,"second impulse accepted")
	t.equal(b._state.mana[1].current,0,"two impulses exhaust focus")
	var snapshot: Dictionary=b.capture(); var saved_hash: String=b.state_hash()
	t.expect(b.restore(snapshot).ok,"domain snapshot reload")
	t.equal(b.state_hash(),saved_hash,"restore does not recover focus or advance round")
	var initial_round: int=int(b.view().round)
	for i: int in 12:
		if int(b.view().round)>initial_round: break
		t.expect(b.execute(bc(b,"end_turn","",0)).accepted,"end turn for resource recovery")
	t.equal(b._state.mana[1].current,3,"exactly one round recovery")
	before=b.state_hash(); var denied: Sm2CommandResult=b.execute(bc(b))
	t.equal(denied.code,"insufficient_concentration","insufficient focus after recovery")
	t.equal(b.state_hash(),before,"insufficient focus rolls back everything")
	var waiting: Sm2CommandResult=b.execute(bc(b,"wait","",0)); t.expect(waiting.accepted,"wait accepted")
	t.equal(b._state.mana[1].current,3,"wait does not recover focus")
	b=battle(t,Sm2ProgressCatalog.XP_LIMIT-10)
	before=b.state_hash(); denied=b.execute(bc(b)); t.equal(denied.code,"experience_limit","late XP cap reached after resolution")
	t.equal(b.state_hash(),before,"late failure restores HP focus RNG XP IDs and revision")
	t.expect(denied.events.is_empty(),"late failure publishes no events")
	b=battle(t); before=b.state_hash()
	var forged: Dictionary=b.capture(); forged.mana[0].current=999
	t.expect(not b.restore(forged).ok,"over-limit resource snapshot rejected"); t.equal(b.state_hash(),before,"corrupt save atomic")
	forged=first.duplicate(true); forged.schema_version=12
	t.expect(not b.restore(forged).ok,"old schema cannot disguise psi")
	b=battle(t,0,false); forged=b.capture(); before=b.state_hash()
	for track: Dictionary in forged.development.members[0].body.tracks:
		if track.track_id==TRACK: track.earned_total=20
	for attack: Dictionary in forged.development.members[0].attacks:
		if attack.ability_id==ABILITY: attack.count=1
	forged.revision="1"; forged.development.sequence="1"
	var invalid: Dictionary=b.restore(forged)
	t.expect(not invalid.ok and "encounter_development_invalid" in invalid.errors,"unlearned psi counter is invalid even with consistent XP")
	t.equal(b.state_hash(),before,"forged practice load atomic")
	b=battle(t,100,true,true)
	result=b.execute(bc(b)); t.expect(result.accepted,"lethal impulse accepted")
	t.expect(b.view().finished and not b._state.actor(3).spatial.alive,"last enemy death resolves victory")
	t.equal(b._state.development.bodies[1].tracks[TRACK].earned,120,"lethal action still grants own practice exactly once")
	t.expect(b.restore(b.capture()).ok,"finished lethal psi snapshot reloads")

static func life_content() -> Dictionary:
	var c: Dictionary=Sm2PsionicContentLoader.load_scenario()
	var injury: Dictionary=PROSTHESIS.loss_content()
	var dev: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new(); var errors: PackedStringArray=dev.build(c.development.to_data(),c.development.progression(),injury.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	c.combat=injury.combat; c.development=dev; c.setup=injury.setup
	c.journey_fingerprint=Sm2Canonical.hash([c.journey_fingerprint,injury.journey_fingerprint])
	return c

static func _lives(t: Sm2TestHarness) -> void:
	var c: Dictionary=life_content(); t.expect(c.ok,"psi and body injury compose")
	var s: Sm2JourneySession=Sm2JourneySession.new(c,Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://psi-lives"))
	t.expect(s.new_game().ok,"lives world starts"); learn(s,t)
	t.expect(s.act(s.command("explore",0,"first_aid")).ok,"world site collected")
	t.expect(s.act(s.command("start_battle")).ok,"lives first fight")
	t.expect(hero_turn(s,t),"hero for lives impulse"); var victim: int=target(s)
	t.expect(victim>0 and s.attack(command(s,"use_ability",ABILITY,victim)).accepted,"impulse before retreat")
	PROSTHESIS.finish_retreat(s,t)
	t.equal(s.world.hero_id(),2,"hero survives genuine encounter")
	t.equal(s.world.bodies[2].progress.tracks[TRACK].earned,120,"outcome transfers psi practice once")
	t.expect(s.save_game().ok and s.load_game().ok,"outcome history reload")
	t.equal(s.world.bodies[2].progress.tracks[TRACK].earned,120,"reload does not duplicate practice")
	var camp: Dictionary=s.capture()
	t.expect(s.act(s.command("start_battle")).ok,"second encounter starts")
	t.equal(s.runner._session._battle._state.mana[1].current,12,"new fight starts with full focus")
	t.expect(s.runner.view().actors[0].abilities.has(ABILITY),"learned impulse in next encounter")
	t.expect(s.restore(camp).ok,"return to saved camp branch")
	var companion: Dictionary=s.world.bodies[4].to_data(); var items: Array=s.journey().items.duplicate(true); var places: Dictionary=s.journey().exploration.to_data(); var knowledge: Array=s.world.soul.knowledge.duplicate()
	var stale: Sm2WorldCommand=s.command("practice",2,PRACTICE)
	t.expect(s.act(s.command("end_life")).ok and s.act(s.command("incarnate",8)).ok,"new pure human body")
	t.equal(s.world.bodies[8].progress.tracks[TRACK].earned,0,"new incarnation practice zero")
	t.expect(s.world.bodies[8].progress.tracks[TRACK].nodes.is_empty(),"new incarnation node absent")
	t.equal(s.world.bodies[4].to_data(),companion,"companion growth persists")
	t.equal(s.journey().items,items,"equipment stays in world")
	t.equal(s.journey().exploration.to_data(),places,"collected places persist")
	t.equal(s.world.soul.knowledge,knowledge,"Soul knowledge persists")
	var before: String=s.state_hash(); t.expect(not s.act(stale).ok,"old body practice command rejected"); t.equal(s.state_hash(),before,"stale command inert")
	var untrained: Dictionary=s.capture()
	t.expect(s.act(s.command("start_battle")).ok,"new body enters second fight")
	t.expect(not s.runner.view().actors[0].abilities.has(ABILITY),"old body cannot grant spell to new body")
	t.expect(s.restore(untrained).ok,"return new body to camp"); learn(s,t)
	t.expect(s.save_game().ok and s.load_game().ok,"new body own training and node persist")
	t.expect(s.act(s.command("start_battle")).ok,"retrained body battle")
	t.expect(s.runner.view().actors[0].abilities.has(ABILITY),"new body's own node grants impulse")
