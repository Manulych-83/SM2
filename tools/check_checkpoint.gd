extends SceneTree
var report: Dictionary={"passed":true,"failures":[],"metrics":[],"performance_passed":true}
var content: Dictionary
var profile: Sm2AiProfile
var history_repository: Sm2HistoryRepository

func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	if not ok: report.passed=false; report.failures.append(message)
func measure(name: String,operation: Callable,budget_ms: float=0.0) -> Variant:
	var start: int=Time.get_ticks_usec(); var value: Variant=operation.call()
	var ms: float=(Time.get_ticks_usec()-start)/1000.0
	report.metrics.append({"name":name,"ms":ms,"budget_ms":budget_ms})
	if budget_ms>0 and ms>budget_ms: report.performance_passed=false
	print("CHECKPOINT %s: %.3f ms" % [name,ms])
	return value
func make(store: Sm2SaveStore=null) -> Sm2CheckpointSession: return Sm2CheckpointSession.new(content,profile,store,history_repository)
func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=4 or args[0]!="--source" or args[2]!="--report": quit(2); return
	content=Sm2SurvivalContentLoader.load_scenario(true,true); profile=Sm2AiContentLoader.load_profile().profile
	history_repository=Sm2HistoryRepository.new("user://checkpoint-scale")
	report.engine=Engine.get_version_info().string; report.version=ProjectSettings.get_setting("application/config/version")
	var source: Sm2SaveStore=Sm2SaveStore.new(args[1].get_base_dir())
	var decoded: Dictionary=source.load_slot(args[1].get_file().get_basename())
	check(decoded.ok,"read historical test save")
	if not decoded.ok: finish(args[3]); return
	var validator: Callable=func(raw: Dictionary): return make(Sm2SaveStore.new("user://checkpoint-scale")).restore(raw)
	var store: Sm2CampaignStore=Sm2CampaignStore.new("user://checkpoint-scale",0,validator)
	var session: Sm2CheckpointSession=make(store)
	var imported: Dictionary=measure("legacy_import_4096",func(): return session.restore(decoded.payload))
	check(imported.ok,"old 4096 history imports: "+str(imported.get("errors",[])))
	if not imported.ok: finish(args[3]); return
	check(session.archive.count==4096,"source has actual 4096 transitions")
	check(Sm2Canonical.hash(session.world.capture())==Sm2Canonical.hash(decoded.payload.world),"legacy world exact")
	check(Sm2Canonical.hash(session.archive.all_entries())==Sm2Canonical.hash(decoded.payload.history),"legacy actions exact")
	measure("extend_to_4160",func():
		for index: int in 64:
			var place: String="ruins" if session.journey().region.location_id=="camp" else "camp"
			check(session.act(session.command("travel",0,place)).ok,"actual command beyond old history bound")
	)
	var before: String=session.state_hash()
	var saved: Dictionary=measure("save_4160",func(): return session.save_game(),3000)
	check(saved.ok,"checkpoint writes: "+str(saved.get("errors",[])))
	if not saved.ok: finish(args[3]); return
	var loaded: Sm2CheckpointSession=make(store)
	var result: Dictionary=measure("load_4160",func(): return loaded.load_game(),3000)
	check(result.ok,"checkpoint loads")
	if result.ok:
		check(loaded.state_hash()==before,"disk round trip exact")
		var journal: Dictionary=measure("journal_4160",func(): return Sm2JournalView.build(loaded),100)
		check(journal.ok and journal.rows.size()==4160,"all journal rows intact")
		var objective: Dictionary=measure("objective_4160",func(): return Sm2ExpeditionView.new().build(loaded),100)
		check(objective.ok and not objective.complete,"objective still incomplete")
		check(loaded.state_hash()==before,"queries do not mutate checkpoint")
	var cold_service: Sm2Campaigns=Sm2Campaigns.new("user://checkpoint-scale")
	var cold: Dictionary=measure("cold_campaign_open_4160",func(): return cold_service.open(0,true),3000)
	check(cold.ok and cold.session.state_hash()==before,"cold app service restores exact checkpoint")
	report.records=session.archive.count; report.blocks=session.archive.refs.size()
	report.snapshot_payload_bytes=Sm2Canonical.stringify(session.capture()).to_utf8_buffer().size()
	report.legacy_payload_bytes=Sm2Canonical.stringify(decoded.payload).to_utf8_buffer().size()
	report.snapshot_format=session.format_id()
	finish(args[3])
func finish(path: String) -> void:
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null: quit(2); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("CHECKPOINT_SCALE_OK" if report.passed else "CHECKPOINT_SCALE_FAILED")
	quit(0 if report.passed and report.performance_passed else 1)
