extends "res://tests/display_ui.gd"

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--output": output = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	display_report = {"captures":[]}
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(app)
	await set_resolution(Vector2i(2560,1440))
	t.expect(_button("ContinueSequencesButton").disabled,"new isolated demo slot absent")
	await _press("NewSequencesButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	t.expect(screen != null,"real additional-mode opens")
	if screen == null: _finish(); return
	screen.auto_advance = false
	var before: String = screen.runner.state_hash()
	await _press("Ability_exhaustion")
	await _hover(Vector2i(5,4))
	t.expect(screen._preview.text.contains("1. Ослабление") and screen._preview.text.contains("2. Отравление"),"ordered compound forecast")
	t.expect(screen._preview.text.contains("Тик: 5 HP"),"preview shows shared poison calculation")
	t.equal(screen.runner.state_hash(),before,"hover and selection are inert")
	await _capture("sequence-2560.png")
	await _cell(Vector2i(5,4),false)
	t.equal(screen._actor(4).effects.size(),2,"physical click applies both steps")
	t.equal(screen._actor(3).ap,6,"single action price")
	await _press("SaveBattleButton")
	var saved: String = screen.runner.state_hash()
	await _hover(Vector2i(5,3))
	t.expect(screen._preview.text.contains("пропуск") and screen._preview.text.contains("невосприимчива"),"immune poison shown as skipped")
	await _capture("immune-2560.png")
	await _cell(Vector2i(5,3),false)
	t.equal(screen._actor(5).effects.size(),1,"immunity leaves weakness only")
	await _press("LoadBattleButton")
	t.equal(screen.runner.state_hash(),saved,"reload exact resource/effect state")
	await set_resolution(Vector2i(1280,720))
	await _press("Ability_protection")
	await _hover(Vector2i(3,4))
	t.expect(screen._preview.text.contains("Нет отрицательных эффектов") and screen._preview.text.contains("2. Прикрытие"),"support skips empty cleanse and offers cover")
	await _capture("support-1280.png")
	await _cell(Vector2i(3,4),false)
	t.equal(screen._actor(3).effects.size(),1,"support physical click at720p")
	await _press("LoadBattleButton")
	t.equal(screen.runner.state_hash(),saved,"support not replayed by load")
	await _press("BattleMenuButton")
	await _press("ContinueSequencesButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	screen.auto_advance = false
	t.equal(screen.runner.state_hash(),saved,"new runner continues separate demo slot")
	t.expect(not app._effects_store.has_slot(Sm2BattleRunner.EFFECT_SLOT),"old demo slot untouched")
	_finish()

func _hover(cell: Vector2i) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = root.get_final_transform()*(screen.board.global_position+screen.board.center(cell))
	event.global_position = event.position
	root.push_input(event,false)
	await _frames()
