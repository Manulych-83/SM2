extends RefCounted
const FIXTURE=preload("res://tests/scenarios/test_survival_tissues.gd")
const OUTING=preload("res://tests/scenarios/test_expedition.gd")
class ObservedCampaigns extends Sm2Campaigns:
	var validations: int=0
	func _validate(payload: Dictionary) -> Dictionary:
		validations+=1
		return super._validate(payload)

static func run(t: Sm2TestHarness) -> void:
	var session: Sm2JourneySession=FIXTURE.make(); t.expect(session.new_game().ok,"checkpoint fixture starts")
	for kind: String in ["initial","travel","end_life","incarnate"]:
		if kind=="travel": t.expect(session.act(session.command(kind,0,"ruins")).ok,"travel before checkpoint")
		if kind=="end_life":
			t.expect(session.act(session.command("start_battle")).ok,"first battle before life transition")
			OUTING.retreat(session,t)
			t.expect(session.act(session.command(kind)).ok,"end life before checkpoint")
		if kind=="incarnate": t.expect(session.act(session.command(kind,8)).ok,"incarnate in the current ruins location")
		var raw: Dictionary=session.world.capture()
		var decoded: Dictionary=Sm2CheckpointWorld.decode(raw,FIXTURE.make().journey())
		t.expect(decoded.ok,"decode "+kind+" "+str(decoded.get("errors",[])))
		if decoded.ok: t.equal(decoded.world.capture(),raw,"exact current world "+kind)
	var bad: Dictionary=session.world.capture(); bad.bodies[0].progress="invalid"
	t.expect(not Sm2CheckpointWorld.decode(bad,FIXTURE.make().journey()).ok,"malformed progress rejected")
	var checkpoint: Sm2CheckpointSession=Sm2CheckpointSession.new(session._content,session._profile,Sm2SaveStore.new("user://checkpoint-tests"))
	var imported: Dictionary=checkpoint.restore(session.capture())
	t.expect(imported.ok,"legacy imported: "+str(imported.get("errors",[])))
	if imported.ok:
		t.equal(checkpoint.world.capture(),session.world.capture(),"import keeps exact world")
		t.equal(checkpoint.archive.all_entries(),session.history,"import keeps exact actions")
		t.equal(Sm2JournalView.build(checkpoint),Sm2JournalView.build(session),"journal materialized exactly")
		t.equal(Sm2ExpeditionView.new().build(checkpoint),Sm2ExpeditionView.new().build(session),"objective materialized exactly")
		var saved: Dictionary=checkpoint.save_game()
		t.expect(saved.ok,"checkpoint saves: "+str(saved.get("errors",[])))
		var reloaded: Sm2CheckpointSession=Sm2CheckpointSession.new(session._content,session._profile,checkpoint._store)
		var result: Dictionary=reloaded.load_game()
		t.expect(result.ok,"checkpoint loads: "+str(result.get("errors",[])))
		if result.ok:
			for key: String in checkpoint.capture(): t.equal(Sm2Canonical.hash(reloaded.capture()[key]),Sm2Canonical.hash(checkpoint.capture()[key]),"canonical checkpoint round trip: "+key)
	full_route(t)
	archive_faults(t)
	runtime_contracts(t)
	container_totals(t)
	t.complete_suite("checkpoint")

static func make(directory: String) -> Sm2CheckpointSession:
	var fixture: Sm2JourneySession=FIXTURE.make()
	return Sm2CheckpointSession.new(fixture._content,fixture._profile,Sm2SaveStore.new(directory))

