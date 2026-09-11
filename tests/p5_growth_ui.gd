extends "res://tests/p5_psionic_ui.gd"
const GROWTH=preload("res://tests/scenarios/test_p5_growth.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewPsionicGrowthButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life!=null,"growth menu opens")
	if life==null: _finish(); return
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(s.slot_name(),Sm2JourneySession.PSIONIC_GROWTH_SLOT,"growth uses independent slot")
	await _press("WorldDevelopment"); await _select_psi()
	var hero: Sm2HeroDevelopmentScreen=app.find_child("HeroDevelopmentScreen",true,false) as Sm2HeroDevelopmentScreen
	t.equal(hero._model.selected.level,0,"untrained own level shown")
	t.equal(hero._model.selected.effective,5,"resonance contribution shown")
	t.expect(_button(_id("HeroBuy",PSI.NODE)).disabled,"high effective skill is not own training")
	await _capture("untrained.png"); await _press("HeroDevelopmentBack")
	for i: int in 4: await _press("PsiTrain")
	await _press("WorldDevelopment"); await _select_psi(); await _press(_id("HeroBuy",PSI.NODE))
	hero=app.find_child("HeroDevelopmentScreen",true,false) as Sm2HeroDevelopmentScreen
	t.expect(str(hero._model.nodes[0].effects).contains("12 HP"),"initial learned damage explained")
	await _press("HeroDevelopmentBack")
	for i: int in 6: await _press("PsiTrain")
	await _press("WorldDevelopment"); await _select_psi()
	hero=app.find_child("HeroDevelopmentScreen",true,false) as Sm2HeroDevelopmentScreen
	t.equal(hero._model.selected.level,2,"own level raised by actual training")
	t.equal(hero._model.selected.effective,7,"own growth plus resonance")
	t.expect(str(hero._model.nodes[0].effects).contains("14 HP") and str(hero._model.nodes[0].effects).contains("Резонанс 10 → +5"),"node explains actual damage and source")
	await _capture("trained.png")
	await _press("HeroDevelopmentBack"); await _press("WorldBattle")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.expect(screen._inspector.text.contains("Резонанс"),"both training tracks in battle inspector")
	await _press("Ability_impulse"); await _motion(Vector2i(4,1))
	t.expect(screen._preview.text.contains("12 (основа) + 2 (развитие) = 14 HP"),"actual forecast explains base plus growth")
	await _capture("forecast.png"); await _cell(Vector2i(4,1),false)
	t.equal(s.runner._session._battle._state.actor(3).combat.hp,46,"mouse cast matches stronger forecast")
	t.equal(s.runner._session._battle._state.development.bodies[1].tracks[PSI.TRACK].earned,270,"mouse gives own skill practice")
	t.equal(s.runner._session._battle._state.development.bodies[1].tracks[GROWTH.RESONANCE].earned,5,"mouse gives own resonance practice")
	t.expect(screen._log.text.contains("Резонанс +5") and screen._log.text.contains("Псионика +20"),"both rewards explained in journal")
	await _capture("cast.png"); await _press("SaveBattleButton"); var saved: String=s.state_hash()
	await _press("BattleMenuButton"); await _press("WorldMenu"); await _press("ContinuePsionicGrowthButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen; s=life.session as Sm2JourneySession
	t.equal(s.state_hash(),saved,"production continue restores growth state")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	await _press("Ability_impulse"); await _motion(Vector2i(4,1))
	t.expect(screen._preview.text.contains("14 HP"),"forecast rebuilt after load")
	# Deterministic injury scenario for the visible new-body flow.
	s=Sm2JourneySession.new(GROWTH.life_content(),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://growth-ui-lives"))
	t.expect(s.new_game().ok,"growth incarnation fixture starts"); PSI.learn(s,t)
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames(); await _fight_to_retreat(s)
	await _press("WorldEndLife"); await _press("WorldConfirmDeath"); await _press("WorldIncarnate8")
	await _press("WorldDevelopment"); await _select_psi()
	hero=app.find_child("HeroDevelopmentScreen",true,false) as Sm2HeroDevelopmentScreen
	t.equal(hero._model.selected.level,0,"new body own skill reset")
	t.equal(hero._model.selected.effective,5,"new body natural resonance baseline")
	t.expect(_button(_id("HeroBuy",PSI.NODE)).disabled,"new body has no unlocked impulse")
	root.size=Vector2i(1280,800); await _frames(); await _capture("new-body.png")
	_finish()
