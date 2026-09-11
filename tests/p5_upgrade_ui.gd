extends "res://tests/p5_psionic_ui.gd"
const UPGRADES=preload("res://tests/scenarios/test_p5_upgrades.gd")
const SHIELD=preload("res://tests/scenarios/test_p5_shield.gd")
func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewUpgradeButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life!=null,"genetics mode opens")
	if life==null: _finish(); return
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(s.slot_name(),Sm2JourneySession.UPGRADE_SLOT,"separate upgrade slot")
	t.expect(_button("UpgradeApply_muscles").disabled,"drug required")
	await _press("UpgradeCollect_muscles"); await _press("UpgradeApply_muscles")
	t.expect(_button("UpgradeCollect_muscles").disabled and _button("UpgradeApply_muscles").disabled,"cache and repeat application disabled")
	t.expect((app.find_child("UpgradeStatus_muscles",true,false) as Label).text.contains("Действует"),"active upgrade shown")
	await _capture("camp.png")
	await _press("WorldDevelopment"); await _select_power()
	var hero: Sm2HeroDevelopmentScreen=app.find_child("HeroDevelopmentScreen",true,false) as Sm2HeroDevelopmentScreen
	t.equal(hero._model.selected.level,10,"own power 10 shown")
	t.equal(hero._model.selected.effective,12,"effective power 12 shown")
	t.expect(_button(_id("HeroBuy","p1:node.strength_1")).disabled,"enhancement does not unlock own-level node")
	await _capture("power.png"); await _press("HeroDevelopmentBack")
	for i: int in 8: await _press("PsiTrain")
	await _press("WorldDevelopment"); await _select_psi()
	await _press(_id("HeroBuy",PSI.NODE)); await _press(_id("HeroBuy",SHIELD.NODE)); await _press("HeroDevelopmentBack")
	var camp: Dictionary=s.capture()
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.expect(screen._inspector.text.contains("Мощь: свой 10 +2 улучшение = 12"),"battle shows own power and improvement")
	await _press("Ability_shield")
	t.equal(s.runner._session._battle._state.actor(1).barrier.remaining,18,"enhanced hero casts shield")
	await _capture("combined.png")
	await _press("SaveBattleButton"); var saved: String=s.state_hash()
	await _press("BattleMenuButton"); await _press("WorldMenu"); await _press("ContinueUpgradeButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen; s=life.session as Sm2JourneySession
	t.equal(s.state_hash(),saved,"menu continuation restores genetic upgrade and shield")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	await _press("Ability_impulse"); await _motion(Vector2i(4,1)); await _cell(Vector2i(4,1),false)
	t.equal(s.runner._session._battle._state.actor(3).combat.hp,48,"genetics leaves impulse at12")
	# Restore a valid camp branch to inspect and execute a physical strike by mouse.
	t.expect(s.restore(camp).ok,"physical UI camp branch restores")
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames()
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	await _cell(Vector2i(2,1),false); await _frames(); await _cell(Vector2i(3,1),false); await _frames()
	await _press("Ability_sword_strike"); await _motion(Vector2i(4,1))
	t.expect(screen._preview.text.contains("+2 усталости"),"physical preview explains penalty")
	var command: Sm2Command=PSI.command(s,"use_ability","m2:ability.sword_strike",3)
	var preview: Dictionary=s.runner.preview(command); t.expect(preview.allowed,"mouse strike legal")
	var fatigue: int=s.runner._session._battle._state.actor(1).spatial.fatigue
	root.size=Vector2i(1280,800); await _frames(); await _capture("physical-forecast.png")
	await _cell(Vector2i(4,1),false)
	t.equal(s.runner._session._battle._state.actor(1).spatial.fatigue,fatigue+int(preview.fatigue_cost),"mouse physical strike pays displayed fatigue")
	# Real injury, retreat and incarnation through existing controls.
	s=Sm2JourneySession.new(UPGRADES.life_content(),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://upgrade-ui-lives"))
	t.expect(s.new_game().ok,"incarnation scenario starts"); UPGRADES.install(s,t)
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames(); await _fight_to_retreat(s)
	await _press("WorldEndLife"); await _press("WorldConfirmDeath"); await _press("WorldIncarnate8")
	t.expect((app.find_child("UpgradeStatus_muscles",true,false) as Label).text.contains("Не установлено"),"new body no modification")
	t.expect(_button("UpgradeCollect_muscles").disabled and _button("UpgradeApply_muscles").disabled,"world retains consumed dose")
	await _press("WorldDevelopment"); await _select_power()
	hero=app.find_child("HeroDevelopmentScreen",true,false) as Sm2HeroDevelopmentScreen
	t.equal(hero._model.selected.effective,10,"new body natural power")
	await _capture("new-body.png"); _finish()

func _select_power() -> void:
	var field: LineEdit=app.find_child("HeroTrackFilter",true,false) as LineEdit
	field.grab_focus(); field.select_all()
	var erase: InputEventKey=InputEventKey.new(); erase.keycode=KEY_BACKSPACE; erase.pressed=true; root.push_input(erase,true)
	for character: String in "Мощь":
		var event: InputEventKey=InputEventKey.new(); event.unicode=character.unicode_at(0); event.pressed=true; root.push_input(event,true)
	await _frames(); await _press(_id("HeroTrack",UPGRADES.POWER))
