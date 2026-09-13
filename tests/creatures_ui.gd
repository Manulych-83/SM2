extends "res://tests/display_ui.gd"
const CREATURES = preload("res://tests/scenarios/test_creatures.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--output": output = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	display_report = {"captures":[]}
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(app)
	await set_resolution(Vector2i(2560,1440))
	await _press("NewCreature_0")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	t.expect(screen != null and screen.runner is Sm2CreatureBattleRunner,"template mode uses real runner")
	if screen == null: _finish(); return
	screen.auto_advance = false
	t.equal(screen.state.actors.size(),5,"authored five-actor encounter")
	t.equal(screen._actor(3).display_name,"Налётчик","name from template")
	t.equal(screen._actor(4).display_name,"Налётчик","second instance same name different number")
	t.equal(screen._actor(2).hp_max,80,"different guard parameters")
	t.equal(screen._actor(5).appearance.tunic_color,"#6e527f","presentation reference resolved")
	var before: String = screen.runner.state_hash()
	await _press("Ability_bow_shot")
	await _hover(Vector2i(5,3))
	t.expect(screen._preview.text.contains("Попадание") and screen._inspector.text.contains("Налётчик №3"),"actual target forecast and template name")
	t.equal(screen.runner.state_hash(),before,"inspection inert")
	await _capture("patrol-2560.png")
	var ammo: int = int(Sm2BattleText.item(screen._actor(1),"weapon").ammo)
	await _cell(Vector2i(5,3),false)
	t.equal(int(Sm2BattleText.item(screen._actor(1),"weapon").ammo),ammo-1,"physical mouse executes authored weapon")
	await _press("SaveBattleButton")
	var saved: String = screen.runner.state_hash()
	await _press("EndTurnButton")
	await _press("LoadBattleButton")
	t.equal(screen.runner.state_hash(),saved,"save/load exact")
	await _press("BattleMenuButton")
	await set_resolution(Vector2i(1280,720))
	await _press("ContinueCreature_0")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance = false
	t.equal(screen.runner.state_hash(),saved,"menu fresh runner continues patrol")
	await _capture("patrol-1280.png")
	await _press("BattleMenuButton")
	await _press("NewCreature_1")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance = false
	t.equal(screen.state.actors.size(),3,"second encounter changes composition from data")
	t.expect(screen._title.text.contains("Дозор"),"authored encounter title")
	await _capture("sentry-1280.png")
	await _press("BattleMenuButton")
	t.expect(_button("ContinueCreature_1").disabled,"separate encounter slot not created by patrol save")
	# An extended catalog still renders only one page of encounter controls.
	var raw: Dictionary = app._creature_content.catalog.to_data()
	for i: int in 28:
		var entry: Dictionary = raw.encounters[0].duplicate(true)
		entry.id = "creatures:encounter.extra_%02d" % i; raw.encounters.append(entry)
	var expanded: Sm2CreatureCatalog = Sm2CreatureCatalog.new()
	t.expect(CREATURES._rebuild(expanded,raw,app._creature_content).is_empty(),"UI pagination fixture validates")
	app._creature_content.catalog = expanded; app._show_creature_page(0); await _frames()
	t.equal(app.find_children("NewCreature_*","Button",true,false).size(),12,"twelve encounter cards maximum")
	await _press("CreatureNext")
	t.equal(app.find_children("NewCreature_*","Button",true,false).size(),12,"second page bounded")
	await _press("CreatureNext")
	t.equal(app.find_children("NewCreature_*","Button",true,false).size(),6,"final page remainder")
	await _press("NewCreature_24")
	screen = app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance = false
	t.equal(screen.state.scenario_id,expanded.encounters()[24],"paged button opens exact authored encounter")
	_finish()

func _hover(cell: Vector2i) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = root.get_final_transform()*(screen.board.global_position+screen.board.center(cell))
	event.global_position = event.position
	root.push_input(event,false); await _frames()
