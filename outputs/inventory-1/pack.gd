extends SceneTree
var app: Control
var failed: bool=false
func _initialize() -> void: call_deferred("run")
func frames() -> void:
	for i: int in 4: await process_frame
func check(value: bool,message: String) -> void:
	if not value: failed=true; push_error(message)
func press(id: String) -> void:
	var button: Button=app.find_child(id,true,false) as Button
	check(button!=null and not button.disabled,"packed button: "+id)
	if button!=null and not button.disabled: button.pressed.emit(); await frames()
func run() -> void:
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate(); root.add_child(app); await frames()
	check(ProjectSettings.get_setting("application/config/version")=="0.8.41-inventory.1","packed version")
	await press("NewSurvivalTissuesButton"); await press("CampInventory")
	var workspace: Sm2SurvivalWorkspace=app.find_child("SurvivalWorkspace",true,false)
	check(workspace.layout.name=="InventoryHome","packed inventory shell")
	check(workspace.inventory_composition.row_buttons.size()<=6,"packed page is bounded")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("E:/GPT/SM2/outputs/inventory-1/pack-inventory.png")
	await press("WorkspaceEquipment_weapon"); var id: String=workspace.ui.item
	await press("WorkspaceDrop")
	check(workspace.session.journey().survival.inventory.items[id].place=="ground","packed action changes actual inventory")
	await press("InventoryNav_body"); await press("CharacterNav_inventory"); await press("WorkspaceBack"); await press("WorldSave")
	var life: Sm2LifeScreen=app.find_child("LifeScreen",true,false); var expected: String=life.session.state_hash()
	await press("WorldMenu"); await press("ContinueSurvivalTissuesButton")
	life=app.find_child("LifeScreen",true,false); check(life.session.state_hash()==expected,"packed checkpoint restores inventory")
	await press("CampInventory")
	if not failed: print("SM2_INVENTORY_1_PACK_OK")
	app.queue_free(); await frames(); quit(1 if failed else 0)
