extends RefCounted
const STRENGTH: String = "p1:stat.strength"
const MELEE: String = "p1:skill.melee"
const PSI: String = "p1:skill.psionics"
const DRILL: String = "p1:activity.sword_drill"
const STR_NODE: String = "p1:node.strength_1"
const MELEE_NODE: String = "p1:node.melee_1"

static func command(lab: Sm2ProgressLab, kind: String = "practice", target: String = DRILL) -> Sm2ProgressCommand:
	var view: Dictionary = lab.view()
	var value: Sm2ProgressCommand = Sm2ProgressCommand.new()
	value.kind=kind; value.target_id=target; value.world_id=view.world_id; value.expected_revision=view.revision
	value.practice_sequence=int(view.practice_sequence)+1 if kind == "practice" else 0
	return value

static func track(lab: Sm2ProgressLab, id: String) -> Dictionary:
	for entry: Dictionary in lab.view().tracks:
		if entry.id == id: return entry
	return {}

static func run(t: Sm2TestHarness) -> void:
	var loaded: Dictionary = Sm2ProgressContentLoader.load_catalog()
	t.expect(loaded.ok,"P1 catalog loads")
	if not loaded.ok: t.complete_suite("p1_progression"); return
	var catalog: Sm2ProgressCatalog = loaded.catalog
	var lab: Sm2ProgressLab = Sm2ProgressLab.new(catalog)
	t.expect(lab.start("p1-test-world").ok,"new ordinary body is linked to Soul")
	t.equal(lab.capture().soul.knowledge,["p1:knowledge.bandaging"],"Soul owns known recipe")
	t.equal([track(lab,STRENGTH).level,track(lab,MELEE).level,track(lab,PSI).earned],[10,1,0],"independent baselines")
	for sample: Array in [[0,10,0,100],[99,10,99,100],[100,11,0,150],[120,11,20,150],[249,11,149,150],[250,12,0,200],[450,13,0,250],[700,14,0,300]]:
		var details: Dictionary = catalog.track(STRENGTH).describe(sample[0])
		t.equal([details.level,details.progress,details.needed],[sample[1],sample[2],sample[3]],"independent threshold oracle "+str(sample[0]))
	var untouched: String = lab.state_hash()
	var first: Sm2ProgressCommand = command(lab)
	for i: int in 8:
		var forecast: Dictionary = lab.preview(first)
		t.expect(forecast.ok,"repeatable preview")
		forecast.awards[0].amount=999
	t.equal(lab.state_hash(),untouched,"preview detached and inert")
	t.expect(not lab.execute(command(lab,"buy_node",STR_NODE)).ok,"level requirement refuses")
	t.equal(lab.state_hash(),untouched,"refused buy inert")
	var replay: Sm2ProgressLab = Sm2ProgressLab.new(catalog)
	t.expect(replay.restore(lab.capture()).ok,"isolated replay starts")
	for i: int in 4:
		var cmd: Sm2ProgressCommand = command(lab)
		var actual: Dictionary = lab.execute(cmd)
		t.expect(actual.ok,"real exercise "+str(i))
		t.equal(replay.execute(cmd),actual,"deterministic events without RNG")
		t.equal(lab.state_hash(),replay.state_hash(),"independent replay state")
	var strength: Dictionary = track(lab,STRENGTH)
	var melee: Dictionary = track(lab,MELEE)
	t.equal([strength.earned,strength.level,strength.progress,strength.needed,strength.available],[120,11,20,150,120],"four exercises strength oracle")
	t.equal([melee.earned,melee.level,melee.progress,melee.effective],[160,2,60,7],"four exercises melee oracle")
	t.equal([track(lab,PSI).earned,track(lab,PSI).available,track(lab,PSI).level],[0,0,0],"no psionics from sword")
	t.equal(lab.view().elapsed,40,"completed activities account logical time")
	t.expect(lab.execute(command(lab,"buy_node",STR_NODE)).ok,"buy first strength node")
	strength=track(lab,STRENGTH)
	t.equal([strength.earned,strength.spent,strength.available,strength.level,strength.progress,strength.effective],[120,70,50,11,20,12],"spending preserves level and level progress")
	t.equal(track(lab,MELEE).effective,8,"strength contribution recomputed")
	t.expect(lab.execute(command(lab,"buy_node",MELEE_NODE)).ok,"buy melee with own XP")
	t.equal([track(lab,MELEE).available,track(lab,MELEE).level,track(lab,MELEE).effective],[100,2,10],"melee node oracle")
	t.equal(lab.view().revision,6,"one revision per completed operation")
	untouched=lab.state_hash()
	var denied: Array[Sm2ProgressCommand] = []
	denied.append(first)
	var duplicate: Sm2ProgressCommand = command(lab); duplicate.practice_sequence=4; denied.append(duplicate)
	var skipped: Sm2ProgressCommand = command(lab); skipped.practice_sequence=6; denied.append(skipped)
	var wrong_body: Sm2ProgressCommand = command(lab); wrong_body.body_id=77; denied.append(wrong_body)
	var wrong_incarnation: Sm2ProgressCommand = command(lab); wrong_incarnation.incarnation_id=77; denied.append(wrong_incarnation)
	var wrong_world: Sm2ProgressCommand = command(lab); wrong_world.world_id="other-world"; denied.append(wrong_world)
	denied.append(command(lab,"buy_node",STR_NODE))
	denied.append(command(lab,"buy_node","unknown"))
	denied.append(command(lab,"unknown",DRILL))
	denied.append(command(lab,"practice","unknown"))
	var invalid_buy: Sm2ProgressCommand = command(lab,"buy_node",MELEE_NODE); invalid_buy.practice_sequence=8; denied.append(invalid_buy)
	for cmd: Sm2ProgressCommand in denied:
		t.expect(not lab.execute(cmd).ok,"invalid command denied")
		t.equal(lab.state_hash(),untouched,"invalid command preserves entire snapshot")
	t.expect(not lab.execute(null).ok,"null command denied")
	var view: Dictionary = lab.view(); view.tracks[0].nodes.append("fake"); view.knowledge[0].name="changed"
	var snapshot: Dictionary = lab.capture(); snapshot.body.tracks[0].earned_total=999
	t.equal(lab.state_hash(),untouched,"read models and snapshots detached")
	var bad_snapshots: Array[Dictionary] = []
	for field: String in lab.capture().keys():
		var missing: Dictionary = lab.capture(); missing.erase(field); bad_snapshots.append(missing)
	for pair: Array in [["schema_version",true],["schema_version",2],["revision",6],["revision","06"],["revision","7"],["source_id","3"],["next_id","4"],["practice_sequence","5"],["content_fingerprint","unknown"],["ruleset","sm2.m4.areas.1"]]:
		var changed: Dictionary = lab.capture(); changed[pair[0]]=pair[1]; bad_snapshots.append(changed)
	var malformed: Dictionary = lab.capture(); malformed.soul.id="2"; bad_snapshots.append(malformed)
	malformed=lab.capture(); malformed.incarnation.body_id="99"; bad_snapshots.append(malformed)
	malformed=lab.capture(); malformed.body.template_id="cyborg"; bad_snapshots.append(malformed)
	malformed=lab.capture(); malformed.soul.knowledge=[]; bad_snapshots.append(malformed)
	malformed=lab.capture(); malformed.body.tracks[0].spent_total=0; bad_snapshots.append(malformed)
	malformed=lab.capture(); malformed.body.tracks[0].earned_total=true; bad_snapshots.append(malformed)
	malformed=lab.capture(); malformed.body.tracks[0].earned_total+=1; bad_snapshots.append(malformed)
	malformed=lab.capture(); malformed.body.tracks.reverse(); bad_snapshots.append(malformed)
	malformed=lab.capture(); malformed.activity_counts[0].count=true; bad_snapshots.append(malformed)
	malformed=lab.capture(); malformed.body.tracks[0].owned_nodes.append("missing"); bad_snapshots.append(malformed)
	for bad: Dictionary in bad_snapshots:
		t.expect(not lab.restore(bad).ok,"malformed snapshot rejected")
		t.equal(lab.state_hash(),untouched,"malformed snapshot cannot replace live state")
	var maximal: Sm2ProgressLab = Sm2ProgressLab.new(catalog); maximal.start("limit-world")
	var limit_data: Dictionary = maximal.capture()
	limit_data.activity_counts[0].count=25000; limit_data.practice_sequence="25000"; limit_data.revision="25000"
	for entry: Dictionary in limit_data.body.tracks:
		entry.earned_total=750000 if entry.track_id == STRENGTH else 1000000 if entry.track_id == MELEE else 0
	t.expect(maximal.restore(limit_data).ok,"large consistent practice history")
	var limit_hash: String = maximal.state_hash()
	t.expect(not maximal.execute(command(maximal)).ok,"award limit preflight")
	t.equal(maximal.state_hash(),limit_hash,"award limit no partial multi-track payment")
	var branches: Sm2ProgressLab = Sm2ProgressLab.new(catalog); branches.start("branches-world")
	for i: int in 9: branches.execute(command(branches))
	var branch_hash: String = branches.state_hash()
	t.equal(branches.execute(command(branches,"buy_node","p1:node.strength_2")).errors[0],"prerequisite_required","trained level still requires parent node")
	t.equal(branches.state_hash(),branch_hash,"missing parent purchase inert")
	t.expect(branches.execute(command(branches,"buy_node",STR_NODE)).ok,"parent branch purchase")
	t.expect(branches.execute(command(branches,"buy_node","p1:node.strength_2")).ok,"child branch purchase")
	t.equal([track(branches,STRENGTH).spent,track(branches,STRENGTH).level,track(branches,STRENGTH).effective],[220,12,15],"both node costs and bonuses compose without lowering level")
	_catalog_tests(t,catalog)
	_storage_tests(t,catalog,lab)
	t.complete_suite("p1_progression")

