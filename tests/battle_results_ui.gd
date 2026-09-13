extends "res://tests/display_ui.gd"
const RESULTS: GDScript=preload("res://tests/scenarios/test_battle_results.gd")
func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output); display_report={"captures":[]}
	await set_resolution(Vector2i(2560,1440))
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	var session: Sm2CheckpointSession=preload("res://tests/scenarios/test_checkpoint.gd").make("user://after-battle-ui")
	t.expect(session.new_game().ok,"main campaign UI starts")
	session.world.bodies[2].progress.tracks["p1:skill.melee"].earned=99
	(session.world.bodies[4].progress as Sm2CompanionProgress).earned=99
	t.expect(session.act(session.command("travel",0,"ruins")).ok and session.act(session.command("start_battle")).ok,"main campaign UI starts deferred encounter")
	t.expect(session.runner.state_copy().development.deferred_growth,"UI tests current after-battle policy")
	app._life=session; app._page="life_battle"; app._redraw_page(); await _frames()
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	for index: int in 500:
		if not session.world.busy(): break
		t.expect(RESULTS.step(session).ok,"real battle command")
		screen.runner=session.runner; screen._refresh()
	await _frames()
	t.expect(screen._results!=null,"committed battle automatically opens results")
	t.expect(screen.find_child("GrowthTable2",true,false) is GridContainer,"hero XP and before/after levels are shown in a table")
	t.expect(session.runner.state_copy().development.pending.is_empty(),"automatic result appears after growth application")
	var before: String=session.state_hash(); var frozen: Array=screen._results.view.party.duplicate(true)
	for dimensions: Vector2i in [Vector2i(2560,1440),Vector2i(1920,1080),Vector2i(1280,720),Vector2i(1280,800)]:
		await set_resolution(dimensions)
		for id: String in ["GrowthTable2","GrowthTable4"]:
			var table: GridContainer=screen.find_child(id,true,false) as GridContainer
			t.expect(table!=null,"growth table present at "+str(dimensions))
			if table!=null:
				for index: int in 4:
					var heading: Label=table.get_child(index) as Label
					t.expect(heading.get_line_count()==1 and heading.size.x>=heading.get_minimum_size().x,"numeric column header stays readable")
		await _capture("results-%s-%s.png" % [dimensions.x,dimensions.y])
	await _press("ResultsField")
	t.expect(screen._results==null,"field inspection closes summary")
	await _press("HudDetails")
	t.expect(screen._results!=null,"utility button reopens results")
	await _press("HudJournal")
	t.expect(screen._results==null and screen.hud.context_panel.visible,"journal opens visibly from results")
	await _press("HudDetails")
	t.equal(session.state_hash(),before,"opening and closing results is read only")
	await _press("SaveBattleButton")
	t.equal(session.state_hash(),before,"saving result cannot award XP again")
	await _press("ResultsBody")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var workspace: Sm2SurvivalWorkspace=app.find_child("SurvivalWorkspace",true,false) as Sm2SurvivalWorkspace
	t.expect(workspace!=null and int(workspace.ui.tab)==0,"results opens actual anatomy workspace")
	t.equal(session.state_hash(),before,"opening anatomy is read only")
	await _press("WorkspaceBack"); await _press("CampBattleResults")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	t.equal(screen._results.view.party,frozen,"camp reopens same settled facts")
	await _press("ResultsLoot")
	workspace=app.find_child("SurvivalWorkspace",true,false) as Sm2SurvivalWorkspace
	t.expect(workspace!=null and int(workspace.ui.tab)==1 and int(workspace.ui.scope)==0,"loot opens all nearby actual items")
	t.equal(session.state_hash(),before,"opening loot cannot grant or collect items")
	await _press("WorkspaceBack"); await _press("WorldLoad"); await _press("CampBattleResults")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	t.equal(screen._results.view.party,frozen,"saved campaign reopens stable results")
	t.equal(session.state_hash(),before,"reloading and opening cannot repeat settlement")
	await _press("BattleMenuButton")
	t.expect(app.find_child("LifeScreen",true,false)!=null,"top menu remains clickable above results")
	await set_resolution(Vector2i(2560,1440))
	var wounded: Sm2JourneySession=RESULTS.started(t,true); RESULTS.finish(t,wounded,true)
	app._life=wounded; app._page="life_battle"; app._redraw_page(); await _frames()
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	await _capture("retreat-results.png")
	var old_button: Button=_button("ResultsBody")
	t.expect(wounded.act(wounded.command("travel",0,"camp")).ok,"world changes after displayed result")
	before=wounded.state_hash(); old_button.pressed.emit(); await _frames()
	t.equal(wounded.state_hash(),before,"stale result navigation cannot change world")
	t.expect(app.find_child("SurvivalWorkspace",true,false)==null,"stale context does not open wrong body")
	_finish()
