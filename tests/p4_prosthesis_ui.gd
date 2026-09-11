extends "res://tests/p3_world_ui.gd"
const PROSTHESIS_TEST=preload("res://tests/scenarios/test_p4_prosthesis.gd")
const BODY_TEST=preload("res://tests/scenarios/test_p4_body.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _capture("menu.png")
	await _press("NewProsthesisJourneyButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life!=null,"prosthesis menu opens world")
	if life==null: _finish(); return
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(s.format_id(),Sm2JourneySession.PROSTHESIS_FORMAT,"explicit new session")
	var device: String=s.journey().prostheses.items[0].id
	t.expect(_button(_item_id(device,"install_prosthesis",2)).disabled,"cannot replace healthy hand")
	await _capture("healthy.png")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.expect(_button("Ability_sever_right")!=null,"loss ability in battle UI")
	await _cell(Vector2i(2,1),false); await _cell(Vector2i(3,1),false)
	await _press("Ability_sever_right"); await _motion(Vector2i(4,1))
	t.expect(screen._preview.text.contains("утрата"),"loss forecast differs from temporary trauma")
	await _capture("loss-preview.png"); await _cell(Vector2i(4,1),false)
	var raw: Dictionary=s.runner.capture().session.battle.development.members[0].body
	var body: Sm2ProgressBodyState=Sm2ProgressRules.decode_body(raw,s._content.development.progression()).body
	t.equal(body.tracks["p1:stat.strength"].earned,30,"actual mouse attack awards personal practice")
	await _press("SaveBattleButton"); var saved: String=s.state_hash()
	await _press("BattleMenuButton"); await _press("WorldMenu"); await _press("ContinueProsthesisJourneyButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.equal(life.session.state_hash(),saved,"production save reloads from menu")
	# The following fixture uses actual enemy attacks, not edited body state.
	s=Sm2JourneySession.new(PROSTHESIS_TEST.loss_content(),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://prosthesis-ui-loss"))
	t.expect(s.new_game().ok,"loss UI fixture starts")
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames()
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	await _fight_to_retreat(s)
	t.expect(s.world.hero_id()==2 and s.world.bodies[2].functions.missing.right_hand,"enemy really severs surviving hero hand")
	if s.world.hero_id()!=2 or not s.world.bodies[2].functions.missing.right_hand: _finish(); return
	await _capture("lost-hand.png")
	t.expect(_button("Heal_right_hand").disabled,"UI refuses treatment for lost arm")
	device=s.journey().prostheses.items[0].id
	var alien: String=s.journey().prostheses.items[3].id
	t.expect(_button(_item_id(alien,"install_prosthesis",2)).disabled,"incompatible installation disabled")
	var xp: Dictionary=s.world.bodies[2].progress.to_data(); var hp: int=s.world.bodies[2].hp
	await _press(_item_id(device,"install_prosthesis",2))
	t.expect(s.world.bodies[2].functions.working.right_hand,"mouse installation restores function")
	t.equal(s.world.bodies[2].progress.to_data(),xp,"installation no practice")
	t.equal(s.world.bodies[2].hp,hp,"installation no HP")
	await _capture("installed.png")
	var install_button: Button=_button(_item_id(device,"remove_prosthesis",0))
	var ancestor: Node=install_button.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer: (ancestor as ScrollContainer).ensure_control_visible(install_button); break
		ancestor=ancestor.get_parent()
	await _capture("device-controls.png")
	await _press("WorldSave"); saved=s.state_hash()
	await _press(_item_id(device,"remove_prosthesis",0))
	t.expect(not s.world.bodies[2].functions.working.right_hand,"mouse removal disables missing hand")
	await _press("WorldLoad"); t.equal(s.state_hash(),saved,"disk load restores installed device")
	await _fight_to_retreat(s)
	t.expect(not s.journey().prostheses.item(device).working,"next enemy hit damages same device")
	await _capture("damaged.png")
	await _press(_item_id(device,"repair_prosthesis",0))
	t.expect(s.journey().prostheses.item(device).working and s.world.bodies[2].functions.working.right_hand,"mouse repair restores installed device")
	await _capture("repaired.png")
	await _press("WorldSave")
	await _press("WorldEndLife"); await _press("WorldConfirmDeath"); await _press("WorldIncarnate8")
	t.equal(s.journey().prostheses.item(device).owner_id,"2","device stays at previous corpse")
	t.expect(s.world.bodies[8].functions.prostheses.right_hand.is_empty(),"fresh incarnation has no device")
	await _press(_item_id(device,"remove_prosthesis",0)); await _press(_item_id(device,"transfer_prosthesis",6))
	t.equal(s.journey().prostheses.item(device).owner_id,"6","mouse retrieval puts device in stash")
	await _press("WorldSave")
	root.size=Vector2i(1280,800); await _frames(); await _capture("new-life.png")
	_finish()

func _fight_to_retreat(s: Sm2JourneySession) -> void:
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	for i: int in 80:
		if not s.world.busy(): break
		t.expect(BODY_TEST.treatment_step(s).ok,"real loss/damage and retreat through session")
		screen.runner=s.runner; screen._refresh()
	t.expect(not s.world.busy(),"battle settles in UI fixture")
	await _press("BattleMenuButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen

static func _item_id(id: String,kind: String,target: int) -> String:
	return "JourneyItem%s_%s_%s" % [id,kind,target]
