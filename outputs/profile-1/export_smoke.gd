extends SceneTree
func _initialize() -> void: call_deferred("run")
func frames() -> void:
	for index: int in 8: await process_frame
func run() -> void:
	if ProjectSettings.get_setting("application/config/version")!="0.8.30-profile.1": quit(1); return
	var path: String="user://survival_tissues/survival_tissues.json"
	var original: String=FileAccess.get_sha256(path)
	var app: Control=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Control; root.add_child(app); await frames()
	app._open_campaign(0,true); await frames()
	var page: Sm2ExpeditionScreen=app.find_child("ExpeditionScreen",true,false) as Sm2ExpeditionScreen
	if page==null or not page.model.complete or page.model.summary.items.size()!=4: quit(2); return
	var session: Sm2CheckpointSession=app._life as Sm2CheckpointSession
	if session==null or FileAccess.get_sha256(path)!=original: quit(3); return
	var before: String=session.state_hash(); var summary: String=Sm2Canonical.hash(page.model.summary)
	(app.find_child("ExpeditionSave",true,false) as Button).pressed.emit(); await frames()
	if FileAccess.get_sha256(path+".bak")!=original or not session.load_game().ok or session.state_hash()!=before: quit(4); return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("E:/GPT/SM2/outputs/profile-1/pack-legacy-completed.png")
	if Sm2Canonical.hash(Sm2ExpeditionView.new().build(session).summary)!=summary: quit(5); return
	app._open_campaign(1,true); await frames()
	page=app.find_child("ExpeditionScreen",true,false) as Sm2ExpeditionScreen
	session=app._life as Sm2CheckpointSession
	if page==null or not page.model.complete or session==null or session.archive.refs.size()<2 or session.journey().incarnations.size()!=2: quit(6); return
	before=session.state_hash()
	if not session.save_game().ok or not session.load_game().ok or session.state_hash()!=before: quit(7); return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("E:/GPT/SM2/outputs/profile-1/pack-new-body.png")
	app._open_campaign(2,false); await frames()
	if not app._life is Sm2CheckpointSession or Sm2ExpeditionView.new().build(app._life).complete: quit(8); return
	(app.find_child("Guide_development",true,false) as Button).pressed.emit(); await frames()
	var development: Sm2HeroDevelopmentScreen=app.find_child("HeroDevelopmentScreen",true,false) as Sm2HeroDevelopmentScreen
	if development==null or not development._model.has("node_count") or app.find_child("HeroNodeSearch",true,false)==null: quit(9); return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("E:/GPT/SM2/outputs/profile-1/pack-development.png")
	session=app._life as Sm2CheckpointSession
	if not session.act(session.command("travel",0,"ruins")).ok or not session.act(session.command("start_battle")).ok: quit(10); return
	var active: Dictionary=session.runner.status()
	var command: Sm2Command=Sm2Command.new(); command.kind="end_turn"; command.actor_id=int(active.active_actor_id); command.expected_revision=int(active.revision); command.battle_id=active.battle_id
	if not session.attack(command).accepted: quit(11); return
	before=session.state_hash()
	if not session.world.busy() or not session.save_game().ok or not session.load_game().ok or session.state_hash()!=before: quit(12); return
	if not session.runner.state_copy().development.deferred_growth or session.runner.growth_profile()==null: quit(13); return
	for i: int in 60:
		var state: Sm2TacticalState=session.runner.state_copy()
		if not state.development.pending.get(1,{}).is_empty(): break
		if not session.world.busy(): quit(14); return
		var who: Sm2TacticalActor=state.actor(int(session.runner.status().active_actor_id))
		if who.spatial.controller=="player" and who.morale!="fleeing":
			var choice: Dictionary=session.runner._session.ai_decision(session._profile)
			if not choice.ok or not session.attack(choice.command).accepted: quit(15); return
		else:
			if not session.step().ok: quit(16); return
	if session.runner.state_copy().development.pending.get(1,{}).is_empty(): quit(17); return
	before=session.state_hash()
	if not session.save_game().ok or not session.load_game().ok or session.state_hash()!=before: quit(18); return
	if session.runner.growth_profile()==null: quit(19); return
	print("SM2_PROFILE_PACK_OK: legacy backup and archived outcomes; new battle defers growth; pending XP survives save/load")
	quit(0)
