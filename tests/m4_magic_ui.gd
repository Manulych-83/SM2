extends "res://tests/m3_ui.gd"
## Uses real Viewport mouse events; deterministic fixtures are explicit below.
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
	t.expect(_button("ContinueMagicButton").disabled,"fresh magic save absent")
	await _capture("menu.png")
	await _press("NewMagicButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	t.expect(screen != null,"magic screen opens")
	if screen == null: _finish(); return
	screen.auto_advance = false
	t.equal(screen.state.ruleset,Sm2MagicSnapshot.RULESET,"magic ruleset")
	t.expect(screen._inspector.text.contains("Мана: 24 / 24"),"mana visible initially")
	for dimensions: Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size = dimensions
		await _frames()
		await _capture("magic-%s.png" % dimensions.x)
	root.size = Vector2i(1280,800)
	await _frames()
	await _press("Ability_arcane_bolt")
	await _motion(Vector2i(5,3))
	t.expect(screen._preview.text.contains("9 HP") and screen._preview.text.contains("50%"),"resistant target forecast")
	await _motion(Vector2i(5,4))
	t.expect(screen._preview.text.contains("18 HP") and screen._preview.text.contains("Мана: 8"),"normal target forecast and mana cost")
	await _capture("spell-preview.png")
	await _cell(Vector2i(5,4),false)
	t.equal([screen._actor(3).mana,screen._actor(4).combat.hp],[16,42],"mouse casts direct spell")
	t.expect(screen._log.text.contains("Магическая стрела"),"spell readable in log")
	await _press("SaveBattleButton")
	var saved: String = screen.runner.state_hash()
	await _cell(Vector2i(5,4),false)
	t.equal([screen._actor(3).mana,screen._actor(4).combat.hp],[8,24],"second spell pays again")
	await _press("LoadBattleButton")
	t.equal(screen.runner.state_hash(),saved,"restore exact mana and damage")
	# Valid fixture: enough AP, but not enough mana for the spell.
	var payload: Dictionary = screen.runner.capture()
	for pool: Dictionary in payload.session.battle.mana:
		if pool.actor_id == "3": pool.current = 7
	t.expect(screen.runner.restore(payload).ok,"mana shortage fixture restores")
	screen._refresh()
	await _frames()
	await _press("Ability_arcane_bolt")
	await _motion(Vector2i(5,4))
	t.expect(screen._preview.text.contains("Не хватает маны"),"mana shortage explained")
	var before: String = screen.runner.state_hash()
	await _cell(Vector2i(5,4),false)
	t.equal(screen.runner.state_hash(),before,"insufficient mana click inert")
	await _capture("mana-shortage.png")
	await _press("LoadBattleButton")
	await _press("EndTurnButton")
	var steps: int = 0
	while not screen._player_turn() and not screen.state.finished and steps < 30:
		screen.auto_advance = true
		screen._delay = 0.0
		screen._process(0.01)
		screen.auto_advance = false
		steps += 1
	t.expect(screen.runner.error_reason().is_empty(),"AI continues magic battle")
	await _capture("after-ai.png")
	await _press("SaveBattleButton")
	var stored: String = screen.runner.state_hash()
	await _press("BattleMenuButton")
	root.size = Vector2i(1000,700)
	await _frames()
	await _capture("menu-minimum.png")
	await _press("ContinueMagicButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	screen.auto_advance = false
	t.equal(screen.runner.state_hash(),stored,"new runner loads magic slot from menu")
	_finish()
