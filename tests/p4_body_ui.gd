extends "res://tests/p3_world_ui.gd"
const BODY_TEST=preload("res://tests/scenarios/test_p4_body.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _capture("menu.png")
	await _press("NewBodyJourneyButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life!=null,"new body mode opens")
	if life==null: _finish(); return
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(s.format_id(),Sm2JourneySession.BODY_FORMAT,"explicit body session format")
	await _capture("healthy.png")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.expect(_button("Ability_hand_strike")!=null,"aimed right-hand attack visible")
	t.expect(not _button("EndTurnButton").disabled,"schema11 controls carry battle identity")
	await _cell(Vector2i(2,1),false); await _cell(Vector2i(3,1),false)
	await _press("Ability_hand_strike"); await _motion(Vector2i(4,1))
	t.expect(screen._preview.text.contains("травма"),"preview explains injury condition")
	await _capture("aimed-preview.png")
	await _cell(Vector2i(4,1),false)
	var member: Dictionary=s.runner.capture().session.battle.development.members[0].body
	var body: Sm2ProgressBodyState=Sm2ProgressRules.decode_body(member,s._content.development.progression()).body
	t.equal(body.tracks["p1:stat.strength"].earned,30,"mouse aimed attack awards normal personal practice")
	await _press("SaveBattleButton"); var saved: String=s.state_hash()
	await _press("BattleMenuButton"); await _press("WorldMenu"); await _press("ContinueBodyJourneyButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.equal(life.session.state_hash(),saved,"production mode reloads through menu")
	# Controlled enemy arm-strike fixture is isolated from the production save.
	var content: Dictionary=BODY_TEST.treatment_content()
	s=Sm2JourneySession.new(content,Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://body-ui-treatment"))
	t.expect(s.new_game().ok,"treatment UI fixture starts")
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames()
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	for i: int in 50:
		if not s.world.busy(): break
		t.expect(BODY_TEST.treatment_step(s).ok,"real injury and retreat through world commands")
		screen.runner=s.runner; screen._refresh()
	t.expect(not s.world.busy(),"treatment fixture ends battle")
	await _press("BattleMenuButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var treated: bool=false
	for id: int in [s.world.hero_id(),4]:
		if id==0 or not s.world.bodies[id].alive: continue
		await _press("WorldHero" if id==s.world.hero_id() else "WorldCompanion")
		for part: String in s.journey().body_catalog.ids():
			if s.world.bodies[id].functions.working[part]: continue
			await _capture("injured.png")
			var hp: int=s.world.bodies[id].hp
			await _press("WorldSave")
			await _press("Heal_"+part)
			t.expect(s.world.bodies[id].functions.working[part],"mouse treatment restores function")
			t.equal(s.world.bodies[id].hp,hp,"UI treatment does not heal HP")
			await _capture("treated.png")
			await _press("WorldLoad")
			t.expect(not s.world.bodies[id].functions.working[part],"load brings back saved injury")
			await _press("Heal_"+part); await _press("WorldSave")
			treated=true
	t.expect(treated,"UI actually treats an injury")
	root.size=Vector2i(1280,800); await _frames(); await _capture("restored-functions.png")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.expect(screen.state.actors[0].abilities.has("p4:ability.hand_strike"),"healed right hand works in next fight")
	await _press("DevelopmentButton"); await _capture("body-panel.png"); await _press("CloseDevelopmentButton")
	_finish()
