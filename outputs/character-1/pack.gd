extends SceneTree
var app: Control
var failed: bool=false
func _initialize() -> void: call_deferred("run")
func frames() -> void:
	for i: int in 4: await process_frame
func check(value: bool, message: String) -> void:
	if not value: failed=true; push_error(message)
func press(id: String) -> void:
	var button: Button=app.find_child(id,true,false) as Button
	check(button!=null and not button.disabled,"packed button: "+id)
	if button!=null and not button.disabled: button.pressed.emit(); await frames()
func run() -> void:
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate(); root.add_child(app); await frames()
	check(ProjectSettings.get_setting("application/config/version")=="0.8.40-character.1","packed version")
	await press("NewSurvivalTissuesButton"); await press("WorldBodyInventory")
	check(app.find_child("CharacterLayout",true,false)!=null,"packed character shell")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("E:/GPT/SM2/outputs/character-1/pack-character.png")
	await press("CharacterTab_body"); await press("WorkspacePart_right_hand"); await press("CharacterTab_upgrades")
	await press("WorkspaceBack"); await press("WorldSave")
	var life: Sm2LifeScreen=app.find_child("LifeScreen",true,false)
	var expected: String=life.session.state_hash()
	await press("WorldMenu"); await press("ContinueSurvivalTissuesButton")
	life=app.find_child("LifeScreen",true,false)
	check(life.session.state_hash()==expected,"packed checkpoint restores")
	await press("WorldBodyInventory"); await press("CharacterDevelopment"); await press("HeroDevelopmentBack")
	if not failed: print("SM2_CHARACTER_1_PACK_OK")
	app.queue_free(); await frames(); quit(1 if failed else 0)
