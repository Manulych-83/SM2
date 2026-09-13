extends SceneTree
var report: Dictionary={"passed":true,"metrics":[],"failures":[]}
func _initialize() -> void: call_deferred("run")
func measure(name: String,operation: Callable) -> Variant:
	var start: int=Time.get_ticks_usec(); var result: Variant=operation.call()
	var elapsed: float=(Time.get_ticks_usec()-start)/1000.0
	report.metrics.append({"name":name,"ms":elapsed}); print("RUNTIME %s %.3f ms" % [name,elapsed])
	return result
func check(ok: bool,message: String) -> void:
	if not ok: report.passed=false; report.failures.append(message)
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0]!="--report": quit(2); return
	report.version=ProjectSettings.get_setting("application/config/version")
	var service: Sm2Campaigns=measure("content_service",func(): return Sm2Campaigns.new("user://runtime_slots"))
	var raw: Dictionary=measure("envelope_read",func(): return Sm2SaveStore.new("user://runtime_slots").load_slot("survival_tissues"))
	check(raw.ok,"fixture envelope")
	if not raw.ok: finish(args[1]); return
	var fresh: Sm2CheckpointSession=Sm2CheckpointSession.new(service.content,service.profile,null,service.history_repository)
	var decoded: Dictionary=measure("world_decode",func(): return Sm2CheckpointWorld.decode(raw.payload.world,fresh.journey()))
	check(decoded.ok,"current world decodes")
	var archive: Sm2CheckpointArchive=Sm2CheckpointArchive.new(); archive.world_id=raw.payload.world.world_id; archive.fingerprint=raw.payload.fingerprint
	check(measure("archive_restore_cold",func(): return archive.restore(raw.payload.archive,service.history_repository)),"archive verified")
	var cold: Sm2Campaigns=Sm2Campaigns.new("user://runtime_slots")
	var opened: Dictionary=measure("campaign_open_cold",func(): return cold.open(0,true))
	check(opened.ok,"open campaign")
	if not opened.ok: finish(args[1]); return
	var session: Sm2CheckpointSession=opened.session; var before: String=session.state_hash()
	measure("world_copy",func(): return session.journey().copy_world())
	measure("session_copy",func(): return session._copy())
	measure("world_validate",func(): return session.journey().validate())
	measure("session_capture",func(): return session.capture())
	var copy: Sm2LifeSession=session._copy()
	check(measure("candidate_publish",func(): return session._publish(copy)).ok,"candidate publishes")
	measure("journal_full",func(): return Sm2JournalView.build(session))
	if ClassDB.class_exists("RefCounted") and session.archive.has_method("page"):
		measure("journal_page_30",func(): return session.archive.page(0,30))
	measure("menu_inspect",func(): return cold.inspect())
	check(measure("save_existing",func(): return session.save_game()).ok,"save")
	check(measure("load_warm",func(): return session.load_game()).ok,"load")
	check(session.state_hash()==before,"all reads/saves preserve exact state")
	var start: int=Time.get_ticks_usec()
	for i: int in 10:
		check(session.act(session.command("travel",0,"ruins" if session.journey().region.location_id=="camp" else "camp")).ok,"real travel")
	report.metrics.append({"name":"travel_mean_10","ms":(Time.get_ticks_usec()-start)/10000.0})
	check(session.save_game().ok and session.load_game().ok,"changed world roundtrip")
	stress(session)
	finish(args[1])
func stress(session: Sm2CheckpointSession) -> void:
	# Isolated domain fixtures, not extra possessions or progression in the campaign.
	for count: int in [100,1000,10000]:
		var inventory: Sm2PhysicalInventory=Sm2PhysicalInventory.new()
		for i: int in count:
			var container_id: int=(i/10)*10+1
			inventory.add(i+1,"stash" if i%10==0 else "medical_kit","ground" if i%10==0 else "container","camp" if i%10==0 else str(container_id))
		var raw: Dictionary=inventory.to_data()
		var decoded: Dictionary=measure("inventory_decode_"+str(count),func(): return Sm2PhysicalInventory.decode(raw,session.journey().survival.catalog,["2","4"],["camp"]))
		check(decoded.ok,"inventory load "+str(count)+" "+str(decoded.get("errors",[])))
		if decoded.ok: check(Sm2Canonical.hash(decoded.inventory.to_data())==Sm2Canonical.hash(raw),"inventory exact "+str(count))
		measure("inventory_copy_"+str(count),func(): return inventory.copy())
	for count: int in [100,1000]:
		var catalog: Sm2ProgressCatalog=Sm2ProgressCatalog.new()
		var fixture: GDScript=load("res://tests/fixtures/sm2_scale_fixture.gd")
		check(catalog.build(fixture.catalog(count)).is_empty(),"progress fixture builds")
		var body: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(2,catalog)
		Sm2ProgressRules.award(body,{"scale:skill":count})
		for i: int in range(count-1,-1,-1):
			var id: String="scale:node.%05d" % i
			check(Sm2ProgressRules.purchase_error(body,catalog,id).is_empty(),"purchase allowed")
			Sm2ProgressRules.purchase(body,catalog.node(id))
		var decoded: Dictionary=measure("developed_body_decode_"+str(count),func(): return Sm2ProgressRules.decode_body(body.to_data(),catalog))
		check(decoded.ok,"developed body restores")
		measure("developed_body_projection_"+str(count),func(): return Sm2ProgressRules.tracks(body,catalog))
func finish(path: String) -> void:
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	quit(0 if report.passed else 1)
