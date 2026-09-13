extends "res://tests/display_ui.gd"
const EPISODE=preload("res://tests/scenarios/test_expedition.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output); display_report={"captures":[]}
	var watchdog: Timer=Timer.new(); watchdog.wait_time=180; watchdog.one_shot=true; watchdog.timeout.connect(func() -> void: t.expect(false,"expedition UI timeout"); _finish()); root.add_child(watchdog); watchdog.start()
	await set_resolution(Vector2i(2560,1440))
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewSurvivalTissuesButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	var before: String=s.state_hash()
	t.expect(app.find_child("ExpeditionCard",true,false)!=null,"objective visible in main campaign")
	await _capture("camp-objective.png")
	await _press("CampExpedition")
	var page: Sm2ExpeditionScreen=app.find_child("ExpeditionScreen",true,false) as Sm2ExpeditionScreen
	t.expect(page!=null and not page.model.complete,"real objective details open")
	await _key(KEY_J); t.expect(app.find_child("JournalScreen",true,false)==null,"objective blocks underlying camp hotkeys")
	await _capture("brief-2560.png"); await _key(KEY_ESCAPE)
	t.equal(s.state_hash(),before,"reading brief cannot mutate campaign")
	SHIELD.learn(s,t); life.redraw(); await _frames()
	await _press("Guide_travel_0_ruins"); await _press("Guide_start_battle_0_")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	EPISODE.retreat(s,t); screen.runner=s.runner; screen._refresh(); await _frames()
	await _press("BattleMenuButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life.expedition.build(s).encounter_done,"settled first battle updates objective")
	# This route withdraws before injury; damage and real bandaging also run in core winning route.
	for id: int in [s.world.hero_id(),4]:
		if id!=0 and s.world.bodies[id].alive: t.equal(s.journey().survival.bodies[str(id)].rate(),0,"test retreat route has no untreated bleeding")
	await _press("Guide_explore_0_first_aid")
	var ids: Array=life.expedition.build(s).ids
	t.equal(ids.size(),4,"real search produces four tracked medicines")
	await _press("Guide_inventory")
	var pack: String=EPISODE.container(s,"backpack",s.world.hero_id())
	for id: String in ids:
		choose(id); await _frames(); destination(pack); await _frames(); await _press("WorkspaceStore")
	await _capture("carried-supplies.png")
	await _press("WorkspaceBack"); await _press("Guide_travel_0_camp")
	t.expect(not life.expedition.build(s).complete,"return with items still requires deposit")
	await _press("Guide_inventory")
	var stash: String=EPISODE.container(s,"stash")
	for id: String in ids:
		choose(id); await _frames(); destination(stash); await _frames(); await _press("WorkspaceStore")
	await _press("WorkspaceBack")
	page=app.find_child("ExpeditionScreen",true,false) as Sm2ExpeditionScreen
	t.expect(page!=null and page.model.complete,"completion opens actual results after final deposit")
	t.expect((app.find_child("ExpeditionTitle",true,false) as Label).text.contains("ЗАВЕРШЁН"),"clear ending")
	before=s.state_hash()
	for dimensions: Vector2i in [Vector2i(2560,1440),Vector2i(1280,720)]:
		await set_resolution(dimensions); await _capture("completed-%s.png" % dimensions.x)
	t.equal(s.state_hash(),before,"report and resizing cannot award twice")
	await _press("ExpeditionSave")
	t.equal((app.find_child("ExpeditionSaveNotice",true,false) as Label).text,"Игра сохранена.","result can save same campaign")
	await _press("ExpeditionBack"); t.expect(app.find_child("ExpeditionScreen",true,false)==null,"results do not reopen immediately")
	await _press("WorldMenu"); await _press("ResumeMainButton")
	t.expect(app.find_child("ExpeditionScreen",true,false)==null,"same process remembers acknowledged result")
	await _press("CampExpedition"); page=app.find_child("ExpeditionScreen",true,false) as Sm2ExpeditionScreen
	t.expect(page.model.complete,"result can be reopened explicitly")
	await _press("ExpeditionBack")
	root.remove_child(app); app.queue_free(); await _frames()
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("ContinueSurvivalTissuesButton")
	page=app.find_child("ExpeditionScreen",true,false) as Sm2ExpeditionScreen
	t.expect(page!=null and page.model.complete,"fresh startup reconstructs completed episode from saved history")
	t.equal(app._life.state_hash(),before,"complete campaign restored exactly")
	await set_resolution(Vector2i(2560,1440)); await _capture("completed-reloaded.png")
	_finish()

func choose(id: String) -> void:
	var workspace: Sm2SurvivalWorkspace=app.find_child("SurvivalWorkspace",true,false) as Sm2SurvivalWorkspace
	var scope: OptionButton=app.find_child("WorkspaceScope",true,false) as OptionButton; scope.select(0); scope.item_selected.emit(0)
	for index: int in workspace.cards.size():
		if id not in workspace.cards[index].ids: continue
		workspace.item_list.select(index); workspace.item_list.item_selected.emit(index)
		var selector: OptionButton=app.find_child("WorkspaceInstance",true,false) as OptionButton
		if selector!=null:
			for entry: int in selector.item_count:
				if str(selector.get_item_metadata(entry))==id: selector.select(entry); selector.item_selected.emit(entry); return
		if workspace.ui.item==id: return
	t.expect(false,"exact tracked item visible "+id)

func destination(id: String) -> void:
	var selector: OptionButton=app.find_child("WorkspaceDestination",true,false) as OptionButton
	for index: int in selector.item_count:
		if str(selector.get_item_metadata(index))==id: selector.select(index); selector.item_selected.emit(index); return
	t.expect(false,"destination visible "+id)
