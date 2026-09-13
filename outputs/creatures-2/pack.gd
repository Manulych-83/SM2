extends SceneTree
func _initialize() -> void:
	var service: Sm2Campaigns=Sm2Campaigns.new("user://pack-campaigns")
	if not service.error.is_empty(): _fail(service.error); return
	var opened: Dictionary=service.open(0,false)
	if not opened.ok: _fail(str(opened)); return
	var session: Sm2CheckpointSession=opened.session
	if session.journey().world_creatures==null: _fail("new profile missing"); return
	if not session.act(session.command("travel",0,"ruins")).ok or not session.act(session.command("start_battle")).ok: _fail("new encounter failed"); return
	if session.runner.state_copy().actor(3).anatomy==null: _fail("anatomy missing"); return
	if not session.save_game().ok: _fail("save failed"); return
	var restored: Dictionary=service.open(0,true)
	if not restored.ok or restored.session.state_hash()!=session.state_hash(): _fail("new active restore mismatch"); return
	var old: Sm2CheckpointSession=Sm2CheckpointSession.new(service.legacy_content,service.legacy_profile,service.store(1),service.history_repository)
	if not old.new_game().ok or not old.save_game().ok: _fail("legacy save failed"); return
	var loaded: Dictionary=service.open(1,true)
	if not loaded.ok or loaded.session.journey().world_creatures!=null or loaded.session.state_hash()!=old.state_hash(): _fail("legacy restore mismatch"); return
	print("SM2_CREATURES_2_PACK_OK: new anatomical encounter, active save/load, old checkpoint profile retained")
	quit(0)
func _fail(message: String) -> void:
	push_error(message); quit(1)