static func full_route(t: Sm2TestHarness) -> void:
	var s: Sm2CheckpointSession=make("user://checkpoint-route")
	t.expect(s.new_game().ok,"checkpoint route starts")
	var malformed: Dictionary=s.capture(); malformed.world.receipt="a".repeat(64)
	var initial_hash: String=s.state_hash()
	t.expect(not s.restore(malformed).ok,"receipt without completed encounter rejected")
	t.equal(s.state_hash(),initial_hash,"unearned receipt cannot alter live world")
	t.expect(s.act(s.command("travel",0,"ruins")).ok and s.act(s.command("start_battle")).ok,"checkpoint route enters combat")
	var view: Dictionary=s.runner.view()
	var command: Sm2Command=Sm2Command.new(); command.kind="end_turn"; command.actor_id=int(view.active_actor_id); command.expected_revision=int(view.revision); command.battle_id=view.battle_id
	t.expect(s.attack(command).accepted,"one actual combat command before active save")
	var before: String=s.state_hash()
	malformed=s.capture(); malformed.world.receipt="b".repeat(64)
	t.expect(not s.restore(malformed).ok,"active encounter cannot also have settlement receipt")
	t.equal(s.state_hash(),before,"active receipt rejection atomic")
	t.expect(s.save_game().ok and s.load_game().ok,"active battle disk roundtrip")
	t.equal(s.state_hash(),before,"active battle exact without extra turns or resource ticks")
	OUTING.retreat(s,t); FIXTURE.bandage_all(t,s)
	var battle: Dictionary=Sm2BattleResultsView.build(s)
	var ids: Array=OUTING.finish_supplies(s,t)
	var stash: String=OUTING.container(s,"stash")
	for id: String in ids: t.expect(s.act(s.command("store_item",int(stash),id)).ok,"checkpoint delivers actual medicine")
	var objective: Dictionary=Sm2ExpeditionView.new().build(s)
	t.expect(objective.ok and objective.complete,"checkpoint first episode completes")
	var summary: Dictionary=objective.summary.duplicate(true)
	t.expect(s.save_game().ok and s.load_game().ok,"completed objective disk roundtrip")
	t.equal(Sm2Canonical.hash(Sm2ExpeditionView.new().build(s).summary),Sm2Canonical.hash(summary),"completed report is preserved across JSON numeric representation")
	t.expect(Sm2ExpeditionView.new().build(s).summary.incarnation is int,"saved incarnation is presented as whole number")
	t.expect(Sm2JournalView.build(s).rows[0].number is int,"saved journal row number is whole")
	for i: int in 70:
		var place: String="ruins" if s.journey().region.location_id=="camp" else "camp"
		t.expect(s.act(s.command("travel",0,place)).ok,"postcombat travel beyond bridge history")
	t.equal(frozen_battle(Sm2BattleResultsView.build(s)),frozen_battle(battle),"last combat facts survive bridge trimming")
	t.equal(Sm2BattleResultsView.build(s).revision,s.world.revision,"combat report navigation uses current revision")
	t.expect(s.act(s.command("end_life")).ok and s.act(s.command("incarnate",18)).ok,"new incarnation after item IDs were allocated")
	before=s.state_hash()
	t.expect(s.save_game().ok and s.load_game().ok,"new body with interleaved IDs disk roundtrip")
	t.equal(s.state_hash(),before,"new body exact")
	t.equal(Sm2Canonical.hash(Sm2ExpeditionView.new().build(s).summary),Sm2Canonical.hash(summary),"historical objective survives new body and reload")
	t.equal(frozen_battle(Sm2BattleResultsView.build(s)),frozen_battle(battle),"historical combat facts survive new body and reload")
	t.equal(Sm2BattleResultsView.build(s).body,s.world.hero_id(),"report navigation follows new body")
	var raw: Dictionary=s.capture()
	for defect: String in ["fingerprint","brief","archive","facts","owner","body","active"]:
		var bad: Dictionary=raw.duplicate(true)
		match defect:
			"fingerprint": bad.fingerprint="unknown"
			"brief": bad.brief_fingerprint="unknown"
			"archive": bad.archive.refs[0].last=999
			"facts": bad.facts.summary.items=["unknown"]
			"owner": bad.world.items[0].owner_id="999999"
			"body": bad.world.bodies[0].progress="broken"
			"active": bad.active={"unexpected":true}
		t.expect(not s.restore(bad).ok,"reject malformed checkpoint "+defect)
		t.equal(s.state_hash(),before,"failed restore is atomic "+defect)

