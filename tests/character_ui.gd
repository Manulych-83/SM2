extends "res://tests/display_ui.gd"
const TISSUES=preload("res://tests/scenarios/test_survival_tissues.gd")
const BODY_TEST=preload("res://tests/scenarios/test_p4_body.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output); display_report={"captures":[]}
	await set_resolution(Vector2i(2560,1440))
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewSurvivalTissuesButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	var before: String=s.state_hash()
	await _press("WorldBodyInventory")
	var workspace: Sm2SurvivalWorkspace=app.find_child("SurvivalWorkspace",true,false)
	t.expect(workspace.find_child("CharacterLayout",true,false)!=null,"camp character opens overview")
	var data: Dictionary=Sm2CharacterView.build(s,s.world.hero_id())
	t.equal(data.attributes.size(),8,"overview resolves eight actual attributes")
	for row: Dictionary in data.attributes: t.equal(row,Sm2HeroDevelopmentView.track_details(s,row.id),"overview agrees with development "+str(row.name))
	data.attributes[0].effective=9999
	t.expect(Sm2CharacterView.build(s,s.world.hero_id()).attributes[0].effective!=9999,"projection is detached")
	await _capture("overview-2560.png")
	await _press("CharacterTab_body"); t.expect(_button("WorkspacePart_right_hand")!=null,"body tab reuses real anatomy")
	await _press("WorkspacePart_right_hand"); await _capture("body-2560.png")
	await _press("CharacterTab_upgrades"); await _capture("upgrades-2560.png")
	await _press("CharacterTab_overview"); await _press("CharacterDevelopment")
	t.expect(app.find_child("HeroDevelopmentBack",true,false)!=null,"development remains reachable")
	await _press("HeroDevelopmentBack")
	t.expect(workspace.layout.visible,"return refreshes character overview")
	await _press("CharacterNav_inventory"); t.expect(workspace.layout.name=="InventoryHome","inventory navigation preserved")
	await _press("InventoryNav_body"); t.expect(workspace.layout.name=="CharacterLayout","inventory returns to character shell")
	workspace.choose_person(4); await _frames()
	t.expect(not Sm2CharacterView.build(s,4).companion.is_empty(),"companion uses automatic growth model")
	await _capture("companion-2560.png")
	workspace.choose_person(s.world.hero_id()); await _frames()
	for dimensions: Vector2i in [Vector2i(1920,1080),Vector2i(1280,720),Vector2i(1280,800)]:
		await set_resolution(dimensions); await _press("CharacterTab_upgrades"); await _press("CharacterTab_overview")
		await _capture("overview-%s-%s.png" % [dimensions.x,dimensions.y])
		var figure: Control=workspace.find_child("CharacterFigure",true,false)
		t.expect(figure.get_global_rect().end.x<workspace.size.x,"figure stays inside logical viewport")
	await _key(KEY_ESCAPE); t.expect(life._content.is_visible_in_tree(),"Escape returns to camp")
	t.equal(s.state_hash(),before,"tabs navigation and inspection never mutate world")
	await _press("WorldBodyInventory"); await _press("CharacterNav_map")
	t.equal(life._camp_page,"map","character map opens existing route planner")
	await _press("CampHomeBack"); await _press("WorldBodyInventory"); await _press("CharacterNav_soul")
	t.expect(app.find_child("SoulScreen",true,false)!=null,"soul navigation works")
	await _key(KEY_ESCAPE)
	# Exercise the no-body UI explicitly without substituting a companion as the hero.
	life._workspace_state={"body":0,"tab":0,"character":true,"part":"","item":"","destination":"","scope":1,"query":""}
	life._open_workspace(); await _frames()
	t.expect(_button("CharacterIncarnate")!=null,"missing body offers incarnation")
	t.expect(app.find_child("CharacterFigure",true,false)==null,"missing body shows no substitute figure")
	await _key(KEY_ESCAPE)
	t.equal(s.state_hash(),before,"empty-state inspection does not alter world")
	await set_resolution(Vector2i(2560,1440))
	await _press("Travel_ruins"); await _press("UpgradeCollect_muscles")
	var dose: String=Sm2PhysicalSupplies.matching(s.journey().survival,"genetic_dose")[0]
	var backpack: String=""
	for id: String in s.journey().survival.inventory.ids():
		if s.journey().survival.inventory.items[id].definition_id=="backpack" and s.journey().survival.inventory.owner(id)==s.world.hero_id(): backpack=id
	t.expect(s.act(s.command("store_item",int(backpack),dose)).ok,"carry actual genetic dose to workshop")
	life.redraw(); await _frames(); await _press("Travel_camp"); await _press("UpgradeApply_muscles")
	await _press("Travel_enclave"); await _press("UpgradeCollect_psi_amplifier"); await _press("UpgradeApply_psi_amplifier")
	await _press("CampHomeBack")
	await _press("WorldBodyInventory"); await _press("CharacterTab_upgrades")
	data=Sm2CharacterView.build(s,s.world.hero_id())
	t.equal(data.upgrades.size(),2,"genetics and implant coexist in character overview")
	for row: Dictionary in data.attributes:
		t.equal(row,Sm2HeroDevelopmentView.track_details(s,row.id),"upgraded values agree with development")
	await _capture("installed-2560.png")
	await _press("WorkspaceBack"); await _press("WorldSave"); before=s.state_hash(); await _press("WorldLoad")
	t.equal(s.state_hash(),before,"character navigation preserves checkpoint save/load")
	await _press("CampTreatment"); t.expect(_button("CharacterTab_body").button_pressed,"treatment opens body directly"); await _press("WorkspaceBack")
	await wound_route()
	_finish()

func wound_route() -> void:
	var s: Sm2JourneySession=TISSUES.make(TISSUES.content(true))
	t.expect(s.new_game().ok,"authored anatomical route starts")
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"route travels to existing encounter")
	t.expect(s.act(s.command("start_battle")).ok,"route starts actual battle")
	t.expect(not str(Sm2CharacterView.build(s,2).message).is_empty(),"active battle cannot expose stale body attributes")
	for index: int in 120:
		if not s.world.busy(): break
		t.expect(BODY_TEST.treatment_step(s).ok,"authored battle advances")
	t.expect(not s.world.busy() and s.world.hero_id()==2,"route settles with surviving hero")
	if s.world.busy() or s.world.hero_id()!=2: return
	app._life=s; app._page="life"; app._redraw_page(); await _frames()
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	await set_resolution(Vector2i(2560,1440)); await _press("WorldBodyInventory"); await _press("CharacterTab_body")
	var workspace: Sm2SurvivalWorkspace=app.find_child("SurvivalWorkspace",true,false)
	var treated: int=0
	for id: int in [2,4]:
		if not s.world.bodies[id].alive: continue
		workspace.choose_person(id); await _frames()
		for wound: Dictionary in s.journey().survival.bodies[str(id)].wounds.duplicate(true):
			if int(wound.rate)==0: continue
			await _press("WorkspacePart_"+wound.part)
			if treated==0: await _capture("wounded-2560.png")
			var layers: Dictionary=s.journey().survival.bodies[str(id)].layers.duplicate(true)
			await _press("WorkspaceBandage_"+str(id)+"_"+wound.id); treated+=1
			t.equal(s.journey().survival.bodies[str(id)].layers,layers,"new body tab bandages without healing tissues")
		t.equal(s.journey().survival.bodies[str(id)].rate(),0,"new body tab stops live member bleeding")
	t.expect(treated>0,"real wound buttons exercised")
	await _press("WorkspaceBack"); await _press("Travel_camp")
	t.expect(s.act(s.command("end_life")).ok,"existing life transition completes")
	life.redraw(); await _frames(); await _press("WorldBodyInventory")
	t.expect(_button("CharacterIncarnate")!=null,"actual disembodied soul has no substitute character")
	t.expect(app.find_child("CharacterBlood",true,false)==null,"disembodied soul never borrows companion blood")
	await _capture("no-body-2560.png"); await _press("WorkspaceBack")
	t.expect(s.act(s.command("incarnate",18)).ok,"existing clean carrier incarnation works")
	life.redraw(); await _frames(); await _press("WorldBodyInventory")
	var data: Dictionary=Sm2CharacterView.build(s,18)
	t.equal(data.body_id,18,"overview follows new carrier")
	for row: Dictionary in data.attributes: t.equal(row.earned,0,"new carrier has no former practice")
	await _capture("new-body-2560.png")
