extends "res://tests/p3_world_ui.gd"
const SHIELD=preload("res://tests/scenarios/test_p5_shield.gd")
var display_report: Dictionary={}

func _press(id: String) -> void:
	if id=="ResumeMainButton" and _button(id)==null and app._page=="menu": await super._press("CampaignsButton")
	# Follow the real camp navigation after splitting the former single long page.
	var target: Button=_button(id)
	var camp: Sm2LifeScreen=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	if (target==null or not target.is_visible_in_tree()) and camp!=null and is_instance_valid(camp._content) and camp._content.is_visible_in_tree():
		var destination: String=""
		if id.begins_with("Travel_") or id.begins_with("MapLocation_") or id.begins_with("Guide_"): destination="CampMap"
		elif id=="PsiTrain" or id.begins_with("Explore_") or id.begins_with("Upgrade") or id.begins_with("WorldIncarnate") or id in ["WorldEndLife","WorldDeposit","WorldTake"]: destination="CampActivities"
		elif id in ["CampInventory","WorldBodyInventory","CampSoul","CampJournal","CampSettings","CampMap","CampActivities","WorldBattle"]: destination="home"
		if not destination.is_empty():
			if camp._camp_page!="home": await super._press("CampHomeBack")
			if destination!="home": await super._press(destination)
	await super._press(id)

