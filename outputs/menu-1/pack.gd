extends SceneTree
func _initialize() -> void: call_deferred("run")

func frames() -> void:
	await process_frame; await process_frame; await process_frame

func run() -> void:
	if ProjectSettings.get_setting("application/config/version")!="0.8.39-menu.1": fail("version"); return
	root.mode=Window.MODE_WINDOWED; root.borderless=true; root.size=Vector2i(2560,1440)
	var app: Control=(load("res://scenes/main.tscn") as PackedScene).instantiate(); root.add_child(app); await frames()
	var start: Button=app.find_child("NewSurvivalTissuesButton",true,false) as Button
	if start==null: fail("new incarnation"); return
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png("E:/GPT/SM2/outputs/menu-1/pack-new-2560.png")!=OK: fail("capture"); return
	(app.find_child("SettingsButton",true,false) as Button).pressed.emit(); await frames()
	if app.find_child("SettingsScreen",true,false)==null: fail("settings"); return
	(app.find_child("SettingsBack",true,false) as Button).pressed.emit(); await frames()
	(app.find_child("CampaignsButton",true,false) as Button).pressed.emit(); await frames()
	if app.find_children("CampaignOpen_*","Button",true,false).size()!=3: fail("three slots"); return
	(app.find_child("CampaignClose",true,false) as Button).pressed.emit(); await frames()
	(app.find_child("NewSurvivalTissuesButton",true,false) as Button).pressed.emit(); await frames()
	(app.find_child("WorldSave",true,false) as Button).pressed.emit(); await frames()
	var saved: String=app._life.state_hash()
	(app.find_child("WorldMenu",true,false) as Button).pressed.emit(); await frames()
	var resume: Button=app.find_child("ContinueSurvivalTissuesButton",true,false) as Button
	if resume==null: fail("continue after save"); return
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png("E:/GPT/SM2/outputs/menu-1/pack-continue-2560.png")!=OK: fail("capture"); return
	resume.pressed.emit(); await frames()
	if app._life.state_hash()!=saved: fail("exact restore"); return
	(app.find_child("WorldMenu",true,false) as Button).pressed.emit(); await frames()
	print("SM2_MENU_1_PACK_OK: new incarnation, settings, three slots, save and exact restore")
	app.tree_exiting.connect(func() -> void: print("SM2_MENU_1_QUIT_OK"))
	(app.find_child("QuitButton",true,false) as Button).pressed.emit()
	await create_timer(0.5).timeout
	fail("close button did not terminate the game")

func fail(message: String) -> void: push_error(message); quit(1)
