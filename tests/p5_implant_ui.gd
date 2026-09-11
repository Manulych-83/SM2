extends "res://tests/p5_upgrade_ui.gd"
const IMPLANTS=preload("res://tests/scenarios/test_p5_implants.gd")
func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewImplantButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life!=null,"three paths mode opens")
	if life==null: _finish(); return
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(s.slot_name(),Sm2JourneySession.IMPLANT_SLOT,"separate implant slot")
	t.expect(_button("UpgradeApply_psi_amplifier").disabled,"kit required")
	for suffix: String in ["muscles","psi_amplifier"]:
		await _press("UpgradeCollect_"+suffix); await _press("UpgradeApply_"+suffix)
		t.expect(_button("UpgradeApply_"+suffix).disabled,"repeat installation disabled")
	t.equal(_button("UpgradeApply_psi_amplifier").text,"Установить имплант","implant operation labelled")
	await _capture("implant.png")
	var scroll_parent: Node=_button("UpgradeApply_psi_amplifier").get_parent()
	while scroll_parent!=null:
		if scroll_parent is ScrollContainer:
			(scroll_parent as ScrollContainer).ensure_control_visible(_button("UpgradeApply_psi_amplifier")); await _frames(); break
		scroll_parent=scroll_parent.get_parent()
	await _capture("implant-controls.png")
	await _press("WorldDevelopment"); await _select_resonance()
	var hero: Sm2HeroDevelopmentScreen=app.find_child("HeroDevelopmentScreen",true,false) as Sm2HeroDevelopmentScreen
	t.equal(hero._model.selected.level,10,"own Resonance10 shown")
	t.equal(hero._model.selected.effective,12,"effective Resonance12 shown")
	t.equal(hero._model.selected.earned,0,"no phantom practice")
	await _capture("resonance.png"); await _press("HeroDevelopmentBack")
	for i: int in 8: await _press("PsiTrain")
	await _press("WorldDevelopment"); await _select_psi()
	await _press(_id("HeroBuy",PSI.NODE)); await _press(_id("HeroBuy",SHIELD.NODE))
	hero=app.find_child("HeroDevelopmentScreen",true,false) as Sm2HeroDevelopmentScreen
	for node: Dictionary in hero._model.nodes:
		if node.id in [PSI.NODE,SHIELD.NODE]: t.expect(str(node.effects).contains("Пси-усилитель: +1"),"learned node cost source")
	await _press("HeroDevelopmentBack"); var camp: Dictionary=s.capture()
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.expect(screen._inspector.text.contains("Мощь: свой 10 +2") and screen._inspector.text.contains("Резонанс: свой 10 +2"),"battle distinguishes both paths")
	var button: Button=_button("Ability_shield"); var rect: Rect2=button.get_global_rect()
	var mouse: InputEventMouseMotion=InputEventMouseMotion.new(); mouse.position=rect.get_center(); root.push_input(mouse,true); await _frames()
	t.expect(screen._preview.text.contains("+1 концентрации") and screen._preview.text.contains("7 концентрации"),"shield forecast explains actual cost")
	await _capture("shield-forecast.png"); await _press("Ability_shield")
	t.equal(s.runner._session._battle._state.actor(1).barrier.remaining,20,"actual shield20")
	t.equal(s.runner._session._battle._state.mana[1].current,5,"focus after shield5")
	t.expect(_button("Ability_shield").disabled,"not enough focus for another shield")
	await _capture("combined.png"); await _press("SaveBattleButton"); var saved: String=s.state_hash()
	await _press("BattleMenuButton"); await _press("WorldMenu"); await _press("ContinueImplantButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen; s=life.session as Sm2JourneySession
	t.equal(s.state_hash(),saved,"menu reload preserves all three paths")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	await _press("Ability_impulse"); await _motion(Vector2i(4,1)); await _cell(Vector2i(4,1),false)
	t.equal(s.state_hash(),saved,"mouse attempt cannot cast with only5 focus")
	t.expect(screen._preview.text.contains("концентрации") or screen._notice.text.contains("концентрации"),"insufficient resource explained")
	# Separate valid camp branch permits observing the actual enhanced impulse.
	t.expect(s.restore(camp).ok,"camp branch restores")
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames()
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	await _press("Ability_impulse"); await _motion(Vector2i(4,1))
	t.expect(screen._preview.text.contains("+1 концентрации"),"impulse forecast explains implant cost")
	root.size=Vector2i(1280,800); await _frames(); await _capture("impulse-forecast.png")
	await _cell(Vector2i(4,1),false)
	t.equal(s.runner._session._battle._state.actor(3).combat.hp,46,"mouse impulse14")
	t.equal(s.runner._session._battle._state.mana[1].current,5,"mouse impulse pays7")
	s=Sm2JourneySession.new(IMPLANTS.life_content(),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://implant-ui-lives"))
	t.expect(s.new_game().ok,"incarnation scenario starts"); IMPLANTS.install(s,t)
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames(); await _fight_to_retreat(s)
	await _press("WorldEndLife"); await _press("WorldConfirmDeath"); await _press("WorldIncarnate8")
	for suffix: String in ["muscles","psi_amplifier"]:
		t.expect((app.find_child("UpgradeStatus_"+suffix,true,false) as Label).text.contains("Не установлено"),"new body missing old upgrade")
		t.expect(_button("UpgradeCollect_"+suffix).disabled and _button("UpgradeApply_"+suffix).disabled,"supply not returned")
	await _press("WorldDevelopment"); await _select_resonance()
	hero=app.find_child("HeroDevelopmentScreen",true,false) as Sm2HeroDevelopmentScreen
	t.equal(hero._model.selected.effective,10,"clean body natural Resonance")
	await _capture("new-body.png"); _finish()
func _select_resonance() -> void:
	var field: LineEdit=app.find_child("HeroTrackFilter",true,false) as LineEdit
	field.grab_focus(); field.select_all()
	var erase: InputEventKey=InputEventKey.new(); erase.keycode=KEY_BACKSPACE; erase.pressed=true; root.push_input(erase,true)
	for character: String in "Резонанс":
		var event: InputEventKey=InputEventKey.new(); event.unicode=character.unicode_at(0); event.pressed=true; root.push_input(event,true)
	await _frames(); await _press(_id("HeroTrack",IMPLANTS.RES))
