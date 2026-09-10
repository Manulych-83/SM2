extends "res://tests/p3_world_ui.gd"

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _capture("menu-1000.png")
	await _press("NewJourneyButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life!=null and life.session is Sm2JourneySession,"P4 opens from menu")
	if life==null: _finish(); return
	var journey: Sm2JourneySession=life.session as Sm2JourneySession
	var sword: String=journey.journey().equipment(2)[0].id
	await _capture("inventory-1000.png")
	await _press("JourneyItem%s_transfer_6" % sword)
	t.equal(journey.journey().item(sword).owner_id,"6","mouse transfers equipped sword to stash")
	await _press("JourneyItem%s_transfer_4" % sword)
	t.equal(journey.journey().item(sword).owner_id,"4","mouse passes sword to companion")
	t.expect(_button("JourneyItem%s_equip_0" % sword).disabled,"occupied slot visually refuses second weapon")
	await _press("JourneyItem%s_transfer_2" % sword)
	await _press("JourneyItem%s_equip_0" % sword)
	t.expect(journey.journey().item(sword).equipped,"mouse equips recovered sword")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	t.expect(screen!=null,"P4 uses shared battle screen"); if screen==null: _finish(); return
	screen.auto_advance=false
	await _capture("first-battle.png")
	for index: int in 200:
		if screen.state.finished: break
		if screen._player_turn():
			var decision: Dictionary=screen.runner._session.ai_decision(journey._profile)
			t.expect(decision.ok,"legal player command for UI flow")
			if not decision.ok: break
			t.expect(screen._execute(decision.command).accepted,"player command passes through persistent-world gateway")
		else:
			screen.auto_advance=true; screen._delay=0; screen._process(0.01); screen.auto_advance=false
	t.expect(screen.state.finished and journey.journey().completed==1,"UI fight settles first encounter")
	await _press("BattleMenuButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	for index: int in 4: await _press("WorldPractice")
	await _press("WorldBuy_strength_1")
	root.size=Vector2i(1280,800); await _frames(); await _capture("after-fight-1280.png")
	await _press("WorldEndLife"); await _press("WorldConfirmDeath")
	await _press("WorldSave"); await _press("WorldLoad")
	t.equal(journey.world.hero_id(),0,"saved Soul remains disembodied")
	await _press("WorldIncarnate8")
	t.equal(journey.world.bodies[8].progress.tracks["p1:stat.strength"].earned,0,"UI new body has zero practice")
	await _press("JourneyItem%s_transfer_8" % sword)
	t.equal(journey.journey().item(sword).owner_id,"8","new body retrieves original sword")
	await _press("JourneyItem%s_equip_0" % sword)
	await _capture("recovered-gear.png")
	await _press("JourneyItem%s_unequip_0" % sword)
	await _press("WorldSave"); var saved: String=journey.state_hash()
	await _press("WorldMenu"); await _press("ContinueJourneyButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen; journey=life.session as Sm2JourneySession
	t.equal(journey.state_hash(),saved,"menu reload restores entire persistent journey")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.equal(screen.runner.capture().session.battle.development.members[0].body.id,"8","next battle controls new body")
	t.expect(screen.state.actors[0].abilities.has("p4:ability.punch"),"empty weapon slot exposes intrinsic punch")
	t.expect(_button("Ability_punch")!=null,"punch has a visible control")
	t.expect(not _button("EndTurnButton").disabled,"new-format controls carry encounter context")
	await _cell(Vector2i(2,1),false)
	await _cell(Vector2i(3,1),false)
	t.equal(int(screen.state.actors[0].q),3,"mouse movement works in new-format encounter")
	await _press("Ability_punch")
	await _cell(Vector2i(4,1),false)
	var practice: Dictionary=screen.runner.capture().session.battle.development.members[0].body
	var progress: Sm2ProgressBodyState=Sm2ProgressRules.decode_body(practice,journey._content.development.progression()).body
	t.equal(progress.tracks["p1:stat.strength"].earned,30,"actual mouse punch awards one strength practice")
	t.equal(progress.tracks["p1:skill.melee"].earned,40,"actual mouse punch awards one melee practice")
	await _capture("second-life-unarmed.png")
	await _press("SaveBattleButton"); saved=journey.state_hash()
	await _press("LoadBattleButton"); screen.auto_advance=false
	t.equal(journey.state_hash(),saved,"battle load preserves new body and equipment")
	await _press("BattleMenuButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(_button("JourneyItem%s_equip_0" % sword).disabled,"gear controls locked while encounter is active")
	root.size=Vector2i(1000,700); await _frames(); await _capture("active-world-1000.png")
	await _press("WorldMenu"); await _press("ContinueJourneyButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.equal(life.session.state_hash(),saved,"menu continue restores active encounter without advancing time")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	await _capture("reloaded-battle-1000.png")
	_finish()