static func archive_faults(t: Sm2TestHarness) -> void:
	var service: Sm2Campaigns=Sm2Campaigns.new("user://checkpoint-faults")
	var opened: Dictionary=service.open(0,false); t.expect(opened.ok,"isolated archive fault campaign")
	if not opened.ok: return
	var s: Sm2CheckpointSession=opened.session
	for stage: int in 2:
		for i: int in 64:
			var place: String="ruins" if s.journey().region.location_id=="camp" else "camp"
			t.expect(s.act(s.command("travel",0,place)).ok,"fault fixture actual travel")
		t.expect(s.save_game().ok,"fault fixture snapshot "+str(stage))
	var hash_value: String=s.archive.refs.back().hash
	var path: String=s.repository.store._slot_path(hash_value)
	var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path)
	var bad: PackedByteArray=bytes.duplicate(); bad[0]=32 # Same byte length, invalid envelope; warm cache must notice.
	write_bytes(path,bad)
	var recovered: Dictionary=service.open(0,true)
	t.expect(recovered.ok and recovered.recovered and recovered.session.archive.count==64,"same-size block damage uses independent valid backup")
	t.equal(FileAccess.get_file_as_bytes(path),bad,"recovery never rewrites damaged block")
	write_bytes(path,bytes)

	t.expect(service.open(0,true).ok and not service.open(0,true).recovered,"restored bytes invalidate damaged cache state")
	t.equal(DirAccess.remove_absolute(path),OK,"remove exact isolated block fixture")
	recovered=service.open(0,true)
	t.expect(recovered.ok and recovered.recovered and recovered.session.archive.count==64,"missing block falls back to backup")
	write_bytes(path,bytes)
	var root_path: String=s._store._slot_path(s.slot_name())
	var root_bytes: PackedByteArray=FileAccess.get_file_as_bytes(root_path)
	var backup: PackedByteArray=FileAccess.get_file_as_bytes(root_path+".bak")
	for i: int in 64:
		var place: String="ruins" if s.journey().region.location_id=="camp" else "camp"
		t.expect(s.act(s.command("travel",0,place)).ok,"new unpublished archive block")
	var before: String=s.state_hash()
	var pending_path: String=s.repository.store._slot_path(s.archive.refs.back().hash)
	t.equal(DirAccess.make_dir_absolute(pending_path+".tmp"),OK,"blocked archive temporary fixture")
	t.expect(not s.save_game().ok,"block write failure rejects snapshot publication")
	t.equal(s.state_hash(),before,"block write failure preserves live state")
	t.equal(FileAccess.get_file_as_bytes(root_path),root_bytes,"block failure retains primary")
	t.equal(FileAccess.get_file_as_bytes(root_path+".bak"),backup,"block failure retains backup")
	t.equal(DirAccess.remove_absolute(pending_path+".tmp"),OK,"remove exact empty fixture")
	t.equal(DirAccess.make_dir_absolute(root_path+".tmp"),OK,"blocked root temporary fixture")
	t.expect(not s.save_game().ok,"root failure after block publication")
	t.expect(FileAccess.file_exists(pending_path),"safe orphan may remain after root failure")
	t.equal(FileAccess.get_file_as_bytes(root_path),root_bytes,"root failure retains primary")
	t.equal(FileAccess.get_file_as_bytes(root_path+".bak"),backup,"root failure retains backup")
	t.equal(s.state_hash(),before,"root failure preserves live state")
	t.equal(DirAccess.remove_absolute(root_path+".tmp"),OK,"remove exact empty root fixture")
	t.expect(s.save_game().ok and s.load_game().ok,"retry reuses immutable orphan and loads")
	t.equal(s.state_hash(),before,"retry exact")
	var invalid: Sm2HistoryRepository=Sm2HistoryRepository.new("res://forbidden-checkpoint-archive")
	var one_block: Dictionary={}; one_block[hash_value]=s.repository.read(hash_value).payload
	t.expect(not invalid.publish(one_block).ok,"archive retains resource-directory write protection")
	t.expect(not DirAccess.dir_exists_absolute("res://forbidden-checkpoint-archive"),"rejected repository creates no resource directory")

static func write_bytes(path: String,bytes: PackedByteArray) -> void:
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE); file.store_buffer(bytes); file.close()

static func frozen_battle(data: Dictionary) -> String:
	var frozen: Dictionary=data.duplicate(true)
	# The established result contract includes live navigation and nearby loot separately.
	for key: String in ["location","ground","body","world_id","revision"]: frozen.erase(key)
	return Sm2Canonical.hash(frozen)

