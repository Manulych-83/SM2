extends RefCounted
const FIXTURE=preload("res://tests/fixtures/sm2_development_scale_fixture.gd")
const OUTING=preload("res://tests/scenarios/test_expedition.gd")

static func run(t: Sm2TestHarness) -> void:
	_storage_and_copy(t)
	var base: Dictionary=Sm2SurvivalContentLoader.load_scenario(true,true).development.progression().to_data()
	var metrics: Array[Dictionary]=[]
	for count: int in [100,1000,10000]:
		var catalog: Sm2ProgressCatalog=Sm2ProgressCatalog.new()
		var raw: Dictionary=FIXTURE.raw(count,base,false)
		var start: int=Time.get_ticks_usec()
		t.expect(catalog.build(raw).is_empty(),"large catalog builds %s" % count)
		var metric: Dictionary={"nodes":count,"tracks":catalog.track_ids().size(),"build_ms":(Time.get_ticks_usec()-start)/1000.0}
		var body: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(2,catalog)
		Sm2ProgressRules.award(body,{FIXTURE.TRACK:count})
		start=Time.get_ticks_usec()
		var allowed: bool=true
		for index: int in range(count-1,-1,-1):
			var id: String=FIXTURE.node_id(index)
			allowed=allowed and Sm2ProgressRules.purchase_error(body,catalog,id).is_empty()
			Sm2ProgressRules.purchase(body,catalog.node(id))
		t.expect(allowed,"all reverse-order purchases respect prerequisites")
		metric.purchase_all_ms=(Time.get_ticks_usec()-start)/1000.0
		start=Time.get_ticks_usec()
		var decoded: Dictionary=Sm2ProgressRules.decode_body(body.to_data(),catalog)
		metric.decode_ms=(Time.get_ticks_usec()-start)/1000.0
		t.expect(decoded.ok,"all learned nodes decode %s" % count)
		if decoded.ok: t.equal(decoded.body.to_data(),body.to_data(),"exact earned/spent/owned roundtrip")
		start=Time.get_ticks_usec()
		var all: Array[Dictionary]=Sm2ProgressRules.tracks(body,catalog)
		metric.all_tracks_ms=(Time.get_ticks_usec()-start)/1000.0
		start=Time.get_ticks_usec()
		var selected: Dictionary=Sm2ProgressRules.track(body,catalog,"p1:skill.psionics")
		metric.unrelated_track_ms=(Time.get_ticks_usec()-start)/1000.0
		for row: Dictionary in all:
			if row.id==selected.id: t.equal(selected,row,"selected projection equals full projection")
		var owned_row: Dictionary=Sm2ProgressRules.track(body,catalog,FIXTURE.TRACK)
		t.equal(owned_row.node_bonus,count,"all learned bonuses summed")
		t.equal(owned_row.earned,count,"purchase does not lower earned XP")
		t.equal(owned_row.available,0,"all node prices accounted")
		var track_index: int=catalog.track_ids().find(FIXTURE.TRACK)
		var bad: Dictionary=body.to_data(); bad.tracks[track_index].spent_total=0
		t.expect(not Sm2ProgressRules.decode_body(bad,catalog).ok,"unpaid nodes rejected")
		bad=body.to_data(); bad.tracks[track_index].owned_nodes.reverse()
		t.expect(not Sm2ProgressRules.decode_body(bad,catalog).ok,"unsorted owned list rejected")
		bad=body.to_data(); bad.tracks[track_index].owned_nodes[0]=bad.tracks[track_index].owned_nodes[1]
		t.expect(not Sm2ProgressRules.decode_body(bad,catalog).ok,"duplicate node rejected")
		var first: Array=catalog.nodes_for_track(FIXTURE.TRACK); first.clear()
		t.equal(catalog.nodes_for_track(FIXTURE.TRACK).size(),count,"index returned detached")
		var fingerprint: String=catalog.fingerprint()
		bad=raw.duplicate(true); bad.nodes[-1].requires=[FIXTURE.node_id(40)]
		t.expect(not catalog.build(bad).is_empty(),"cycle rejected iteratively")
		t.equal(catalog.fingerprint(),fingerprint,"failed rebuild preserves fingerprint")
		t.equal(catalog.nodes_for_track(FIXTURE.TRACK).size(),count,"failed rebuild preserves index")
		metrics.append(metric); print("SCALE "+JSON.stringify(metric))
	# Old versions retain their lower authored and saved-list limits.
	var old: Sm2ProgressCatalog=Sm2ProgressCatalog.new()
	var too_many: Dictionary=FIXTURE.raw(1001,base); too_many.version=Sm2ProgressCatalog.CROSS_VERSION
	t.expect(not old.build(too_many).is_empty(),"legacy version does not silently accept larger content")
	var overflow: Sm2ProgressCatalog=Sm2ProgressCatalog.new()
	t.expect(not overflow.build(FIXTURE.raw(10001,base)).is_empty(),"new catalog bound still enforced")
	_integration(t,metrics)
	var file: FileAccess=FileAccess.open("user://development-scale-metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics,"\t")); file.close()
	print("DEVELOPMENT_SCALE "+JSON.stringify(metrics))
	t.complete_suite("development_scale")

static func _storage_and_copy(t: Sm2TestHarness) -> void:
	var payload: Dictionary={"groups":[]}
	for i: int in 6:
		var group: Array=[]; group.resize(10000); group.fill(i); payload.groups.append(group)
	var legacy: Sm2SaveStore=Sm2SaveStore.new("user://scale-budget-legacy")
	t.expect(not legacy.save_slot(payload).ok,"old store retains 50000 structural-node limit")
	var store: Sm2SaveStore=Sm2SaveStore.new("user://scale-budget-large"); store.large_profile=true
	t.expect(store.save_slot(payload).ok and store.load_slot().ok,"explicit large policy writes and reads over 50000 nodes")
	t.expect(not Sm2SaveStore._read_envelope(store._slot_path("session")).ok,"default reader does not infer larger budget from file")
	var before: String=FileAccess.get_sha256(store._slot_path("session"))
	for i: int in 15: payload.groups.append(payload.groups[0].duplicate())
	t.expect(not store.save_slot(payload).ok,"large profile still bounds structural nodes at 200000")
	t.equal(FileAccess.get_sha256(store._slot_path("session")),before,"oversized refusal preserves previous file")
	var body: Sm2CompanionProgress=Sm2CompanionProgress.new(); body.id=4; body.earned=55
	var copy: Sm2ProgressBodyState=body.copy()
	t.expect(copy is Sm2CompanionProgress,"transaction copy preserves companion growth type")
	(copy as Sm2CompanionProgress).earned=100
	t.equal(body.earned,55,"companion transaction copy detached")
	var content: Dictionary=Sm2SurvivalContentLoader.load_scenario(true,true)
	var development: Sm2DevelopmentCatalog=content.development
	var fingerprint: String=development.fingerprint()
	t.equal(fingerprint,Sm2Canonical.hash([development.to_data(),development.progression().to_data()]),"cached development hash uses original encoding")
	var public_copy: Sm2ProgressCatalog=development.progression()
	var raw: Dictionary=public_copy.to_data(); raw.nodes[0].bonus+=1
	t.expect(public_copy.build(raw).is_empty(),"public defensive copy independently rebuilds")
	t.equal(development.fingerprint(),fingerprint,"public copy cannot mutate cached catalog")
	var changed: Dictionary=development.to_data(); changed.mappings[0].scale+=1
	t.expect(development.build(changed,development.progression(),content.combat).is_empty(),"development catalog rebuild succeeds")
	t.expect(development.fingerprint()!=fingerprint,"successful rebuild invalidates cached fingerprint")

static func _integration(t: Sm2TestHarness,metrics: Array[Dictionary]) -> void:
	print("SCALE integration")
	var content: Dictionary=FIXTURE.content()
	t.expect(content.ok,"large progression composes with anatomy, genetics, implants and psionics")
	if not content.ok: return
	var s: Sm2CheckpointSession=Sm2CheckpointSession.new(content,Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://development-scale"))
	t.expect(s.new_game().ok,"large campaign starts")
	var before: String=s.state_hash()
	var start: int=Time.get_ticks_usec()
	var page: Dictionary=Sm2HeroDevelopmentView.build(s,FIXTURE.TRACK)
	metrics.append({"name":"large_view_first_page","ms":(Time.get_ticks_usec()-start)/1000.0})
	t.equal(page.nodes.size(),24,"large view materializes only a page")
	var last_id: String=s.world._progress.nodes_for_track(FIXTURE.TRACK)[-1]
	page=Sm2HeroDevelopmentView.build(s,FIXTURE.TRACK,{"focus":last_id})
	t.equal(page.nodes[-1].id,last_id,"linked node opens on last page")
	t.equal(page.nodes[-1].unlocks.size(),12,"branching root links are paginated")
	t.expect(int(page.nodes[-1].unlocks_count)>12,"root has more links than visible controls")
	var root_page: Dictionary=Sm2HeroDevelopmentView.build(s,FIXTURE.TRACK,{"focus":last_id,"link_offsets":{last_id+"/unlocks":1}})
	t.expect(root_page.nodes[-1].unlocks[0].id!=page.nodes[-1].unlocks[0].id,"link page reaches remaining children")
	page=Sm2HeroDevelopmentView.build(s,FIXTURE.TRACK,{"query":"00001"})
	t.equal(page.nodes.size(),1,"search includes nodes outside visible page")
	page=Sm2HeroDevelopmentView.build(s,FIXTURE.TRACK,{"filter":2})
	t.equal(page.node_count,0,"owned filter has no fabricated nodes")
	t.equal(s.state_hash(),before,"large queries do not mutate campaign")
	for i: int in 8: t.expect(s.act(s.command("practice",2,"p5:activity.psionics")).ok,"real practice remains available")
	t.expect(s.act(s.command("buy_node",2,"p5:node.impulse")).ok,"actual node purchase through session")
	# Explicit synthetic late-game fixture: stress storage, not the provenance of XP.
	var body: Sm2ProgressBodyState=s.world.bodies[2].progress
	var ids: Array=s.world._progress.nodes_for_track(FIXTURE.TRACK)
	Sm2ProgressRules.award(body,{FIXTURE.TRACK:ids.size()})
	for index: int in range(ids.size()-1,-1,-1): Sm2ProgressRules.purchase(body,s.world._progress.node(ids[index]))
	before=s.state_hash(); start=Time.get_ticks_usec()
	var saved: Dictionary=s.save_game()
	t.expect(saved.ok,"developed large campaign saves: "+str(saved.get("errors",[])))
	metrics.append({"name":"large_campaign_save","ms":(Time.get_ticks_usec()-start)/1000.0,"owned_fixture_nodes":ids.size()})
	start=Time.get_ticks_usec()
	var loaded: Dictionary=s.load_game()
	t.expect(loaded.ok,"developed large campaign loads: "+str(loaded.get("errors",[])))
	metrics.append({"name":"large_campaign_load","ms":(Time.get_ticks_usec()-start)/1000.0})
	t.equal(s.state_hash(),before,"large campaign roundtrip exact")
	page=Sm2HeroDevelopmentView.build(s,FIXTURE.TRACK,{"filter":2,"page":99999})
	t.equal(page.node_count,ids.size(),"owned filter includes all late pages")
	t.expect(page.nodes.size()<=24,"last page clamped")
	page=Sm2HeroDevelopmentView.build(s,FIXTURE.TRACK,{"filter":1})
	t.equal(page.node_count,0,"no purchased node offered twice")
	t.expect(s.act(s.command("travel",0,"ruins")).ok and s.act(s.command("start_battle")).ok,"large catalog enters real combat")
	print("SCALE combat started")
	if not _retreat(s,t): return
	print("SCALE combat settled")
	t.expect(s.act(s.command("end_life")).ok and s.act(s.command("incarnate",8)).ok,"large campaign reincarnates")
	t.equal(s.world.bodies[8].progress.tracks[FIXTURE.TRACK].earned,0,"new body has zero practice")
	t.expect(s.world.bodies[8].progress.tracks[FIXTURE.TRACK].nodes.is_empty(),"new body has no inherited nodes")
	t.equal(s.world.bodies[2].progress.tracks[FIXTURE.TRACK].nodes.size(),ids.size(),"old body retains its development")
	t.expect(s.save_game().ok and s.load_game().ok,"large previous body and clean new body roundtrip")

static func _retreat(s: Sm2CheckpointSession,t: Sm2TestHarness) -> bool:
	for i: int in 150:
		if not s.world.busy(): return true
		var started: int=Time.get_ticks_usec()
		var view: Dictionary=s.runner.view(); var player: bool=false
		for actor: Dictionary in view.actors:
			if int(actor.actor_id)!=int(view.active_actor_id) or actor.controller!="player" or actor.morale=="fleeing": continue
			player=true
			var command: Sm2Command=Sm2Command.new(); command.actor_id=int(actor.actor_id); command.expected_revision=int(view.revision); command.battle_id=view.battle_id
			command.kind="escape" if int(actor.q)==0 else "move"; command.target=Vector2i(0,int(actor.r))
			if not s.runner.preview(command).allowed: command.kind="end_turn"
			var result: Sm2CommandResult=s.attack(command)
			t.expect(result.accepted,"large retreat accepted: "+str(result.code))
			if not result.accepted: return false
		if not player:
			var result: Dictionary=s.step()
			t.expect(result.ok,"large enemy step: "+str(result.get("errors",result.get("reason",""))))
			if not result.ok: return false
		print("SCALE combat step %s %.3f ms" % [i,(Time.get_ticks_usec()-started)/1000.0])
	t.expect(false,"large retreat bounded")
	return false
