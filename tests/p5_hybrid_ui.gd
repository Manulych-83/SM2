extends "res://tests/p4_hero_screen_ui.gd"
const HYBRID=preload("res://tests/scenarios/test_p5_hybrids.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewHybridButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.equal((life.session as Sm2JourneySession).slot_name(),Sm2JourneySession.HYBRID_SLOT,"primary new game opens hybrid profile")
	await _press("WorldDevelopment"); _find_screen(); await _press(_id("HeroTrack",HYBRID.MELEE)); _find_screen()
	t.expect(_button(_id("HeroBuy",HYBRID.NODE)).disabled,"new body cannot buy hybrid immediately")
	var s: Sm2JourneySession=HYBRID.prepared(t,app.get("_hybrid_store"))
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames()
	await _press("WorldDevelopment"); _find_screen(); await _press(_id("HeroTrack",HYBRID.MELEE)); _find_screen()
	var node: Dictionary={}
	for row: Dictionary in hero_screen._model.nodes:
		if row.id==HYBRID.NODE: node=row
	t.expect(node.allowed and str(node.effects).contains("концентрации"),"own practice enables explained hybrid")
	await _press(_id("HeroCrossRequirement",HYBRID.NODE+HYBRID.TRACK)); _find_screen()
	t.equal(hero_screen.selected_id,HYBRID.TRACK,"cross requirement opens psi skill")
	await _press(_id("HeroTrack",HYBRID.MELEE)); _find_screen()
	hero_screen._details.ensure_control_visible(_button(_id("HeroBuy",HYBRID.NODE))); await _frames(); await _capture("hybrid-node.png")
	await _press(_id("HeroBuy",HYBRID.NODE)); _find_screen()
	var hero: int=s.world.hero_id()
	t.equal([s.world.bodies[hero].progress.tracks[HYBRID.MELEE].spent,s.world.bodies[hero].progress.tracks[HYBRID.TRACK].spent],[70,90],"real UI purchase pays both prices")
	await _press("HeroDevelopmentBack"); await _press("WorldBattle")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	var victim: int=0
	for i: int in 40:
		if not s.world.busy(): break
		if int(s.runner.view().active_actor_id)==1:
			for id: int in [3,4]:
				if s.runner.preview(HYBRID.PSI.command(s,"use_ability",HYBRID.ID,id)).allowed: victim=id; break
		if victim>0: break
		t.expect(HYBRID.PSI.JOURNEY.advance(s).ok,"approach through normal game commands")
		screen.runner=s.runner; screen._refresh()
	t.expect(victim>0,"hero reaches melee target")
	if victim==0: _finish(); return
	screen.runner=s.runner; screen._refresh(); await _frames()
	t.expect(_button("Ability_psionic_strike")!=null,"learned hybrid in action list")
	await _press("Ability_psionic_strike")
	var target: Dictionary=screen._actor(victim); var cell: Vector2i=Vector2i(int(target.q),int(target.r))
	var action: Sm2Command=HYBRID.PSI.command(s,"use_ability",HYBRID.ID,victim)
	var forecast: Dictionary=s.runner.preview(action)
	await _motion(cell)
	t.expect(screen._preview.text.contains("Концентрация: "+str(forecast.mana_cost)) and screen._preview.text.contains("Промах"),"forecast shows focus and miss rule")
	t.expect(screen._preview.text.contains("пси-часть") and screen._preview.text.contains("включена"),"combined HP forecast explains component")
	await _capture("hybrid-forecast.png")
	var battle: Sm2TacticalBattle=s.runner._session._battle
	var previous_focus: int=battle._state.mana[1].current
	var previous_melee: int=battle._state.development.bodies[1].tracks[HYBRID.MELEE].earned
	var previous_psi: int=battle._state.development.bodies[1].tracks[HYBRID.TRACK].earned
	await _cell(cell,false)
	battle=s.runner._session._battle
	t.equal(battle._state.mana[1].current,previous_focus-int(forecast.mana_cost),"click spends focus exactly once")
	t.equal(battle._state.development.bodies[1].tracks[HYBRID.MELEE].earned,previous_melee+20,"click gives melee practice")
	t.equal(battle._state.development.bodies[1].tracks[HYBRID.TRACK].earned,previous_psi+20,"click gives psi practice")
	t.expect(screen._log.text.contains("Псионический удар") and screen._log.text.contains("концентрации"),"journal names hybrid and cost")
	await _press("SaveBattleButton"); var saved: String=s.state_hash()
	await _press("BattleMenuButton"); await _press("WorldMenu"); await _press("ContinueHybridButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen; s=life.session as Sm2JourneySession
	t.equal(s.state_hash(),saved,"main Continue restores hybrid battle exactly")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	root.size=Vector2i(1280,800); await _frames(); await _capture("hybrid-restored.png")
	HYBRID.PSI.JOURNEY.finish(s,t); screen.runner=s.runner; screen._refresh(); await _frames()
	await _press("BattleMenuButton")
	if s.world.hero_id()>0: await _press("WorldEndLife"); await _press("WorldConfirmDeath")
	await _press("WorldIncarnate8" if hero!=8 else "WorldIncarnate9")
	await _press("WorldDevelopment"); _find_screen(); await _press(_id("HeroTrack",HYBRID.MELEE)); _find_screen()
	t.expect(_button(_id("HeroBuy",HYBRID.NODE)).disabled,"new embodiment has no hybrid node")
	t.equal(s.world.bodies[s.world.hero_id()].progress.tracks[HYBRID.TRACK].earned,0,"new body must practice psionics again")
	_finish()
