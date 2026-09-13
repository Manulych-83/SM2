extends SceneTree
const FIXTURE=preload("res://tests/fixtures/sm2_scale_fixture.gd")
var report: Dictionary={"format":"sm2.foundation.audit.1","passed":true,"failures":[],"metrics":[],"blockers":[],"budgets_ms":{"catalog_build":1000,"graph":250,"journal":100,"objective":100,"restore":2000,"save":3000,"load":3000}}
var content: Dictionary
var profile: Sm2AiProfile

func _initialize() -> void: call_deferred("_run")

func check(ok: bool,label: String) -> void:
	if not ok: report.passed=false; report.failures.append(label)

func measure(name: String,count: int,operation: Callable) -> Variant:
	var start: int=Time.get_ticks_usec(); var value: Variant=operation.call()
	var elapsed: float=(Time.get_ticks_usec()-start)/1000.0
	report.metrics.append({"operation":name,"count":count,"ms":elapsed})
	if elapsed>report.budgets_ms.get(name,1e30): report.blockers.append({"kind":"latency","operation":name,"count":count,"ms":elapsed,"budget_ms":report.budgets_ms[name]})
	print("FOUNDATION %s %s: %.3f ms" % [name,count,elapsed])
	return value

func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(content,profile,store)

func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0]!="--report": push_error("Expected --report path"); quit(2); return
	report.engine=Engine.get_version_info().string
	report.app_version=ProjectSettings.get_setting("application/config/version")
	report.processor=OS.get_processor_name()
	content=Sm2SurvivalContentLoader.load_scenario(true,true)
	check(content.ok,"production layered campaign content validates")
	if not content.ok: _finish(args[1]); return
	profile=Sm2AiContentLoader.load_profile().profile
	var live: Sm2JourneySession=make(); live.world.start("foundation:fixed-world")
	check(Sm2ExpeditionBrief.valid(Sm2ExpeditionBrief.load_for(live.journey()),live.journey()),"production objective references")
	report.content=Sm2ProgressContentAudit.inspect(content.development.progression().to_data())
	report.content.journey_fingerprint=content.journey_fingerprint
	check(report.content.ok,"production progression audit")
	for count: int in [100,1000]:
		var raw: Dictionary=FIXTURE.catalog(count); var catalog: Sm2ProgressCatalog=Sm2ProgressCatalog.new()
		var errors: PackedStringArray=measure("catalog_build",count,func(): return catalog.build(raw))
		check(errors.is_empty(),"synthetic catalog %s" % count)
		var hash_value: String=catalog.fingerprint()
		measure("fingerprint_100_reads",count,func():
			for index: int in 100: check(catalog.fingerprint()==hash_value,"stable fingerprint")
		)
	var denied: Dictionary=Sm2ProgressContentAudit.inspect(FIXTURE.catalog(1001))
	check(not denied.ok and "progress_content_group" in denied.validation,"legacy group bound remains enforced")
	report.blockers.append({"kind":"catalog_limit","supported_group_size":1000,"rejected_group_size":1001,"errors":denied.validation})
	for count: int in [1000,10000]:
		var input: Dictionary=FIXTURE.graph(count)
		var graph: Dictionary=measure("graph",count,func(): return Sm2DependencyGraph.inspect(input.ids,input.dependencies))
		check(graph.ok and graph.order.size()==count and graph.order[0]==input.ids[-1],"large reverse dependency chain")
	for count: int in [100,1000,4096]:
		var start: int=Time.get_ticks_usec()
		while live.history.size()<count:
			var destination: String="ruins" if live.journey().region.location_id=="camp" else "camp"
			var result: Dictionary=live.act(live.command("travel",0,destination))
			if not result.ok: check(false,"travel: "+str(result)); _finish(args[1]); return
		print("FOUNDATION generated %s real transitions in %.3f ms" % [count,(Time.get_ticks_usec()-start)/1000.0])
		_history(live,count)
	var unchanged: String=live.state_hash()
	check(not live.act(live.command("travel",0,"ruins")).ok,"history limit command refused")
	check(live.state_hash()==unchanged,"history limit refusal atomic")
	report.blockers.append({"kind":"history_limit","entries":Sm2JourneySession.HISTORY_LIMIT,"checkpoint_archive":false})
	_finish(args[1])

func _history(live: Sm2JourneySession,count: int) -> void:
	var snapshot: Dictionary=live.capture(); var unchanged: String=live.state_hash()
	var loaded: Sm2JourneySession=make()
	var restored: Dictionary=measure("restore",count,func(): return loaded.restore(snapshot))
	check(restored.ok and loaded.state_hash()==unchanged,"restore exact world at %s" % count)
	var journal: Dictionary=measure("journal",count,func(): return Sm2JournalView.build(live))
	check(journal.ok and journal.rows.size()==count,"all journal entries at %s" % count)
	var query: Sm2ExpeditionView=Sm2ExpeditionView.new()
	var objective: Dictionary=measure("objective",count,func(): return query.build(live))
	check(objective.ok and not objective.complete,"unchanged objective at %s" % count)
	measure("objective_cached",count,func(): return query.build(live))
	check(live.state_hash()==unchanged,"read projections cannot mutate world")
	var validator: Callable=func(payload: Dictionary): return make().restore(payload)
	var store: Sm2CampaignStore=Sm2CampaignStore.new("user://foundation/%s" % count,0,validator)
	var persisted: Sm2JourneySession=make(store)
	check(persisted.restore(snapshot).ok,"save candidate restored")
	var saved: Dictionary=measure("save",count,func(): return persisted.save_game())
	var budget: Array[int]=[Sm2SaveStore.MAX_NODES]
	var storage_error: String=store._validate_value(snapshot,0,budget)
	var bytes: int=Sm2Canonical.stringify(snapshot).to_utf8_buffer().size()
	report.metrics.append({"operation":"payload","count":count,"bytes":bytes,"tree_values":Sm2SaveStore.MAX_NODES-budget[0],"save_ok":saved.ok,"save_errors":Array(saved.get("errors",[]))})
	if saved.ok:
		var receiver: Sm2JourneySession=make(store)
		var disk: Dictionary=measure("load",count,func(): return receiver.load_game())
		check(disk.ok and receiver.state_hash()==unchanged,"disk round trip exact at %s" % count)
	else:
		check(not storage_error.is_empty(),"failure explained by measured storage constraint")
		report.blockers.append({"kind":"save_capacity","count":count,"bytes":bytes,"value_budget":Sm2SaveStore.MAX_NODES,"error":storage_error,"errors":Array(saved.get("errors",[]))})
	check(persisted.state_hash()==unchanged,"save cannot mutate state")
	var bad: Dictionary=snapshot.duplicate(true); bad.history[0].command.content_id="unknown:place"
	var before: String=loaded.state_hash()
	check(not loaded.restore(bad).ok and loaded.state_hash()==before,"invalid history refuses atomically")

func _finish(path: String) -> void:
	report.ready_for_large_campaign=report.passed and report.blockers.is_empty()
	report.static_memory_bytes=OS.get_static_memory_usage()
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null: push_error("Cannot write foundation report"); quit(2); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("FOUNDATION_AUDIT_OK" if report.passed else "FOUNDATION_AUDIT_FAILED")
	quit(0 if report.passed else 1)
