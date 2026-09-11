extends "res://tests/p4_hero_screen_ui.gd"
const CROSS=preload("res://tests/scenarios/test_p5_cross_nodes.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(app); await _frames()
	var session: Sm2JourneySession=CROSS.prepared(t)
	app.set("_life",session); app.set("_page","life"); app.call("_redraw_page"); await _frames()
	await _press("WorldDevelopment"); _find_screen()
	await _press(_id("HeroTrack",CROSS.MELEE)); _find_screen()
	var card: Control=app.find_child(_id("HeroNode",CROSS.NODE),true,false) as Control
	t.expect(card!=null,"cross node card visible")
	if card==null: _finish(); return
	hero_screen._details.ensure_control_visible(card); await _frames()
	t.expect(not _button(_id("HeroBuy",CROSS.NODE)).disabled,"own practice enables purchase")
	var requirement: Button=_button(_id("HeroCrossRequirement",CROSS.NODE+CROSS.PSI))
	t.expect(requirement!=null and requirement.text.contains("требуется 2"),"second own level displayed")
	var extra_price: bool=false
	for label: Node in card.find_children("*","Label",true,false):
		extra_price=extra_price or (label as Label).text.contains("Дополнительно: 90")
	t.expect(extra_price,"second payment visible in card")
	await _capture("two-prices.png")
	var before: String=session.state_hash()
	await _press(_id("HeroCrossRequirement",CROSS.NODE+CROSS.PSI)); _find_screen()
	t.equal(hero_screen.selected_id,CROSS.PSI,"requirement navigates to psi track")
	t.equal(session.state_hash(),before,"navigation does not spend practice")
	await _press(_id("HeroTrack",CROSS.MELEE)); _find_screen()
	await _press(_id("HeroBuy",CROSS.NODE)); _find_screen()
	t.equal([session.world.bodies[2].progress.tracks[CROSS.MELEE].spent,session.world.bodies[2].progress.tracks[CROSS.PSI].spent],[70,90],"real click pays both directions")
	t.expect(_button(_id("HeroBuy",CROSS.NODE)).disabled,"owned cross node disabled")
	root.size=Vector2i(1280,800); await _frames()
	hero_screen._details.ensure_control_visible(app.find_child(_id("HeroNode",CROSS.NODE),true,false) as Control); await _frames()
	await _capture("learned.png")
	before=session.state_hash(); await _press("HeroDevelopmentSave"); await _press("HeroDevelopmentLoad")
	t.equal(session.state_hash(),before,"screen disk roundtrip no duplicate payment")
	await _press("HeroDevelopmentBack"); await _press("WorldEndLife"); await _press("WorldConfirmDeath"); await _press("WorldIncarnate8")
	await _press("WorldDevelopment"); _find_screen(); await _press(_id("HeroTrack",CROSS.MELEE)); _find_screen()
	t.expect(_button(_id("HeroBuy",CROSS.NODE)).disabled,"new body needs practice again")
	t.equal([session.world.bodies[8].progress.tracks[CROSS.MELEE].spent,session.world.bodies[8].progress.tracks[CROSS.PSI].spent],[0,0],"new body has clean balances")
	_finish()