func _initialize() -> void:
	# Keep project startup settings, unlike the historical pixel layout suites.
	call_deferred("_run")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	await _frames()
	display_report={"mode":root.mode,"window":str(root.size),"base":str(root.content_scale_size),"ui_scale":root.content_scale_factor,"logical":str(root.get_visible_rect().size),"driver":DisplayServer.get_name(),"captures":[]}
	t.equal(root.mode,Window.MODE_EXCLUSIVE_FULLSCREEN,"production fullscreen startup")
	t.equal(root.content_scale_size,Vector2i(2560,1440),"QHD design size")
	t.expect(is_equal_approx(root.content_scale_factor,1.6),"readable design scale")
	t.equal(root.content_scale_aspect,Window.CONTENT_SCALE_ASPECT_KEEP,"preserve 16:9")
	t.equal(root.content_scale_mode,Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,"native resolution 2D rendering")
	if DisplayServer.get_name()!="headless":
		display_report["monitor"]=str(DisplayServer.screen_get_size(root.current_screen))
		t.equal(root.size,DisplayServer.screen_get_size(root.current_screen),"fullscreen covers monitor")
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _capture("menu-fullscreen.png")
	# If this workstation has another monitor size, render QHD in a separate test window.
	if root.size!=Vector2i(2560,1440): await set_resolution(Vector2i(2560,1440))
	await _press("NewSurvivalTissuesButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	await _capture("camp-2560.png")
	var before: String=s.state_hash()
	await _press("Guide_inventory"); await _capture("inventory-2560.png")
	await _press("WorkspaceBodyTab"); await _capture("body-2560.png")
	await _press("WorkspaceBack"); await _press("Guide_development"); await _capture("development-2560.png")
	await _press("HeroDevelopmentBack")
	t.equal(s.state_hash(),before,"scaled screen navigation is read only")
	SHIELD.learn(s,t); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen; life.redraw(); await _frames()
	await _press("Guide_travel_0_ruins"); await _press("Guide_start_battle_0_")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	before=s.state_hash()
	await _capture("layout-overview-2560.png")
	await _press("HudParty_2")
	t.equal(screen._active,1,"party inspection cannot seize turn")
	t.equal(screen.hud.layout.active_name.text,"Герой","bottom card stays on active actor")
	t.expect(screen.hud.person.text.contains("Спутник"),"party opens companion context")
	await _press("HudCloseContext")
	t.expect(not screen.hud.context_panel.visible,"context can be closed")
	await _press("HudCategory_aimed")
	t.expect(_button("Ability_hand_strike").is_visible_in_tree(),"aimed group reveals real hand attack")
	t.expect(not _button("Ability_impulse").is_visible_in_tree(),"filter hides psi without removing it")
	await _press("HudCategory_main")
	t.expect(_button("Ability_impulse").is_visible_in_tree(),"main group restores psi")
	await _key(KEY_3)
	t.equal(s.state_hash(),before,"disabled sword shortcut does not act")
	await _press("DevelopmentButton")
	var selection_before: String=screen._selected
	await _key(KEY_4)
	t.equal(screen._selected,selection_before,"development overlay blocks combat keys")
	t.equal(s.state_hash(),before,"overlay key cannot change battle")
	await _press("CloseDevelopmentButton")
	await _key(KEY_4)
	t.equal(screen._selected,"p5:ability.impulse","number key selects displayed fourth action")
	var motion: InputEventMouseMotion=InputEventMouseMotion.new()
	motion.position=root.get_final_transform()*(screen.board.global_position+screen.board.center(Vector2i(4,1)))
	root.push_input(motion,false); await _frames()
	t.expect(screen.hud.context_panel.visible,"target hover opens context")
	t.expect(screen.hud.person.text.contains("3"),"target context identifies actual enemy")
	t.equal(screen.hud.layout.active_name.text,"Герой","target hover leaves active card intact")
	await _capture("layout-target-2560.png")
	await _press("HudDetails")
	t.expect(screen._inspector.text.contains("№3"),"details match hovered identity")
	await _press("HudCloseContext")
	await _press("MoveButton")
	t.equal(s.state_hash(),before,"categories shortcuts and context are read-only")
	for dimensions: Vector2i in [Vector2i(2560,1440),Vector2i(1920,1080),Vector2i(1280,720),Vector2i(1280,800)]:
		await set_resolution(dimensions)
		t.equal(Vector2i(root.get_visible_rect().size),Vector2i(1600,900),"same logical composition "+str(dimensions))
		if dimensions==Vector2i(1280,800): t.equal(root.get_final_transform().origin,Vector2(0,40),"16:10 has symmetric 40 pixel letterbox offset")
		for row: int in screen.board.field.height():
			for col: int in screen.board.field.width():
				var cell: Vector2i=Vector2i(col,row); t.equal(screen.board.pick(screen.board.center(cell)),cell,"hex picking under scaling")
		await _press("HudTurn_3"); t.equal(screen._inspected,3,"scaled queue click")
		await _press("HudTurn_1")
		await _capture("battle-%s-%s.png" % [dimensions.x,dimensions.y])
	t.equal(s.state_hash(),before,"resizing and inspection preserve session")
	# Physical pixel input exercises the engine stretch transform, including 16:10 bars.
	await _cell(Vector2i(2,1),false)
	t.equal(int(screen._actor(1).q),2,"scaled native-pixel click moves to intended hex")
	await _key(KEY_5); t.equal(screen._actor(1).barrier.remaining,18,"scaled shortcut casts real shield once")
	await _press("SaveBattleButton"); before=s.state_hash(); await _press("LoadBattleButton")
	t.equal(s.state_hash(),before,"scaled save/load exact")
	await set_resolution(Vector2i(2560,1440))
	await _capture("shield-2560.png")
	var file: FileAccess=FileAccess.open(output.path_join("display.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(display_report,"\t")); file.close()
	_finish()

func set_resolution(dimensions: Vector2i) -> void:
	root.mode=Window.MODE_WINDOWED; root.borderless=true; root.size=dimensions
	await _frames(); await _frames()
	t.equal(root.size,dimensions,"requested physical window size")

func _mouse(point: Vector2,right: bool) -> void:
	var physical: Vector2=root.get_final_transform()*point
	for pressed: bool in [true,false]:
		var event: InputEventMouseButton=InputEventMouseButton.new()
		event.position=physical; event.global_position=physical; event.button_index=MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT; event.pressed=pressed
		root.push_input(event,false)
	await _frames()

func _capture(filename: String) -> void:
	await super._capture(filename)
	if DisplayServer.get_name()!="headless":
		var picture: Image=root.get_texture().get_image()
		var scale: float=minf(float(root.size.x)/2560.0,float(root.size.y)/1440.0)
		var active_pixels: Vector2i=Vector2i(Vector2(2560,1440)*scale)
		# Viewport readback contains the rendered area; OS letterbox bars are outside it.
		t.equal(picture.get_size(),active_pixels,"native render size inside preserved aspect area")
		display_report.captures.append({"file":filename,"window":str(root.size),"pixels":str(picture.get_size()),"logical":str(root.get_visible_rect().size),"offset":str(root.get_final_transform().origin)})

func _key(code: Key) -> void:
	for pressed: bool in [true,false]:
		var event: InputEventKey=InputEventKey.new(); event.physical_keycode=code; event.pressed=pressed; root.push_input(event)
	await _frames()
