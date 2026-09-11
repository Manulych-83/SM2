extends "res://tests/p3_world_ui.gd"
func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	t.equal(_button("NewRegionButton").text,"Новая игра","current mode is primary New Game")
	t.expect(_button("NewRegionButton").is_visible_in_tree(),"primary start visible")
	t.expect(_button("ContinueRegionButton").disabled,"no main save on fresh start")
	t.expect(_button("ResumeMainButton").disabled,"no running main game")
	t.expect(not _button("NewUpgradeButton").is_visible_in_tree(),"previous mode initially hidden")
	t.expect(not _button("NewMagicButton").is_visible_in_tree(),"older battle initially hidden")
	t.equal(app.find_children("QuitButton","Button",true,false).size(),1,"one exit control")
	for id: String in ["NewRegionButton","ContinueRegionButton","ResumeMainButton","OtherModesButton","QuitButton"]:
		t.expect((app.find_child("MenuScroll",true,false) as ScrollContainer).get_global_rect().encloses(_button(id).get_global_rect()),"primary control visible without scroll "+id)
	await _capture("main-1000.png")
	await _press("OtherModesButton")
	t.expect(_button("NewUpgradeButton").is_visible_in_tree() and _button("NewMagicButton").is_visible_in_tree(),"both mode columns expand")
	t.expect(_button("OtherModesButton").text.contains("Скрыть"),"collapse action clearly named")
	var older: Button=_button("NewUpgradeButton"); var parent: Node=older.get_parent()
	while parent!=null:
		if parent is ScrollContainer: (parent as ScrollContainer).ensure_control_visible(older); await _frames(); break
		parent=parent.get_parent()
	await _capture("other-modes.png")
	await _press("NewUpgradeButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life!=null,"older mode opens by mouse")
	if life==null: _finish(); return
	var old: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(old.slot_name(),Sm2JourneySession.UPGRADE_SLOT,"older mode retains own slot")
	await _press("WorldSave"); var old_path: String=old._store._slot_path(old.slot_name())
	var old_bytes: PackedByteArray=FileAccess.get_file_as_bytes(old_path)
	await _press("WorldMenu")
	t.expect(_button("ContinueRegionButton").disabled,"legacy save is not main Continue")
	t.expect(_button("ResumeMainButton").disabled,"legacy session is not main Resume")
	t.expect(not _button("ContinueUpgradeButton").disabled,"legacy Continue sees own save")
	await _press("ContinueUpgradeButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.equal(life.session.state_hash(),old.state_hash(),"legacy continuation exact")
	await _press("WorldMenu"); await _press("OtherModesButton")
	t.expect(not _button("NewUpgradeButton").is_visible_in_tree(),"collapse hides old mode")
	await _press("NewRegionButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var current: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(current.slot_name(),Sm2JourneySession.REGION_SLOT,"main starts actual three-path profile")
	await _press("WorldSave"); var saved: String=current.state_hash()
	var path: String=current._store._slot_path(current.slot_name()); var saved_bytes: PackedByteArray=FileAccess.get_file_as_bytes(path)
	await _press("PsiTrain"); var unsaved: String=current.state_hash()
	t.expect(unsaved!=saved,"performed unsaved world action")
	await _press("WorldMenu")
	t.expect(not _button("ResumeMainButton").disabled and not _button("ContinueRegionButton").disabled,"save and current session available")
	await _press("ResumeMainButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life.session==current,"resume retains existing session object")
	t.equal(life.session.state_hash(),unsaved,"resume preserves unsaved action")
	t.equal(FileAccess.get_file_as_bytes(path),saved_bytes,"resume never writes disk")
	await _press("WorldMenu"); await _press("ContinueRegionButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen; current=life.session as Sm2JourneySession
	t.equal(current.state_hash(),saved,"Continue restores disk rather than unsaved memory")
	t.equal(current.journey().upgrade_supply.remaining["p5:upgrade.psi_amplifier"],0,"unsaved collection is not in disk snapshot")
	await _press("Travel_ruins"); await _press("WorldBattle")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	var in_battle: String=current.state_hash()
	await _press("BattleMenuButton"); await _press("WorldMenu"); await _press("ResumeMainButton"); await _press("WorldBattle")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.equal(current.state_hash(),in_battle,"resume battle does not advance time queue or resources")
	await _press("BattleMenuButton"); await _press("WorldMenu")
	var broken: FileAccess=FileAccess.open(path,FileAccess.WRITE); t.expect(broken!=null,"isolated corrupt-save fixture opens")
	if broken==null: _finish(); return
	broken.store_string("{broken"); broken.close()
	await _press("ContinueRegionButton")
	t.equal(app.get("_page"),"menu","failed Continue remains on menu")
	t.expect(app.get("_life")==current,"failed Continue preserves live session")
	t.equal(current.state_hash(),in_battle,"failed load is atomic")
	t.expect(not (app.find_child("StatusLabel",true,false) as Label).text.is_empty(),"load error visible")
	t.equal((app.find_child("StatusLabel",true,false) as Label).text,"Файл сохранения повреждён.","save error uses plain language")
	await _capture("load-error.png")
	var restored: FileAccess=FileAccess.open(path,FileAccess.WRITE); restored.store_buffer(saved_bytes); restored.close()
	await _press("ResumeMainButton"); await _press("WorldMenu")
	await _press("NewRegionButton")
	t.equal(FileAccess.get_file_as_bytes(path),saved_bytes,"New Game does not overwrite existing disk save")
	await _press("WorldMenu")
	root.remove_child(app); app.queue_free(); await _frames()
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	t.expect(_button("ResumeMainButton").disabled,"new application has no in-memory session")
	t.expect(not _button("ContinueRegionButton").disabled,"new application discovers saved game")
	t.expect(not _button("NewUpgradeButton").is_visible_in_tree(),"new application starts compact")
	root.size=Vector2i(1280,800); await _frames(); await _capture("main-1280.png")
	await _press("ContinueRegionButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.equal(life.session.state_hash(),saved,"fresh application continues exact saved game")
	t.equal(FileAccess.get_file_as_bytes(old_path),old_bytes,"main routing never touches legacy save")
	_finish()
