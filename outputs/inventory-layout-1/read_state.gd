extends SceneTree
func _initialize() -> void:
	var session: Sm2JourneySession=Sm2JourneySession.new(Sm2SurvivalContentLoader.load_scenario(true,true),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://inventory-mockup"))
	var started: Dictionary=session.new_game()
	if not started.ok: quit(1); return
	var view: Dictionary=Sm2SurvivalWorkspaceView.build(session)
	var file: FileAccess=FileAccess.open("res://outputs/inventory-layout-1/source-state.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(view,"\t")); file.close()
	print(JSON.stringify(view)); quit()
