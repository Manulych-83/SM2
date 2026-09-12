extends "res://tests/survival_workspace_ui.gd"

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewSurvivalTissuesButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	var before: String=s.state_hash()
	t.expect(app.find_child("JourneyGuide",true,false)!=null,"guide in production start")
	await _capture("camp-1000.png")
	await _press("Guide_inventory"); t.expect(workspace()!=null and workspace().ui.tab==1,"guide opens inventory tab")
	await _press("WorkspaceBack"); t.equal(s.state_hash(),before,"guide navigation never mutates world")
	await _press("Guide_development")
	t.expect(app.find_child("HeroDevelopmentScreen",true,false)!=null,"guide opens hero development")
	# Return via production page navigation, then exercise captured stale command safety.
	await _press("HeroDevelopmentBack"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var stale: Sm2WorldCommand=s.command("travel",0,"ruins")
	t.expect(s.act(s.command("practice",2,"p5:activity.psionics")).ok,"advance revision after render")
	before=s.state_hash(); Sm2JourneyGuide.activate(life,{},stale); await _frames()
	t.equal(s.state_hash(),before,"old guide travel rejected")
	t.expect(not life._notice.is_empty(),"stale action gives feedback")
	await _press("Guide_travel_0_ruins")
	t.equal(s.journey().region.location_id,"ruins","guide travels using real command")
	await _capture("ruins-1000.png")
	# Real wounds from the existing severe attack fixture exercise the post-battle handoff.
	s=Sm2JourneySession.new(TISSUES.content(true),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://guide-ui-route"))
	t.expect(s.new_game().ok,"authored injury route starts")
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames()
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	await _press("Guide_travel_0_ruins"); await _press("Guide_start_battle_0_")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.expect(screen.hud!=null,"guide enters illustrated battle HUD")
	for index: int in 120:
		if not s.world.busy(): break
		var step: Dictionary=BODY_TEST.treatment_step(s); t.expect(step.ok,"actual encounter action")
		if not step.ok: break
		screen.runner=s.runner; screen._refresh()
	t.expect(not s.world.busy() and s.world.hero_id()!=0,"actual retreat settled")
	await _press("BattleMenuButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	before=s.state_hash(); Sm2JourneyGuide.activate(life,{"link":"resume"},null); await _frames()
	t.equal(s.state_hash(),before,"stale resume never starts another encounter")
	t.expect(app.find_child("LifeScreen",true,false)!=null,"stale resume stays outside battle")
	await _capture("after-battle-1000.png")
	await _press("Guide_body"); t.expect(workspace()!=null and workspace().ui.tab==0,"injury opens anatomy")
	await _bandage_all(s); await _press("WorkspaceBack")
	t.expect(Sm2JourneyGuideView.build(s).stage!="bleeding","real bandage clears urgent instruction")
	await _press("Guide_explore_0_first_aid")
	t.expect(life._notice.contains("находки с земли"),"search feedback explains where things are")
	await _capture("loot-1000.png")
	await _press("Guide_inventory")
	var pack: String=""
	for row: Dictionary in workspace().view.items:
		if row.owner==2 and row.name.contains("рюкзак"): pack=row.id
	if pack.is_empty():
		for id: String in s.journey().survival.inventory.ids():
			if s.journey().survival.inventory.items[id].definition_id=="backpack" and s.journey().survival.inventory.owner(id)==2: pack=id
	var finds: Array[String]=[]
	for row: Dictionary in workspace().view.items:
		if row.place=="ground" and row.capacity==0: finds.append(row.id)
	for id: String in finds:
		_choose(id); _destination(pack); await _frames(); await _press("WorkspaceStore")
	t.expect(not finds.is_empty(),"real ground finds moved with mouse")
	await _press("WorkspaceBack"); await _press("Guide_travel_0_camp")
	t.equal(Sm2JourneyGuideView.build(s).stage,"develop","loop returns to development")
	root.size=Vector2i(1280,800); await _frames(); await _capture("return-1280.png")
	await _press("WorldSave"); before=s.state_hash(); await _press("WorldLoad")
	t.equal(s.state_hash(),before,"guide route save restores exact existing state")
	await _press("WorldEndLife")
	t.expect(s.act(s.command("practice",s.world.hero_id(),"p5:activity.psionics")).ok,"advance revision after confirmation opens")
	before=s.state_hash(); await _press("WorldConfirmDeath")
	t.equal(s.state_hash(),before,"stale confirmation cannot end a newer world state")
	await _press("WorldEndLife"); await _press("WorldConfirmDeath")
	await _capture("soul-1280.png")
	await _press("Guide_incarnate_18_")
	t.equal(s.world.hero_id(),18,"guide reincarnates into accepted local carrier")
	t.equal(s.journey().completed,1,"previous encounter not reset")
	_finish()
