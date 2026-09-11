extends "res://tests/m3_ui.gd"
const ATTR: GDScript = preload("res://tests/scenarios/test_p4_attributes.gd")
var attribute_screen: Sm2AttributeScreen

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1280,800)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(app); await _frames()
	await _capture("menu.png")
	await _press("AttributesButton")
	attribute_screen=app.find_child("AttributeScreen",true,false) as Sm2AttributeScreen
	t.expect(attribute_screen != null,"new lab opens through menu")
	if attribute_screen == null: _finish(); return
	t.expect(_button("AttributePractice_power_bare").disabled,"bare trial disabled initially")
	t.expect(not _button("AttributePractice_power_assisted").disabled,"stand enables trial")
	t.expect(_button("AttributeBuy_power").disabled,"stand does not enable node")
	await _capture("initial.png")
	await _press("AttributePractice_power_assisted")
	t.equal(ATTR.track(attribute_screen.session.lab,ATTR.POWER).earned,10,"mouse exercise awards ten")
	t.expect(_button("AttributeBuy_power").disabled,"performed assisted practice insufficient for node")
	await _press("NewAttributeButton")
	for i: int in 4: await _press("AttributePractice_power")
	await _press("AttributeBuy_power")
	t.equal(ATTR.track(attribute_screen.session.lab,ATTR.POWER).available,30,"mouse purchase exact own cost")
	t.expect(not _button("AttributePractice_power_bare").disabled,"trained body can lift bare")
	await _press("AttributePractice_power_bare")
	await _capture("power-trained.png")
	for suffix: String in ["motorics","resilience","intellect","perception","will","resonance","synchronization"]:
		await _press("Select_"+suffix)
		t.equal(attribute_screen.selected,"p4a:stat."+suffix,"selection "+suffix)
		await _press("AttributePractice_"+suffix)
		t.equal(ATTR.track(attribute_screen.session.lab,"p4a:stat."+suffix).earned,25,"selected exercise own XP "+suffix)
	await _capture("synchronization.png")
	await _press("SaveAttributeButton")
	var saved: String = attribute_screen.session.lab.state_hash()
	await _press("NewAttributeButton")
	await _press("LoadAttributeButton")
	t.equal(attribute_screen.session.lab.state_hash(),saved,"UI save/load exact")
	await _press("AttributeMenuButton")
	root.size=Vector2i(1000,700); await _frames()
	await _capture("menu-minimum.png")
	await _press("AttributesButton")
	attribute_screen=app.find_child("AttributeScreen",true,false) as Sm2AttributeScreen
	t.equal(attribute_screen.session.lab.state_hash(),saved,"menu resumes same session")
	await _capture("power-minimum.png")
	await _press("Select_synchronization")
	await _capture("synchronization-minimum.png")
	app.queue_free(); await _frames()
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(app); await _frames(); await _press("AttributesButton")
	attribute_screen=app.find_child("AttributeScreen",true,false) as Sm2AttributeScreen
	await _press("LoadAttributeButton")
	t.equal(attribute_screen.session.lab.state_hash(),saved,"new application restores saved eight tracks")
	var store: Sm2SaveStore = Sm2SaveStore.new("user://attributes")
	var bad: Dictionary = attribute_screen.session.lab.capture(); bad.revision="99999"
	t.expect(store.save_slot(bad,"p4_attribute_lab").ok,"invalid domain fixture")
	await _press("LoadAttributeButton")
	t.equal(attribute_screen.session.lab.state_hash(),saved,"failed load preserves live lab")
	t.expect((app.find_child("AttributeNotice",true,false) as Label).text.contains("не загружено"),"failed load visible")
	await _press("SaveAttributeButton")
	_finish()
