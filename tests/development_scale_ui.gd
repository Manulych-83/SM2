extends "res://tests/display_ui.gd"
const FIXTURE=preload("res://tests/fixtures/sm2_development_scale_fixture.gd")
var development: Sm2HeroDevelopmentScreen

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output); display_report={"captures":[]}
	await set_resolution(Vector2i(2560,1440))
	var s: Sm2CheckpointSession=FIXTURE.session()
	t.expect(s.new_game().ok,"large UI campaign starts")
	development=Sm2HeroDevelopmentScreen.new(); development.session=s; development.selected_id=FIXTURE.TRACK
	app=development; root.add_child(app); await _frames()
	var before: String=s.state_hash()
	t.equal(app.find_children("HeroBuy_*","Button",true,false).size(),24,"only 24 node cards exist")
	t.equal(app.find_children("HeroTrack_*","Button",true,false).size(),24,"only 24 track buttons exist")
	await _capture("large-first-page-2560.png")
	await _press("HeroNodesNext")
	t.equal(development._node_page,1,"mouse opens next node page")
	t.equal(development._model.nodes[0].id,FIXTURE.node_id(24),"page selects next catalog IDs")
	await _press("HeroTracksNext")
	t.equal(development._track_page,1,"mouse opens next track page")
	var search: LineEdit=app.find_child("HeroNodeSearch",true,false) as LineEdit
	search.text="00001"; search.text_submitted.emit(search.text); await _frames()
	t.equal(app.find_children("HeroBuy_*","Button",true,false).size(),1,"search renders one matching node")
	var node: Dictionary=development._model.nodes[0]
	var link: Dictionary=node.requires[0]
	await _press(_id("HeroRequires",node.id+link.id))
	t.expect(development._node_page>1,"clicking prerequisite opens distant page")
	t.equal(development._node_query,"","relationship navigation clears incompatible search")
	var root_node: Dictionary=development._model.nodes[-1]
	t.equal(root_node.id,link.id,"linked root is visible")
	t.equal(root_node.unlocks.size(),12,"fan-out creates at most twelve forward links")
	await _press(_id("HeroLinks",root_node.id+"unlocks")+"Next")
	t.equal(development._model.nodes[-1].unlocks_page,1,"next link page works with a real mouse click")
	await _capture("large-root-links-2560.png")
	t.equal(s.state_hash(),before,"pagination and links do not change world or XP")
	var track_filter: LineEdit=app.find_child("HeroTrackFilter",true,false) as LineEdit
	track_filter.text="150"; track_filter.text_changed.emit(track_filter.text); await _frames()
	t.equal(app.find_children("HeroTrack_*","Button",true,false).size(),1,"track search finds a distant track")
	await _press(_id("HeroTrack","scale:skill.150"))
	t.equal(development.selected_id,"scale:skill.150","filtered track is selectable")
	# Learn a production ability through the same authoritative session, in the large fixture.
	for i: int in 8: t.expect(s.act(s.command("practice",2,"p5:activity.psionics")).ok,"real practice for large UI purchase")
	development._select("p1:skill.psionics","p5:node.impulse"); await _frames()
	await _press(_id("HeroBuy","p5:node.impulse"))
	t.expect(s.world.bodies[2].progress.tracks["p1:skill.psionics"].owns("p5:node.impulse"),"large catalog purchase button acts")
	await _press("HeroDevelopmentSave"); before=s.state_hash(); await _press("HeroDevelopmentLoad")
	t.equal(s.state_hash(),before,"large UI save and load preserve purchase")
	await set_resolution(Vector2i(1280,720))
	development._select(FIXTURE.TRACK,""); await _frames()
	await _press("HeroNodesNext"); await _capture("large-page-1280.png")
	t.equal(development._node_page,1,"scaled input opens correct page")
	_finish()

func _id(prefix: String,id: String) -> String: return Sm2HeroDevelopmentScreen.control_id(prefix,id)
