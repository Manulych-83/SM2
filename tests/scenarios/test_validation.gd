extends RefCounted
const FIXTURE=preload("res://tests/fixtures/sm2_development_scale_fixture.gd")
const CHECKPOINT=preload("res://tests/scenarios/test_checkpoint.gd")

class CapacityFailure extends Sm2CheckpointSession:
	var blocked: bool=false
	func _check_capacity(candidate: Sm2CheckpointSession) -> Dictionary:
		return _error("injected_capacity_failure") if blocked else super._check_capacity(candidate)

static func run(t: Sm2TestHarness) -> void:
	var c: Sm2ProgressCatalog=FIXTURE.content(100).development.progression()
	var body: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(2,c)
	var ids: Array=c.nodes_for_track(FIXTURE.TRACK)
	Sm2ProgressRules.award(body,{FIXTURE.TRACK:ids.size()+20})
	for i: int in range(ids.size()-1,-1,-1): Sm2ProgressRules.purchase(body,c.node(ids[i]))
	var raw: Dictionary=body.to_data(); var index: int=c.track_ids().find(FIXTURE.TRACK)
	var cache: Sm2ProgressDecodeCache=Sm2ProgressDecodeCache.new()
	t.expect(Sm2ProgressRules.decode_body(raw,c,cache).ok,"full checked paid graph seeds certificate")
	var grown: Dictionary=raw.duplicate(true); grown.tracks[index].earned_total+=10
	t.expect(cache.find_growth(grown,c)==null,"default/file cache cannot use incremental proof")
	var live: Sm2ProgressDecodeCache=cache.growth_copy()
	var proof: Sm2ProgressBodyState=live.find_growth(grown,c)
	t.expect(proof!=null,"live XP-only growth can reuse checked graph")
	t.equal(proof.to_data(),Sm2ProgressRules.decode_body(grown,c).body.to_data(),"incremental proof equals full decoder")
	proof.tracks[FIXTURE.TRACK].spent=0
	t.equal(live.find_growth(grown,c).to_data(),grown,"proof returns detached mutable state")
	t.equal(cache.find(raw,c).to_data(),raw,"temporary proof cannot mutate source certificate")
	for defect: String in ["spent","nodes","packed","duplicate","track","body","extra","bool","fraction","negative","overflow","decrease","body_type","template_type","track_type","spent_type"]:
		var bad: Dictionary=grown.duplicate(true)
		match defect:
			"spent": bad.tracks[index].spent_total-=1
			"nodes": bad.tracks[index].owned_nodes.pop_back()
			"packed": bad.tracks[index].owned_nodes=PackedStringArray(bad.tracks[index].owned_nodes)
			"duplicate": bad.tracks[index].owned_nodes[0]=bad.tracks[index].owned_nodes[1]
			"track": bad.tracks[index].track_id="missing"
			"body": bad.id="99"
			"body_type": bad.id=[]
			"template_type": bad.template_id=[]
			"track_type": bad.tracks[index].track_id=[]
			"spent_type": bad.tracks[index].spent_total=[]
			"extra": bad.extra=true
			"bool": bad.tracks[index].earned_total=true
			"fraction": bad.tracks[index].earned_total=105.5
			"negative": bad.tracks[index].earned_total=-1
			"overflow": bad.tracks[index].earned_total=Sm2ProgressCatalog.XP_LIMIT+1
			"decrease": bad.tracks[index].earned_total=int(raw.tracks[index].earned_total)-1
		t.expect(live.find_growth(bad,c)==null,"changed invariant cannot use XP-only proof: "+defect)
		var fast: Dictionary=Sm2ProgressRules.decode_body(bad,c,live)
		var full: Dictionary=Sm2ProgressRules.decode_body(bad,c)
		t.equal(fast.ok,full.ok,"fallback preserves full-decoder acceptance: "+defect)
		if fast.ok: t.equal(fast.body.to_data(),full.body.to_data(),"fallback exact: "+defect)
	# Separate mutations may validly decode (e.g. lower XP above paid amount).
	# They may not alter another cached body or enable growth on the strict cache.
	cache.adopt_certificates(live)
	t.expect(not cache.growth_enabled,"adoption never enables growth on file decoder")
	t.expect(cache._entries.size()<=Sm2ProgressDecodeCache.CAPACITY,"growth certificates remain bounded")
	var other: Sm2ProgressCatalog=Sm2ProgressCatalog.new(); var definitions: Dictionary=c.to_data(); definitions.nodes[0].bonus+=1
	t.expect(other.build(definitions).is_empty(),"different catalog fixture")
	t.expect(live.find_growth(grown,other)==null,"growth proof is catalog-specific")
	for amount: int in [0,1,10,1000,1000000]:
		var value: Dictionary=raw.duplicate(true)
		for row: Dictionary in value.tracks: row.earned_total+=amount
		var a: Dictionary=Sm2ProgressRules.decode_body(value,c,live); var b: Dictionary=Sm2ProgressRules.decode_body(value,c)
		t.equal(a.ok,b.ok,"all-track growth agrees with full decode")
		if a.ok: t.equal(a.body.to_data(),b.body.to_data(),"all-track growth exact")
	restore_contracts(t)
	t.complete_suite("validation")

static func restore_contracts(t: Sm2TestHarness) -> void:
	var s: Sm2CheckpointSession=CHECKPOINT.make("user://validation-source")
	t.expect(s.new_game().ok and s.act(s.command("travel",0,"ruins")).ok and s.act(s.command("start_battle")).ok,"restore fixture starts active battle")
	var raw: Dictionary=s.capture(); var before: String=s.state_hash()
	for defect: String in ["world_xp","active_xp","archive","facts"]:
		var bad: Dictionary=raw.duplicate(true)
		match defect:
			"world_xp": bad.world.bodies[0].progress.tracks[0].earned_total=-1
			"active_xp": bad.active.session.battle.development.members[0].body.tracks[0].earned_total+=1
			"archive": bad.archive.count+=1
			"facts": bad.facts["unknown"]=true
		t.expect(not s.restore(bad).ok,"single validation restore rejects "+defect)
		t.equal(s.state_hash(),before,"failed restore atomic: "+defect)
	t.expect(s.restore(raw).ok,"valid restored candidate accepted")
	t.equal(s.state_hash(),before,"full restore exact")
	t.expect(not s.runner._session._battle._progress_decode_cache.growth_enabled,"restored battle has strict default cache")
	var fail: CapacityFailure=CapacityFailure.new(s._content,s._profile,null,null,true)
	t.expect(fail.new_game().ok,"capacity refusal target initialized")
	fail.blocked=true; var prior: String=fail.state_hash()
	t.expect(not fail.restore(raw).ok,"capacity checked after full decode before adoption")
	t.equal(fail.state_hash(),prior,"late restore refusal preserves previous campaign")
