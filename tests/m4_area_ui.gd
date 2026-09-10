extends "res://tests/m3_ui.gd"
const Scenario: GDScript = preload("res://tests/scenarios/test_m4_areas.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--output": output = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,800)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(app)
	await _frames()
	t.expect(_button("ContinueAreaButton").disabled,"fresh area slot absent")
	await _capture("menu.png")
	await _press("NewAreaButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	screen.auto_advance = false
	t.equal(screen.state.ruleset,Sm2MagicSnapshot.AREA_RULESET,"area mode opens")
	var c: Dictionary = Sm2AreaContentLoader.load_scenario()
	t.expect(screen.runner.new_battle(Scenario.setup(c)).ok,"explicit area UI fixture starts")
	screen._refresh()
	await _frames()
	for dimensions: Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size = dimensions
		await _frames()
		await _press("Ability_arcane_burst")
		await _motion(Vector2i(2,2))
		t.equal(screen.board.area_cells.size(),7,"preview highlights seven cells")
		t.equal(screen.board.area_targets.size(),2,"only enemy targets highlighted")
		t.expect(screen._preview.text.contains("№4: 14 HP") and screen._preview.text.contains("№5: 7 HP"),"each target forecast visible")
		t.expect(screen._preview.text.contains("Только противники"),"friendly safety stated")
		await _capture("area-preview-%s.png" % dimensions.x)
	root.size = Vector2i(1280,800)
	await _frames()
	var ally: Dictionary = screen._actor(2).duplicate(true)
	await _cell(Vector2i(2,2),false)
	t.equal([screen._actor(4).combat.hp,screen._actor(5).combat.hp],[46,58],"empty-center mouse click applies both hits")
	t.equal(screen._actor(2),ally,"ally in blast unchanged")
	t.equal(screen._actor(3).mana,12,"one area mana payment")
	t.expect(screen._log.text.contains("Чародейский взрыв") and screen._log.text.contains("целей: 2"),"readable area journal")
	await _capture("after-cast.png")
	await _press("SaveBattleButton")
	var saved: String = screen.runner.state_hash()
	await _cell(Vector2i(0,2),false)
	t.equal(screen.runner.state_hash(),saved,"empty area click inert")
	await _cell(Vector2i(2,2),true)
	t.expect(screen.board.area_cells.is_empty() and screen.board.area_targets.is_empty(),"right click clears area")
	# Restore enough AP but insufficient mana; denied forecast never executes.
	var payload: Dictionary = screen.runner.capture()
	Sm2CombatFixtures.actor(payload.session.battle,3).ap = 9
	Scenario.mana(payload.session.battle,3).current = 11
	t.expect(screen.runner.restore(payload).ok,"mana shortage fixture valid")
	screen._refresh()
	await _frames()
	await _press("Ability_arcane_burst")
	await _motion(Vector2i(2,2))
	t.expect(screen._preview.text.contains("Не хватает маны"),"area mana shortage explained")
	var before: String = screen.runner.state_hash()
	await _cell(Vector2i(2,2),false)
	t.equal(screen.runner.state_hash(),before,"denied area click inert")
	await _capture("mana-shortage.png")
	await _press("LoadBattleButton")
	t.equal(screen.runner.state_hash(),saved,"area load restores exact snapshot")
	await _press("BattleMenuButton")
	root.size = Vector2i(1000,700)
	await _frames()
	await _capture("menu-minimum.png")
	await _press("ContinueAreaButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	screen.auto_advance = false
	t.equal(screen.runner.state_hash(),saved,"menu area continuation exact")
	_finish()