static func runtime_contracts(t: Sm2TestHarness) -> void:
	var service: ObservedCampaigns=ObservedCampaigns.new("user://checkpoint-runtime")
	var opened: Dictionary=service.open(0,false)
	t.expect(opened.ok,"runtime fixture starts")
	if not opened.ok: return
	var s: Sm2CheckpointSession=opened.session
	for i: int in 70:
		t.expect(s.act(s.command("travel",0,"ruins" if s.journey().region.location_id=="camp" else "camp")).ok,"runtime paging fixture real action")
	t.expect(s.save_game().ok,"runtime fixture saves")
	t.expect(s.archive.blocks.is_empty(),"published archive does not retain blocks in pending writes")
	var snapshot: String=s.state_hash()
	service.validations=0
	t.expect(service.inspect()[0].ok,"menu has checked world preview")
	t.equal(service.validations,0,"menu never reconstructs a complete campaign")
	opened=service.open(0,true)
	t.expect(opened.ok,"runtime opens saved campaign")
	t.equal(service.validations,1,"one semantic restore per load")
	t.equal(opened.session.state_hash(),snapshot,"direct adoption preserves exact checkpoint")
	s=opened.session
	var rows: Array=s.archive.rows(); rows.reverse()
	for offset: int in [0,30,60,70]:
		var page: Dictionary=s.archive.page(offset,30)
		t.expect(page.ok,"archive page reads")
		t.equal(page.rows,rows.slice(offset,offset+30),"page matches complete journal at "+str(offset))
	var definitions: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/journal.json"))
	var query: Sm2JournalQuery=Sm2JournalQuery.new(s,definitions)
	var page: Dictionary=query.page("","Все",0)
	t.equal(page.rows.size(),30,"screen receives at most its visible page")
	t.equal(page.total,70,"screen knows total without copying all rows")
	page.rows[0].subject="changed by UI"
	t.equal(query.page("","Все",0).rows[0],rows[0],"page detached from source")
	t.expect(query.page("never matches","Все",0).rows.is_empty(),"negative query")
	t.equal(query.page("Руины","Все",1).count,70,"search includes from and destination")
	t.equal(query.page("Руины","Все",1).rows,rows.slice(30,60),"cached search preserves page order")
	t.equal(s.state_hash(),snapshot,"all page/search reads are nonmutating")
	var candidate: Sm2CheckpointSession=s._copy() as Sm2CheckpointSession
	t.expect(candidate._content.combat==s._content.combat,"internal candidates reuse built catalogs")
	candidate.world.bodies[2].progress.tracks.values()[0].earned+=1
	t.equal(s.state_hash(),snapshot,"mutable body practice is never shared with candidate")
	# A menu preview must not pretend that an unread archive has passed validation.
	var hash_value: String=s.archive.refs[0].hash; var path: String=s.repository.store._slot_path(hash_value)
	var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path)
	write_bytes(path,PackedByteArray([123,125]))
	t.expect(service.inspect()[0].ok,"preview does not read historical blocks")
	t.expect(not service.open(0,true).ok,"actual loading rejects damaged archive")
	t.equal(s.state_hash(),snapshot,"failed full load cannot change existing session")
	write_bytes(path,bytes)

static func container_totals(t: Sm2TestHarness) -> void:
	var s: Sm2CheckpointSession=make("user://container-totals")
	t.expect(s.new_game().ok,"container totals fixture")
	var catalog: Sm2SurvivalCatalog=s.journey().survival.catalog
	var item: Dictionary=catalog.item("medical_kit"); var container: Dictionary=catalog.item("stash")
	var limit: int=mini(int(container.capacity)/int(item.volume),int(container.max_mass)/int(item.mass))
	var inventory: Sm2PhysicalInventory=Sm2PhysicalInventory.new()
	inventory.add(1,"stash","ground","camp"); inventory.add(2,"stash","ground","camp")
	for i: int in limit*2: inventory.add(i+3,"medical_kit","container","1" if i<limit else "2")
	t.equal(inventory.validate(catalog,["2","4"],["camp"]),"","independent containers exactly at safe limits")
	for id: String in ["1","2"]:
		var used: Dictionary=inventory.usage(id,catalog)
		t.equal(used.mass,limit*int(item.mass),"reference mass for container "+id)
		t.equal(used.volume,limit*int(item.volume),"reference volume for container "+id)
	inventory.items[str(limit+3)].holder="1"
	t.equal(inventory.validate(catalog,["2","4"],["camp"]),"physical_capacity","one extra item rejected by aggregated capacity")
	inventory.items[str(limit+3)].holder="missing"
	t.equal(inventory.validate(catalog,["2","4"],["camp"]),"physical_container_reference","missing holder remains rejected before aggregate lookup")
	inventory.items[str(limit+3)].holder="2"; inventory.items["2"].place="container"; inventory.items["2"].holder="1"
	t.equal(inventory.validate(catalog,["2","4"],["camp"]),"physical_container_reference","nested containers remain rejected")
