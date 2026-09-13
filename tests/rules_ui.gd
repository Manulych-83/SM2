extends "res://tests/display_ui.gd"

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	display_report = {"captures":[]}
	await set_resolution(Vector2i(2560,1440))
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(app); await _frames()
	var session: Sm2CheckpointSession=preload("res://tests/scenarios/test_checkpoint.gd").make("user://rules-ui")
	t.expect(session.new_game().ok,"main checkpoint campaign starts")
	# Prepared initial practice is a UI fixture, not a reward or a change to learning rules.
	# Psionic training alone deliberately does not grant a melee bonus.
	session.world.bodies[2].progress.tracks["p1:skill.melee"].earned=100
	t.expect(session.act(session.command("travel",0,"ruins")).ok and session.act(session.command("start_battle")).ok,"prepared hero enters real encounter")
	app._life=session; app._page="life_battle"; app._redraw_page(); await _frames()
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	screen.auto_advance=false
	var before: String=session.state_hash()
	for dimensions: Vector2i in [Vector2i(2560,1440),Vector2i(1280,720)]:
		await set_resolution(dimensions)
		await _press("HudTurn_1")
		t.expect(screen._inspector.text.contains("Расчёт боевых параметров"),"real details expose modifier trace")
		var stat: Dictionary = screen._actor(1).stats.melee_skill
		t.expect(screen._inspector.text.contains(Sm2BattleText.stat_calculation("melee_skill",stat)),"screen renders exact domain explanation")
		t.expect(screen._inspector.text.contains("Развитие:"),"prepared practiced hero shows growth source")
		var scroll: VScrollBar=screen._inspector.get_v_scroll_bar()
		scroll.value=scroll.max_value
		await _frames(); await _capture("rules-%s.png" % dimensions.x)
		t.expect(screen._inspector.is_visible_in_tree(),"details remain visible")
		t.expect(screen._inspector.get_global_rect().end.x <= root.get_visible_rect().size.x+1,"details stay inside logical screen")
		await _press("HudTurn_2")
		t.expect(screen._inspector.text.contains("Спутник"),"inspection switches to companion")
		t.equal(session.state_hash(),before,"view navigation and resizing do not advance battle")
	await _press("SaveBattleButton"); await _press("LoadBattleButton")
	t.equal(session.state_hash(),before,"UI save/load preserves state")
	await _press("HudTurn_1")
	t.expect(screen._inspector.text.contains("Расчёт боевых параметров"),"explanation is reconstructed after load")
	_finish()
