extends RefCounted
const FIXTURE=preload("res://tests/scenarios/test_checkpoint.gd")
const OUTING=preload("res://tests/scenarios/test_expedition.gd")

static func run(t: Sm2TestHarness) -> void:
	var s: Sm2CheckpointSession=FIXTURE.make("user://combat-io-contracts")
	t.expect(s.new_game().ok,"IO fixture starts")
	t.expect(s.act(s.command("travel",0,"ruins")).ok and s.act(s.command("start_battle")).ok,"IO fixture enters battle")
	var original: Dictionary=s.runner.capture(); var before: String=s.state_hash()
	var detached: Sm2TacticalState=s.runner.state_copy()
	t.equal(detached.to_data(s._encounter.catalog.fingerprint()),original.session.battle,"state projection equals admitted snapshot")
	detached.rng.draws+=1; detached.actor(1).spatial.fatigue+=1; detached.survival.bodies["2"].blood-=1
	detached.development.bodies[1].tracks["p1:skill.melee"].earned+=100
	t.equal(s.state_hash(),before,"state projection cannot mutate live RNG, actor, anatomy or XP")
	var empty: Sm2BattleRunner=Sm2BattleRunner.new(s._encounter.catalog,s._encounter.combat,s._profile)
	t.expect(empty.state_copy()==null,"unstarted runner has no admitted state")
	var checked: Dictionary=s._copy()._check_battle(original)
	t.expect(checked.ok,"single restored state passes encounter binding")
	if checked.ok: t.equal(checked.state.to_data(s._encounter.catalog.fingerprint()),original.session.battle,"checked encounter exact")
	for defect: String in ["rng","revision","progress","anatomy","receipt","identity"]:
		var bad: Dictionary=original.duplicate(true)
		match defect:
			"rng": bad.session.battle.rng.state="0"
			"revision": bad.session.battle.revision="-1"
			"progress": bad.session.battle.development.members[0].body.tracks[0].spent_total=-1
			"anatomy": bad.session.battle["survival"]={}
			"receipt": bad.session.result_recorded=true
			"identity": bad.session.battle.battle_id="wrong"
		t.expect(not s._copy()._check_battle(bad).ok,"full incoming decoder retained: "+defect)
		t.equal(s.state_hash(),before,"incoming refusal preserves live state: "+defect)
	var shared: Sm2ProgressCatalog=s._encounter.development._shared_progression()
	t.expect(shared==s._content.development._shared_progression(),"factory shares only built progression definitions")
	var public: Sm2ProgressCatalog=s._encounter.development.progression()
	var fingerprint: String=shared.fingerprint(); var raw: Dictionary=public.to_data(); raw.nodes[0].bonus+=1
	t.expect(public.build(raw).is_empty(),"public copy independently rebuilds")
	t.equal(shared.fingerprint(),fingerprint,"public definition edit cannot alter compiled encounter")
	var rebuilt: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	t.expect(rebuilt.build(s._encounter.development.to_data(),shared,s._encounter.combat).is_empty(),"default builder stays defensive")
	t.expect(rebuilt._shared_progression()!=shared,"default builder owns its copy")
	t.equal(rebuilt.fingerprint(),s._encounter.development.fingerprint(),"shared and defensive compilation fingerprints identical")
	var invalid: Dictionary=s._encounter.development.to_data(); invalid.mappings[0].track_id="missing"
	t.expect(not rebuilt.build(invalid,shared,s._encounter.combat,true).is_empty(),"sharing does not bypass mapping validation")
	OUTING.retreat(s,t)
	var results: Dictionary=Sm2BattleResultsView.build(s)
	t.equal(results.title,"Отряд отступил","result screen distinguishes retreat")
	t.equal(s.archive.rows().back().outcome,results.title,"short journal title agrees with full result")
	var frozen: String=Sm2Canonical.hash(results)
	t.expect(s.save_game().ok and s.load_game().ok,"completed snapshot disk roundtrip")
	t.equal(Sm2Canonical.hash(Sm2BattleResultsView.build(s)),frozen,"optimized result stays exact across loading")
	for row: Array in [["company",0,"Победа отряда"],["opposition",1,"Отряд отступил"],["opposition",0,"Отряд разбит"],["",0,"Ничья"]]:
		t.equal(Sm2BattleResultsView.title_for({"winner":row[0],"counts":{"company":{"escaped":row[1]}}}),row[2],"outcome title category")
	t.complete_suite("combat_io")
