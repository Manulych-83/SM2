extends "res://tests/p5_psionic_ui.gd"
const SHIELD=preload("res://tests/scenarios/test_p5_shield.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewPsionicShieldButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life!=null,"shield mode opens from menu")
	if life==null: _finish(); return
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(s.slot_name(),Sm2JourneySession.PSIONIC_SHIELD_SLOT,"independent shield slot")
	await _press("WorldDevelopment"); await _select_psi()
	t.expect(_button(_id("HeroBuy",SHIELD.NODE)).disabled,"own practice required for shield")
	await _capture("untrained.png"); await _press("HeroDevelopmentBack")
	for i: int in 8: await _press("PsiTrain")
	await _press("WorldDevelopment"); await _select_psi()
	await _press(_id("HeroBuy",PSI.NODE)); await _press(_id("HeroBuy",SHIELD.NODE))
	var hero: Sm2HeroDevelopmentScreen=app.find_child("HeroDevelopmentScreen",true,false) as Sm2HeroDevelopmentScreen
	t.expect(str(hero._model.nodes).contains("18 защиты"),"node explains capacity")
	t.expect(str(hero._model.nodes).contains("Резонанс 10"),"node shows growth source")
	await _capture("learned.png"); await _press("HeroDevelopmentBack"); await _press("WorldBattle")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.expect(_button("Ability_shield")!=null and not _button("Ability_shield").disabled,"learned shield usable")
	# Real pointer hover requests the shared shield forecast.
	var button: Button=_button("Ability_shield")
	var motion: InputEventMouseMotion=InputEventMouseMotion.new(); motion.position=button.get_global_rect().get_center(); root.push_input(motion,true); await _frames()
	t.expect(screen._preview.text.contains("18 защиты") and screen._preview.text.contains("6 концентрации"),"hover previews protection and cost")
	await _capture("forecast.png"); await _press("Ability_shield")
	var battle: Sm2TacticalBattle=s.runner._session._battle
	t.equal(battle._state.actor(1).barrier.remaining,18,"button casts on self")
	t.equal(battle._state.mana[1].current,6,"real button spends focus")
	t.expect(screen._inspector.text.contains("Пси-щит: 18"),"remaining protection visible")
	t.expect(screen._log.text.contains("пси-щит") and screen._log.text.contains("Резонанс +5"),"journal explains shield and practice")
	await _capture("cast.png"); await _press("SaveBattleButton"); var saved: String=s.state_hash()
	await _press("BattleMenuButton"); await _press("WorldMenu"); await _press("ContinuePsionicShieldButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen; s=life.session as Sm2JourneySession
	t.equal(s.state_hash(),saved,"continue restores exact shield and resources")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.expect(screen._inspector.text.contains("Пси-щит: 18"),"loaded shield remains visible")
	root.size=Vector2i(1280,800); await _frames(); await _capture("loaded.png")
	await _press("Ability_impulse"); await _motion(Vector2i(4,1)); await _cell(Vector2i(4,1),false)
	t.equal(s.runner._session._battle._state.actor(3).combat.hp,48,"impulse still usable alongside shield")
	t.expect(_button("Ability_shield").disabled,"no focus prevents another cast")
	# Existing real injury/retreat flow, then clean body must learn both abilities again.
	s=Sm2JourneySession.new(SHIELD.life_content(),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://shield-ui-lives"))
	t.expect(s.new_game().ok,"new-body fixture starts"); SHIELD.learn(s,t)
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames(); await _fight_to_retreat(s)
	await _press("WorldEndLife"); await _press("WorldConfirmDeath"); await _press("WorldIncarnate8")
	await _press("WorldDevelopment"); await _select_psi()
	t.expect(_button(_id("HeroBuy",SHIELD.NODE)).disabled,"new body shield must be learned again")
	t.expect((app.find_child("HeroTrackSummary",true,false) as Label).text.contains("заработано 0"),"new body's practice reset visible")
	await _capture("new-body.png")
	_finish()
