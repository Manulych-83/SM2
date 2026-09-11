extends RefCounted
const PATH: String = "res://content/p4/attributes.tres"
const POWER: String = "p4a:stat.power"
const EXERCISE: String = "p4a:activity.power"
const ASSISTED: String = "p4a:activity.power_assisted"
const BARE: String = "p4a:activity.power_bare"
const NODE: String = "p4a:node.power"

static func command(lab: Sm2ProgressLab, kind: String, target: String) -> Sm2ProgressCommand:
	var state: Dictionary = lab.view()
	var result: Sm2ProgressCommand = Sm2ProgressCommand.new()
	result.world_id=state.world_id; result.body_id=state.body_id; result.incarnation_id=state.incarnation_id
	result.expected_revision=state.revision; result.practice_sequence=int(state.practice_sequence)+1 if kind == "practice" else 0
	result.kind=kind; result.target_id=target
	return result

static func track(lab: Sm2ProgressLab, id: String) -> Dictionary:
	for row: Dictionary in lab.view().tracks:
		if row.id == id: return row
	return {}

static func run(t: Sm2TestHarness) -> void:
	var loaded: Dictionary = Sm2ProgressContentLoader.load_catalog(PATH)
	t.expect(loaded.ok,"attribute catalogue loads")
	if not loaded.ok: return
	var catalog: Sm2ProgressCatalog = loaded.catalog
	var lab: Sm2ProgressLab = Sm2ProgressLab.new(catalog)
	t.expect(lab.start("attributes-test").ok,"attributes start")
	t.equal(lab.view().tracks.size(),8,"eight independent attributes")
	t.equal(lab.capture().format,"sm2.attributes_lab","separate format")
	var initial: String = lab.state_hash()
	var blocked: Dictionary = lab.execute(command(lab,"practice",BARE))
	t.equal(blocked.errors[0],"capability_required","bare load initially unavailable")
	t.equal(lab.state_hash(),initial,"failed trial entirely atomic")
	var assisted: Sm2ProgressCommand = command(lab,"practice",ASSISTED)
	var prediction: Dictionary = lab.preview(assisted)
	t.expect(prediction.ok,"stand enables exercise")
	t.equal(prediction.capability.effective,15,"stand value 10 plus 5")
	t.equal(track(lab,POWER).effective,10,"stand not global characteristic bonus")
	t.equal(lab.state_hash(),initial,"preview cannot award practice")
	t.expect(not lab.execute(command(lab,"buy_node",NODE)).ok,"stand cannot bypass learned level")
	t.expect(lab.execute(assisted).ok,"assisted exercise executes")
	t.equal(track(lab,POWER).earned,10,"only performed exercise awards ten")
	t.equal(track(lab,POWER).level,10,"assistance does not train instant levels")
	t.expect(not lab.preview(command(lab,"buy_node",NODE)).ok,"node remains unavailable")
	var after_assisted: String = lab.state_hash()
	t.expect(not lab.execute(assisted).ok,"duplicate source rejected")
	t.equal(lab.state_hash(),after_assisted,"duplicate does not change state")
	# Every ordinary exercise changes exactly its own direction, including psi and interface.
	for id: String in catalog.track_ids():
		t.expect(lab.start("single-"+id).ok,"fresh independent exercise")
		var exercise_id: String = "p4a:activity."+id.get_slice(".",1)
		for i: int in 4: t.expect(lab.execute(command(lab,"practice",exercise_id)).ok,"practice threshold")
		for other: String in catalog.track_ids():
			t.equal(track(lab,other).earned,100 if other == id else 0,"only corresponding practice: "+other)
		t.equal(track(lab,id).level,11,"four practices level 11")
		t.expect(lab.execute(command(lab,"buy_node","p4a:node."+id.get_slice(".",1))).ok,"own node purchased")
		var row: Dictionary = track(lab,id)
		t.equal([row.level,row.earned,row.spent,row.available,row.progress,row.needed,row.effective],[11,100,70,30,0,150,12],"purchase oracle")
		var purchased: String = lab.state_hash()
		t.expect(not lab.execute(command(lab,"buy_node","p4a:node."+id.get_slice(".",1))).ok,"node cannot be bought twice")
		t.equal(lab.state_hash(),purchased,"second purchase atomic")
	# Natural training permits the same trial without assistance.
	t.expect(lab.start("trained-power").ok,"start natural training")
	for i: int in 4: t.expect(lab.execute(command(lab,"practice",EXERCISE)).ok,"train power")
	t.expect(not lab.preview(command(lab,"practice",BARE)).ok,"level 11 insufficient before own node")
	t.expect(lab.execute(command(lab,"buy_node",NODE)).ok,"own power node")
	t.expect(lab.preview(command(lab,"practice",BARE)).ok,"own preparation enables bare trial")
	t.expect(lab.execute(command(lab,"practice",BARE)).ok,"bare trial executes")
	var saved: Dictionary = lab.capture()
	var restored: Sm2ProgressLab = Sm2ProgressLab.new(catalog)
	t.expect(restored.restore(saved).ok,"restore trained body")
	t.equal(restored.state_hash(),lab.state_hash(),"restore exact before next activity")
	var next: Sm2ProgressCommand = command(lab,"practice",EXERCISE)
	t.equal(lab.execute(next),restored.execute(next),"next command and events identical")
	t.equal(restored.state_hash(),lab.state_hash(),"next state identical")
	for key: String in ["format","ruleset","content_fingerprint"]:
		var bad: Dictionary = saved.duplicate(true); bad[key]="wrong"
		var before: String = restored.state_hash()
		t.expect(not restored.restore(bad).ok,"reject altered "+key)
		t.equal(restored.state_hash(),before,"failed restore atomic "+key)
	var corrupt: Dictionary = saved.duplicate(true); corrupt.body.tracks[0].earned_total+=1
	t.expect(not restored.restore(corrupt).ok,"reject unsupported XP")
	corrupt=saved.duplicate(true); corrupt.activity_counts[0].count+=1
	t.expect(not restored.restore(corrupt).ok,"reject false activity count")
	corrupt=saved.duplicate(true); corrupt.body.tracks.append(corrupt.body.tracks[0].duplicate(true))
	t.expect(not restored.restore(corrupt).ok,"reject duplicate track")
	var wrong_command: Sm2ProgressCommand = command(lab,"practice",EXERCISE); wrong_command.world_id="other"
	t.expect(not lab.execute(wrong_command).ok,"wrong world rejected")
	wrong_command=command(lab,"practice",EXERCISE); wrong_command.practice_sequence+=1
	t.expect(not lab.execute(wrong_command).ok,"out of order practice rejected")
	# Old and new profiles remain mutually incompatible; original P1 still executes.
	var old: Sm2ProgressCatalog = Sm2ProgressContentLoader.load_catalog().catalog
	var old_lab: Sm2ProgressLab = Sm2ProgressLab.new(old)
	t.expect(old_lab.start("old-p1").ok,"old laboratory starts")
	t.expect(not old_lab.restore(saved).ok,"old mode rejects new save")
	t.expect(not restored.restore(old_lab.capture()).ok,"new mode rejects old save")
	t.expect(old_lab.execute(command(old_lab,"practice","p1:activity.sword_drill")).ok,"old sword exercise unchanged")
	var raw: Dictionary = catalog.to_data()
	for change: String in ["reference","negative","operation","source","extra"]:
		var bad_raw: Dictionary = raw.duplicate(true)
		var activity: Dictionary = bad_raw.activities[-1]
		match change:
			"reference": activity.capability.track_id="missing"
			"negative": activity.capability.bonus=-1
			"operation": activity.operation="sword_exercise"
			"source": activity.capability.source=""
			"extra": activity.capability.cheat=true
		t.expect(not catalog.build(bad_raw).is_empty(),"invalid definition rejected: "+change)
		t.equal(catalog.to_data(),raw,"catalog failure atomic")
	var old_raw: Dictionary = old.to_data(); old_raw.activities[0].operation="attribute_exercise"
	t.expect(not old.build(old_raw).is_empty(),"old profile remains strict")
	# Disk saves use independent slots; invalid loads preserve the live lab.
	var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/p4_attributes")
	var session: Sm2ProgressSession = Sm2ProgressSession.new(catalog,store,"p4_attribute_lab")
	t.expect(session.new_game().ok,"session new world")
	t.expect(session.act("practice",ASSISTED).ok,"session practice")
	t.expect(session.save_game().ok,"session save")
	var disk_hash: String = session.lab.state_hash()
	t.expect(session.new_game().ok,"session replacement")
	t.expect(session.load_game().ok,"session load")
	t.equal(session.lab.state_hash(),disk_hash,"disk restore exact")
	t.expect(not store.has_slot(Sm2ProgressSession.SLOT),"old slot untouched")
	var invalid_save: Dictionary = session.lab.capture(); invalid_save.revision="999"
	t.expect(store.save_slot(invalid_save,"p4_attribute_lab").ok,"store accepts checksum-valid invalid domain fixture")
	t.expect(not session.load_game().ok,"invalid domain load rejected")
	t.equal(session.lab.state_hash(),disk_hash,"bad disk load preserves current world")
	t.expect(session.save_game().ok,"valid save replaces invalid fixture")
	t.completed_suites["p4_attributes"]=true
