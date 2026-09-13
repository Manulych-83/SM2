extends "res://tests/display_ui.gd"

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output); display_report={"captures":[]}
	await set_resolution(Vector2i(2560,1440))
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(app); await _frames()
	await _press("NewSurvivalTissuesButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var session: Sm2CheckpointSession=life.session as Sm2CheckpointSession
	t.expect(session!=null and session.journey().world_creatures!=null,"normal New Game uses persistent templates")
	await _press("Travel_ruins"); await _press("WorldBattle")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.equal(screen._actor(3).display_name,"Страж руин","template name in actual battle UI")
	t.expect(session.runner.state_copy().actor(3).anatomy!=null,"full enemy anatomy behind UI")
	await _capture("main-battle-2560.png")
	await set_resolution(Vector2i(1280,720)); await _capture("main-battle-1280.png")
	await _press("SaveBattleButton")
	var saved: String=session.state_hash()
	await _press("BattleMenuButton"); await _press("WorldMenu")
	await _press("ContinueSurvivalTissuesButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	session=life.session as Sm2CheckpointSession
	t.equal(session.state_hash(),saved,"real menu continuation preserves active template encounter")
	await _press("WorldBattle")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.equal(screen._actor(3).display_name,"Страж руин","template name restored after loading")
	t.expect(session.runner.state_copy().actor(3).anatomy!=null,"anatomy restored after loading")
	_finish()
