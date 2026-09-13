extends RefCounted
const FIXTURE=preload("res://tests/scenarios/test_checkpoint.gd")
const SHIELD=preload("res://tests/scenarios/test_p5_shield.gd")

## The old coordinator always decoded its copy and validated the whole world.
class SlowSession extends Sm2CheckpointSession:
	func _fresh() -> Sm2CheckpointSession: return SlowSession.new(_content,_profile,_store,repository,true)
	func _copy() -> Sm2LifeSession:
		var candidate: Sm2CheckpointSession=super._copy() as Sm2CheckpointSession
		if runner!=null:
			var result: Dictionary=candidate.runner.restore(runner.capture())
			if not result.ok: return null
		return candidate
	func _commit_battle_action(value: Sm2JourneySession) -> Dictionary: return _publish(value)

class RejectCommit extends Sm2CheckpointSession:
	func _check_capacity(_value: Sm2CheckpointSession) -> Dictionary: return _error("injected_capacity_failure")

static func run(t: Sm2TestHarness) -> void:
	cache_contracts(t)
	var s: Sm2CheckpointSession=FIXTURE.make("user://combat-runtime-tests")
	t.expect(s.new_game().ok,"runtime fixture starts")
	SHIELD.learn(s,t)
	t.expect(s.act(s.command("travel",0,"ruins")).ok and s.act(s.command("start_battle")).ok,"runtime fixture enters combat")
	copy_contracts(s,t)
	var slow: SlowSession=SlowSession.new(s._content,s._profile,null,null,true)
	t.expect(slow.restore(s.capture()).ok,"old coordinator oracle restored")
	var seen: Dictionary={}; var moves: int=0
	for i: int in 160:
		if not s.world.busy(): break
		var status: Dictionary=s.runner.status(); var view: Dictionary=s.runner.view()
		for key: String in status:
			if key!="actors": t.equal(status[key],view[key],"compact status agrees: "+key)
		var actor: Dictionary={}
		for row: Dictionary in status.actors:
			if row.actor_id==status.active_actor_id: actor=row
		var events: Array=[]
		if actor.controller=="player" and actor.morale!="fleeing":
			var decision: Dictionary=s.runner._session.ai_decision(s._profile)
			t.expect(decision.ok,"oracle chooses one legal ordinary command")
			if not decision.ok: break
			var a: Sm2CommandResult=s.attack(decision.command); var b: Sm2CommandResult=slow.attack(decision.command)
			t.expect(a.accepted and b.accepted,"both coordinators accept player command")
			t.equal([a.code,a.events,a.revision],[b.code,b.events,b.revision],"player events and revision identical")
			events=a.events
		else:
			var a: Dictionary=s.step(); var b: Dictionary=slow.step()
			t.expect(a.ok and b.ok,"both coordinators advance AI")
			t.equal(a,b,"AI choice, events and outcome identical")
			events=a.get("events",[])
		for event: Dictionary in events: seen[event.type]=true
		moves+=1
		t.equal(s.state_hash(),slow.state_hash(),"entire world, RNG, XP, anatomy and archive identical after command")
		if i==6:
			var before: String=s.state_hash()
			t.expect(s.world.busy() and s.save_game().ok and s.load_game().ok,"mid-combat physical save/load")
			t.equal(s.state_hash(),before,"no additional turn, XP, bleed or resource tick on load")
	t.expect(not s.world.busy() and moves>6,"oracle combat reaches settlement")
	t.expect(seen.has("attack_hit"),"oracle includes real damage")
	t.expect(seen.has("attack_missed"),"oracle includes real miss")
	t.expect(s.world.validate().is_empty(),"settled world validates")
	print("COMBAT_RUNTIME_ORACLE "+JSON.stringify({"commands":moves,"events":seen.keys()}))
	t.complete_suite("combat_runtime")

