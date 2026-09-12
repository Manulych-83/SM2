extends "res://tests/p3_world_ui.gd"
const DEVICE_TEST=preload("res://tests/scenarios/test_survival_devices.gd")
const BODY_TEST=preload("res://tests/scenarios/test_p4_body.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _capture("menu.png"); await _press("NewSurvivalDevicesButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	if life==null: t.expect(false,"device screen starts"); _finish(); return
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(s.format_id(),"sm2.survival_journey_session.2","new device session")
	var device: String=s.journey().prostheses.items[0].id
	_choose(device); await _frames()
	t.expect(_button("Physical_attach_device").disabled,"healthy arm cannot accept prosthesis")
	await _capture("healthy.png")
	await _press("WorldSave"); var saved: String=s.state_hash()
	await _press("WorldMenu"); await _press("ContinueSurvivalDevicesButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.equal(life.session.state_hash(),saved,"production menu continuation exact")
	# Diagnostic authored encounter, real attacks; no direct editing of anatomy.
	s=Sm2JourneySession.new(DEVICE_TEST.loss_content(),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://device-ui-fixture"))
	t.expect(s.new_game().ok,"loss fixture starts")
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames()
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	device=s.journey().prostheses.items[0].id
	await _press("Travel_ruins"); await _fight(s)
	t.expect(s.world.hero_id()==2 and s.world.bodies[2].functions.missing.right_hand,"actual enemy severs hero hand")
	if s.world.hero_id()!=2 or not s.world.bodies[2].functions.missing.right_hand: _finish(); return
	await _capture("stump.png"); await _bandage_all()
	await _press("Travel_camp"); _choose(device); await _frames()
	var blood: int=s.journey().survival.bodies["2"].blood
	await _press("Physical_attach_device")
	t.expect(s.world.bodies[2].functions.working.right_hand,"mouse installs same physical device")
	t.equal(s.journey().survival.bodies["2"].blood,blood,"installation no blood restoration")
	await _capture("installed.png"); await _press("WorldSave"); saved=s.state_hash()
	_choose(device); await _frames(); await _press("Physical_detach_device")
	t.equal(s.journey().survival.inventory.items[device].place,"ground","mouse detachment explicit ground")
	await _press("WorldLoad"); t.equal(s.state_hash(),saved,"installed device exact load")
	await _press("Travel_ruins"); await _fight(s)
	t.equal(s.journey().survival.inventory.items[device].current,0,"real subsequent hit breaks device")
	await _capture("damaged.png")
	await _bandage_all(); await _press("Travel_camp"); _choose(device); await _frames()
	await _press("Physical_repair_device")
	t.equal(s.journey().survival.inventory.items[device].current,30,"mouse repair restores device")
	root.size=Vector2i(1280,800); await _frames(); await _capture("repaired.png")
	await _press("WorldEndLife"); await _press("WorldConfirmDeath"); await _press("WorldIncarnate18")
	t.equal(s.journey().survival.inventory.items[device].holder,"2","device stays on old corpse")
	_choose(device); await _frames(); await _press("Physical_detach_device")
	t.equal(s.journey().survival.inventory.items[device].holder,"camp","retrieved device keeps ID and explicit place")
	await _press("WorldSave"); saved=s.state_hash(); await _press("WorldLoad")
	t.equal(s.state_hash(),saved,"retrieved device and new incarnation exact save")
	await _capture("new-life.png"); _finish()

func _choose(id: String) -> void:
	var selector: OptionButton=app.find_child("PhysicalItemSelect",true,false) as OptionButton
	for index: int in selector.item_count:
		if str(selector.get_item_metadata(index))==id:
			selector.select(index); selector.item_selected.emit(index); return
	t.expect(false,"physical device visible in selector")

func _fight(s: Sm2JourneySession) -> void:
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	for index: int in 120:
		if not s.world.busy(): break
		var result: Dictionary=BODY_TEST.treatment_step(s)
		t.expect(result.ok,"real anatomical fight progression")
		if not result.ok: break
		screen.runner=s.runner; screen._refresh()
	t.expect(not s.world.busy(),"anatomical fight settles")
	await _capture("battle-%s.png" % s.journey().completed)
	await _press("BattleMenuButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen

func _bandage_all() -> void:
	for index: int in 16:
		var selected: Button=null
		for node: Node in app.find_children("*","Button",true,false):
			if str(node.name).begins_with("Physical_bandage") and not node.disabled: selected=node; break
		if selected==null: break
		await _press(str(selected.name))
