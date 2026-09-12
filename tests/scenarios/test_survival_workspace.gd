extends RefCounted
const FIXTURE=preload("res://tests/scenarios/test_survival_tissues.gd")

static func run(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=FIXTURE.make(); t.expect(s.new_game().ok,"workspace world starts")
	var hash_before: String=s.state_hash()
	var view: Dictionary=Sm2SurvivalWorkspaceView.build(s)
	t.equal(view.body.id,2,"hero selected by default")
	t.equal(view.parts.size(),8,"authored parts projected")
	t.equal(view.parts[0].layers.size(),3,"authored tissue rows projected")
	t.expect(view.items.size()>10 and view.containers.size()>3,"physical items and containers projected")
	var companion: Dictionary=Sm2SurvivalWorkspaceView.build(s,4)
	t.equal(companion.body.id,4,"companion selectable")
	t.equal(Sm2SurvivalWorkspaceView.build(s,99999).body.id,2,"unknown selection falls back")
	view.parts[0].layers[0].current=0; view.items[0].name="Changed"; view.containers[0].volume=999
	t.equal(s.state_hash(),hash_before,"editing read model cannot mutate simulation")
	t.expect(Sm2SurvivalWorkspaceView.build(s).parts[0].layers[0].current>0,"read model detached")
	check_cards(s,t)
	var w: Sm2JourneyWorld=s.journey().copy_world()
	w.survival.bodies["2"].injure("right_hand",14,false,w.survival.catalog.to_data()); w.survival.sync_world(w)
	var fixture: Sm2JourneySession=FIXTURE.make(); fixture.world=w
	var damaged: Dictionary=Sm2SurvivalWorkspaceView.build(fixture)
	for row: Dictionary in damaged.parts:
		if row.id=="right_hand": t.expect(row.damaged and not row.working and row.bleeding==0,"closed muscle injury projected without invented bleed")
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"travel with physical inventory")
	view=Sm2SurvivalWorkspaceView.build(s)
	for row: Dictionary in view.items:
		t.expect(s.journey().survival.inventory.location(row.id,s.journey().region.bodies)=="ruins","read model excludes remote stash")
	t.expect(s.act(s.command("start_battle")).ok,"start battle")
	hash_before=s.state_hash(); view=Sm2SurvivalWorkspaceView.build(s)
	t.expect(not view.message.is_empty() and view.items.is_empty() and view.body.is_empty(),"busy world exposes no stale anatomy or inventory actions")
	t.equal(s.state_hash(),hash_before,"busy query no simulation tick")
	t.complete_suite("survival_workspace")

static func check_cards(s: Sm2JourneySession,t: Sm2TestHarness) -> void:
	var before: String=s.state_hash()
	var view: Dictionary=Sm2SurvivalWorkspaceView.build(s)
	var ui: Dictionary={"query":"","scope":1,"body":2,"storage":"","kind":0,"sort":0}
	var result: Dictionary=Sm2InventoryCards.build(view,ui)
	t.equal(result.rows.size(),10,"ten exact owned objects")
	t.equal(result.groups.size(),8,"three bandages share one visual card")
	var ids: Array=[]
	for group: Dictionary in result.groups:
		if "59" in group.ids: ids=group.ids
	t.equal(ids,["59","60","61"],"group keeps each distinct physical ID")
	ui.storage="62"; t.expect(Sm2InventoryCards.build(view,ui).rows.is_empty(),"empty backpack filter is empty")
	ui.storage="58"; t.equal(Sm2InventoryCards.build(view,ui).rows.size(),3,"belt filter contains bandages only")
	ui.storage=""; ui.query="  ПЕРЕВЯЗ  "; t.equal(Sm2InventoryCards.build(view,ui).rows.size(),3,"search ignores case and edge spaces")
	ui.query=""; ui.kind=3; t.equal(Sm2InventoryCards.build(view,ui).rows.size(),3,"three wearable containers")
	ui.kind=4; t.expect(Sm2InventoryCards.build(view,ui).rows.is_empty(),"hero has no installed device initially")
	ui.kind=0; ui.scope=0
	result=Sm2InventoryCards.build(view,ui)
	for group: Dictionary in result.groups:
		if "59" in group.ids: t.equal(group.ids,["59","60","61"],"nearby same supplies in other holders stay separate")
	ui.sort=1; result=Sm2InventoryCards.build(view,ui)
	for i: int in range(1,result.rows.size()): t.expect(int(result.rows[i-1].mass)>=int(result.rows[i].mass),"mass sorted descending")
	ui.sort=2; result=Sm2InventoryCards.build(view,ui)
	for i: int in range(1,result.rows.size()): t.expect(int(result.rows[i-1].volume)>=int(result.rows[i].volume),"volume sorted descending")
	result.rows[0].name="Edited"; result.groups[0].row.name="Edited"; result.groups[0].ids.clear()
	t.equal(view,Sm2SurvivalWorkspaceView.build(s),"card results are detached from read model")
	t.equal(s.state_hash(),before,"all card filters leave world untouched")
	var sample: Dictionary=view.items[0].duplicate(true)
	for row: Dictionary in view.items:
		if row.id=="59": sample=row.duplicate(true)
	var other: Dictionary=sample.duplicate(true); other.id="999"; other.current=int(sample.current)+1
	ui.scope=0; ui.kind=0; ui.query=""; ui.storage=""
	t.equal(Sm2InventoryCards.build({"items":[sample,other]},ui).groups.size(),2,"different item condition cannot collapse")