static func _catalog_tests(t: Sm2TestHarness, catalog: Sm2ProgressCatalog) -> void:
	var baseline: String = catalog.fingerprint()
	var raw: Dictionary = catalog.to_data()
	var invalid: Array[Dictionary] = []
	for pair: Array in [["step",0],["step",true],["growth",-1],["base_level",1.5]]:
		var bad: Dictionary = raw.duplicate(true); bad.tracks[0][pair[0]]=pair[1]; invalid.append(bad)
	var bad: Dictionary = raw.duplicate(true); bad.nodes[0].track_id="missing"; invalid.append(bad)
	bad=raw.duplicate(true); bad.nodes[0].requires=[bad.nodes[1].id]; invalid.append(bad)
	bad=raw.duplicate(true); bad.nodes[0].cost=true; invalid.append(bad)
	bad=raw.duplicate(true); bad.activities[0].awards[0].amount=0; invalid.append(bad)
	bad=raw.duplicate(true); bad.activities[0].operation="run_script"; invalid.append(bad)
	bad=raw.duplicate(true); bad.contributions[0].denominator=0; invalid.append(bad)
	bad=raw.duplicate(true); bad.contributions.append({"source":MELEE,"target":STRENGTH,"numerator":1,"denominator":2}); invalid.append(bad)
	bad=raw.duplicate(true); bad.tracks.append(bad.tracks[0].duplicate(true)); invalid.append(bad)
	bad=raw.duplicate(true); bad.knowledge[0].id=STRENGTH; invalid.append(bad)
	bad=raw.duplicate(true); bad.tracks[0].unknown=1; invalid.append(bad)
	for entry: Dictionary in invalid:
		t.expect(not catalog.build(entry).is_empty(),"invalid authoring refused")
		t.equal(catalog.fingerprint(),baseline,"catalog validation atomic")
	catalog.track(STRENGTH).step=1
	catalog.node(STR_NODE).cost=1
	catalog.activity(DRILL).awards[PSI]=100
	t.equal(catalog.fingerprint(),baseline,"definitions returned as copies")
	var extra: Dictionary = raw.duplicate(true)
	extra.activities[0].awards[0].amount=300
	var expanded: Sm2ProgressCatalog = Sm2ProgressCatalog.new()
	t.expect(expanded.build(extra).is_empty(),"new activity award via data")
	var lab: Sm2ProgressLab = Sm2ProgressLab.new(expanded); lab.start("multi-level")
	t.expect(lab.execute(command(lab)).ok,"large authored practice")
	t.equal(track(lab,STRENGTH).level,12,"cross two thresholds in one action")
	t.equal(track(lab,MELEE).earned,40,"second track unchanged by first award scale")
	t.expect(not Sm2ProgressLab.new(Sm2ProgressCatalog.new()).start("empty").ok,"empty catalog cannot create lab")
	var pricey: Dictionary = raw.duplicate(true); pricey.nodes[0].cost=130
	var price_catalog: Sm2ProgressCatalog = Sm2ProgressCatalog.new(); price_catalog.build(pricey)
	var price_lab: Sm2ProgressLab = Sm2ProgressLab.new(price_catalog); price_lab.start("price-world")
	for i: int in 4: price_lab.execute(command(price_lab))
	var before: String = price_lab.state_hash()
	t.equal(price_lab.execute(command(price_lab,"buy_node",STR_NODE)).errors[0],"experience_required","level alone does not buy unaffordable node")
	t.equal(price_lab.state_hash(),before,"insufficient XP inert")

