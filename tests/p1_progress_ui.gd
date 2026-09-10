extends "res://tests/m3_ui.gd"
const P1: GDScript = preload("res://tests/scenarios/test_p1_progression.gd")
var lab_screen: Sm2ProgressScreen

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1280,800)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(app); await _frames()
	await _capture("menu.png")
	await _press("ProgressButton")
	lab_screen=app.find_child("ProgressScreen",true,false) as Sm2ProgressScreen
	t.expect(lab_screen != null,"P1 opens through menu")
	t.expect(_button("LoadProgressButton").disabled,"fresh progression slot absent")
	t.expect((app.find_child("ProgressIdentity",true,false) as Label).text.contains("Основы перевязки"),"Soul knowledge shown")
	t.expect(_button("Buy_strength_1").disabled,"untrained body cannot buy node")
	var initial: String = lab_screen.session.lab.state_hash()
	await _capture("initial.png")
	t.equal(lab_screen.session.lab.state_hash(),initial,"rendering and previews do not award XP")
	for i: int in 4: await _press("PracticeButton")
	t.equal(P1.track(lab_screen.session.lab,P1.STRENGTH).level,11,"UI exercise crosses threshold")
	t.equal(P1.track(lab_screen.session.lab,P1.PSI).earned,0,"UI exercise no psi XP")
	await _capture("four-exercises.png")
	await _buy("Buy_strength_1")
	t.equal(P1.track(lab_screen.session.lab,P1.STRENGTH).available,50,"UI purchase pays own balance")
	t.equal(P1.track(lab_screen.session.lab,P1.STRENGTH).level,11,"UI purchase retains level")
	await _buy("Buy_melee_1")
	t.equal(P1.track(lab_screen.session.lab,P1.MELEE).effective,10,"UI explains final melee")
	for dimensions: Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=dimensions; await _frames()
		await _capture("purchased-"+str(dimensions.x)+".png")
	await _press("SaveProgressButton")
	var saved: String = lab_screen.session.lab.state_hash()
	await _press("PracticeButton")
	t.expect(lab_screen.session.lab.state_hash() != saved,"practice after save changes state")
	await _press("LoadProgressButton")
	t.equal(lab_screen.session.lab.state_hash(),saved,"P1 UI disk restore exact")
	await _press("ProgressMenuButton")
	await _capture("menu-minimum.png")
	await _press("ProgressButton")
	lab_screen=app.find_child("ProgressScreen",true,false) as Sm2ProgressScreen
	t.equal(lab_screen.session.lab.state_hash(),saved,"menu resumes same lab")
	await _press("NewProgressButton")
	t.equal(P1.track(lab_screen.session.lab,P1.STRENGTH).earned,0,"new example resets practice")
	await _press("LoadProgressButton")
	t.equal(lab_screen.session.lab.state_hash(),saved,"new example preserves disk save")
	app.queue_free(); await _frames()
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(app); await _frames()
	await _press("ProgressButton")
	lab_screen=app.find_child("ProgressScreen",true,false) as Sm2ProgressScreen
	await _press("LoadProgressButton")
	t.equal(lab_screen.session.lab.state_hash(),saved,"new app restores previous world and purchases")
	await _capture("reloaded.png")
	# Domain-invalid payload has a valid envelope: presentation must preserve its live session.
	var store: Sm2SaveStore = Sm2SaveStore.new("user://progression")
	var invalid: Dictionary = lab_screen.session.lab.capture(); invalid.body.tracks[0].spent_total=0
	t.expect(store.save_slot(invalid,Sm2ProgressSession.SLOT).ok,"invalid domain save fixture")
	await _press("LoadProgressButton")
	t.equal(lab_screen.session.lab.state_hash(),saved,"failed UI load preserves live state")
	t.expect((app.find_child("ProgressNotice",true,false) as Label).text.contains("не загружено"),"failed UI load explains refusal")
	await _press("SaveProgressButton")
	_finish()

func _buy(id: String) -> void:
	var scroll: ScrollContainer = app.find_child("ProgressNodesScroll",true,false) as ScrollContainer
	scroll.ensure_control_visible(_button(id)); await _frames()
	await _press(id)
