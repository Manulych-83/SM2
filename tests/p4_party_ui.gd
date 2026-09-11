extends "res://tests/p3_world_ui.gd"

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _capture("menu.png")
	await _press("NewPartyJourneyButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life!=null,"mixed journey opens")
	if life==null: _finish(); return
	var journey: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(journey.format_id(),Sm2JourneySession.PARTY_FORMAT,"new menu uses independent mode")
	await _capture("hero.png")
	await _press("WorldCompanion")
	t.expect(_button("WorldPractice")==null,"companion has no exercise button")
	t.expect(_button("WorldBuy_strength_1")==null,"companion has no purchase button")
	await _capture("companion.png")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	t.expect(screen!=null,"shared battle opens")
	if screen==null: _finish(); return
	screen.auto_advance=false
	t.expect(not _button("EndTurnButton").disabled,"schema10 action controls enabled")
	await _press("DevelopmentButton"); await _press("DevelopActor2")
	await _capture("battle-companion.png")
	await _press("SaveDevelopmentButton")
	t.expect(journey._store.has_slot(Sm2JourneySession.PARTY_SLOT),"development panel saves whole journey")
	await _press("CloseDevelopmentButton")
	for index: int in 250:
		if screen.state.finished: break
		if screen._player_turn():
			var decision: Dictionary=screen.runner._session.ai_decision(journey._profile)
			t.expect(decision.ok,"UI legal action")
			if not decision.ok: break
			t.expect(screen._execute(decision.command).accepted,"UI action through world coordinator")
		else:
			screen.auto_advance=true; screen._delay=0; screen._process(0.01); screen.auto_advance=false
	t.expect(screen.state.finished and journey.journey().completed==1,"mixed UI fight settles")
	await _press("BattleMenuButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	await _press("WorldCompanion"); await _capture("companion-grown.png")
	var companion: Dictionary=journey.world.bodies[4].to_data()
	t.expect(companion.progress.growth.earned_total>0,"UI earned companion XP")
	await _press("WorldHero")
	for i: int in 4: await _press("WorldPractice")
	await _press("WorldBuy_strength_1")
	await _press("HeroTrain")
	await _press("WorldSave"); var saved: String=journey.state_hash()
	await _press("WorldMenu"); await _press("ContinuePartyJourneyButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen; journey=life.session as Sm2JourneySession
	t.equal(journey.state_hash(),saved,"menu reload exact")
	root.size=Vector2i(1280,800); await _frames(); await _capture("hero-developed.png")
	await _press("WorldEndLife"); await _press("WorldConfirmDeath")
	await _press("WorldIncarnate8")
	t.equal(journey.world.bodies[4].to_data(),companion,"UI reincarnation retains companion")
	for track: Sm2ProgressTrackState in journey.world.bodies[8].progress.tracks.values(): t.equal(track.earned,0,"UI new body resets every track")
	await _press("WorldSave"); await _press("WorldLoad")
	await _capture("new-life.png")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	await _cell(Vector2i(2,1),false); await _cell(Vector2i(3,1),false)
	await _press("Ability_punch"); await _cell(Vector2i(4,1),false)
	var hero: Dictionary=screen.runner.capture().session.battle.development.members[0].body
	var body: Sm2ProgressBodyState=Sm2ProgressRules.decode_body(hero,journey._content.development.progression()).body
	t.equal(body.tracks["p1:stat.strength"].earned,30,"actual mouse punch awards hero power")
	t.equal(screen.runner.capture().session.battle.development.members[1].body,companion.progress,"hero mouse attack gives no companion XP")
	await _press("SaveBattleButton"); saved=journey.state_hash()
	await _press("LoadBattleButton"); screen.auto_advance=false
	t.equal(journey.state_hash(),saved,"active mixed battle reload exact")
	await _press("DevelopmentButton"); await _press("DevelopActor1")
	await _capture("battle-hero.png")
	await _press("CloseDevelopmentButton")
	await _press("BattleMenuButton"); await _press("WorldCompanion")
	root.size=Vector2i(1000,700); await _frames(); await _capture("active-camp.png")
	_finish()