static func _storage_tests(t: Sm2TestHarness, catalog: Sm2ProgressCatalog, source: Sm2ProgressLab) -> void:
	var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/p1/storage")
	t.expect(store.save_slot({"marker":41},"session").ok,"unrelated slot fixture")
	var first: Sm2ProgressSession = Sm2ProgressSession.new(catalog,store)
	t.expect(first.lab.restore(source.capture()).ok,"session binds validated lab")
	t.expect(first.save_game().ok,"real disk save")
	var second: Sm2ProgressSession = Sm2ProgressSession.new(catalog,store)
	t.expect(second.load_game().ok,"new session disk restore")
	t.equal(second.lab.state_hash(),source.state_hash(),"disk JSON exact state")
	t.equal(second.act("practice",DRILL),first.act("practice",DRILL),"next events identical after load")
	t.equal(second.lab.state_hash(),first.lab.state_hash(),"continued disk state")
	var before: String = second.lab.state_hash()
	var bad: Dictionary = source.capture(); bad.soul.knowledge=[]
	t.expect(store.save_slot(bad,Sm2ProgressSession.SLOT).ok,"valid envelope invalid domain fixture")
	t.expect(not second.load_game().ok,"invalid loaded domain refused")
	t.equal(second.lab.state_hash(),before,"disk load failure keeps live lab")
	t.equal(Sm2Canonical.hash(store.load_slot("session").payload),Sm2Canonical.hash({"marker":41}),"P1 never touches old slot")
	t.expect(first.save_game().ok,"restore valid P1 checkpoint")
	var old_world: String = first.view().world_id
	t.expect(first.new_game().ok,"new lab through application")
	t.expect(first.view().world_id != old_world,"new lab uses new world identity")
	t.equal(track(first.lab,STRENGTH).earned,0,"new lab has new practice")
	t.expect(first.load_game().ok,"new lab did not overwrite saved game")
	t.equal(first.lab.state_hash(),second.lab.state_hash(),"save remains prior world and progression")
