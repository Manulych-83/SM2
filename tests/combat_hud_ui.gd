extends "res://tests/battle_feedback_ui.gd"

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1280,800)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewSurvivalTissuesButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	SHIELD_TEST.learn(s,t); life.redraw(); await _frames()
	await _press("Travel_ruins"); await _press("WorldBattle")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.expect(screen.hud!=null,"production uses dedicated combat HUD")
	if screen.hud==null: _finish(); return
	var before: String=s.state_hash()
	await _press("HudTurn_2")
	t.equal(screen._active,1,"queue click does not seize companion's turn")
	t.expect(screen.hud.person.text.contains("Спутник"),"queue click displays companion card")
	t.equal(s.state_hash(),before,"queue inspection preserves world")
	await _press("HudTurn_1")
	t.expect(_button("Ability_sword_strike").disabled,"out of range attack disabled")
	t.expect(_button("Ability_sword_strike").text.contains("4 ОД"),"cost visible before a target is reachable")
	await hover_button("Ability_sword_strike")
	t.expect(screen._preview.text.contains("Цель вне дальности"),"disabled hover explains domain refusal")
	t.equal(s.state_hash(),before,"hover does not simulate action")
	for dimensions: Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=dimensions; await _frames(); await _capture("hud-%s.png" % dimensions.x)
		for id: String in ["SaveBattleButton","EndTurnButton","HudTurn_1"]: t.expect(_button(id).is_visible_in_tree(),"persistent control visible "+id)
	root.size=Vector2i(1280,800); await _frames(); await _press("SaveBattleButton")
	# An action from a stale frame is refused even when kept alive by an external caller.
	var old: Dictionary={}
	for row: Dictionary in screen.hud.action_rows:
		if row.id=="p5:ability.shield": old=row.duplicate(true)
	t.expect(s.attack(screen._command("move","",0,Vector2i(2,1))).accepted,"external legal move changes revision")
	before=s.state_hash(); screen.hud.activate(old)
	t.equal(s.state_hash(),before,"stale action cannot cast using refreshed context")
	t.expect(screen._notice.text.contains("Выберите действие заново"),"stale action explains refresh")
	await _press("LoadBattleButton"); before=s.state_hash()
	await _press("Ability_impulse"); await _motion(Vector2i(4,1))
	var check: Dictionary=s.runner.preview(screen._command("use_ability","p5:ability.impulse",3))
	t.expect(check.allowed,"production impulse target legal")
	t.expect(screen._preview.text.contains("Повреждение тканей: %s" % check.hp_loss),"forecast uses actual tissue damage parameter")
	t.expect(screen._preview.text.contains("6 конц."),"forecast includes shared cost")
	t.equal(s.state_hash(),before,"target forecast read-only")
	await _capture("forecast.png"); await _cell(Vector2i(4,1),false)
	t.equal(screen._actor(1).mana,6,"selected ability executes one paid action")
	await _press("Ability_shield")
	t.equal(screen._actor(1).barrier.remaining,18,"self-target card executes shield")
	t.expect(_button("Ability_impulse").disabled,"resource exhaustion disables ability")
	await hover_button("Ability_impulse"); t.expect(screen._preview.text.contains("Не хватает"),"exhausted ability explains refusal")
	# Tabs share the same selected actor and never issue a command.
	before=s.state_hash()
	for index: int in [1,2,0]:
		var bar: TabBar=screen.hud.tabs.get_tab_bar(); await _mouse(bar.global_position+bar.get_tab_rect(index).get_center(),false)
		t.equal(screen.hud.tabs.current_tab,index,"mouse changes information tab")
		if index==2:
			await _capture("details-1280.png")
			root.size=Vector2i(1000,700); await _frames(); await _capture("details-1000.png")
			root.size=Vector2i(1280,800); await _frames()
	t.equal(s.state_hash(),before,"tabs preserve game")
	await _press("LoadBattleButton")
	# Real incoming attacks create wounds; the new action panel sends the old bandage command.
	var treatment: Dictionary={}
	for index: int in 120:
		for row: Dictionary in screen.hud.action_rows:
			if row.kind=="bandage" and row.allowed: treatment=row; break
		if not treatment.is_empty() or screen.state.finished: break
		if screen._player_turn(): screen._execute(screen._command("end_turn"))
		else: screen.auto_advance=true; screen._delay=0; screen._process(0.01); screen.auto_advance=false
		screen.board.clear_motion()
	t.expect(not treatment.is_empty(),"actual fight exposes a usable bandage card")
	if not treatment.is_empty():
		await hover_button(treatment.button); await _capture("bandage.png")
		await _press(treatment.button)
		for wound: Dictionary in screen._actor(int(treatment.target)).anatomy.wounds:
			if str(wound.id)==str(treatment.id): t.equal(wound.rate,0,"mouse bandages exact chosen wound")
	await _press("SaveBattleButton"); before=s.state_hash(); await _press("LoadBattleButton")
	t.equal(s.state_hash(),before,"HUD save/load exact after treatment")
	_finish()

func hover_button(id: String) -> void:
	var value: Button=_button(id); t.expect(value!=null,"hover target exists "+id)
	if value==null: return
	var ancestor: Node=value.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer: (ancestor as ScrollContainer).ensure_control_visible(value); await _frames()
		ancestor=ancestor.get_parent()
	var event: InputEventMouseMotion=InputEventMouseMotion.new(); event.position=value.get_global_rect().get_center(); root.push_input(event,true); await _frames()
