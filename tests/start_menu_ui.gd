extends "res://tests/display_ui.gd"
func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output); display_report={"captures":[]}
	await set_resolution(Vector2i(2560,1440))
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	t.expect(_button("ContinueSurvivalTissuesButton").disabled,"fresh application has no saved outing")
	t.expect(_button("ResumeMainButton").disabled,"no live world to resume")
	t.expect(app.find_child("NewRegionButton",true,false)==null,"previous map is secondary")
	t.expect(app.find_child("NewSurvivalDevicesButton",true,false)==null,"previous anatomy example is secondary")
	t.equal(app.find_children("QuitButton","Button",true,false).size(),1,"one quit control")
	for dimensions: Vector2i in [Vector2i(2560,1440),Vector2i(1920,1080),Vector2i(1280,720),Vector2i(1280,800)]:
		await set_resolution(dimensions)
		var viewport: Rect2=(app.find_child("MenuScroll",true,false) as ScrollContainer).get_global_rect()
		for id: String in ["NewSurvivalTissuesButton","ContinueSurvivalTissuesButton","ResumeMainButton","OtherModesButton","QuitButton"]:
			t.expect(viewport.encloses(_button(id).get_global_rect()),"primary action without scrolling "+id+str(dimensions))
		await _capture("menu-%s.png" % dimensions.x)
	await _press("OtherModesButton")
	for id: String in ["NewRegionButton","NewMagicButton","NewEffectsButton","NewSurvivalDevicesButton","ProgressButton","AttributesButton"]:
		t.expect(app.find_child(id,true,false)==null,"historical entry absent from normal menu "+id)
	for id: String in ["NewSequencesButton","NewCreature_0","NewCreature_1"]:
		t.expect(_button(id).is_visible_in_tree(),"current example available "+id)
	await _capture("current-examples-1280.png")
	await set_resolution(Vector2i(2560,1440)); await _capture("current-examples-2560.png")
	# Explicit compatibility launch restores original navigation, never migrates old saves.
	OS.set_environment("SM2_LEGACY_DEMOS","1"); app._redraw_page(); await _frames()
	t.expect(_button("NewRegionButton").is_visible_in_tree() and _button("NewMagicButton").is_visible_in_tree(),"both legacy groups open")
	await _press("NewRegionButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var legacy: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(legacy.slot_name(),Sm2JourneySession.REGION_SLOT,"legacy starts its original profile")
	await _press("WorldSave")
	var legacy_path: String=legacy._store._slot_path(legacy.slot_name()); var legacy_bytes: PackedByteArray=FileAccess.get_file_as_bytes(legacy_path)
	await _press("WorldMenu")
	await _press("ContinueRegionButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.equal(life.session.state_hash(),legacy.state_hash(),"archived slot restores exactly")
	legacy=life.session as Sm2JourneySession
	await _press("WorldMenu")
	OS.set_environment("SM2_LEGACY_DEMOS","0"); app._redraw_page(); await _frames()
	if app._modes_expanded: await _press("CloseModesButton")
	t.expect(_button("ContinueSurvivalTissuesButton").disabled,"legacy save cannot become current Continue")
	await _press("ResumeMainButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life.session==legacy,"legacy live world remains resumable")
	await _press("WorldMenu")
	await _press("NewSurvivalTissuesButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var current: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(current.slot_name(),"survival_tissues","primary starts current tissue campaign")
	t.expect(not current._store.has_slot(current.slot_name()),"new game does not create disk save")
	await _press("WorldSave")
	var saved: String=current.state_hash(); var path: String=current._store._slot_path(current.slot_name())
	var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path)
	await _press("PsiTrain"); var unsaved: String=current.state_hash()
	t.expect(unsaved!=saved,"real practice creates unsaved progress")
	await _press("WorldMenu")
	t.expect((app.find_child("MenuCurrentGame",true,false) as Label).text.contains("Лагерь"),"menu describes live location")
	t.equal(current.state_hash(),unsaved,"menu summary is read only")
	await set_resolution(Vector2i(2560,1440)); await _capture("menu-live.png")
	await _press("ResumeMainButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life.session==current,"Resume keeps same object")
	t.equal(current.state_hash(),unsaved,"Resume keeps unsaved practice")
	t.equal(FileAccess.get_file_as_bytes(path),bytes,"Resume never writes save")
	await _press("WorldMenu"); await _press("ContinueSurvivalTissuesButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen; current=life.session as Sm2JourneySession
	t.equal(current.state_hash(),saved,"Continue restores saved state")
	await _press("Travel_ruins"); await _press("WorldBattle")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	var in_battle: String=current.state_hash()
	await _press("BattleMenuButton"); await _press("WorldMenu")
	t.expect((app.find_child("MenuCurrentGame",true,false) as Label).text.contains("В сражении"),"menu distinguishes running battle")
	await _press("ResumeMainButton"); await _press("WorldBattle")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.equal(current.state_hash(),in_battle,"Resume cannot advance battle clock or queue")
	await _press("BattleMenuButton"); await _press("WorldMenu")
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE); file.store_string("{broken"); file.close()
	# UI 9 introduced validated backup recovery; UI 8's unconditional error is obsolete.
	file=FileAccess.open(path+".bak",FileAccess.WRITE); file.store_buffer(bytes); file.close()
	await _press("ContinueSurvivalTissuesButton")
	t.equal(app._life.state_hash(),saved,"current Continue recovers validated backup")
	t.equal(current.state_hash(),in_battle,"backup restore leaves former live battle object untouched")
	t.expect((app.find_child("CampNotice",true,false) as Label).text.contains("резервная копия"),"backup recovery explained")
	current=app._life as Sm2JourneySession; await _press("WorldMenu")
	file=FileAccess.open(path+".bak",FileAccess.WRITE); file.store_string("{broken backup"); file.close()
	await _press("ContinueSurvivalTissuesButton")
	t.equal(app._page,"menu","no valid checkpoint remains in menu")
	t.expect(app.find_child("CampaignChooser",true,false)!=null,"unavailable Continue opens current campaign chooser")
	t.expect(app._life==current and current.state_hash()==saved,"failed continuation preserves live session")
	await _capture("menu-error.png")
	file=FileAccess.open(path,FileAccess.WRITE); file.store_buffer(bytes); file.close()
	await _key(KEY_ESCAPE)
	await _press("NewSurvivalTissuesButton")
	t.equal(FileAccess.get_file_as_bytes(path),bytes,"New Game never overwrites existing save")
	await _press("WorldMenu")
	root.remove_child(app); app.queue_free(); await _frames()
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	t.expect(_button("ResumeMainButton").disabled,"new application has no live world")
	t.expect(not _button("ContinueSurvivalTissuesButton").disabled,"new application discovers existing save")
	t.expect(app.find_child("NewRegionButton",true,false)==null,"new application starts collapsed")
	await _press("ContinueSurvivalTissuesButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.equal(life.session.state_hash(),saved,"restart restores actual campaign")
	t.equal(FileAccess.get_file_as_bytes(legacy_path),legacy_bytes,"current routing preserves legacy bytes")
	_finish()
