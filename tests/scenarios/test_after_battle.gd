extends RefCounted
const CHECKPOINT=preload("res://tests/scenarios/test_checkpoint.gd")
const RESULTS=preload("res://tests/scenarios/test_battle_results.gd")
const OUTING=preload("res://tests/scenarios/test_expedition.gd")
const SHIELD=preload("res://tests/scenarios/test_p5_shield.gd")
const TISSUES=preload("res://tests/scenarios/test_survival_tissues.gd")

static func run(t: Sm2TestHarness) -> void:
	_psionics(t)
	for retreat: bool in [false,true]: _route(t,retreat)
	_legacy(t)
	t.complete_suite("after_battle")

static func _psionics(t: Sm2TestHarness) -> void:
	var growth: GDScript=preload("res://tests/scenarios/test_p5_growth.gd")
	var psi: GDScript=preload("res://tests/scenarios/test_p5_psionics.gd")
	var s: Sm2JourneySession=growth.make(); s.world.start("p5:after-battle-test")
	var body: Sm2ProgressBodyState=s.world.bodies[2].progress
	body.tracks[growth.TRACK].earned=240; body.tracks[growth.TRACK].spent=100; body.tracks[growth.TRACK].nodes.append(growth.NODE)
	body.tracks[growth.RESONANCE].earned=245
	s.world.apply(s.command("start_battle"))
	var content: Dictionary=Sm2EncounterFactory.build(s._content,s.journey())
	content.setup.actors[2].q=2; content.setup.actors[2].r=1; content.setup.growth_timing=Sm2BattleDevelopment.AFTER_BATTLE
	var b: Sm2TacticalBattle=Sm2TacticalBattle.new(content.catalog,content.combat,true,content.effects,content.magic,content.development,content.origin)
	t.expect(b.start(content.setup).ok,"explicit after-battle psi encounter starts")
	t.equal(b.preview(psi.bc(b)).damage,12,"known initial impulse damage")
	var result: Sm2CommandResult=b.execute(psi.bc(b))
	t.expect(result.accepted,"actual impulse crosses two pending XP thresholds")
	t.equal(b._state.development.bodies[1].tracks[growth.TRACK].earned,240,"own skill not increased during cast")
	t.equal(b._state.development.bodies[1].tracks[growth.RESONANCE].earned,245,"attribute not increased during cast")
	t.equal(b._state.development.pending[1],{growth.TRACK:20,growth.RESONANCE:5},"both own XP sources accumulate separately")
	t.equal(b.preview(psi.bc(b)).damage,12,"next impulse remains unchanged instead of old 16")
	var raw: Dictionary=b.capture(); var before: String=b.state_hash()
	t.expect(b.restore(raw).ok,"pending psi snapshot fully restores")
	t.equal(b.state_hash(),before,"restore neither applies nor loses pending XP")
	t.equal(b.preview(psi.bc(b)).damage,12,"loaded prediction uses prebattle growth")
	var invalid: Sm2Command=psi.bc(b); invalid.expected_revision=-1
	t.expect(not b.execute(invalid).accepted,"stale command rejected")
	t.equal(b.state_hash(),before,"rejected action cannot accumulate practice")
	result=b.execute(psi.bc(b))
	t.expect(result.accepted,"second impulse accepted")
	t.equal(b._state.actor(3).combat.hp,36,"both actual hits use the original damage")
	# Limit refusal is atomic even while XP has not yet been applied.
	var dev: Sm2BattleDevelopment=b._state.development.copy()
	dev.bodies[1].tracks[growth.TRACK].earned=Sm2ProgressCatalog.XP_LIMIT-40
	before=Sm2Canonical.hash(dev.to_data()); var pending: Dictionary=dev.pending.duplicate(true)
	var events: Array[Dictionary]=[]
	t.equal(dev.award(1,growth.ABILITY,events),"experience_limit","pending amount counts against XP limit")
	t.equal(Sm2Canonical.hash(dev.to_data()),before,"overflow cannot change counters or body")
	t.equal(dev.pending,pending,"overflow leaves pending untouched")
	t.expect(events.is_empty(),"overflow cannot publish practice event")

