extends "res://tests/m3_ui.gd"
## Reuses the real Viewport input and rendered layout checks from M3.
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
	t.expect(_button("ContinueEffectsButton").disabled,"fresh effects slot absent")
	await _capture("menu.png")
	await _press("NewEffectsButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	t.expect(screen != null,"effects menu opens real battle")
	if screen == null: _finish(); return
	screen.auto_advance = false
	t.equal(screen.state.ruleset,Sm2EffectSnapshot.RULESET,"M4 ruleset active")
	for dimensions: Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size = dimensions
		await _frames()
		await _capture("effects-%s.png" % dimensions.x)
	root.size = Vector2i(1280,800)
	await _frames()
	await _press("Ability_poison")
	var before: String = screen.runner.state_hash()
	await _motion(Vector2i(5,3))
	t.expect(screen._preview.text.contains("невосприимчива"),"immune target explained")
	await _cell(Vector2i(5,3),false)
	t.equal(screen.runner.state_hash(),before,"immune click inert")
	await _motion(Vector2i(5,4))
	t.expect(screen._preview.text.contains("Тик: 5 HP"),"poison forecast uses shared tick")
	await _capture("poison-preview.png")
	await _cell(Vector2i(5,4),false)
	t.equal(screen._actor(4).effects[0].remaining,3,"mouse applies poison")
	t.expect(screen._inspector.text.contains("Отравление"),"target effect displayed")
	await _press("SaveBattleButton")
	var saved: String = screen.runner.state_hash()
	await _press("Ability_weakness")
	await _cell(Vector2i(5,4),false)
	t.equal(screen._actor(4).stats.melee_skill.value,60,"mouse weakness affects stats")
	await _press("Ability_cover")
	await _motion(Vector2i(3,4))
	t.expect(screen._preview.text.contains("Прикрытие"),"helpful action previews allied target")
	await _cell(Vector2i(3,4),false)
	t.equal(screen._actor(3).effects[0].remaining,1,"self cover lastAP executes one end tick")
	t.expect(not screen._player_turn(),"AP0 yields to enemy")
	await _press("LoadBattleButton")
	t.equal(screen.runner.state_hash(),saved,"load restores poison only and resources")
	# Explicit setup for cleansing: a hostile weakness already on the active player.
	var payload: Dictionary = screen.runner.capture()
	payload.session.battle.effects.append({"effect_id":"2","definition_id":"m4:effect.weakness","source_actor_id":"4","target_actor_id":"3","remaining":2,"applied_revision":"1"})
	payload.session.battle.next_effect_id = "3"
	t.expect(screen.runner.restore(payload).ok,"cleansing fixture validates")
	screen._refresh()
	await _frames()
	await _press("Ability_cleanse")
	await _motion(Vector2i(3,4))
	await _capture("cleanse-preview.png")
	await _cell(Vector2i(3,4),false)
	t.expect(screen._actor(3).effects.is_empty(),"cleanse clicked on self removes harmful effect")
	t.equal(screen._actor(4).effects.size(),1,"cleanse leaves enemy poison")
	await _press("EndTurnButton")
	var steps: int = 0
	while not screen._player_turn() and not screen.state.finished and steps < 30:
		screen.auto_advance = true
		screen._delay = 0.0
		screen._process(0.01)
		screen.auto_advance = false
		steps += 1
	t.expect(screen.runner.error_reason().is_empty(),"AI continues with effects")
	await _capture("after-ai.png")
	await _press("SaveBattleButton")
	var stored: String = screen.runner.state_hash()
	await _press("BattleMenuButton")
	root.size = Vector2i(1000,700)
	await _frames()
	await _capture("menu-minimum.png")
	await _press("ContinueEffectsButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	screen.auto_advance = false
	t.equal(screen.runner.state_hash(),stored,"fresh menu runner restores effects slot")
	_finish()
