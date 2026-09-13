extends SceneTree
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if ProjectSettings.get_setting("application/config/version")!="0.8.38-camp.1": fail("pack version"); return
	var service: Sm2Campaigns=Sm2Campaigns.new("user://camp-pack-check")
	var opened: Dictionary=service.open(0,false)
	if not opened.get("ok",false): fail("new campaign"); return
	var session: Sm2CheckpointSession=opened.session
	var before: String=session.state_hash()
	var camp: Sm2LifeScreen=Sm2LifeScreen.new(); camp.session=session; root.add_child(camp)
	await process_frame; await process_frame
	var scene: Sm2CampScene=camp.find_child("CampScene",true,false) as Sm2CampScene
	if scene==null or scene.background.texture==null or scene.fire.texture==null or scene.figure==null: fail("packed scene layers"); return
	for entry: Dictionary in scene.manifest.backgrounds.values():
		if load(entry.path)==null: fail("packed background"); return
	for dimensions: Vector2i in [Vector2i(2560,1440),Vector2i(1280,720)]:
		root.mode=Window.MODE_WINDOWED; root.borderless=true; root.size=dimensions
		await process_frame; await process_frame; await process_frame
		await RenderingServer.frame_post_draw
		var picture: Image=root.get_texture().get_image()
		if picture.get_size()!=dimensions: fail("render size"); return
		if picture.save_png("E:/GPT/SM2/outputs/camp-1/pack-camp-%s.png" % dimensions.x)!=OK: fail("capture"); return
	if session.state_hash()!=before: fail("presentation changed world"); return
	if not session.save_game().ok: fail("save"); return
	var restored: Dictionary=service.open(0,true)
	if not restored.ok or restored.session.state_hash()!=before: fail("restore"); return
	print("SM2_CAMP_1_PACK_OK: separate scene layers, QHD/720p, unchanged world, save/load")
	quit(0)

func fail(message: String) -> void:
	push_error(message); quit(1)