static func cache_contracts(t: Sm2TestHarness) -> void:
	var catalog: Sm2ProgressCatalog=Sm2SurvivalContentLoader.load_scenario(true,true).development.progression()
	var body: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(2,catalog)
	var cache: Sm2ProgressDecodeCache=Sm2ProgressDecodeCache.new()
	var raw: Dictionary=body.to_data()
	t.expect(Sm2ProgressRules.decode_body(raw,catalog,cache).ok,"cache seeded only by full successful decode")
	for defect: String in ["bool_xp","fraction_xp","negative_xp","spent","node","packed","id","extra"]:
		var bad: Dictionary=raw.duplicate(true)
		match defect:
			"bool_xp": bad.tracks[0].earned_total=false
			"fraction_xp": bad.tracks[0].earned_total=0.5
			"negative_xp": bad.tracks[0].earned_total=-1
			"spent": bad.tracks[0].spent_total=1
			"node": bad.tracks[0].owned_nodes=["missing"]
			"packed": bad.tracks[0].owned_nodes=PackedStringArray()
			"id": bad.id=2
			"extra": bad.extra=true
		t.expect(not Sm2ProgressRules.decode_body(bad,catalog,cache).ok,"warm cache rejects "+defect)
	var known: Sm2ProgressBodyState=cache.find(raw,catalog)
	t.expect(known!=null,"exact known value reuses certificate")
	known.tracks[catalog.track_ids()[0]].earned=999
	t.equal(cache.find(raw,catalog).to_data(),raw,"returned body detached from certificate")
	var changed: Dictionary=raw.duplicate(true); changed.tracks[0].earned_total=10
	t.expect(cache.find(changed,catalog)==null,"changed XP cannot reuse certificate")
	t.expect(Sm2ProgressRules.decode_body(changed,catalog,cache).ok,"changed legal XP fully decoded")
	changed.tracks[0].earned_total=-1
	t.expect(not Sm2ProgressRules.decode_body(changed,catalog,cache).ok,"caller cannot mutate stored certificate")
	for i: int in 12:
		var variant: Dictionary=raw.duplicate(true); variant.tracks[0].earned_total=i+20
		t.expect(Sm2ProgressRules.decode_body(variant,catalog,cache).ok,"bounded cache accepts independently checked value")
	t.equal(cache._entries.size(),Sm2ProgressDecodeCache.CAPACITY,"certificate storage bounded")
	t.expect(cache.find(raw,catalog)==null,"oldest certificate evicted")
	var definitions: Dictionary=catalog.to_data(); definitions.nodes[0].bonus+=1
	t.expect(catalog.build(definitions).is_empty(),"test rebuild valid catalog")
	var last_raw: Dictionary=raw.duplicate(true); last_raw.tracks[0].earned_total=31
	t.expect(cache.find(last_raw,catalog)==null,"different catalog fingerprint cannot reuse old certificate")
	var companion: Sm2CompanionProgress=Sm2CompanionProgress.new(); companion.id=4
	t.expect(Sm2ProgressRules.decode_body(companion.to_data(),catalog,cache).ok,"companion certificate stores concrete type")
	t.expect(cache.find(companion.to_data(),catalog) is Sm2CompanionProgress,"companion cache copy preserves type")
	var bad_companion: Dictionary=companion.to_data(); bad_companion.growth.earned_total=false
	t.expect(not Sm2ProgressRules.decode_body(bad_companion,catalog,cache).ok,"warm companion cache rejects boolean XP")

static func copy_contracts(s: Sm2CheckpointSession,t: Sm2TestHarness) -> void:
	var before: String=s.state_hash(); var copy: Sm2CheckpointSession=s._copy() as Sm2CheckpointSession
	t.equal(copy.state_hash(),before,"in-memory copy exact before mutation")
	t.expect(copy.world._progress==s.world._progress,"internal immutable catalog shared")
	copy.world.bodies[2].progress.tracks["p1:skill.psionics"].earned+=1
	copy.runner._session._battle._state.rng.draws+=1
	copy.runner._session._battle._state.actor(1).spatial.fatigue+=1
	copy.runner._session._battle._state.development.bodies[1].tracks["p1:skill.psionics"].earned+=1
	copy.runner._origin["copy_probe"]=true
	copy.runner._attempts+=1
	copy.facts["copy_probe"]=true
	t.equal(s.state_hash(),before,"mutable world, combat, RNG, progress, runner and facts detached")
	var foreign: Sm2CheckpointSession=s._fresh()
	t.expect(not s._commit_battle_action(foreign).ok,"foreign candidate rejected")
	copy=s._copy() as Sm2CheckpointSession
	copy._copy_revision-=1; copy.world.revision+=1
	t.expect(not s._commit_battle_action(copy).ok,"stale candidate rejected")
	t.equal(s.state_hash(),before,"candidate refusals atomic")
	copy=s._copy() as Sm2CheckpointSession; copy.world.bodies[2].progress.tracks["p1:skill.psionics"].spent=-1
	t.expect(not s._publish(copy).ok,"general publisher retains full world validation")
	t.equal(s.state_hash(),before,"invalid general publish atomic")
	var command: Sm2Command=Sm2Command.new(); var status: Dictionary=s.runner.status()
	command.kind="end_turn"; command.actor_id=int(status.active_actor_id); command.battle_id=status.battle_id; command.expected_revision=-1
	t.expect(not s.attack(command).accepted,"stale command rejected")
	t.equal(s.state_hash(),before,"failed command leaves no XP, RNG or revision mutation")
	var failing: RejectCommit=RejectCommit.new(s._content,s._profile,null,null,true)
	var seed: Sm2CheckpointSession=s._copy() as Sm2CheckpointSession
	failing.world=seed.world; failing.runner=seed.runner; failing._encounter=seed._encounter
	failing.archive=seed.archive; failing.facts=seed.facts; failing.last=seed.last; failing.battle_world=seed.battle_world; failing.history=seed.history
	var failure_before: String=failing.state_hash(); command.expected_revision=int(status.revision)
	t.expect(not failing.attack(command).accepted,"capacity failure after kernel acceptance rejects publication")
	t.equal(failing.state_hash(),failure_before,"late failure leaves live state unchanged")
