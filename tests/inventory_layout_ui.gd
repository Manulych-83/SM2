extends "res://tests/display_ui.gd"

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output); display_report={"captures":[]}
	await _frames()
	await set_resolution(Vector2i(2560,1440))
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewSurvivalTissuesButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var s: Sm2JourneySession=life.session as Sm2JourneySession; var before: String=s.state_hash()
	await _press("Guide_inventory")
	t.equal(workspace().ui.scope,1,"guide opens selected participant inventory")
	t.equal(workspace().cards.size(),8,"ten physical items shown as eight cards")
	await _card("59"); t.equal(workspace().ui.item,"59","physical click selects correct scaled card")
	await _capture("inventory-2560.png")
	# Mouse opens the real native popup; item activation exercises its signal gateway.
	await _press("WorkspaceInstance")
	var popup: PopupMenu=(app.find_child("WorkspaceInstance",true,false) as OptionButton).get_popup()
	t.expect(popup.visible,"instance popup is actually open")
	popup.index_pressed.emit(1); popup.hide(); await _frames()
	t.equal(workspace().ui.item,"60","popup chooses second physical bandage")
	await _card("60"); t.equal(workspace().ui.item,"60","revisiting the group keeps its chosen instance")
	_select("WorkspaceDestination","68"); await _frames()
	t.equal(s.state_hash(),before,"selection and destination do not move objects")
	await _press("WorkspaceStore")
	t.equal(s.journey().survival.inventory.items["60"].holder,"68","only selected instance moves to companion backpack")
	t.equal(s.journey().survival.inventory.items["59"].holder,"58","first instance stays in hero belt")
	t.equal(s.journey().survival.inventory.items["61"].holder,"58","third instance stays in hero belt")
	before=s.state_hash()
	await _press("WorkspaceContainer_58")
	t.equal(workspace().filtered.size(),2,"container filter reflects remaining exact items")
	t.equal(workspace().cards[0].ids,["59","61"],"remaining card has correct two IDs")
	await _press("WorkspaceContainer_62"); t.expect(workspace().cards.is_empty(),"empty backpack gives empty result")
	await _press("WorkspaceEquipment_weapon")
	t.equal(workspace().ui.item,"20","equipment slot selects actual sword and clears filters")
	t.equal(workspace().ui.storage,"","equipment remains reachable from empty container")
	await _press("WorkspacePerson_4")
	t.equal(workspace().view.body.id,4,"portrait selects companion")
	await _press("WorkspaceContainer_68"); t.equal(workspace().cards[0].ids,["60"],"companion backpack contains transferred instance")
	await _press("WorkspacePerson_2"); await _press("WorkspaceBodyTab"); await _press("WorkspacePart_right_hand")
	t.equal(workspace().composition.figure.selected,"right_hand","anatomy marker follows actual selected part")
	t.expect(workspace().composition.figure.anatomy,"body view does not draw equipment over anatomy")
	await _capture("body-2560.png")
	await _press("WorkspaceDevelopment")
	t.expect(is_instance_valid(workspace().development_screen),"existing hero development opens above workspace")
	t.expect(not workspace().layout.visible,"workspace is hidden beneath development")
	await _press("HeroDevelopmentBack")
	t.expect(workspace().layout.visible and not is_instance_valid(workspace().development_screen),"return restores same workspace")
	t.equal(workspace().ui.part,"right_hand","return retains inspected part")
	t.equal(s.state_hash(),before,"all viewing and development navigation are read only")
	await _press("WorkspaceInventoryTab")
	for dimensions: Vector2i in [Vector2i(1920,1080),Vector2i(1280,720),Vector2i(1280,800)]:
		await set_resolution(dimensions); await _press("WorkspaceEquipment_weapon")
		t.equal(workspace().ui.item,"20","physical slot input survives aspect scaling")
		await _capture("inventory-%s-%s.png" % [dimensions.x,dimensions.y])
	await _press("WorkspaceBack"); await _press("WorldSave"); before=s.state_hash(); await _press("WorldLoad")
	t.equal(s.state_hash(),before,"individual transfer survives exact save/load")
	_finish()

func workspace() -> Sm2SurvivalWorkspace:
	return app.find_child("SurvivalWorkspace",true,false) as Sm2SurvivalWorkspace

func _card(id: String) -> void:
	var list: ItemList=workspace().item_list
	for index: int in workspace().cards.size():
		if id not in workspace().cards[index].ids: continue
		await _mouse(list.global_position+list.get_item_rect(index).get_center(),false); return
	t.expect(false,"visible card contains "+id)

func _select(name: String,id: String) -> void:
	var selector: OptionButton=app.find_child(name,true,false) as OptionButton
	for index: int in selector.item_count:
		if str(selector.get_item_metadata(index))==id: selector.select(index); selector.item_selected.emit(index); return
	t.expect(false,"destination exists "+id)
