extends "res://tests/p4_prosthesis_ui.gd"
const PSI=preload("res://tests/scenarios/test_p5_psionics.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewPsionicButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life!=null,"new psionic mode opens from menu")
	if life==null: _finish(); return
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(s.slot_name(),Sm2JourneySession.PSIONIC_SLOT,"production independent slot")
	await _press("WorldDevelopment"); await _select_psi()
	t.expect(_button(_id("HeroBuy",PSI.NODE)).disabled,"no initial psi node")
	await _press("HeroDevelopmentBack")
	for i: int in 4: await _press("PsiTrain")
	t.equal(s.world.bodies[2].progress.tracks[PSI.TRACK].earned,100,"four real training clicks")
	await _press("WorldDevelopment"); await _select_psi()
	t.expect(not _button(_id("HeroBuy",PSI.NODE)).disabled,"own training makes node available")
	await _capture("unlock.png")
	await _press(_id("HeroBuy",PSI.NODE))
	t.equal(s.world.bodies[2].progress.tracks[PSI.TRACK].spent,100,"real node purchase spends own XP")
	await _press("HeroDevelopmentBack"); await _press("WorldBattle")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.expect(_button("Ability_impulse")!=null,"learned impulse appears as battle action")
	t.expect(screen._inspector.text.contains("Концентрация"),"resource visible in hero inspector")
	await _press("Ability_impulse"); await _motion(Vector2i(4,1))
	t.expect(screen._preview.text.contains("Концентрация: 6") and screen._preview.text.contains("12 HP"),"forecast explains focus and exact damage")
	t.expect(not screen._inspector.text.contains("Мана"),"enemy inspector has no legacy magic resource")
	await _capture("forecast.png")
	await _cell(Vector2i(4,1),false)
	t.equal(s.runner._session._battle._state.mana[1].current,6,"mouse cast spends concentration")
	t.equal(s.runner._session._battle._state.development.bodies[1].tracks[PSI.TRACK].earned,120,"mouse cast gives psi practice")
	t.expect(screen._log.text.contains("концентрации") and screen._log.text.contains("Псионика"),"journal explains cost and practice")
	await _capture("cast.png")
	await _press("SaveBattleButton"); var saved: String=s.state_hash()
	await _press("BattleMenuButton"); await _press("WorldMenu"); await _press("ContinuePsionicButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen; s=life.session as Sm2JourneySession
	t.equal(s.state_hash(),saved,"menu continuation restores exact live encounter")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.expect(screen._inspector.text.contains("6/12"),"loaded focus shown without recovery")
	# Separate injury scenario exercises the visible incarnation flow reliably.
	s=Sm2JourneySession.new(PSI.life_content(),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://psi-ui-lives"))
	t.expect(s.new_game().ok,"incarnation UI fixture starts"); PSI.learn(s,t)
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames()
	await _fight_to_retreat(s)
	t.equal(s.world.hero_id(),2,"real fight survivor for incarnation UI")
	await _press("WorldEndLife"); await _press("WorldConfirmDeath"); await _press("WorldIncarnate8")
	await _press("WorldDevelopment"); await _select_psi()
	t.expect(_button(_id("HeroBuy",PSI.NODE)).disabled,"new body has no inherited impulse")
	t.expect((app.find_child("HeroTrackSummary",true,false) as Label).text.contains("заработано 0"),"new body practice visibly zero")
	await _capture("new-body.png")
	await _press("HeroDevelopmentBack")
	for i: int in 4: await _press("PsiTrain")
	await _press("WorldDevelopment"); await _select_psi(); await _press(_id("HeroBuy",PSI.NODE))
	await _press("HeroDevelopmentBack"); await _press("WorldBattle")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.expect(_button("Ability_impulse")!=null,"retrained unarmed incarnation can cast")
	root.size=Vector2i(1280,800); await _frames(); await _capture("new-body-battle.png")
	_finish()

static func _id(prefix: String,id: String) -> String: return Sm2HeroDevelopmentScreen.control_id(prefix,id)
func _select_psi() -> void:
	var field: LineEdit=app.find_child("HeroTrackFilter",true,false) as LineEdit
	field.grab_focus(); field.select_all()
	var erase: InputEventKey=InputEventKey.new(); erase.keycode=KEY_BACKSPACE; erase.pressed=true; root.push_input(erase,true)
	for character: String in "Псионика":
		var event: InputEventKey=InputEventKey.new(); event.unicode=character.unicode_at(0); event.pressed=true; root.push_input(event,true)
	await _frames(); await _press(_id("HeroTrack",PSI.TRACK))
