extends "res://tests/p4_prosthesis_ui.gd"
const DISCOVERY=preload("res://tests/scenarios/test_p4_discovery.gd")
const TRACK: String="p4s:skill.search"
const NODE: String="p4s:node.attentive"
var hero_screen: Sm2HeroDevelopmentScreen

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewDiscoveryButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	var before: String=s.state_hash()
	await _press("WorldDevelopment"); _find_screen()
	t.expect(hero_screen!=null,"hero development opens from camp")
	if hero_screen==null: _finish(); return
	await _filter("Поиск")
	t.expect(_button(_id("HeroTrack",TRACK))!=null,"filter finds search skill")
	t.expect(_button(_id("HeroTrack","p1:stat.strength"))==null,"filter hides unrelated attribute")
	await _press(_id("HeroTrack",TRACK)); _find_screen()
	t.expect(_button(_id("HeroBuy",NODE)).disabled,"initial node unavailable in new screen")
	await _capture("search.png")
	await _filter("несуществующее направление")
	t.expect(hero_screen.find_children("HeroTrack_*","Button",true,false).is_empty(),"empty filter result handled")
	await _filter(""); await _press(_id("HeroTrack","p1:stat.strength"))
	await _press(_id("HeroNext","p1:node.strength_1p1:node.strength_2")); _find_screen()
	t.equal(hero_screen.selected_id,"p1:stat.strength","next-node link keeps correct direction")
	t.equal(hero_screen._focused,"p1:node.strength_2","next-node link focuses destination")
	await _capture("connections.png")
	await _press(_id("HeroRequires","p1:node.strength_2p1:node.strength_1")); _find_screen()
	t.equal(hero_screen._focused,"p1:node.strength_1","prerequisite link focuses prior node")
	await _press(_id("HeroContribution","p1:skill.melee")); _find_screen()
	t.equal(hero_screen.selected_id,"p1:skill.melee","characteristic contribution navigates to linked skill")
	t.equal(s.state_hash(),before,"filtering and all navigation are read-only")
	await _press("HeroDevelopmentSave"); await _press("HeroDevelopmentBack")
	t.equal(s.state_hash(),before,"return and save keep same world")
	# The same session is handed to the screen; no new game, ruleset or save slot.
	s=DISCOVERY.prepared(t,Sm2SaveStore.new("user://hero-screen-flow"))
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames()
	await _press("WorldDevelopment"); _find_screen(); await _filter("Поиск"); await _press(_id("HeroTrack",TRACK)); _find_screen()
	t.expect(not _button(_id("HeroBuy",NODE)).disabled,"earned practice enables existing node")
	var old_button: Button=_button(_id("HeroBuy",NODE))
	t.expect(s.act(s.command("explore",0,"abandoned_camp")).ok,"external revision advances while old screen is retained")
	before=s.state_hash(); old_button.pressed.emit(); await _frames(); _find_screen()
	t.equal(s.state_hash(),before,"stale visible button cannot silently target newer state")
	t.equal(s.world.bodies[2].progress.tracks[TRACK].spent,0,"stale click spends no XP")
	await _press(_id("HeroBuy",NODE)); _find_screen()
	t.equal(s.world.bodies[2].progress.tracks[TRACK].earned,150,"screen purchase retains earned practice")
	t.equal(s.world.bodies[2].progress.tracks[TRACK].spent,100,"screen purchase spends correct own balance")
	t.expect(_button(_id("HeroBuy",NODE)).disabled,"owned node disabled")
	t.expect((app.find_child("HeroTrackSummary",true,false) as Label).text.contains("доступно 50"),"remaining XP visible")
	root.size=Vector2i(1280,800); await _frames(); await _capture("learned.png")
	await _press("HeroDevelopmentSave"); before=s.state_hash(); await _press("HeroDevelopmentLoad")
	t.equal(s.state_hash(),before,"screen save/load exact without duplicate purchase")
	await _press("HeroDevelopmentBack"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.expect(not _button("Explore_hidden_niche").disabled,"screen purchase opens actual camp action")
	await _press("Explore_hidden_niche")
	t.equal(s.world.bodies[2].progress.tracks[TRACK].earned,200,"unlocked camp action uses same hero state")
	await _press("WorldEndLife"); await _press("WorldConfirmDeath")
	await _press("WorldDevelopment"); _find_screen()
	t.expect(hero_screen._model.hero_id==0 and hero_screen._model.nodes.is_empty(),"soul alone has no fake progression")
	await _capture("without-body.png")
	await _press("HeroDevelopmentBack"); await _press("WorldIncarnate8")
	await _press("WorldDevelopment"); _find_screen(); await _filter("Поиск"); await _press(_id("HeroTrack",TRACK)); _find_screen()
	t.equal(hero_screen._model.context.body_id,8,"new screen targets new incarnation")
	t.expect((app.find_child("HeroTrackSummary",true,false) as Label).text.contains("заработано 0"),"new body zero practice shown")
	t.expect(_button(_id("HeroBuy",NODE)).disabled,"new body has not learned former node")
	await _press("HeroDevelopmentSave"); await _capture("new-life.png")
	_finish()

func _find_screen() -> void: hero_screen=app.find_child("HeroDevelopmentScreen",true,false) as Sm2HeroDevelopmentScreen
static func _id(prefix: String,id: String) -> String: return Sm2HeroDevelopmentScreen.control_id(prefix,id)
func _filter(value: String) -> void:
	var input: LineEdit=app.find_child("HeroTrackFilter",true,false) as LineEdit
	input.grab_focus(); input.select_all()
	var erase: InputEventKey=InputEventKey.new(); erase.keycode=KEY_BACKSPACE; erase.pressed=true; root.push_input(erase,true)
	for character: String in value:
		var event: InputEventKey=InputEventKey.new(); event.unicode=character.unicode_at(0); event.pressed=true; root.push_input(event,true)
	await _frames()
