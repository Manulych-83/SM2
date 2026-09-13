extends "res://tests/display_ui.gd"
const PSI_TRACK: String="p1:skill.psionics"
const RESONANCE: String="p4a:stat.resonance"
const IMPULSE: String="p5:node.impulse"

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output); display_report={"captures":[]}
	await set_resolution(Vector2i(2560,1440))
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewSurvivalTissuesButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var s: Sm2JourneySession=life.session as Sm2JourneySession; var before: String=s.state_hash()
	await _press("Guide_development")
	await _press("HeroKind_attribute")
	t.equal(hero().find_children("HeroTrack_*","Button",true,false).size(),8,"all eight authored attributes visible")
	await _press(_id("HeroTrack","p1:stat.strength"))
	await _capture("attributes-2560.png")
	await _press("HeroKind_skill"); await _press(_id("HeroTrack",PSI_TRACK))
	t.expect(_button(_id("HeroBuy",IMPULSE)).disabled,"untrained hero cannot buy impulse")
	t.expect(not hero()._sources.practice.is_empty(),"actual practice sources shown for selected skill")
	await _capture("untrained-2560.png")
	await _press("HeroDevelopmentCompanion")
	t.expect(hero().find_children("HeroBuy_*","Button",true,false).is_empty(),"companion cannot buy hero nodes")
	t.equal(hero().find_children("CompanionAttribute_*","Label",true,false).size(),8,"companion automatic attribute values shown")
	await _capture("companion-2560.png")
	await _press("HeroDevelopmentHero")
	t.equal(s.state_hash(),before,"view modes and filters cannot award XP")
	for index: int in 8: t.expect(s.act(s.command("practice",2,"p5:activity.psionics")).ok,"real psionic exercise")
	hero().redraw(); await _frames()
	var old: Button=_button(_id("HeroBuy",IMPULSE)); t.expect(not old.disabled,"earned XP unlocks purchase")
	t.expect(s.act(s.command("practice",2,"p5:activity.psionics")).ok,"external action advances revision")
	before=s.state_hash(); old.pressed.emit(); await _frames()
	t.equal(s.state_hash(),before,"stale button cannot buy in newer revision")
	await _press(_id("HeroBuy",IMPULSE))
	t.expect(IMPULSE in s.world.bodies[2].progress.tracks[PSI_TRACK].nodes,"mouse buys actual impulse")
	var earned: int=s.world.bodies[2].progress.tracks[PSI_TRACK].earned
	t.equal(earned,225,"purchase preserves nine authored exercises of twenty-five XP")
	var selector: OptionButton=app.find_child("HeroNodeFilter",true,false) as OptionButton
	selector.select(2); selector.item_selected.emit(2); await _frames()
	t.equal(hero().find_children("HeroBuy_*","Button",true,false).size(),1,"owned filter shows only purchased node")
	selector=app.find_child("HeroNodeFilter",true,false) as OptionButton
	selector.select(0); selector.item_selected.emit(0); await _frames()
	await _capture("psionics-2560.png")
	await _press("HeroDevelopmentSave"); before=s.state_hash(); await _press("HeroDevelopmentLoad")
	t.equal(s.state_hash(),before,"save/load keeps actual purchase and XP")
	t.expect(s.act(s.command("travel",0,"enclave")).ok,"reach implant workshop")
	t.expect(s.act(s.command("collect_upgrade",0,"p5:upgrade.psi_amplifier")).ok,"collect real kit")
	t.expect(s.act(s.command("apply_upgrade",2,"p5:upgrade.psi_amplifier")).ok,"install real implant")
	hero()._kind=""; hero()._select(RESONANCE,""); await _frames()
	t.equal(hero()._model.selected.upgrade_bonus,2,"implant bonus displayed separately")
	t.equal(hero()._model.selected.earned,0,"implant does not fabricate resonance practice")
	await _capture("resonance-2560.png")
	for dimensions: Vector2i in [Vector2i(1920,1080),Vector2i(1280,720),Vector2i(1280,800)]:
		await set_resolution(dimensions); await _press(_id("HeroTrack",PSI_TRACK))
		t.equal(hero().selected_id,PSI_TRACK,"scaled input selects intended skill")
		await _capture("development-%s-%s.png" % [dimensions.x,dimensions.y])
	for down: bool in [true,false]:
		var escape: InputEventKey=InputEventKey.new(); escape.keycode=KEY_ESCAPE; escape.physical_keycode=KEY_ESCAPE; escape.pressed=down; root.push_input(escape)
	await _frames()
	t.expect(app.find_child("HeroDevelopmentScreen",true,false)==null,"escape returns from development")
	_finish()

func hero() -> Sm2HeroDevelopmentScreen:
	return app.find_child("HeroDevelopmentScreen",true,false) as Sm2HeroDevelopmentScreen
func _id(prefix: String,id: String) -> String: return Sm2HeroDevelopmentScreen.control_id(prefix,id)
