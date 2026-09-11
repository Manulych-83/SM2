extends RefCounted
const SEARCH_TEST=preload("res://tests/scenarios/test_p4_search.gd")
const PROSTHESIS=preload("res://tests/scenarios/test_p4_prosthesis.gd")
const JOURNEY=preload("res://tests/scenarios/test_p4_journey.gd")
const TRACK: String="p4s:skill.search"
const NODE: String="p4s:node.attentive"
const SITE: String="hidden_niche"

static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2DiscoveryContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)

static func fixture_content() -> Dictionary:
	var c: Dictionary=SEARCH_TEST.fixture_content(); var source: Dictionary=Sm2DiscoveryContentLoader.load_scenario()
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	var errors: PackedStringArray=development.build(c.development.to_data(),source.development.progression(),c.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	c.development=development; c.exploration=source.exploration
	c.journey_fingerprint=Sm2Canonical.hash([c.journey_fingerprint,development.fingerprint(),c.exploration.to_data()]); return c

static func prepared(t: Sm2TestHarness,store: Sm2SaveStore=null) -> Sm2JourneySession:
	var s: Sm2JourneySession=Sm2JourneySession.new(fixture_content(),Sm2AiContentLoader.load_profile().profile,store)
	t.expect(s.new_game().ok,"discovery fixture starts")
	t.expect(s.act(s.command("explore",0,"first_aid")).ok,"first own search")
	t.expect(s.act(s.command("start_battle")).ok,"real first encounter")
	PROSTHESIS.finish_retreat(s,t)
	t.expect(s.world.hero_id()==2,"hero survives first encounter")
	t.expect(s.act(s.command("explore",0,"workshop")).ok,"second own search")
	return s

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2DiscoveryContentLoader.load_scenario()
	t.expect(c.ok,"discovery content validates "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("p4_discovery"); return
	_catalog(t,c)
	var s: Sm2JourneySession=prepared(t,Sm2SaveStore.new("user://discovery-tests"))
	t.equal(s.format_id(),Sm2JourneySession.DISCOVERY_FORMAT,"explicit discovery session")
	t.equal(s.slot_name(),Sm2JourneySession.DISCOVERY_SLOT,"separate discovery slot")
	var before: String=s.state_hash()
	t.expect(not s.act(s.command("explore",0,SITE)).ok,"level alone cannot access hidden site")
	t.expect(not s.act(s.command("buy_node",4,NODE)).ok,"companion cannot buy hero node")
	t.equal(s.state_hash(),before,"failed access and companion purchase atomic")
	var companion: Dictionary=s.world.bodies[4].to_data()
	var gear: Array=s.journey().items.duplicate(true)
	var stale: Sm2WorldCommand=s.command("buy_node",2,NODE)
	t.expect(s.act(s.command("buy_node",2,NODE)).ok,"own search experience buys node")
	var track: Sm2ProgressTrackState=s.world.bodies[2].progress.tracks[TRACK]
	t.equal(track.earned,100,"buy preserves earned total")
	t.equal(track.spent,100,"buy spends only search XP")
	t.equal(track.earned-track.spent,0,"search remainder exhausted")
	var rows: Array[Dictionary]=Sm2ProgressRules.tracks(s.world.bodies[2].progress,c.development.progression())
	for row: Dictionary in rows:
		if row.id==TRACK:
			t.equal(row.level,2,"buy preserves own level")
			t.equal(row.progress,0,"buy preserves advancement")
			t.equal(row.effective,2,"unlock node adds no artificial numeric bonus")
	t.equal(s.world.bodies[4].to_data(),companion,"purchase leaves companion intact")
	t.equal(s.journey().items,gear,"purchase leaves equipment intact")
	before=s.state_hash()
	t.expect(not s.act(stale).ok and not s.act(s.command("buy_node",2,NODE)).ok,"stale and repeat purchases refused")
	t.equal(s.state_hash(),before,"repeat purchase cannot charge twice")
	t.equal(s.world.check(s.command("explore",0,SITE)),"","node opens real action")
	t.expect(s.save_game().ok,"node ownership saved")
	var loaded: Sm2JourneySession=Sm2JourneySession.new(fixture_content(),s._profile,s._store)
	t.expect(loaded.load_game().ok,"node ownership loaded")
	t.equal(loaded.state_hash(),s.state_hash(),"purchase replay exact")
	var uncollected: Dictionary=s.capture()
	var stocks: Dictionary=s.journey().care.supplies.duplicate()
	t.expect(s.act(s.command("explore",0,SITE)).ok,"unlocked site awards real resources")
	t.equal(s.journey().care.supplies.medicine,stocks.medicine+2,"hidden medicine received")
	t.equal(s.journey().care.supplies.parts,stocks.parts+2,"hidden parts received")
	t.equal(s.world.bodies[2].progress.tracks[TRACK].earned,150,"hidden search gives own practice")
	t.equal(s.world.bodies[2].progress.tracks[TRACK].spent,100,"hidden search does not refund node")
	before=s.state_hash()
	t.expect(not s.act(s.command("explore",0,SITE)).ok,"hidden site collected only once")
	t.equal(s.state_hash(),before,"duplicate cannot repeat hidden reward")
	for defect: String in ["remove_node","remove_purchase","spent"]:
		var bad: Dictionary=s.capture()
		match defect:
			"remove_purchase":
				for i: int in range(bad.history.size()-1,-1,-1):
					if bad.history[i].kind=="camp" and bad.history[i].command.kind=="buy_node": bad.history.remove_at(i)
			_:
				for body: Dictionary in bad.world.bodies:
					if body.id!="2": continue
					for value: Dictionary in body.progress.tracks:
						if value.track_id!=TRACK: continue
						if defect=="remove_node": value.owned_nodes=[]; value.spent_total=0
						else: value.spent_total=0
		t.expect(not s.restore(bad).ok,"forged unlock history refused "+defect)
		t.equal(s.state_hash(),before,"bad unlock save not published "+defect)
	t.expect(s.act(s.command("start_battle")).ok,"owned unlock enters next battle")
	before=s.state_hash()
	t.expect(not s.act(s.command("buy_node",2,NODE)).ok and not s.act(s.command("explore",0,SITE)).ok,"camp operations blocked during battle")
	t.equal(s.state_hash(),before,"busy command leaves whole battle unchanged")
	t.expect(s.save_game().ok and loaded.load_game().ok,"active save contains zero-bonus owned node")
	t.equal(s.state_hash(),loaded.state_hash(),"active save exact")
	t.equal(JOURNEY.advance(s),JOURNEY.advance(loaded),"same next action with unlock node")
	t.equal(s.state_hash(),loaded.state_hash(),"same subsequent battle state")
	_lives(t,uncollected)
	t.complete_suite("p4_discovery")

static func _lives(t: Sm2TestHarness,uncollected: Dictionary) -> void:
	var c: Dictionary=fixture_content(); var profile: Sm2AiProfile=Sm2AiContentLoader.load_profile().profile
	for collect_before_death: bool in [false,true]:
		var s: Sm2JourneySession=Sm2JourneySession.new(c,profile,Sm2SaveStore.new("user://discovery-lives-"+str(collect_before_death)))
		t.expect(s.restore(uncollected).ok,"life branch starts with learned node")
		if collect_before_death: t.expect(s.act(s.command("explore",0,SITE)).ok,"previous incarnation collects hidden site")
		var old: Dictionary=s.world.bodies[2].progress.to_data(); var companion: Dictionary=s.world.bodies[4].to_data()
		var knowledge: Array=s.world.soul.knowledge.duplicate()
		t.expect(s.act(s.command("end_life")).ok and s.act(s.command("incarnate",8)).ok,"clean new incarnation")
		t.expect(s.world.bodies[8].progress.tracks[TRACK].nodes.is_empty(),"new body does not inherit learned node")
		t.equal(s.world.bodies[8].progress.tracks[TRACK].earned,0,"new body has no search XP")
		t.equal(s.world.bodies[2].progress.to_data(),old,"former node remains in old body record")
		t.equal(s.world.bodies[4].to_data(),companion,"companion is preserved across lives")
		t.equal(s.world.soul.knowledge,knowledge,"soul knowledge remains separate")
		t.expect(not s.act(s.command("explore",0,SITE)).ok,"new body cannot use previous body's unlock")
		if not collect_before_death:
			t.expect(s.act(s.command("explore",0,"abandoned_camp")).ok,"new body has a remaining ordinary practice source")
			t.expect(not s.act(s.command("buy_node",8,NODE)).ok,"50 own XP insufficient for node")
			t.expect(s.act(s.command("start_battle")).ok,"new body participates in second encounter")
			PROSTHESIS.finish_retreat(s,t)
			t.expect(s.world.hero_id()==8,"new hero survives")
			t.expect(s.act(s.command("explore",0,"supply_cache")).ok,"second fresh source trains new body")
			t.expect(s.act(s.command("buy_node",8,NODE)).ok,"new body relearns with own 100 XP")
			t.expect(s.act(s.command("explore",0,SITE)).ok,"relearned node permits uncollected site")
			t.equal(s.world.bodies[8].progress.tracks[TRACK].earned,150,"new own earned total")
			t.equal(s.world.bodies[8].progress.tracks[TRACK].spent,100,"new own spent total")
		t.expect(SITE in s.journey().exploration.collected,"hidden collection stays in world")
		t.expect(s.save_game().ok,"life branch saves")
		var loaded: Sm2JourneySession=Sm2JourneySession.new(c,profile,s._store)
		t.expect(loaded.load_game().ok,"life branch loads")
		t.equal(s.state_hash(),loaded.state_hash(),"history does not require old node on current body")

static func _catalog(t: Sm2TestHarness,c: Dictionary) -> void:
	var progress: Sm2ProgressCatalog=c.development.progression()
	t.equal(progress.node(NODE).bonus,0,"unlock has zero numeric bonus")
	var old_raw: Dictionary=progress.to_data(); old_raw.version=Sm2ProgressCatalog.PARTY_VERSION
	t.expect(not Sm2ProgressCatalog.new().build(old_raw).is_empty(),"old catalog still rejects zero-bonus nodes")
	for defect: String in ["negative","fraction","unknown_track"]:
		var raw: Dictionary=progress.to_data()
		for node: Dictionary in raw.nodes:
			if node.id!=NODE: continue
			if defect=="negative": node.bonus=-1
			elif defect=="fraction": node.bonus=0.5
			else: node.track_id="unknown"
		t.expect(not Sm2ProgressCatalog.new().build(raw).is_empty(),"invalid unlock definition "+defect)
	for defect: String in ["missing","unknown","duplicate","type","old_version"]:
		var raw: Dictionary=c.exploration.to_data()
		match defect:
			"missing": raw.sites[0].erase("required_nodes")
			"unknown": raw.sites[0].required_nodes=["unknown"]
			"duplicate": raw.sites[0].required_nodes=[NODE,NODE]
			"type": raw.sites[0].required_nodes=NODE
			"old_version": raw.version="sm2.exploration.content.2"
		t.expect(not Sm2ExplorationCatalog.new().build(raw,c.care,3,progress).is_empty(),"invalid access requirement "+defect)
	var s: Sm2JourneySession=make(); t.expect(s.new_game().ok,"ordinary discovery profile starts")
	var old: Sm2JourneySession=SEARCH_TEST.make(); t.expect(old.new_game().ok,"old search profile starts")
	t.expect(not old.restore(s.capture()).ok and not s.restore(old.capture()).ok,"old and new profiles separated")
	t.expect(old._content.development.progression().node(NODE)==null,"old profile has no new node")
	var detached: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(2,progress)
	detached.tracks["p4a:stat.perception"].earned=10000
	t.equal(Sm2ProgressRules.purchase_error(detached,progress,NODE),"level_required","another track cannot pay or substitute own practice")
	var boosted_raw: Dictionary=progress.to_data()
	boosted_raw.contributions.append({"source":"p4a:stat.perception","target":TRACK,"numerator":1,"denominator":1})
	var boosted: Sm2ProgressCatalog=Sm2ProgressCatalog.new()
	t.expect(boosted.build(boosted_raw).is_empty(),"assistance fixture validates")
	t.equal(Sm2ProgressRules.purchase_error(detached,boosted,NODE),"level_required","effective assistance cannot replace own level")
	var changed: Dictionary=Sm2DiscoveryContentLoader.load_scenario(); var places: Dictionary=changed.exploration.to_data()
	places.sites[-1].required_nodes=[]
	var catalog: Sm2ExplorationCatalog=Sm2ExplorationCatalog.new()
	t.expect(catalog.build(places,changed.care,3,progress).is_empty(),"different requirements validate as separate content")
	changed.exploration=catalog; changed.journey_fingerprint=Sm2Canonical.hash([changed.journey_fingerprint,places])
	t.expect(not Sm2JourneySession.new(changed,s._profile).restore(s.capture()).ok,"changed gate fingerprint cannot reinterpret history")
