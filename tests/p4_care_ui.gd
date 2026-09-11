extends "res://tests/p4_prosthesis_ui.gd"
const CARE_TEST=preload("res://tests/scenarios/test_p4_care.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _capture("menu.png")
	await _press("NewCareJourneyButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(life!=null,"new care mode opens")
	if life==null: _finish(); return
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(s.format_id(),Sm2JourneySession.CARE_FORMAT,"separate care format")
	t.expect(_button("HealHpButton").disabled,"full health cannot consume medicine")
	t.expect(_label_text("CareSupply_medicine").contains("12"),"initial medicine visible")
	await _capture("camp.png")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	await _press("SaveBattleButton"); var saved: String=s.state_hash()
	await _press("BattleMenuButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(_button("HealHpButton").disabled,"camp HP treatment disabled during battle")
	await _press("WorldMenu"); await _press("ContinueCareJourneyButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.equal(life.session.state_hash(),saved,"production care save loads via menu")
	# Actual injury, then separate paid HP and hand treatment.
	s=await _open_fixture(false,false,"user://care-ui-healing")
	await _fight_to_retreat(s)
	t.expect(s.world.hero_id()==2 and s.world.bodies[2].hp==51,"actual enemy wound in UI fixture")
	if s.world.hero_id()!=2: _finish(); return
	await _capture("wounded.png")
	var practice: Dictionary=s.world.bodies[2].progress.to_data()
	await _press("HealHpButton")
	t.equal(s.world.bodies[2].hp,60,"mouse treatment restores bounded HP")
	t.equal(s.world.bodies[2].progress.to_data(),practice,"treatment no XP")
	t.expect(not s.world.bodies[2].functions.working.right_hand,"HP recovery leaves trauma")
	t.equal(s.journey().care.supplies.medicine,10,"mouse treatment consumes two medicine")
	t.equal(s.journey().care.minutes,120,"mouse treatment advances procedure time")
	await _press("Heal_right_hand")
	t.expect(s.world.bodies[2].functions.working.right_hand,"paid functional treatment restores hand")
	t.equal(s.journey().care.supplies.medicine,7,"hand treatment price")
	t.equal(s.journey().care.minutes,360,"hand treatment duration")
	t.expect(_label_text("CareElapsed").contains("360"),"updated procedure time visible")
	await _press("WorldSave"); saved=s.state_hash(); await _press("WorldLoad")
	t.equal(s.state_hash(),saved,"paid operations survive UI save/load")
	root.size=Vector2i(1280,800); await _frames(); await _capture("treated.png")
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.equal(screen.state.actors[0].combat.hp,60,"healed body starts next actual battle at full HP")
	# Separate limited supply fixture demonstrates an unavailable paid repair.
	s=await _open_fixture(true,true,"user://care-ui-limited")
	await _fight_to_retreat(s)
	var device: String=s.journey().prostheses.items[0].id
	await _press(_item_id(device,"install_prosthesis",2))
	t.equal(s.journey().care.supplies.medicine,0,"limited medicine consumed by installation")
	t.equal(s.journey().care.supplies.parts,0,"limited parts consumed by installation")
	await _fight_to_retreat(s)
	t.expect(not s.journey().prostheses.item(device).working,"real damaged device in limited supply case")
	var repair: Button=_button(_item_id(device,"repair_prosthesis",0))
	t.expect(repair.disabled and repair.tooltip_text.contains("Не хватает"),"repair button explains missing parts")
	t.expect(_button("HealHpButton").disabled,"wounded body cannot heal with no medicine")
	await _capture("no-supplies.png")
	await _press("WorldSave"); await _press("WorldEndLife"); await _press("WorldConfirmDeath"); await _press("WorldIncarnate8")
	t.equal(s.journey().care.supplies.medicine,0,"new incarnation does not refill supplies")
	t.equal(s.journey().care.minutes,180,"new incarnation does not reset procedure time")
	await _press("WorldSave"); await _capture("new-life.png")
	_finish()

func _open_fixture(sever: bool,limited: bool,store_path: String) -> Sm2JourneySession:
	var s: Sm2JourneySession=Sm2JourneySession.new(CARE_TEST.fixture_content(sever,limited),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new(store_path))
	t.expect(s.new_game().ok,"care UI fixture starts")
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames()
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen; return s

func _label_text(id: String) -> String:
	var label: Label=app.find_child(id,true,false) as Label
	t.expect(label!=null,"visible care label "+id)
	return label.text if label!=null else ""
