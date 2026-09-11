extends RefCounted
const OLD=preload("res://tests/scenarios/test_p4_journey.gd")
const STRIKE: String="m2:ability.sword_strike"
const POWER: String="p1:stat.strength"
const MELEE: String="p1:skill.melee"

static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2PartyContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2PartyContentLoader.load_scenario()
	t.expect(c.ok,"party content validates: "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("p4_party"); return
	var p: Sm2ProgressCatalog=c.development.progression()
	var attrs: int=0
	for id: String in p.track_ids():
		if p.track(id).kind=="attribute": attrs+=1
	t.equal(attrs,8,"hero has eight attributes")
	var simple: Sm2CompanionProgress=Sm2CompanionProgress.new(); simple.id=4
	for earned: int in [0,99,100,249,250,449,450]:
		simple.earned=earned
		var expected: int=1 if earned<100 else 2 if earned<250 else 3 if earned<450 else 4
		t.equal(simple.describe(p).level,expected,"independent level threshold oracle")
		for row: Dictionary in simple.attributes(p): t.equal(row.effective,9+expected,"automatic attribute gains")
	t.expect(simple.tracks.is_empty(),"companion stores no hero tracks")
	var original: String=p.fingerprint()
	for defect: String in ["step","negative","missing","duplicate","skill"]:
		var raw: Dictionary=p.to_data()
		match defect:
			"step": raw.companion_growth.step=0
			"negative": raw.companion_growth.attack_xp=-1
			"missing": raw.companion_growth.attributes.pop_back()
			"duplicate": raw.companion_growth.attributes.append(raw.companion_growth.attributes[0])
			"skill": raw.companion_growth.attributes[0].track_id=MELEE
		t.expect(not p.build(raw).is_empty(),"bad growth content rejected "+defect)
		t.equal(p.fingerprint(),original,"failed content build atomic")
	_attacks(t,c)
	_growth_and_death(t,c)
	var store: Sm2SaveStore=Sm2SaveStore.new("user://party-tests")
	var s: Sm2JourneySession=make(store)
	t.expect(s.new_game().ok,"party world starts")
	t.expect(s.world.bodies[4].progress is Sm2CompanionProgress,"world companion simple")
	t.expect(s.act(s.command("start_battle")).ok,"mixed battle starts")
	t.equal(s.runner.capture().session.battle.schema_version,10,"new schema explicit")
	for i: int in 7: t.expect(OLD.advance(s).ok,"mixed encounter advances")
	t.expect(s.save_game().ok,"mixed active save")
	var loaded: Sm2JourneySession=make(store)
	t.expect(loaded.load_game().ok,"active reload")
	t.equal(loaded.state_hash(),s.state_hash(),"active round trip exact")
	t.equal(OLD.advance(loaded),OLD.advance(s),"next command deterministic after reload")
	t.equal(loaded.state_hash(),s.state_hash(),"next resulting state exact")
	var before: String=s.state_hash()
	for defect: String in ["xp","model","version","world"]:
		var bad: Dictionary=s.capture()
		match defect:
			"xp": bad.active.session.battle.development.members[1].body.growth.earned_total+=1
			"model": bad.active.session.battle.development.members[1].body=Sm2ProgressRules.empty_body(4,p).to_data()
			"version": bad.active.session.battle.schema_version=9
			"world": bad.world.bodies[1].progress.growth.earned_total+=1
		t.expect(not s.restore(bad).ok,"tampered save rejected "+defect)
		t.equal(s.state_hash(),before,"invalid load atomic")
	t.expect(not OLD.make().restore(s.capture()).ok,"old journey refuses new format")
	OLD.finish(s,t)
	t.equal(s.journey().completed,1,"mixed outcome settles")
	t.expect(s.world.hero_id()!=0 and s.world.bodies[4].alive,"first seed leaves both alive")
	if s.world.hero_id()==0 or not s.world.bodies[4].alive: t.complete_suite("p4_party"); return
	var comp: Dictionary=s.world.bodies[4].to_data()
	t.expect(comp.progress.growth.earned_total>0,"companion keeps personal battle XP")
	before=s.state_hash()
	for kind: String in ["practice","buy_node"]:
		t.expect(not s.act(s.command(kind,4,"p1:node.strength_1")).ok,"companion cannot train or buy nodes")
		t.equal(s.state_hash(),before,"rejected companion action atomic")
	for id: String in p.activity_ids():
		t.expect(s.act(s.command("practice",s.world.hero_id(),id)).ok,"hero camp exercise "+id)
	for id: String in p.track_ids():
		if p.track(id).kind=="attribute": t.expect(s.world.bodies[2].progress.tracks[id].earned>0,"hero attribute owns XP")
	for i: int in 4: t.expect(s.act(s.command("practice",2)).ok,"hero sword practice")
	var hero_level: int=p.track(POWER).describe(s.world.bodies[2].progress.tracks[POWER].earned).level
	t.expect(s.act(s.command("buy_node",2,"p1:node.strength_1")).ok,"hero can buy node")
	t.equal(p.track(POWER).describe(s.world.bodies[2].progress.tracks[POWER].earned).level,hero_level,"purchase does not lower level")
	t.equal(s.world.bodies[4].to_data(),comp,"hero training never trains companion")
	t.expect(s.save_game().ok and loaded.load_game().ok,"camp disk round trip")
	t.equal(loaded.state_hash(),s.state_hash(),"camp restore includes eight tracks and node")
	var camp: Dictionary=s.capture()
	t.expect(s.act(s.command("start_battle")).ok,"second encounter accepts accumulated growth")
	t.equal(s.runner.capture().session.battle.development.members[1].body,comp.progress,"companion baseline transferred")
	t.expect(s.restore(camp).ok,"restore reincarnation branch")
	var knowledge: Array[String]=s.world.soul.knowledge.duplicate()
	var items: Array[Dictionary]=s.journey().items.duplicate(true)
	t.expect(s.act(s.command("end_life")).ok,"hero ends body")
	t.expect(s.act(s.command("incarnate",8)).ok,"new human body")
	for track: Sm2ProgressTrackState in s.world.bodies[8].progress.tracks.values():
		t.equal(track.earned,0,"every new-body track resets")
		t.expect(track.nodes.is_empty(),"new-body nodes reset")
	t.equal(s.world.bodies[4].to_data(),comp,"companion survives reincarnation unchanged")
	t.equal(s.world.soul.knowledge,knowledge,"Soul knowledge preserved")
	t.equal(s.journey().items,items,"items remain in world")
	t.expect(s.save_game().ok and loaded.load_game().ok,"new incarnation disk round trip")
	t.equal(loaded.state_hash(),s.state_hash(),"new incarnation exact")
	t.expect(s.act(s.command("start_battle")).ok,"new body enters next fight")
	t.equal(s.runner.capture().session.battle.development.members[0].body.id,"8","new hero binding")
	t.equal(s.runner.capture().session.battle.development.members[1].body,comp.progress,"old companion retained with new hero")
	t.complete_suite("p4_party")

static func battle(c: Dictionary, seed_value: int=1, capped: bool=false, initial_xp: int=0) -> Sm2TacticalBattle:
	var world: Sm2JourneyWorld=Sm2JourneyWorld.new(c.development.progression(),c.world_definition,c.combat,c.meetings,c.initial_loadout)
	world.start("party-oracle")
	(world.bodies[4].progress as Sm2CompanionProgress).earned=initial_xp
	if capped: (world.bodies[4].progress as Sm2CompanionProgress).earned=1000000
	var e: Dictionary=Sm2EncounterFactory.build(c,world)
	e.setup.seed=seed_value
	# Enemy adjacent only to companion, so its departure has one eligible reactor.
	e.setup.actors[2].q=2; e.setup.actors[2].r=3
	var b: Sm2TacticalBattle=Sm2TacticalBattle.new(e.catalog,e.combat,true,null,null,e.development,e.origin)
	b.start(e.setup)
	return b

static func cmd(b: Sm2TacticalBattle, kind: String, target: int=0) -> Sm2Command:
	var v: Sm2Command=Sm2Command.new()
	v.kind=kind; v.actor_id=b.view().active_actor_id; v.expected_revision=b.view().revision; v.battle_id=b.view().battle_id
	v.target_actor_id=target; v.ability_id=STRIKE if kind=="use_ability" else ""
	return v

static func _attacks(t: Sm2TestHarness,c: Dictionary) -> void:
	var outcomes: Dictionary={}
	for seed_value: int in range(1,40):
		var b: Sm2TacticalBattle=battle(c,seed_value)
		t.expect(not b.view().is_empty(),"companion attack fixture starts")
		if b.view().is_empty(): return
		t.expect(b.execute(cmd(b,"end_turn")).accepted,"hero passes")
		t.equal(b.view().active_actor_id,2,"companion activation")
		var before: String=b.state_hash()
		var attack: Sm2Command=cmd(b,"use_ability",3)
		t.expect(b.preview(attack).allowed,"companion preview allowed")
		t.equal(b.state_hash(),before,"preview grants no XP")
		var result: Sm2CommandResult=b.execute(attack)
		t.expect(result.accepted,"companion personal attack "+result.code)
		for event: Dictionary in result.events:
			if event.type in ["attack_hit","attack_missed"]: outcomes[event.type]=true
		t.equal(b.capture().development.members[1].body.growth.earned_total,40,"hit or miss gives exactly 40 personal XP")
		for track: Dictionary in b.capture().development.members[0].body.tracks: t.equal(track.earned_total,0,"companion never trains hero")
		before=b.state_hash()
		t.expect(not b.execute(attack).accepted,"duplicate attack rejected")
		t.equal(b.state_hash(),before,"duplicate preserves XP RNG HP")
		if outcomes.size()==2: break
	t.equal(outcomes.size(),2,"real hit and real miss observed")
	var b: Sm2TacticalBattle=battle(c)
	for i: int in 2: t.expect(b.execute(cmd(b,"end_turn")).accepted,"reach enemy turn")
	var move: Sm2Command=cmd(b,"move"); move.target=Vector2i(3,3)
	var result: Sm2CommandResult=b.execute(move)
	t.expect(result.accepted,"enemy departure "+result.code)
	var reacted: bool=false
	for event: Dictionary in result.events:
		if event.type=="reaction_spent" and event.actor_id=="2": reacted=true
	t.expect(reacted,"actual companion reaction")
	t.equal(b.capture().development.members[1].body.growth.earned_total,40,"reaction gives same XP")
	b=battle(c,1,true)
	t.expect(b.execute(cmd(b,"end_turn")).accepted,"capped companion reaches turn")
	var before: String=b.state_hash()
	result=b.execute(cmd(b,"use_ability",3))
	t.equal(result.code,"experience_limit","late companion XP-cap refusal")
	t.equal(b.state_hash(),before,"late refusal rolls back HP armor RNG counters")
	t.expect(result.events.is_empty(),"failed attack publishes no events")
	b=battle(c,1,true)
	for i: int in 2: t.expect(b.execute(cmd(b,"end_turn")).accepted,"capped reaction reaches enemy")
	before=b.state_hash(); move=cmd(b,"move"); move.target=Vector2i(3,3)
	result=b.execute(move)
	t.equal(result.code,"experience_limit","late reaction XP cap rejected")
	t.equal(b.state_hash(),before,"failed reaction rolls back departure and all actors")

static func _growth_and_death(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle=battle(c,1,false,80)
	t.expect(b.execute(cmd(b,"end_turn")).accepted,"reach companion near threshold")
	var command: Sm2Command=cmd(b,"use_ability",3)
	var baseline: Dictionary=b.preview(command)
	t.expect(b.execute(command).accepted,"attack crosses level threshold")
	var actor: Dictionary=b.view().actors[1]
	t.equal(actor.development.growth.level,2,"real attack raises general level")
	t.equal(actor.development.melee_bonus,2,"level adds prototype combat bonus")
	t.equal(actor.melee_stat.value,72,"shared stat query observes new level")
	for row: Dictionary in actor.development.tracks: t.equal(row.effective,11,"level automatically raises all eight attributes")
	var decoded: Dictionary=Sm2DevelopmentSnapshot.decode(b.capture(),b._catalog,b._combat,null,null,b._development,b._origin)
	t.expect(decoded.ok,"leveled companion snapshot accepted")
	if decoded.ok:
		decoded.state.actor(2).spatial.ap=decoded.state.actor(2).spatial.ap_max
		decoded.state.actor(2).spatial.fatigue=0
		var query: Sm2AiQueries=Sm2AiQueries.new(decoded.state,b._combat)
		var forecast: Dictionary=query.attack(command,decoded.state.actor(2).spatial.position)
		var resolved: Dictionary=Sm2AttackResolver.preview(decoded.state,b._combat,command)
		t.expect(forecast.allowed and resolved.allowed,"leveled attack forecast available")
		t.equal(forecast.modifiers.skill,72,"AI uses simple companion growth")
		t.equal(forecast.hit_chance,resolved.hit_chance,"AI and attack share final accuracy")
		(decoded.state.development.bodies[2] as Sm2CompanionProgress).earned=0
		t.equal(query.attack(command,decoded.state.actor(2).spatial.position),forecast,"AI projection detached from body")
	t.equal(baseline.modifiers.skill,70,"earning attack used pre-level stats")
	var before: String=b.state_hash()
	t.expect(b.restore(b.capture()).ok,"restore own leveled snapshot")
	t.equal(b.state_hash(),before,"restore does not apply level gains twice")
	# Explicit prepared death fixture, independent of fight balance or chosen seeds.
	var world: Sm2JourneyWorld=Sm2JourneyWorld.new(c.development.progression(),c.world_definition,c.combat,c.meetings,c.initial_loadout)
	world.start("dead-companion-fixture")
	world.bodies[4].alive=false; world.bodies[4].hp=0; world.bodies[4].death_cause="battle"
	(world.bodies[4].progress as Sm2CompanionProgress).earned=200
	var companion: Dictionary=world.bodies[4].to_data()
	world.receipt="fixture-completed"
	var end: Sm2WorldCommand=Sm2WorldCommand.new(); end.kind="end_life"
	world.apply(end)
	var incarnate: Sm2WorldCommand=Sm2WorldCommand.new(); incarnate.kind="incarnate"; incarnate.target_id=8
	world.apply(incarnate)
	t.equal(world.bodies[4].to_data(),companion,"dead companion not resurrected by incarnation")
	var e: Dictionary=Sm2EncounterFactory.build(c,world)
	b=Sm2TacticalBattle.new(e.catalog,e.combat,true,null,null,e.development,e.origin)
	t.expect(b.start(e.setup).ok,"encounter accepts dead companion history")
	t.expect(not b.view().actors[1].alive,"dead companion absent from living roster")
	var denied: Sm2Command=cmd(b,"use_ability",3); denied.actor_id=2
	before=b.state_hash()
	t.expect(not b.execute(denied).accepted,"dead companion cannot attack")
	t.equal(b.state_hash(),before,"dead actor cannot earn XP")
	var changed: Dictionary=b.capture(); changed.development.members[1].body.growth.earned_total+=40
	t.expect(not b.restore(changed).ok,"dead companion forged XP rejected")
