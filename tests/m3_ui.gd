extends SceneTree
## GUI routing and presentation contracts; native mouse acceptance is separate.
var t: Sm2TestHarness = Sm2TestHarness.new()
var app: Control
var screen: Sm2BattleScreen
var output: String = "user://m3-ui"
var captured: Sm2ErrorCapture = Sm2ErrorCapture.new()

func _initialize() -> void:
	call_deferred("_run")

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
	t.expect(_button("ContinueBattleButton").disabled, "fresh runtime has no battle save")
	await _press("NewBattleButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	t.expect(screen != null, "menu opens battle")
	if screen == null: _finish(); return
	screen.auto_advance = false
	t.equal(screen.state.actors.size(),6,"six actors visible")
	for dimensions: Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size = dimensions
		await _frames()
		for r: int in screen.board.field.height():
			for q: int in screen.board.field.width():
				var cell: Vector2i = Vector2i(q,r)
				t.equal(screen.board.pick(screen.board.center(cell)),cell,"hex center maps back at " + str(dimensions))
		t.equal(screen.board.pick(Vector2(-20,-20)),Vector2i(-1,-1),"outside field")
		await _capture("field-%s.png" % dimensions.x)
	root.size = Vector2i(1280,800)
	await _frames()
	var before: String = screen.runner.state_hash()
	await _cell(Vector2i(1,2),false)
	t.equal(screen.runner.state_hash(),before,"inspection cannot change active actor or RNG")
	await _motion(Vector2i(3,4))
	t.expect(screen._preview.text.contains("Цена пути: 4 действий"),"hover displays shared two-step cost")
	t.equal(screen.runner.state_hash(),before,"hover preserves full state")
	await _cell(Vector2i(3,4),false)
	t.equal(screen._actor(3).q,2,"mouse route first step executed")
	t.equal(screen._path.size(),1,"remaining route is presentation intent")
	var first_step: String = screen.runner.state_hash()
	await _cell(Vector2i(3,4),true)
	t.expect(screen._path.is_empty(),"right click cancels remaining steps")
	t.equal(screen.runner.state_hash(),first_step,"cancel does not refund or mutate completed step")
	await _press("SaveBattleButton")
	var saved: String = screen.runner.state_hash()
	await _press("WaitButton")
	t.expect(not screen._player_turn(),"wait yields to AI")
	t.expect(_button("EndTurnButton").disabled,"player controls blocked during AI turn")
	screen._delay = 0.0
	screen.auto_advance = true
	screen._process(0.01)
	screen.auto_advance = false
	t.expect(screen.runner.state_hash() != saved,"AI advances through screen")
	await _press("LoadBattleButton")
	t.equal(screen.runner.state_hash(),saved,"load restores exact RNG queue and state")
	await _press("BattleMenuButton")
	await _press("ResumeBattleButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	screen.auto_advance = false
	t.equal(screen.runner.state_hash(),saved,"menu resume retains battle")
	await _fixture()
	before = screen.runner.state_hash()
	await _motion(Vector2i(2,2))
	var prediction: Dictionary = screen.runner.preview(screen._command("use_ability","m2:ability.sword_strike",5))
	t.expect(prediction.allowed,"adjacent enemy is attackable")
	t.expect(screen._preview.text.contains("Попадание: %s%%" % prediction.hit_chance),"UI shows domain hit chance")
	t.equal(screen.runner.state_hash(),before,"attack forecast preserves state")
	await _capture("attack-preview.png")
	var revision: int = screen.state.revision
	await _cell(Vector2i(2,2),false)
	t.equal(screen.state.revision,revision+1,"enemy mouse click executes one attack")
	t.expect(not screen._journal.is_empty(),"attack produces visible journal")
	await _fixture()
	await _motion(Vector2i(0,4))
	t.expect(screen._reachable[Vector2i(0,4)].path.size() > 1,"departure fixture has multi-step path")
	await _cell(Vector2i(0,4),false)
	t.expect(screen._path.is_empty(),"reaction hit cancels all remaining steps")
	t.equal([screen._actor(2).q,screen._actor(2).r],[1,2],"interrupted pawn remains at origin")
	t.equal(screen.state.revision,1,"interrupted route submits only first command")
	t.expect(screen._notice.text.contains("остановлен"),"interruption explained")
	await _capture("reaction.png")
	# Play the rest through the same screen command gateway, using shared AI only to choose player commands.
	var profile: Sm2AiProfile = Sm2AiContentLoader.load_profile().profile
	var steps: int = 0
	while not screen.state.finished and steps < 500:
		if screen._player_turn():
			var battle: Sm2TacticalBattle = Sm2TacticalBattle.new(Sm2CombatFixtures.loaded().catalog,Sm2CombatFixtures.loaded().combat,true)
			t.expect(battle.restore(screen.runner.capture().session.battle).ok,"query fixture restores")
			var decision: Dictionary = battle.ai_decision(profile)
			t.expect(decision.ok,"player action chosen from shared legality")
			if not decision.ok: break
			t.expect(screen._execute(decision.command).accepted,"screen accepts legal player command")
		else:
			screen.auto_advance = true
			screen._delay = 0.0
			screen._process(0.01)
			screen.auto_advance = false
		steps += 1
	t.expect(screen.state.finished,"battle completes through screen gateway")
	t.expect(screen._preview.text.contains("ИТОГ СРАЖЕНИЯ"),"outcome visible")
	t.expect(_button("EndTurnButton").disabled,"finished battle disables actions")
	for actor: Dictionary in screen.state.actors:
		if actor.alive and actor.on_field:
			await _motion(Vector2i(int(actor.q),int(actor.r)))
			t.expect(screen._inspector.text.contains(Sm2BattleText.actor(actor)),"survivors remain inspectable after outcome")
			t.expect(screen._preview.text.contains("ИТОГ СРАЖЕНИЯ"),"inspection preserves outcome panel")
	await _capture("outcome.png")
	await _press("SaveBattleButton")
	var finished_hash: String = screen.runner.state_hash()
	await _press("BattleMenuButton")
	root.size = Vector2i(1000,700)
	await _frames()
	await _capture("menu-minimum.png")
	await _press("ContinueBattleButton")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	screen.auto_advance = false
	t.equal(screen.runner.state_hash(),finished_hash,"fresh runner reloads finished battle without duplicate result")
	t.expect(screen._notice.text.contains("Бой завершён"),"finished load keeps outcome notice")
	_finish()

func _fixture() -> void:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	t.expect(screen.runner.new_battle(Sm2CombatFixtures.setup(content,[2,5],1231)).ok,"UI adjacent fixture starts")
	screen._path.clear()
	screen._selected = ""
	screen._refresh()
	await _frames()

func _frames() -> void:
	await process_frame
	await process_frame

func _button(id: String) -> Button:
	return app.find_child(id,true,false) as Button

func _press(id: String) -> void:
	var button: Button = _button(id)
	t.expect(button != null and not button.disabled,"usable button " + id)
	if button != null and not button.disabled:
		await _mouse(button.get_global_rect().get_center(),false)

func _cell(cell: Vector2i, right: bool) -> void:
	await _mouse(screen.board.global_position+screen.board.center(cell),right)

func _motion(cell: Vector2i) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = screen.board.global_position+screen.board.center(cell)
	event.global_position = event.position
	root.push_input(event,true)
	await _frames()

func _mouse(point: Vector2, right: bool) -> void:
	for down: bool in [true,false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event,true)
	await _frames()

func _capture(filename: String) -> void:
	await _frames()
	for node: Node in app.find_children("*","Control",true,false):
		if node is Label or node is Button or node is RichTextLabel:
			t.expect(app.get_global_rect().encloses((node as Control).get_global_rect()),filename+": inside screen "+str(node.name))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var picture: Image = root.get_texture().get_image()
		t.expect(not picture.is_empty(),"rendered image "+filename)
		t.equal(picture.save_png(output.path_join(filename)),OK,"save screenshot "+filename)

func _finish() -> void:
	OS.remove_logger(captured)
	t.failures.append_array(captured.messages())
	var report: Dictionary = {"passed":t.failures.is_empty(),"checks":t.checks,"failures":t.failures,"rendered":DisplayServer.get_name() != "headless"}
	var file: FileAccess = FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file == null: push_error("Cannot write UI report"); quit(2); return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("SM2_M3_UI_REPORT " + JSON.stringify(report))
	quit(0 if report.passed else 1)
