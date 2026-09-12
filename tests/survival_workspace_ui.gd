extends "res://tests/p3_world_ui.gd"
const TISSUES=preload("res://tests/scenarios/test_survival_tissues.gd")
const BODY_TEST=preload("res://tests/scenarios/test_p4_body.gd")

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _press("NewSurvivalTissuesButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	if life==null: t.expect(false,"world opens"); _finish(); return
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	var before: String=s.state_hash()
	await _press("WorldBodyInventory")
	t.expect(workspace()!=null,"dedicated workspace opens")
	if workspace()==null: _finish(); return
	await _press("WorkspacePart_right_hand"); await _capture("body-1000.png")
	_person(4); await _frames(); t.equal(workspace().view.body.id,4,"companion selected")
	_person(2); await _frames(); await _press("WorkspaceInventoryTab")
	t.equal(s.state_hash(),before,"opening selecting and switching tabs never change simulation")
	var scopes: OptionButton=app.find_child("WorkspaceScope",true,false) as OptionButton
	for scope: int in [1,2,3]:
		scopes.select(scope); scopes.item_selected.emit(scope); await _frames()
		for item: Dictionary in workspace().filtered:
			t.expect(int(item.owner)==2 if scope==1 else item.place=="ground" if scope==2 else bool(item.stash),"storage scope filters actual placement")
	scopes.select(0); scopes.item_selected.emit(0); await _frames()
	var sword: String=""
	for item: Dictionary in workspace().view.items:
		if int(item.owner)==2 and item.slot=="weapon": sword=item.id; break
	_choose(sword); await _frames(); await _press("WorkspaceDrop")
	t.equal(s.journey().survival.inventory.items[sword].place,"ground","mouse drops equipped weapon")
	await _press("WorkspaceWear")
	t.equal(s.journey().survival.inventory.items[sword].place,"equipped","mouse equips same weapon again")
	var hero_bandages: Array[String]=[]
	var companion_pack: String=""; var hero_belt: String=""; var supplies: Array[String]=[]
	for id: String in s.journey().survival.inventory.ids():
		var entry: Dictionary=s.journey().survival.inventory.items[id]
		var owner: int=s.journey().survival.inventory.owner(id)
		if entry.definition_id=="backpack" and owner==4: companion_pack=id
		if entry.definition_id=="belt" and owner==2: hero_belt=id
		if entry.definition_id=="bandage":
			if owner==2: hero_bandages.append(id)
			elif owner==0: supplies.append(id)
	_choose(hero_bandages[0]); _destination(companion_pack); await _frames(); await _press("WorkspaceStore")
	t.equal(s.journey().survival.inventory.owner(hero_bandages[0]),4,"mouse transfer to companion physical container")
	t.equal(workspace().ui.item,hero_bandages[0],"chosen item survives redraw")
	# Fill the real belt, then show its actual refusal without spending or losing items.
	for index: int in 4:
		_choose(supplies[index]); _destination(hero_belt); await _frames(); await _press("WorkspaceStore")
	_choose(supplies[4]); await _frames()
	t.expect(_button("WorkspaceStore").disabled,"full belt disables transfer")
	t.expect(_button("WorkspaceStore").tooltip_text.contains("объёма"),"capacity reason visible from domain")
	await _capture("inventory-full.png")
	var search: LineEdit=app.find_child("WorkspaceSearch",true,false) as LineEdit
	search.text="нет-такой-вещи"; search.text_changed.emit(search.text); await _frames()
	t.equal((app.find_child("WorkspaceItems",true,false) as ItemList).item_count,0,"search empty state")
	search.text=""; search.text_changed.emit(""); await _frames()
	_choose(supplies[4]); before=s.state_hash()
	t.expect(s.act(s.command("practice",2,"p5:activity.psionics")).ok,"external revision advance for stale UI test")
	before=s.state_hash(); await _press("WorkspaceDrop")
	t.equal(s.state_hash(),before,"stale rendered action rejected atomically")
	t.expect(workspace().message.contains("Устаревшая"),"stale action explains reason")
	var selected_item: String=workspace().ui.item
	var cancel: InputEventKey=InputEventKey.new(); cancel.keycode=KEY_ESCAPE; cancel.pressed=true; root.push_input(cancel,true); await _frames()
	t.expect(workspace()==null,"Escape returns to camp")
	await _press("WorldBodyInventory"); t.equal(workspace().ui.item,selected_item,"reopening retains selected item")
	await _press("WorkspaceBack"); await _press("WorldSave"); before=s.state_hash()
	await _press("WorldMenu"); await _press("ContinueSurvivalTissuesButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	t.equal(life.session.state_hash(),before,"production save continues same existing format")
	# Full anatomical route uses authored attacks; no editing body state.
	s=Sm2JourneySession.new(TISSUES.content(true),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://workspace-ui-route"))
	t.expect(s.new_game().ok,"authored route starts")
	app.set("_life",s); app.set("_page","life"); app.call("_redraw_page"); await _frames()
	await _press("Travel_ruins"); await _fight(s)
	t.expect(s.world.hero_id()==2 and s.world.bodies[2].functions.missing.right_hand,"real severing produces missing hand")
	if s.world.hero_id()!=2: _finish(); return
	await _press("WorldBodyInventory"); await _press("WorkspacePart_right_hand"); await _capture("wound-1000.png")
	await _bandage_all(s); await _press("WorkspaceBack"); await _press("Travel_camp")
	await _press("WorldBodyInventory"); _person(2); await _frames(); await _press("WorkspaceInventoryTab")
	var device: String=s.journey().prostheses.items[0].id
	_choose(device); await _frames(); await _press("WorkspaceAttach")
	t.expect(s.world.bodies[2].functions.working.right_hand,"mouse installation restores device function")
	await _press("WorkspaceDetach"); t.equal(s.journey().survival.inventory.items[device].place,"ground","mouse detachment explicit ground")
	await _press("WorkspaceAttach")
	await _press("WorkspaceBodyTab"); await _press("WorkspacePart_right_hand"); await _capture("prosthesis-1000.png")
	await _press("WorkspaceBack"); await _press("WorldSave"); before=s.state_hash(); await _press("WorldLoad")
	t.equal(s.state_hash(),before,"installed device exact restore")
	await _press("Travel_ruins"); await _fight(s)
	t.equal(s.journey().survival.inventory.items[device].current,0,"real next encounter breaks device")
	await _press("WorldBodyInventory"); await _bandage_all(s); await _press("WorkspaceBack"); await _press("Travel_camp")
	await _press("WorldBodyInventory"); _person(2); await _frames(); await _press("WorkspaceInventoryTab"); _choose(device); await _frames()
	await _press("WorkspaceRepair"); t.equal(s.journey().survival.inventory.items[device].current,30,"mouse repair restores physical device")
	root.size=Vector2i(1280,800); await _frames(); await _capture("inventory-1280.png")
	await _press("WorkspaceBodyTab"); await _press("WorkspacePart_right_hand"); await _capture("body-1280.png")
	await _press("WorkspaceBack"); await _press("WorldEndLife"); await _press("WorldConfirmDeath")
	await _press("WorldBodyInventory"); await _capture("soul-without-body.png"); await _press("WorkspaceBack")
	await _press("WorldIncarnate18"); await _press("WorldBodyInventory"); _person(18); await _frames(); await _press("WorkspaceInventoryTab"); _choose(device); await _frames()
	await _press("WorkspaceDetach")
	t.equal(s.journey().survival.inventory.items[device].holder,"camp","retrieve unchanged item from previous corpse")
	t.expect(_button("WorkspaceAttach").disabled,"new healthy body cannot install missing-part device")
	await _press("WorkspaceBack"); await _press("WorldSave"); before=s.state_hash(); await _press("WorldLoad")
	t.equal(s.state_hash(),before,"retrieval and fresh incarnation persist")
	_finish()

func workspace() -> Sm2SurvivalWorkspace:
	return app.find_child("SurvivalWorkspace",true,false) as Sm2SurvivalWorkspace

func _person(id: int) -> void:
	var selector: OptionButton=app.find_child("WorkspacePerson",true,false) as OptionButton
	for index: int in selector.item_count:
		if int(selector.get_item_metadata(index))==id: selector.select(index); selector.item_selected.emit(index); return
	t.expect(false,"person exists: "+str(id))

func _choose(id: String) -> void:
	# Locate the exact object through the visible group and instance selector.
	var scope: OptionButton=app.find_child("WorkspaceScope",true,false) as OptionButton
	if scope!=null: scope.select(0); scope.item_selected.emit(0)
	var selector: ItemList=app.find_child("WorkspaceItems",true,false) as ItemList
	for index: int in workspace().cards.size():
		if id not in workspace().cards[index].ids: continue
		selector.select(index); selector.ensure_current_is_visible(); selector.item_selected.emit(index)
		var instance: OptionButton=app.find_child("WorkspaceInstance",true,false) as OptionButton
		if instance!=null:
			for entry: int in instance.item_count:
				if str(instance.get_item_metadata(entry))==id: instance.select(entry); instance.item_selected.emit(entry); return
		if workspace().ui.item==id: return
	t.expect(false,"item visible: "+id)

func _destination(id: String) -> void:
	var selector: OptionButton=app.find_child("WorkspaceDestination",true,false) as OptionButton
	for index: int in selector.item_count:
		if str(selector.get_item_metadata(index))==id: selector.select(index); selector.item_selected.emit(index); return
	t.expect(false,"container visible: "+id)

func _bandage_all(s: Sm2JourneySession) -> void:
	await _press("WorkspaceBodyTab")
	for body: int in [2,4]:
		if not s.world.bodies[body].alive: continue
		_person(body); await _frames()
		for wound: Dictionary in s.journey().survival.bodies[str(body)].wounds.duplicate(true):
			if int(wound.rate)==0: continue
			await _press("WorkspacePart_"+wound.part); await _press("WorkspaceBandage_"+str(body)+"_"+wound.id)
	for body: int in [2,4]:
		if s.world.bodies[body].alive: t.equal(s.journey().survival.bodies[str(body)].rate(),0,"all live party wounds treated by buttons")

func _fight(s: Sm2JourneySession) -> void:
	await _press("WorldBattle"); screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	for index: int in 120:
		if not s.world.busy(): break
		var result: Dictionary=BODY_TEST.treatment_step(s); t.expect(result.ok,"real encounter command")
		if not result.ok: break
		screen.runner=s.runner; screen._refresh()
	t.expect(not s.world.busy(),"encounter settles")
	await _press("BattleMenuButton")
