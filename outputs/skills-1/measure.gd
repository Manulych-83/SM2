extends SceneTree
func _initialize() -> void:
	var begin: int=Time.get_ticks_usec()
	var fixture=preload("res://tests/fixtures/sm2_skill_scale_fixture.gd")
	var c: Dictionary=fixture.content()
	var catalog_ms: float=float(Time.get_ticks_usec()-begin)/1000.0
	if not c.ok: quit(1); return
	var s: Sm2CheckpointSession=Sm2CheckpointSession.new(c,Sm2AiContentLoader.load_profile().profile,null)
	if not s.new_game().ok: quit(2); return
	for track: Sm2ProgressTrackState in s.world.bodies[2].progress.tracks.values(): track.earned=100
	begin=Time.get_ticks_usec()
	for i: int in 1000: Sm2ProgressRules.track(s.world.bodies[2].progress,s.world._progress,fixture.TRACK)
	var addressed_ms: float=float(Time.get_ticks_usec()-begin)/1000.0
	begin=Time.get_ticks_usec()
	var view: Dictionary=Sm2HeroDevelopmentView.build(s,fixture.TRACK,{"compact_tracks":true})
	var view_ms: float=float(Time.get_ticks_usec()-begin)/1000.0
	begin=Time.get_ticks_usec()
	Sm2DevelopmentSources.build(s,fixture.TRACK)
	var sources_ms: float=float(Time.get_ticks_usec()-begin)/1000.0
	var sparse_bytes: int=JSON.stringify(s.world.capture()).to_utf8_buffer().size()
	for body: Sm2WorldBody in s.world.bodies.values(): body.progress.sparse=false
	var dense_bytes: int=JSON.stringify(s.world.capture()).to_utf8_buffer().size()
	var report: Dictionary={"passed":true,"skills":5000,"attributes":8,"catalog_pipeline_ms":catalog_ms,"query_1000_ms":addressed_ms,"view_ms":view_ms,"sources_ms":sources_ms,"search_rows":view.tracks.size(),"sparse_world_bytes":sparse_bytes,"dense_world_bytes":dense_bytes,"note":"One generated fixture, all hero tracks practiced. World JSON size only, not whole save. No battle timing claim."}
	var f: FileAccess=FileAccess.open("res://outputs/skills-1/measure.json",FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	print(JSON.stringify(report)); quit(0)
