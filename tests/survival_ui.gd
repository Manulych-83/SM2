extends "res://tests/p3_world_ui.gd"

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await _frames()
	await _capture("menu.png")
	await _press("NewSurvivalButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	if life==null: t.expect(false,"new survival screen"); _finish(); return
	var s: Sm2JourneySession=life.session as Sm2JourneySession
	t.equal(s.slot_name(),"survival_journey","new mode uses own slot")
	t.expect(app.find_child("PhysicalItemSelect",true,false)!=null,"physical inventory is visible")
	await _capture("camp-1000.png")
	var inv: Sm2PhysicalInventory=s.journey().survival.inventory
	var sword: String=""; var pack: String=""
	for id: String in inv.ids():
		if inv.owner(id)!=s.world.hero_id(): continue
		if inv.items[id].definition_id=="m2:equipment.sword": sword=id
		if inv.items[id].definition_id=="backpack": pack=id
	_choose("PhysicalItemSelect",sword); _choose("PhysicalDestination",pack)
	await _frames(); await _press("Physical_store_item")
	t.equal(s.journey().survival.inventory.items[sword].holder,pack,"UI puts sword into backpack")
	_choose("PhysicalItemSelect",sword); await _frames(); await _press("Physical_wear_item")
	t.equal(s.journey().survival.inventory.items[sword].place,"equipped","UI equips same object")

	await _press("WorldSave"); var saved: String=s.state_hash()
	await _press("Travel_ruins")
	await _press("WorldLoad"); t.equal(s.state_hash(),saved,"UI exact restore")
	root.size=Vector2i(1280,800); await _frames(); await _capture("camp-1280.png")
	await _press("Travel_ruins"); await _press("WorldBattle")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.equal(s.runner.capture().session.battle.schema_version,19,"UI starts anatomical battle")
	await _press("EndTurnButton"); await _capture("battle.png")
	await _press("SaveBattleButton"); var battle_saved: String=s.state_hash()
	await _press("BattleMenuButton"); await _press("WorldMenu"); await _press("ContinueSurvivalButton")
	life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	if life==null:
		t.expect(false,"continue survival failed: "+str(app._notice)); await _capture("continue-failure.png"); _finish(); return
	t.equal(life.session.state_hash(),battle_saved,"menu continue restores active anatomy")
	await _press("WorldBattle")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	var treated: bool=false
	for index: int in 250:
		if screen.state.finished: break
		if screen._player_turn():
			for node: Node in screen._actions.get_children():
				if node is Button and str(node.name).begins_with("Bandage_") and not node.disabled:
					await _capture("wounded.png")
					await _press(str(node.name)); treated=true; break
			if treated: await _capture("bandaged.png"); break
			var decision: Dictionary=screen.runner._session.ai_decision(screen.life_session._profile)
			if not decision.ok: t.expect(false,"UI player decision"); break
			t.expect(screen._execute(decision.command).accepted,"UI battle progression")
		else:
			screen.auto_advance=true; screen._delay=0; screen._process(0.01); screen.auto_advance=false
	t.expect(treated,"real mouse bandaging in combat")
	for index: int in 300:
		if screen.state.finished: break
		if screen._player_turn():
			var decision: Dictionary=screen.runner._session.ai_decision(screen.life_session._profile)
			if not decision.ok: t.expect(false,"UI finish decision"); break
			t.expect(screen._execute(decision.command).accepted,"UI reaches anatomical outcome")
		else:
			screen.auto_advance=true; screen._delay=0; screen._process(0.01); screen.auto_advance=false
	t.expect(screen.state.finished,"UI anatomical outcome reached")
	await _press("BattleMenuButton"); life=app.find_child("LifeScreen",true,false) as Sm2LifeScreen
	if life.session.world.hero_id()!=0:
		await _press("WorldEndLife"); await _press("WorldConfirmDeath")
	await _capture("soul.png")
	var wear: Button=_button("Physical_wear_item")
	t.expect(wear!=null and wear.disabled,"bodyless physical action visibly disabled")
	await _press("WorldIncarnate8")
	t.equal(life.session.world.hero_id(),8,"UI chooses clean new body")
	await _press("WorldSave"); var incarnation_hash: String=life.session.state_hash()
	await _press("WorldLoad")
	t.equal(life.session.state_hash(),incarnation_hash,"new incarnation UI exact load")
	await _capture("new-life.png")

	_finish()

func _choose(id: String,value: String) -> void:
	var option: OptionButton=app.find_child(id,true,false) as OptionButton
	for index: int in option.item_count:
		if str(option.get_item_metadata(index))==value:
			option.select(index); option.item_selected.emit(index); return
	t.expect(false,"selector has requested item: "+id)
