extends "res://tests/m3_ui.gd"
var panel: Sm2BattleProgressPanel

func _run() -> void:
	OS.add_logger(captured)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--output": output=args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size=Vector2i.ZERO; root.size=Vector2i(1000,700)
	app=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(app); await _frames()
	t.expect(_button("ContinueDevelopmentButton").disabled,"P2 fresh runtime has no save")
	await _capture("menu-1000.png")
	await _press("NewDevelopmentButton")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen
	t.expect(screen != null,"P2 menu opens common battle screen")
	if screen == null: _finish(); return
	screen.auto_advance=false
	t.equal(screen.state.actors.size(),4,"P2 two controlled members and two opponents")
	t.expect(screen._inspector.text.contains("Герой"),"P2 hero identified in inspector")
	await _capture("battle-1000.png")
	await _press("DevelopmentButton")
	panel=app.find_child("BattleProgressPanel",true,false) as Sm2BattleProgressPanel
	t.expect(panel != null,"P2 development panel opens")
	t.expect(_button("DevBuy_strength_1").disabled,"P2 node unavailable during battle")
	var hash: String=screen.runner.state_hash()
	screen.auto_advance=true; screen._delay=0.0; screen._process(1.0); screen.auto_advance=false
	t.equal(screen.runner.state_hash(),hash,"P2 panel pauses automatic UI advance")
	await _press("DevelopActor2")
	t.equal(panel.selected_actor,2,"P2 player inspects companion separately")
	t.equal(screen.runner.state_hash(),hash,"P2 viewing another body cannot change battle")
	await _capture("companion-1000.png")
	await _press("CloseDevelopmentButton")
	root.size=Vector2i(1280,800); await _frames()
	await _cell(Vector2i(2,1),false)
	await _cell(Vector2i(3,1),false)
	await _motion(Vector2i(4,1))
	var forecast: Dictionary=screen.runner.preview(screen._command("use_ability","m2:ability.sword_strike",3))
	t.expect(forecast.allowed,"P2 actual mouse approach enables sword attack")
	t.expect(screen._preview.text.contains("Попадание: %s%%" % forecast.hit_chance),"P2 forecast displays domain probability")
	await _capture("attack-preview.png")
	await _cell(Vector2i(4,1),false)
	t.equal(_earned(1,"p1:skill.melee"),40,"P2 mouse attack awards hero melee XP")
	t.equal(_earned(2,"p1:skill.melee"),0,"P2 mouse attack does not train companion")
	t.expect(screen._log.text.contains("Ближний бой +40 опыта"),"P2 battle journal explains practice")
	await _press("SaveBattleButton")
	var saved: String=screen.runner.state_hash()
	await _press("EndTurnButton")
	t.expect(screen.runner.state_hash() != saved,"P2 continues after save")
	await _press("LoadBattleButton")
	t.equal(screen.runner.state_hash(),saved,"P2 UI load restores both battle and practice")
	await _press("DevelopmentButton")
	await _capture("earned-1280.png")
	await _press("CloseDevelopmentButton")
	# Complete the same battle through its ordinary command handlers; no fake outcome.
	var profile: Sm2AiProfile=Sm2AiContentLoader.load_profile().profile
	for step_index: int in 300:
		if screen.state.finished: break
		if screen._player_turn():
			var decision: Dictionary=screen.runner._session.ai_decision(profile)
			t.expect(decision.ok,"P2 diagnostic player decision valid")
			if not decision.ok: break
			screen._execute(decision.command)
		else:
			var step: Dictionary=screen.runner.step()
			t.expect(step.ok,"P2 enemy step valid")
			if not step.ok: break
			if step.has("events"): screen._append(step.events)
			screen._refresh()
	await _frames()
	t.expect(screen.state.finished,"P2 UI reaches real outcome")
	t.equal(screen.state.winner,"company","P2 selected example is winnable with both members")
	t.expect(_earned(1,"p1:skill.melee") >= 160 and _earned(2,"p1:skill.melee") >= 160,"P2 both bodies learned from their own combat")
	await _capture("outcome.png")
	await _press("DevelopmentButton")
	panel=app.find_child("BattleProgressPanel",true,false) as Sm2BattleProgressPanel
	var hero_xp: int=_earned(1,"p1:skill.melee")
	var companion_xp: int=_earned(2,"p1:skill.melee")
	await _buy("DevBuy_strength_1")
	await _buy("DevBuy_melee_1")
	t.equal(_earned(1,"p1:skill.melee"),hero_xp,"P2 purchase preserves earned XP and derived level")
	t.equal(_earned(2,"p1:skill.melee"),companion_xp,"P2 hero purchase does not spend companion practice")
	await _press("DevelopActor2")
	await _buy("DevBuy_melee_1")
	for dimensions: Vector2i in [Vector2i(1280,800),Vector2i(1000,700)]:
		root.size=dimensions; await _frames(); await _capture("purchases-"+str(dimensions.x)+".png")
	await _press("SaveDevelopmentButton")
	var completed: String=screen.runner.state_hash()
	await _press("CloseDevelopmentButton")
	await _press("BattleMenuButton")
	await _capture("menu-resume-1000.png")
	await _press("ContinueDevelopmentButton")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.equal(screen.runner.state_hash(),completed,"P2 new runner restores post-combat purchases")
	await _press("DevelopmentButton")
	await _capture("reloaded-1000.png")
	await _press("CloseDevelopmentButton")
	var store: Sm2SaveStore=Sm2SaveStore.new("user://development")
	var malformed: Dictionary=screen.runner.capture(); malformed.session.battle.development.members[1].body.id="2"
	t.expect(store.save_slot(malformed,Sm2BattleRunner.DEVELOPMENT_SLOT).ok,"P2 malformed domain save with valid envelope fixture")
	await _press("LoadBattleButton")
	t.equal(screen.runner.state_hash(),completed,"P2 malformed load retains live completed game")
	t.expect(screen._notice.text.contains("Не удалось загрузить"),"P2 UI reports rejected load")
	await _press("SaveBattleButton")
	var previous_world: String=screen.state.battle_id
	await _press("BattleMenuButton"); await _press("NewDevelopmentButton")
	screen=app.find_child("BattleScreen",true,false) as Sm2BattleScreen; screen.auto_advance=false
	t.expect(screen.state.battle_id != previous_world,"P2 new example has different world identity")
	t.equal(_earned(1,"p1:skill.melee"),0,"P2 new example starts without old practice")
	await _press("LoadBattleButton")
	t.equal(screen.runner.state_hash(),completed,"P2 new example does not overwrite old save")
	_finish()

func _earned(actor_id: int, key: String) -> int:
	for member: Dictionary in screen.runner.view().actors:
		if member.actor_id == actor_id:
			for track: Dictionary in member.development.tracks:
				if track.id == key: return track.earned
	return -1

func _buy(id: String) -> void:
	var scroll: ScrollContainer=app.find_child("DevelopmentNodes",true,false) as ScrollContainer
	scroll.ensure_control_visible(_button(id)); await _frames(); await _press(id)
