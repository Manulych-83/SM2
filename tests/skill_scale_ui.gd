extends "res://tests/display_ui.gd"
const FIXTURE=preload("res://tests/fixtures/sm2_skill_scale_fixture.gd")
var development: Sm2HeroDevelopmentScreen
func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output); display_report={"captures":[]}
	await set_resolution(Vector2i(2560,1440))
	var s: Sm2CheckpointSession=FIXTURE.session()
	t.expect(s.new_game().ok,"5000 skill UI starts")
	t.expect(s.act(s.command("travel",0,"ruins")).ok and s.act(s.command("start_battle")).ok,"first encounter before training")
	preload("res://tests/scenarios/test_expedition.gd").retreat(s,t)
	preload("res://tests/scenarios/test_survival_tissues.gd").bandage_all(t,s)
	t.expect(s.act(s.command("travel",0,"camp")).ok,"return for UI practice")
	development=Sm2HeroDevelopmentScreen.new(); development.session=s; development.selected_id=FIXTURE.TRACK
	app=development; root.add_child(app); await _frames()
	var before: String=s.state_hash()
	t.equal(app.find_children("HeroTrack_*","Button",true,false).size(),24,"only 24 visible skill buttons")
	t.expect(not development._model.tracks[0].has("earned"),"unseen tracks carry search metadata only")
	await _capture("skills-5000-2560.png")
	await _press("HeroTracksNext")
	t.equal(development._track_page,1,"next page click")
	var search: LineEdit=app.find_child("HeroTrackFilter",true,false) as LineEdit
	search.text="04999"; search.text_changed.emit(search.text); await _frames()
	t.equal(app.find_children("HeroTrack_*","Button",true,false).size(),1,"search locates distant skill")
	await _press(Sm2HeroDevelopmentScreen.control_id("HeroTrack",FIXTURE.TRACK))
	t.equal(development.selected_id,FIXTURE.TRACK,"search result selected")
	t.equal(s.state_hash(),before,"navigation leaves world untouched")
	for id: String in [FIXTURE.ACTIVITY,"wide:practice.04998"]: t.expect(s.act(s.command("practice",2,id)).ok,"actual skill practice")
	development.redraw(); await _frames()
	await _press(Sm2HeroDevelopmentScreen.control_id("HeroBuy",FIXTURE.NODE))
	t.expect(s.world.bodies[2].progress.tracks[FIXTURE.TRACK].owns(FIXTURE.NODE),"cross-node button buys using two XP pools")
	await _press("HeroDevelopmentSave"); before=s.state_hash(); await _press("HeroDevelopmentLoad")
	t.equal(s.state_hash(),before,"wide UI save/load")
	await _capture("skills-5000-purchased-2560.png")
	await set_resolution(Vector2i(1280,720)); await _frames()
	search=app.find_child("HeroTrackFilter",true,false) as LineEdit
	search.text=""; search.text_changed.emit(""); await _frames()
	await _press("HeroTracksNext")
	t.equal(development._track_page,1,"720p page click")
	await _capture("skills-5000-1280.png")
	_finish()
