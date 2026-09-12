extends "res://tests/display_ui.gd"
const RESULTS: GDScript=preload("res://tests/scenarios/test_battle_results.gd")
const TISSUES: GDScript=preload("res://tests/scenarios/test_survival_tissues.gd")
func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output); display_report={"captures":[]}
	await set_resolution(Vector2i(2560,1440))
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewSurvivalTissuesButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var s: Sm2JourneySession=life.session as Sm2JourneySession; var before: String=s.state_hash()
	await _press("CampJournal"); var journal: Sm2JournalScreen=app.find_child("JournalScreen",true,false) as Sm2JournalScreen
	t.expect(journal.model.ok and journal.model.rows.is_empty(),"new world has no invented events")
	t.equal(s.state_hash(),before,"opening empty journal is read only")
	await _key(KEY_ESCAPE); t.expect(app.find_child("JournalScreen",true,false)==null,"Escape closes journal")
	s=RESULTS.started(t,true)
	before=s.state_hash(); var active: Dictionary=Sm2JournalView.build(s)
	t.expect(active.ok and active.busy,"active battle history reconstructs without settlement")
	t.equal(s.state_hash(),before,"journal cannot advance active battle")
	RESULTS.finish(t,s,true); TISSUES.bandage_all(t,s)
	t.expect(s.act(s.command("explore",0,"first_aid")).ok,"actual search adds physical items")
	t.expect(s.act(s.command("travel",0,"camp")).ok,"actual return")
	for index: int in 32: t.expect(s.act(s.command("practice",2,"p5:activity.psionics")).ok,"actual practice for pagination")
	t.expect(s.act(s.command("end_life")).ok and s.act(s.command("incarnate",18)).ok,"actual new incarnation")
	before=s.state_hash(); var facts: Dictionary=Sm2JournalView.build(s)
	t.expect(facts.ok,"full journal reconstruction matches current world")
	t.equal(facts.rows.size(),s.history.size(),"one journal row per historical entry")
	t.equal(s.state_hash(),before,"replaying history cannot reward live session")
	var found: bool=false
	for row: Dictionary in facts.rows:
		if row.kind=="explore": found=true; t.equal(row.new_items,int(s.journey().exploration_catalog.site("first_aid").rewards.medicine),"actual first aid find count matches authored supply")
	t.expect(found,"search retained in journal")
	var frozen: String=Sm2Canonical.hash(facts)
	t.expect(s.save_game().ok and s.load_game().ok,"normal save/load")
	t.equal(Sm2Canonical.hash(Sm2JournalView.build(s)),frozen,"journal survives normal load exactly")
	t.equal(s.state_hash(),before,"journal/load never duplicate consequences")
	app._life=s; app._page="life"; app._redraw_page(); await _frames(); await _press("CampJournal")
	journal=app.find_child("JournalScreen",true,false) as Sm2JournalScreen
	await _capture("journal-2560-1440.png")
	t.expect(not _button("JournalNext").disabled,"history has second page")
	await _press("JournalNext"); t.equal(journal.page_index,1,"real older-page click")
	await _press("JournalPrevious"); t.equal(journal.page_index,0,"real newer-page click")
	var search: LineEdit=journal.find_child("JournalSearch",true,false) as LineEdit
	search.text="несуществующее"; search.text_changed.emit(search.text); await _frames()
	t.expect(journal.filtered.is_empty(),"search no matches")
	search.text="Руины"; search.text_changed.emit(search.text); await _frames()
	t.expect(not journal.filtered.is_empty(),"search finds actual location")
	search.text=""; search.text_changed.emit("")
	var filter: OptionButton=journal.find_child("JournalGroup",true,false) as OptionButton
	for index: int in filter.item_count:
		if filter.get_item_text(index)=="Воплощения": filter.select(index); filter.item_selected.emit(index); break
	t.equal(journal.filtered.size(),2,"life filter shows ending and incarnation only")
	for dimensions: Vector2i in [Vector2i(1920,1080),Vector2i(1280,720),Vector2i(1280,800)]:
		await set_resolution(dimensions); await _capture("journal-%s-%s.png" % [dimensions.x,dimensions.y])
	t.equal(s.state_hash(),before,"filters pagination resize are read only")
	await _press("JournalBack")
	var wounded: Sm2JourneySession=RESULTS.started(t,true); RESULTS.finish(t,wounded,true)
	t.expect(wounded.act(wounded.command("travel",0,"camp")).ok,"accepted travel can end in blood loss")
	var interrupted: Dictionary=Sm2JournalView.build(wounded)
	t.expect(interrupted.ok,"interrupted action reconstructs exactly")
	t.expect(interrupted.rows.back().interrupted and interrupted.rows.back().life_ended,"journal distinguishes interrupted travel")
	t.equal(interrupted.rows.back().location,wounded.journey().region_catalog.location(wounded.journey().region.location_id).name,"interrupted journey has actual destination")
	_finish()
