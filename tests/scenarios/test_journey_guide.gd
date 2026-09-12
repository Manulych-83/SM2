extends RefCounted
const FIXTURE=preload("res://tests/scenarios/test_survival_tissues.gd")
const BODY=preload("res://tests/scenarios/test_p4_body.gd")

static func run(t: Sm2TestHarness) -> void:
	_camp(t)
	var s: Sm2JourneySession=FIXTURE.make(); t.expect(s.new_game().ok,"guide production world")
	var before: String=s.state_hash()
	var v: Dictionary=Sm2JourneyGuideView.build(s)
	t.equal(v.stage,"prepare","fresh body preparation")
	v.actions.clear(); v.facts.append("changed")
	t.equal(s.state_hash(),before,"guidance detached and read only")
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"reach real ruins")
	v=Sm2JourneyGuideView.build(s)
	for row: Dictionary in v.actions:
		if row.has("kind"): t.equal(row.reason,s.world.check(s.command(row.kind,row.target,row.content)),"same command availability")
	t.expect(s.act(s.command("start_battle")).ok,"start real battle")
	t.equal(Sm2JourneyGuideView.build(s).stage,"battle","busy ignores stale camp bodies")
	# Authored severe wound fixture: guidance must follow real injury and retreat settlement.
	s=FIXTURE.make(FIXTURE.content(true)); t.expect(s.new_game().ok,"injury route")
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"route travel")
	t.expect(s.act(s.command("start_battle")).ok,"route battle")
	for index: int in 120:
		if not s.world.busy(): break
		var step: Dictionary=BODY.treatment_step(s); t.expect(step.ok,"actual battle action")
		if not step.ok: break
	t.expect(not s.world.busy() and s.world.hero_id()!=0,"survive actual retreat")
	t.equal(Sm2JourneyGuideView.build(s).stage,"bleeding","wound priority before search and travel")
	FIXTURE.bandage_all(t,s)
	v=Sm2JourneyGuideView.build(s); t.expect(v.stage!="bleeding","bandage updates recommendation")
	var old: Dictionary=s.view()
	t.expect(s.act(s.command("explore",0,"first_aid")).ok,"real search")
	t.expect(Sm2JourneyGuideView.feedback("explore",old,s.view()).contains("находки с земли"),"explicit physical loot feedback")
	t.equal(Sm2JourneyGuideView.build(s).stage,"carry","ground loot handoff")
	var inv: Sm2PhysicalInventory=s.journey().survival.inventory
	var pack: String=""
	for id: String in inv.ids():
		if inv.items[id].definition_id=="backpack" and inv.owner(id)==s.world.hero_id(): pack=id
	for id: String in inv.ids():
		if inv.items[id].place=="ground" and inv.items[id].holder=="ruins" and int(s.journey().survival.catalog.item(inv.items[id].definition_id).capacity)==0:
			t.expect(s.act(s.command("store_item",int(pack),id)).ok,"store actual ground find")
	t.expect(Sm2JourneyGuideView.build(s).stage!="carry","carried loot no longer reported on ground")
	t.expect(s.act(s.command("travel",0,"camp")).ok,"return to camp")
	t.equal(Sm2JourneyGuideView.build(s).stage,"develop","post encounter camp growth")
	before=s.state_hash(); v=Sm2JourneyGuideView.build(s)
	t.expect(s.save_game().ok,"save guide route")
	t.expect(s.load_game().ok,"reload guide route")
	t.equal(s.state_hash(),before,"exact world restore")
	t.equal(Sm2JourneyGuideView.build(s),v,"guidance reconstructed without quest state")
	t.expect(s.act(s.command("end_life")).ok,"end life")
	v=Sm2JourneyGuideView.build(s); t.equal(v.stage,"soul","soul recovery route")
	for row: Dictionary in v.actions: t.equal(row.kind,"incarnate","soul only valid carrier actions")
	t.expect(s.act(s.command("incarnate",18)).ok,"local ordinary carrier")
	t.equal(Sm2JourneyGuideView.build(s).body,18,"new body selected")
	t.equal(s.journey().completed,1,"old encounter remains completed")
	# Boundary projections on independent world copies, not production completion evidence.
	var copy: Sm2JourneySession=FIXTURE.make(); copy.world=s.journey().copy_world()
	copy.journey().completed=copy.journey().encounters.size()
	t.equal(Sm2JourneyGuideView.build(copy).stage,"complete","finite encounter boundary")
	t.complete_suite("journey_guide")

static func _camp(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=FIXTURE.make(); t.expect(s.new_game().ok,"camp projection world starts")
	var before: String=s.state_hash(); var view: Dictionary=Sm2CampView.build(s)
	t.equal(view.places.size(),3,"three real locations")
	t.equal(view.party.size(),2,"hero and companion projected")
	for row: Dictionary in view.places:
		if row.id=="ruins": t.equal(row.seconds,1800,"authored travel duration")
	for row: Dictionary in view.activities:
		t.expect(row.kind!="explore","camp does not offer remote searches")
		t.equal(row.reason,s.world.check(s.command(row.kind,row.target,row.content)),"same command availability")
	view.party[0].blood=0; view.places[0].name="Changed"; view.routes.clear()
	t.equal(s.state_hash(),before,"camp view fully detached")
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"reach ruins for camp projection")
	view=Sm2CampView.build(s); var sites: int=0
	for row: Dictionary in view.activities:
		t.expect(row.kind!="practice","ruins do not expose camp-only practice")
		if row.kind=="explore": sites+=1
	t.equal(sites,5,"all authored local sites represented")
	t.expect(s.act(s.command("start_battle")).ok,"busy camp boundary")
	before=s.state_hash(); view=Sm2CampView.build(s)
	t.expect(view.activities.is_empty() and not view.party[0].has("blood"),"busy projection hides stale camp health and actions")
	t.equal(s.state_hash(),before,"busy camp query does not advance encounter")
