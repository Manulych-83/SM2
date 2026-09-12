extends "res://tests/m3_ui.gd"
var life: Sm2LifeScreen
const Fixture=preload("res://tests/scenarios/test_p3_world.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _capture("menu.png")
	await _press("NewWorldButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life!=null,"P3 world opens from menu"); if life==null: _finish(); return
	await _capture("camp-before.png")
	await _press("WorldDeposit"); t.equal(life.session.world.item_owner,6,"UI places unique item in stash")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	t.expect(screen!=null,"same tactical screen opens for world encounter"); if screen==null: _finish(); return
	screen.auto_advance=false
	await _capture("battle.png")
	for index: int in 200:
		if screen.state.finished: break
		if screen._player_turn():
			var decision: Dictionary=screen.runner._session.ai_decision(screen.life_session._profile)
			t.expect(decision.ok,"legal player action chosen for UI exercise")
			if not decision.ok: break
			t.expect(screen._execute(decision.command).accepted,"world gateway accepts normal player action")
		else:
			screen.auto_advance=true; screen._delay=0; screen._process(0.01); screen.auto_advance=false
		if index==9:
			await _press("SaveBattleButton"); var before: String=screen.life_session.state_hash()
			await _press("LoadBattleButton"); t.equal(screen.life_session.state_hash(),before,"battle screen saves and loads whole world")
	t.expect(screen.state.finished,"world fight reaches outcome through UI gateway")
	t.expect(screen.life_session.view().battle_applied,"outcome applied to world before leaving field")
	await _press("BattleMenuButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life.session.world.bodies[2].alive,"selected example keeps hero alive")
	for index: int in 4: await _press("WorldPractice")
	await _press("WorldBuy_strength_1")
	await _capture("developed-1000.png")
	root.size=Vector2i(1280,800); await _frames(); await _capture("developed-1280.png")
	var old: Dictionary=life.session.world.bodies[2].to_data()
	await _press("WorldEndLife")
	var dialog: Control=app.find_child("WorldDeathDialog",true,false) as Control
	t.expect(dialog!=null,"explicit end-life action explains result")
	if dialog==null: _finish(); return
	await _capture("confirm-death.png")
	await _press("WorldCancelDeath")
	t.equal(life.session.world.hero_id(),2,"cancelling keeps current life")
	await _press("WorldEndLife"); await _press("WorldConfirmDeath")
	t.equal(life.session.world.hero_id(),0,"death leaves Soul without body")
	var enhanced: Button=_button("WorldIncarnate9")
	t.expect(enhanced!=null and enhanced.disabled,"enhanced corpse visually unavailable")
	if enhanced==null: _finish(); return
	await _capture("soul.png")
	await _press("WorldSave"); await _press("WorldLoad")
	t.equal(life.session.world.hero_id(),0,"load does not resurrect")
	await _press("WorldIncarnate8")
	t.equal(life.session.world.hero_id(),8,"UI incarnates in prepared human")
	t.equal(life.session.world.bodies[2].to_data(),old.merged({"hp":0,"alive":false,"death_cause":"fixture"},true),"old developed body preserved")
	t.equal(life.session.world.bodies[8].progress.tracks["p1:stat.strength"].earned,0,"new carrier starts with no old XP")
	t.equal(life.session.world.item_owner,6,"stash survived UI life cycle")
	await _capture("new-life.png")
	await _press("WorldTake"); await _press("WorldPractice")
	await _press("WorldSave"); var saved: String=life.session.state_hash()
	await _press("WorldMenu"); await _press("ContinueWorldButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.equal(life.session.state_hash(),saved,"fresh menu session restores new life and world exactly")
	root.size=Vector2i(1000,700); await _frames(); await _capture("restored-1000.png")
	_finish()

func _press(id: String) -> void:
	var button: Button=_button(id)
	if button!=null:
		var parent: Node=button.get_parent()
		while parent!=null:
			if parent is ScrollContainer:
				(parent as ScrollContainer).ensure_control_visible(button); await _frames(); break
			parent=parent.get_parent()
	await super._press(id)

func _capture(filename: String) -> void:
	await _frames()
	# Off-screen scroll contents are intentionally clipped; headers and scroll bounds must fit.
	for node: Node in app.find_children("*","Control",true,false):
		var parent: Node=node.get_parent(); var clipped: bool=false
		while parent!=null:
			if parent is ScrollContainer: clipped=true; break
			parent=parent.get_parent()
		if not clipped and (node as Control).is_visible_in_tree() and (node is Label or node is Button or node is ScrollContainer):
			t.expect(app.get_global_rect().encloses((node as Control).get_global_rect()),filename+": screen bounds "+str(node.name))
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var picture: Image=root.get_texture().get_image()
		t.expect(not picture.is_empty(),"rendered "+filename)
		t.equal(picture.save_png(output.path_join(filename)),OK,"save "+filename)
