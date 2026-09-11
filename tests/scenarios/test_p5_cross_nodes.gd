extends RefCounted
## Diagnostic content: tests the general contract, not an authored combat ability.
const P1=preload("res://tests/scenarios/test_p1_progression.gd")
const MELEE: String="p1:skill.melee"
const PSI: String="p1:skill.psionics"
const NODE: String="test:node.cross"
const OTHER: String="test:node.other"
const DRILL: String="test:activity.both"
const DISCOVERY=preload("res://tests/scenarios/test_p4_discovery.gd")

static func journey_content() -> Dictionary:
	var content: Dictionary=DISCOVERY.fixture_content()
	var raw: Dictionary=content.development.progression().to_data()
	raw.version=Sm2ProgressCatalog.CROSS_VERSION
	for node: Dictionary in raw.nodes: node["extra_requirements"]=[]; node["extra_costs"]=[]
	var diagnostic: Dictionary=data()
	raw.nodes.append(diagnostic.nodes[0])
	var activity: Dictionary=diagnostic.activities[0]
	for award: Dictionary in activity.awards: award.amount=250
	raw.activities.append(activity)
	var progress: Sm2ProgressCatalog=Sm2ProgressCatalog.new()
	var errors: PackedStringArray=progress.build(raw)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var dev: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	errors=dev.build(content.development.to_data(),progress,content.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	content.development=dev
	content.journey_fingerprint=Sm2Canonical.hash([content.journey_fingerprint,dev.fingerprint()])
	return content

static func prepared(t: Sm2TestHarness) -> Sm2JourneySession:
	var session: Sm2JourneySession=Sm2JourneySession.new(journey_content(),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://cross-node-fixture"))
	t.expect(session.new_game().ok,"cross journey starts")
	t.expect(session.act(session.command("start_battle")).ok,"fixture encounter starts")
	DISCOVERY.PROSTHESIS.finish_retreat(session,t)
	t.expect(session.world.hero_id()==2,"fixture hero survives")
	t.expect(session.act(session.command("practice",2,DRILL)).ok,"real diagnostic practice command after encounter")
	return session

static func data() -> Dictionary:
	var raw: Dictionary=Sm2ImplantContentLoader.load_scenario().development.progression().to_data()
	raw.version=Sm2ProgressCatalog.CROSS_VERSION
	# Equal diagnostic curves make the payment oracle independent of game balance.
	for track: Dictionary in raw.tracks:
		if track.id in [MELEE,PSI]: track.base_level=1; track.step=100; track.growth=50
	raw.nodes=[{"id":NODE,"name":"Междисциплинарный узел","track_id":MELEE,"min_level":2,"cost":70,"bonus":0,"requires":[],"extra_requirements":[{"track_id":PSI,"min_level":2}],"extra_costs":[{"track_id":PSI,"amount":90}]},{"id":OTHER,"name":"Второй узел","track_id":PSI,"min_level":2,"cost":30,"bonus":0,"requires":[NODE],"extra_requirements":[],"extra_costs":[]}]
	raw.activities=[{"id":DRILL,"name":"Диагностическое упражнение","operation":"attribute_exercise","seconds":1,"awards":[{"track_id":MELEE,"amount":100},{"track_id":PSI,"amount":100}],"capability":{}}]
	return raw

static func run(t: Sm2TestHarness) -> void:
	var raw: Dictionary=data(); var catalog: Sm2ProgressCatalog=Sm2ProgressCatalog.new()
	t.expect(catalog.build(raw).is_empty(),"cross catalog loads")
	if not catalog.is_ready(): t.complete_suite("p5_cross_nodes"); return
	_catalog(t,raw,catalog); _purchase(t,catalog); _lab(t,catalog); _journey(t)
	t.complete_suite("p5_cross_nodes")

static func _catalog(t: Sm2TestHarness,raw: Dictionary,catalog: Sm2ProgressCatalog) -> void:
	var original: String=catalog.fingerprint()
	for defect: String in ["old_profile","missing","dictionary","string","null","extra_field","unknown","primary","duplicate","zero","negative","fraction","bool","huge","many"]:
		for field: String in ["extra_requirements","extra_costs"]:
			var bad: Dictionary=raw.duplicate(true); var node: Dictionary=bad.nodes[0]
			var key: String="min_level" if field=="extra_requirements" else "amount"
			match defect:
				"old_profile": bad.version=Sm2ProgressCatalog.UNLOCK_VERSION
				"missing": node.erase(field)
				"dictionary": node[field]={}
				"string": node[field]="invalid"
				"null": node[field]=null
				"extra_field": node[field][0].script="forbidden"
				"unknown": node[field][0].track_id="missing"
				"primary": node[field][0].track_id=MELEE
				"duplicate": node[field].append(node[field][0].duplicate(true))
				"zero": node[field][0][key]=0
				"negative": node[field][0][key]=-1
				"fraction": node[field][0][key]=1.5
				"bool": node[field][0][key]=true
				"huge": node[field][0][key]=1010001
				"many": node[field].resize(65)
			t.expect(not catalog.build(bad).is_empty(),"reject "+field+" "+defect)
			t.equal(catalog.fingerprint(),original,"invalid content does not replace catalog")
	var copy: Sm2ProgressNodeDefinition=catalog.node(NODE)
	copy.extra_costs[0].amount=1; copy.extra_requirements[0].min_level=1
	t.equal(catalog.node(NODE).prices()[PSI],90,"detached prices")
	t.equal(catalog.node(NODE).own_levels()[PSI],2,"detached requirements")
	var changed: Dictionary=raw.duplicate(true); changed.nodes[0].extra_costs[0].amount=91
	var altered: Sm2ProgressCatalog=Sm2ProgressCatalog.new(); t.expect(altered.build(changed).is_empty(),"alternate valid price")
	t.expect(altered.fingerprint()!=original,"cross price belongs to fingerprint")

static func _purchase(t: Sm2TestHarness,catalog: Sm2ProgressCatalog) -> void:
	var body: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(2,catalog)
	body.tracks[MELEE].earned=100; body.tracks[PSI].earned=100
	var previous: Dictionary=body.to_data()
	t.equal(Sm2ProgressRules.purchase_error(body,catalog,NODE),"","own levels and both wallets sufficient")
	Sm2ProgressRules.purchase(body,catalog.node(NODE))
	t.equal([body.tracks[MELEE].earned,body.tracks[PSI].earned],[100,100],"spend never reduces earned XP")
	t.equal([body.tracks[MELEE].spent,body.tracks[PSI].spent],[70,90],"each wallet pays its own price")
	t.equal([body.tracks[MELEE].nodes,body.tracks[PSI].nodes],[[NODE],[]],"one node owner despite two payments")
	t.equal([catalog.track(MELEE).describe(100).level,catalog.track(PSI).describe(100).level],[2,2],"both own levels preserved")
	t.expect(Sm2ProgressRules.decode_body(body.to_data(),catalog).ok,"cross payment roundtrip")
	t.equal(Sm2ProgressRules.purchase_error(body,catalog,NODE),"node_owned","repeat purchase denied")
	t.equal(Sm2ProgressRules.purchase_error(body,catalog,OTHER),"experience_required","second node sees money already spent elsewhere")
	body.tracks[PSI].earned=200
	t.equal(Sm2ProgressRules.purchase_error(body,catalog,OTHER),"","prerequisite can be owned in another track")
	Sm2ProgressRules.purchase(body,catalog.node(OTHER))
	t.equal(body.tracks[PSI].spent,120,"cross and own prices accumulate")
	t.expect(Sm2ProgressRules.decode_body(body.to_data(),catalog).ok,"combined payments roundtrip")
	for defect: String in ["unpaid_primary","unpaid_extra","overpaid","missing_node","wrong_owner","low_extra_level","duplicate"]:
		var bad: Dictionary=body.to_data()
		for entry: Dictionary in bad.tracks:
			if defect=="unpaid_primary" and entry.track_id==MELEE: entry.spent_total=0
			if defect=="unpaid_extra" and entry.track_id==PSI: entry.spent_total=30
			if defect=="overpaid" and entry.track_id==PSI: entry.spent_total=121
			if defect=="missing_node" and entry.track_id==MELEE: entry.owned_nodes=[]
			if defect=="wrong_owner":
				if entry.track_id==MELEE: entry.owned_nodes=[]
				if entry.track_id==PSI: entry.owned_nodes.append(NODE); entry.owned_nodes.sort()
			if defect=="low_extra_level" and entry.track_id==PSI: entry.earned_total=99; entry.spent_total=90; entry.owned_nodes=[]
			if defect=="duplicate" and entry.track_id==MELEE: entry.owned_nodes.append(NODE)
		t.expect(not Sm2ProgressRules.decode_body(bad,catalog).ok,"reject forged "+defect)
	body=Sm2ProgressRules.decode_body(previous,catalog).body
	body.tracks[PSI].earned=99
	var modifiers: Array[Dictionary]=[{"track_id":PSI,"amount":100,"name":"Diagnostic enhancement"}]
	var effective: int=0
	for row: Dictionary in Sm2ProgressRules.tracks(body,catalog,modifiers):
		if row.id==PSI: effective=row.effective
	t.expect(effective>2,"effective ability can be high")
	t.equal(Sm2ProgressRules.purchase_error(body,catalog,NODE),"level_required","enhancement and contribution cannot replace own practice")
	var fresh: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(5,catalog)
	t.equal([fresh.tracks[MELEE].spent,fresh.tracks[PSI].spent,fresh.tracks[MELEE].nodes],[0,0,[]],"new body owns no prior purchase")

static func _lab(t: Sm2TestHarness,catalog: Sm2ProgressCatalog) -> void:
	var lab: Sm2ProgressLab=Sm2ProgressLab.new(catalog)
	t.expect(lab.start("cross-nodes-test").ok,"new diagnostic session")
	t.expect(lab.execute(P1.command(lab,"practice",DRILL)).ok,"own practice in both directions")
	var buy: Sm2ProgressCommand=P1.command(lab,"buy_node",NODE)
	var before: String=lab.state_hash(); var preview: Dictionary=lab.preview(buy)
	t.equal(preview.prices,{MELEE:70,PSI:90},"preview names both exact prices")
	preview.prices[PSI]=0
	t.equal(lab.state_hash(),before,"preview is detached")
	var result: Dictionary=lab.execute(buy)
	t.expect(result.ok,"atomic dual purchase command")
	t.equal(result.events[0].prices,{MELEE:70,PSI:90},"receipt records both payments")
	before=lab.state_hash()
	t.expect(not lab.execute(buy).ok,"stale repeat rejected")
	t.equal(lab.state_hash(),before,"stale repeat does not pay twice")
	t.expect(not lab.execute(P1.command(lab,"buy_node",OTHER)).ok,"insufficient second wallet rejected")
	t.equal(lab.state_hash(),before,"failed purchase changes no state or revision")
	var restored: Sm2ProgressLab=Sm2ProgressLab.new(catalog)
	t.expect(restored.restore(lab.capture()).ok,"lab full snapshot roundtrip")
	t.equal(restored.state_hash(),before,"saved practice, ownership, payments exact")
	var forged: Dictionary=lab.capture()
	for entry: Dictionary in forged.body.tracks:
		if entry.track_id==PSI: entry.spent_total=0
	t.expect(not lab.restore(forged).ok,"unpaid second wallet load rejected")
	t.equal(lab.state_hash(),before,"invalid load does not publish")
	# Valid initial levels but a price beyond one wallet: no partial debit of the other.
	for expensive: String in [MELEE,PSI]:
		var raw: Dictionary=data()
		if expensive==MELEE: raw.nodes[0].cost=101
		else: raw.nodes[0].extra_costs[0].amount=101
		var costly: Sm2ProgressCatalog=Sm2ProgressCatalog.new(); t.expect(costly.build(raw).is_empty(),"valid expensive catalog")
		var session: Sm2ProgressLab=Sm2ProgressLab.new(costly); session.start("costly"); session.execute(P1.command(session,"practice",DRILL))
		var hash_before: String=session.state_hash()
		t.expect(not session.execute(P1.command(session,"buy_node",NODE)).ok,"insufficient wallet "+expensive)
		t.equal(session.state_hash(),hash_before,"both wallets and node unchanged "+expensive)

static func _journey(t: Sm2TestHarness) -> void:
	var session: Sm2JourneySession=prepared(t)
	var before: String=session.state_hash()
	var view: Dictionary=Sm2HeroDevelopmentView.build(session,MELEE)
	var node: Dictionary={}
	for row: Dictionary in view.nodes:
		if row.id==NODE: node=row
	t.expect(not node.is_empty() and node.allowed,"common world check enables cross node")
	if node.is_empty(): return
	t.equal(node.extra_requirements[0].min_level,2,"read model includes second own level")
	t.equal(node.extra_costs[0].cost,90,"read model includes second wallet")
	node.extra_costs[0].cost=0
	t.equal(session.state_hash(),before,"read model cannot alter purchase cost")
	t.expect(not session.act(session.command("buy_node",4,NODE)).ok,"companion cannot use hero cross nodes")
	t.equal(session.state_hash(),before,"companion refusal atomic")
	var old: Dictionary=session.world.bodies[2].progress.to_data()
	t.expect(session.act(session.command("buy_node",2,NODE)).ok,"world command purchases cross node")
	var body: Sm2ProgressBodyState=session.world.bodies[2].progress
	t.equal([body.tracks[MELEE].spent,body.tracks[PSI].spent],[70,90],"world debits both balances")
	for entry: Dictionary in old.tracks: t.equal(body.tracks[entry.track_id].earned,entry.earned_total,"world preserves earned "+entry.track_id)
	before=session.state_hash()
	t.expect(session.save_game().ok and session.load_game().ok,"world history and disk validate cross purchase")
	t.equal(session.state_hash(),before,"world reload exact")
	var snapshot: Dictionary=session.capture()
	for entry: Dictionary in snapshot.world.bodies:
		if entry.id!="2": continue
		for track: Dictionary in entry.progress.tracks:
			if track.track_id==PSI: track.spent_total=0
	t.expect(not session.restore(snapshot).ok,"world rejects unpaid cross wallet")
	t.equal(session.state_hash(),before,"world corrupt restore atomic")
	t.expect(session.act(session.command("end_life")).ok,"end first body")
	t.expect(session.act(session.command("incarnate",8)).ok,"new incarnation")
	body=session.world.bodies[8].progress
	t.equal([body.tracks[MELEE].earned,body.tracks[PSI].earned,body.tracks[MELEE].nodes],[0,0,[]],"new incarnation loses both practices and owned node")
	t.expect(session.save_game().ok and session.load_game().ok,"history preserves old body payments after incarnation")
