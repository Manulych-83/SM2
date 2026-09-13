extends "res://tests/inventory_layout_ui.gd"

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output); display_report={"captures":[]}
	await set_resolution(Vector2i(2560,1440))
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewSurvivalTissuesButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	var s: Sm2JourneySession=life.session as Sm2JourneySession; var inv: Sm2PhysicalInventory=s.journey().survival.inventory
	var bandages: Array[String]=[]; var pack: String=""; var belt: String=""; var sword: String=""
	for id: String in inv.ids():
		var row: Dictionary=inv.items[id]
		if row.definition_id=="bandage" and inv.owner(id)==s.world.hero_id(): bandages.append(id)
		if row.definition_id=="backpack" and inv.owner(id)==4: pack=id
		if row.definition_id=="belt" and inv.owner(id)==s.world.hero_id(): belt=id
		if row.place=="equipped" and inv.owner(id)==s.world.hero_id() and s.journey().survival.catalog.item(row.definition_id).slot=="weapon": sword=id
	t.equal(bandages.size(),3,"three distinct bandages in actual inventory")
	await _press("CampInventory"); var before: String=s.state_hash()
	t.expect(workspace().layout.name=="InventoryHome","camp opens approved inventory shell")
	t.expect(workspace().inventory_composition.row_buttons.size()<=6,"at most six rows are constructed")
	await choose_exact(bandages[0]); await _capture("inventory-2560.png")
	await _press("WorkspaceInstance")
	var popup: PopupMenu=(app.find_child("WorkspaceInstance",true,false) as OptionButton).get_popup()
	popup.index_pressed.emit(1); popup.hide(); await _frames()
	t.equal(workspace().ui.item,bandages[1],"group chooses second physical instance")
	_select("WorkspaceDestination",pack); await _frames(); t.equal(s.state_hash(),before,"selection does not move items")
	await _press("WorkspaceStore")
	t.equal(s.journey().survival.inventory.items[bandages[1]].holder,pack,"exact selected instance transferred to companion")
	t.expect(s.journey().survival.inventory.items[bandages[0]].holder!=pack,"other grouped instance stays")
	await _press("InventoryScope_1_4")
	t.equal(workspace().ui.body,4,"companion tab selects companion equipment")
	t.expect(workspace().filtered.any(func(row: Dictionary) -> bool: return row.id==bandages[1]),"companion filter includes received instance")
	await _press("InventoryScope_2_0"); _select("InventoryStorage",pack); await _frames()
	t.expect(workspace().filtered.any(func(row: Dictionary) -> bool: return row.id==bandages[1]),"container selection from ground shows its contents")
	t.equal(workspace().filtered.size(),1,"container filter excludes other holders")
	await _press("InventoryScope_1_2")
	await _press("WorkspaceEquipment_weapon"); t.equal(workspace().ui.item,sword,"equipment click finds correct page and instance")
	_select("WorkspaceDestination",belt); await _frames()
	t.expect(_button("WorkspaceStore").disabled and not _button("WorkspaceStore").tooltip_text.is_empty(),"unsuitable container refuses sword with explanation")
	await _press("WorkspaceDrop"); t.equal(s.journey().survival.inventory.items[sword].place,"ground","drop leaves actual weapon on ground")
	await choose_exact(sword); await _press("WorkspaceWear"); t.equal(s.journey().survival.inventory.items[sword].place,"equipped","wear restores same weapon")
	await _press("InventoryScope_0_0"); before=s.state_hash()
	t.expect(not _button("InventoryNext").disabled,"nearby contents span several pages")
	await _press("InventoryNext"); t.equal(int(workspace().ui.inventory_page),1,"next page advances")
	t.expect(workspace().cards.size()<=6,"second page remains bounded")
	var search: LineEdit=app.find_child("WorkspaceSearch",true,false) as LineEdit
	search.text="ничего_такого"; search.text_changed.emit(search.text); await _frames()
	t.equal(workspace().inventory_composition.row_buttons.size(),0,"empty search clears visible list and detail")
	t.expect(_button("WorkspaceStore")==null,"empty result has no stale transfer command")
	search.text=""; search.text_changed.emit(""); await _frames(); t.equal(int(workspace().ui.inventory_page),0,"new search returns to first page")
	t.equal(s.state_hash(),before,"paging and filters are read only")
	await choose_exact(bandages[0]); t.expect(s.act(s.command("practice",2,"p5:activity.psionics")).ok,"advance revision through existing action")
	before=s.state_hash(); await _press("WorkspaceDrop")
	t.equal(s.state_hash(),before,"stale inventory command rejected atomically")
	t.expect(workspace().message.contains("Устаревшая"),"stale action explains refusal")
	for dimensions: Vector2i in [Vector2i(1920,1080),Vector2i(1280,720),Vector2i(1280,800)]:
		await set_resolution(dimensions); await _press("WorkspaceEquipment_weapon")
		await _capture("inventory-%s-%s.png" % [dimensions.x,dimensions.y])
		var panel: Control=workspace().details.get_parent().get_parent()
		t.expect(panel.get_global_rect().end.x<=workspace().size.x,"detail panel stays inside viewport")
	await _press("InventoryNav_body"); t.expect(workspace().layout.name=="CharacterLayout","inventory reaches character")
	await _press("CharacterNav_inventory"); t.expect(workspace().layout.name=="InventoryHome","character returns to modern inventory")
	await _press("InventoryTreatment"); t.expect(_button("CharacterTab_body").button_pressed,"treatment opens existing body actions")
	await _key(KEY_ESCAPE); await _press("WorldSave"); before=s.state_hash(); await _press("WorldLoad")
	t.equal(s.state_hash(),before,"inventory changes survive exact checkpoint restore")
	_finish()

func choose_exact(id: String) -> void:
	workspace().ui.scope=0; workspace().ui.storage=""; workspace().ui.query=""; workspace().ui.item=id; workspace().refresh(); await _frames()
	await _card(id)

func _card(id: String) -> void:
	for index: int in workspace().cards.size():
		if id in workspace().cards[index].ids: await _press("InventoryRow_"+str(index)); return
	t.expect(false,"visible row contains "+id)