static func _route(t: Sm2TestHarness,retreat: bool) -> void:
	var s: Sm2CheckpointSession=CHECKPOINT.make("user://after-battle-"+str(retreat))
	t.expect(s.new_game().ok,"main campaign starts")
	SHIELD.learn(s,t)
	# Valid isolated initial body one XP below each next level. This is not a reward.
	var hero: Sm2ProgressBodyState=s.world.bodies[2].progress
	var catalog: Sm2ProgressCatalog=s.world._progress
	for id: String in hero.tracks:
		var definition: Sm2ProgressTrackDefinition=catalog.track(id)
		var advances: int=int(definition.describe(hero.tracks[id].earned).level)-definition.base_level
		hero.tracks[id].earned=definition.threshold(advances+1)-1
	(s.world.bodies[4].progress as Sm2CompanionProgress).earned=99
	t.expect(s.world.validate().is_empty(),"near-threshold initial fixture is valid")
	t.expect(s.act(s.command("travel",0,"ruins")).ok and s.act(s.command("start_battle")).ok,"new main encounter uses deferred growth")
	var initial: Sm2TacticalState=s.runner.state_copy()
	t.expect(initial.development.deferred_growth,"new encounter explicitly records timing")
	var baseline: Dictionary={}; var bonus: Dictionary={}
	for id: int in [1,2]:
		baseline[id]=initial.development.bodies[id].to_data(); bonus[id]=initial.development.stat_bonus(id,"melee_skill")
	var totals: Dictionary[int,Dictionary]={1:{},2:{}}
	var saved: bool=false
	var pending_snapshot: Dictionary={}
	for index: int in 400:
		if not s.world.busy(): break
		var active: Dictionary=s.runner.status()
		var actor: Sm2TacticalActor=s.runner.state_copy().actor(int(active.active_actor_id))
		var events: Array=[]
		if actor.spatial.controller=="player" and actor.morale!="fleeing":
			var choice: Dictionary=s.runner._session.ai_decision(s._profile)
			t.expect(choice.ok,"real AI choice for controlled member")
			if not choice.ok: break
			var result: Sm2CommandResult=s.attack(choice.command)
			t.expect(result.accepted,"real action accepted: "+result.code)
			if not result.accepted: break
			events=result.events
		else:
			var result: Dictionary=s.step(); t.expect(result.ok,"real AI step accepted")
			if not result.ok: break
			events=result.get("events",[])
		for event: Dictionary in events:
			if event.type=="battle_practice_accumulated":
				var owner: int=int(event.actor_id)
				totals[owner][event.track_id]=int(totals[owner].get(event.track_id,0))+int(event.amount)
				t.expect(not event.has("level_after"),"accumulation does not calculate levels")
		if not s.world.busy(): break
		var state: Sm2TacticalState=s.runner.state_copy()
		for id: int in [1,2]:
			t.equal(state.development.bodies[id].to_data(),baseline[id],"entire learned body remains fixed while fighting")
			t.equal(state.development.stat_bonus(id,"melee_skill"),bonus[id],"development combat bonus does not grow midfight")
		if not state.development.pending.get(1,{}).is_empty() and not saved:
			pending_snapshot=s.capture(); var before: String=s.state_hash()
			t.expect(s.save_game().ok and s.load_game().ok,"active pending practice survives disk roundtrip")
			t.equal(s.state_hash(),before,"load cannot apply pending XP")
			t.equal(s.runner.state_copy().development.pending,state.development.pending,"pending totals reconstructed from action counters")
			for defect: String in ["early_xp","timing","pending","counts"]:
				var bad: Dictionary=pending_snapshot.duplicate(true)
				var dev: Dictionary=bad.active.session.battle.development
				match defect:
					"early_xp": dev.members[0].body.tracks[0].earned_total+=1
					"timing": dev.growth_timing="unknown"
					"pending": dev["pending"]={"free_xp":999}
					"counts": dev.members[0].attacks[0].count+=1
				t.expect(not s.restore(bad).ok,"incoming inconsistent pending snapshot rejected: "+defect)
				t.equal(s.state_hash(),before,"failed restore is atomic: "+defect)
			saved=true
			if retreat:
				OUTING.retreat(s,t)
				break
	t.expect(saved,"route includes practice before battle ends")
	t.expect(not s.world.busy(),"real encounter settled")
	if s.world.busy(): return
	var final: Sm2TacticalState=s.runner.state_copy()
	t.expect(final.development.pending.is_empty(),"pending consumed on closing command")
	var view: Dictionary=Sm2BattleResultsView.build(s)
	t.expect(not view.is_empty(),"frozen final growth table available")
	var grew: bool=false
	for row: Dictionary in view.party:
		var actor_id: int=1 if row.name=="Герой" else 2
		t.equal(s.world.bodies[row.body_id].progress.to_data(),final.development.bodies[actor_id].to_data(),"settlement transfers XP into correct living or dead body")
		for practice: Dictionary in row.practice:
			t.expect(practice.xp>=0 and practice.after>=practice.before,"table reports positive practice and final levels")
			if practice.after>practice.before: grew=true
	t.expect(grew,"at least one threshold crossed only after encounter")
	var before: String=s.state_hash(); var summary: Array=view.party.duplicate(true)
	t.expect(s.save_game().ok and s.load_game().ok,"closed battle saves and loads")
	t.equal(s.state_hash(),before,"closed reload cannot double award")
	t.equal(Sm2BattleResultsView.build(s).party,summary,"reopening final table cannot grant practice")
	var early: Sm2CheckpointSession=CHECKPOINT.make("user://after-battle-early-"+str(retreat))
	t.expect(early.restore(pending_snapshot).ok,"earlier in-fight save remains independently loadable")
	t.equal(early.runner.state_copy().development.bodies[1].to_data(),baseline[1],"early save never inherits later growth")

static func _legacy(t: Sm2TestHarness) -> void:
	var old: Sm2JourneySession=TISSUES.make()
	t.expect(old.new_game().ok and old.act(old.command("travel",0,"ruins")).ok and old.act(old.command("start_battle")).ok,"old session fixture starts")
	for i: int in 12:
		if not old.world.busy(): break
		t.expect(RESULTS.step(old).ok,"old active encounter advances")
	var s: Sm2CheckpointSession=CHECKPOINT.make("user://after-battle-legacy")
	var raw: Dictionary=old.capture()
	t.expect(s.restore(raw).ok,"legacy active encounter imports")
	t.expect(not s.runner.state_copy().development.deferred_growth,"already running legacy encounter keeps its original rule")
	t.equal(s.runner.capture(),old.runner.capture(),"legacy combat snapshot unchanged")
