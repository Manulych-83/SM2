extends RefCounted
const FIXTURE=preload("res://tests/fixtures/sm2_skill_scale_fixture.gd")

class CountCatalog extends Sm2ProgressCatalog:
	var reads: Array[String]=[]
	func track(id: String) -> Sm2ProgressTrackDefinition:
		reads.append(id); return super.track(id)

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=FIXTURE.content()
	t.expect(c.ok,"wide packages compile into production rules: "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("skill_scale"); return
	var p: Sm2ProgressCatalog=c.development._shared_progression()
	var skills: int=0
	for row: Dictionary in p.track_summaries():
		if row.kind=="skill": skills+=1
	t.equal(skills,5000,"5000 actual independent skills plus attributes")
	t.expect(p.activity_ids().size()>5000 and p.contributions().size()>1000,"practice and contribution limits expanded with catalog")
	var base: Dictionary=Sm2SurvivalContentLoader.load_scenario(true,true).development.progression().to_data()
	var identity: Dictionary=Sm2ProgressPackageLoader.load_extensions(base)
	t.expect(identity.ok,"default extension manifest loads")
	t.equal(identity.raw,base,"production default package preserves exact raw data")
	t.equal(identity.catalog.fingerprint(),Sm2Canonical.hash(base),"default fingerprint unchanged")
	var bad: Dictionary=p.to_data(); bad.version=Sm2ProgressCatalog.CROSS_VERSION
	t.expect(not Sm2ProgressCatalog.new().build(bad).is_empty(),"legacy group limits unchanged")
	bad=p.to_data(); bad.activities[0].awards={"missing":1}
	t.expect(not Sm2ProgressCatalog.new().build(bad).is_empty(),"missing XP reference fails")
	bad=p.to_data(); bad.contributions.append({"source":FIXTURE.TRACK,"target":"p1:stat.strength","numerator":1,"denominator":1})
	t.expect(not Sm2ProgressCatalog.new().build(bad).is_empty(),"cross-track cycle fails")
	_sparse(t,p)
	var body: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(2,p)
	var counting: CountCatalog=CountCatalog.new(); t.expect(counting.build(p.to_data()).is_empty(),"instrumented catalog")
	var one: Dictionary=Sm2ProgressRules.track(body,counting,FIXTURE.TRACK)
	t.equal(counting.reads,[FIXTURE.TRACK,"p1:stat.strength"],"single skill reads only itself and immediate contributor")
	var full: Array[Dictionary]=Sm2ProgressRules.tracks(body,p)
	for row: Dictionary in full:
		if row.id==FIXTURE.TRACK: t.equal(one,row,"addressed calculation equals full projection")
	t.equal(p.activities_for_track(FIXTURE.TRACK),[FIXTURE.ACTIVITY],"indexed XP sources")
	_journey(t,c)
	t.complete_suite("skill_scale")

static func _sparse(t: Sm2TestHarness,p: Sm2ProgressCatalog) -> void:
	var body: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(2,p)
	t.equal(body.to_data().tracks.size(),0,"new body omits all unpracticed tracks")
	t.equal(body.to_data().track_layout,Sm2ProgressBodyState.SPARSE_LAYOUT,"explicit sparse layout")
	var decoded: Dictionary=Sm2ProgressRules.decode_body(body.to_data(),p)
	t.expect(decoded.ok and decoded.body.tracks.size()==p.track_ids().size(),"omitted tracks restored as zero practice")
	Sm2ProgressRules.award(body,{FIXTURE.TRACK:10,"wide:skill.04998":10})
	t.equal(Sm2ProgressRules.purchase_error(body,p,FIXTURE.NODE),"","cross-skill unlock allowed")
	Sm2ProgressRules.purchase(body,p.node(FIXTURE.NODE))
	t.equal(body.tracks[FIXTURE.TRACK].spent,5,"own payment")
	t.equal(body.tracks["wide:skill.04998"].spent,5,"second skill payment")
	decoded=Sm2ProgressRules.decode_body(body.to_data(),p)
	t.expect(decoded.ok,"sparse purchased cross-node decodes")
	if decoded.ok: t.equal(decoded.body.to_data(),body.to_data(),"sparse roundtrip exact")
	t.equal(body.copy().to_data(),body.to_data(),"copy preserves layout")
	for defect: String in ["layout","layout_type","unknown","duplicate","order","zero","spent","missing_paid","xp_bool"]:
		var raw: Dictionary=body.to_data()
		match defect:
			"layout": raw.track_layout="unknown"
			"layout_type": raw.track_layout=[]
			"unknown": raw.tracks[0].track_id="unknown"
			"duplicate": raw.tracks.append(raw.tracks[0].duplicate(true))
			"order": raw.tracks.reverse()
			"zero": raw.tracks[0].earned_total=0; raw.tracks[0].spent_total=0; raw.tracks[0].owned_nodes=[]
			"spent": raw.tracks[0].spent_total=0
			"missing_paid": raw.tracks.remove_at(0)
			"xp_bool": raw.tracks[0].earned_total=true
		t.expect(not Sm2ProgressRules.decode_body(raw,p).ok,"sparse invalid: "+defect)
	body.sparse=false; var dense: Dictionary=body.to_data()
	decoded=Sm2ProgressRules.decode_body(dense,p)
	t.expect(decoded.ok,"explicit dense layout still accepted for wide catalog")
	if decoded.ok: t.equal(decoded.body.to_data(),dense,"dense representation preserved")
	var ordinary: Sm2ProgressCatalog=Sm2SurvivalContentLoader.load_scenario(true,true).development._shared_progression()
	var forbidden: Dictionary=Sm2ProgressRules.empty_body(2,ordinary).to_data(); forbidden.track_layout=Sm2ProgressBodyState.SPARSE_LAYOUT; forbidden.tracks=[]
	t.expect(not Sm2ProgressRules.decode_body(forbidden,ordinary).ok,"ordinary catalog cannot select sparse policy from file")
	body.sparse=true
	for id: String in body.tracks: body.tracks[id].earned=maxi(body.tracks[id].earned,10)
	decoded=Sm2ProgressRules.decode_body(body.to_data(),p)
	t.expect(decoded.ok,"all 5000 skills have practice and restore")
	if decoded.ok: t.equal(Sm2Canonical.hash(decoded.body.to_data()),Sm2Canonical.hash(body.to_data()),"fully practiced body exact")

static func _journey(t: Sm2TestHarness,c: Dictionary) -> void:
	var s: Sm2CheckpointSession=Sm2CheckpointSession.new(c,Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://skill-scale"))
	t.expect(s.new_game().ok,"wide new campaign fits structural budget")
	if s.world.hero_id()==0: return
	# Synthetic broad practice stresses a developed body, without pretending to have played 5000 exercises.
	for track: Sm2ProgressTrackState in s.world.bodies[2].progress.tracks.values(): track.earned=100
	t.expect(s.act(s.command("travel",0,"ruins")).ok and s.act(s.command("start_battle")).ok,"first encounter before non-psionic training")
	preload("res://tests/scenarios/test_expedition.gd").retreat(s,t)
	preload("res://tests/scenarios/test_survival_tissues.gd").bandage_all(t,s)
	t.expect(s.act(s.command("travel",0,"camp")).ok,"return to camp for training")
	var initial: String=s.state_hash()
	var begin: int=Time.get_ticks_usec()
	var view: Dictionary=Sm2HeroDevelopmentView.build(s,FIXTURE.TRACK,{"compact_tracks":true})
	t.equal(view.tracks.size(),s.world._progress.track_ids().size(),"search metadata covers entire catalog")
	t.expect(not view.tracks[0].has("earned"),"search list does not calculate full progression")
	t.equal(view.selected.id,FIXTURE.TRACK,"distant selection")
	t.equal(view.nodes.size(),1,"selected skill nodes only")
	var sources: Dictionary=Sm2DevelopmentSources.build(s,FIXTURE.TRACK)
	t.equal(sources.practice.size(),1,"selected XP source only")
	t.equal(s.state_hash(),initial,"read queries do not change world")
	print("SKILL_SCALE skills=5000 view_ms=",float(Time.get_ticks_usec()-begin)/1000.0)
	for activity: String in [FIXTURE.ACTIVITY,"wide:practice.04998"]:
		var practiced: Dictionary=s.act(s.command("practice",2,activity))
		t.expect(practiced.ok,"actual practice command: "+activity+" "+str(practiced.get("errors",[])))
	t.expect(s.act(s.command("buy_node",2,FIXTURE.NODE)).ok,"actual cross-skill purchase")
	var before: String=s.state_hash()
	t.expect(s.save_game().ok,"wide camp save")
	t.expect(s.load_game().ok,"wide camp load")
	t.equal(s.state_hash(),before,"wide saved state exact")
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"travel")
	t.expect(s.act(s.command("start_battle")).ok,"wide battle starts")
	for step: int in 180:
		if not s.world.busy(): break
		var status: Dictionary=s.runner.status()
		var actor: Sm2TacticalActor=s.runner.state_copy().actor(int(status.active_actor_id))
		if actor.spatial.controller=="player" and actor.morale!="fleeing":
			var decision: Dictionary=s.runner._session.ai_decision(s._profile)
			t.expect(decision.ok,"player oracle")
			if not decision.ok: break
			t.expect(s.attack(decision.command).accepted,"wide battle action")
		else: t.expect(s.step().ok,"wide AI action")
		if step==6:
			before=s.state_hash(); t.expect(s.save_game().ok,"active sparse save"); t.expect(s.load_game().ok,"active sparse load"); t.equal(s.state_hash(),before,"active exact")
	t.expect(not s.world.busy(),"wide battle completes")
	t.expect(not Sm2BattleResultsView.build(s).is_empty(),"wide results available")
	before=s.state_hash(); t.expect(s.save_game().ok,"finished save"); t.expect(s.load_game().ok,"finished load"); t.equal(s.state_hash(),before,"finished exact")
