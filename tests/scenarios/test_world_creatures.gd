extends RefCounted
const OUTING=preload("res://tests/scenarios/test_expedition.gd")

static func run(t: Sm2TestHarness) -> void:
	var content: Dictionary=Sm2WorldCreatureContentLoader.load_scenario()
	t.expect(content.ok,"world creature content: "+str(content.get("errors",[])))
	if not content.ok: return
	_validation(t,content)
	var ai: Dictionary=Sm2AiContentLoader.load_profile(Sm2AiContentLoader.ABILITY_PATH)
	var session: Sm2CheckpointSession=Sm2CheckpointSession.new(content,ai.profile,Sm2SaveStore.new("user://world-creatures-test"))
	var started: Dictionary=session.new_game()
	t.expect(started.ok,"new template world: "+str(started.get("errors",[])))
	if not started.ok: return
	t.equal(session.world.capture().format,Sm2WorldCreatureCatalog.WORLD_FORMAT,"explicit new world format")
	t.equal(session.world.capture().creatures.bindings.size(),6,"all six persistent enemies bound")
	var first_gear: Array[Dictionary]=session.journey().equipment(10)
	var second_gear: Array[Dictionary]=session.journey().equipment(11)
	t.equal(first_gear.size(),4,"physical starter equipment from guard template")
	for i: int in first_gear.size():
		t.equal(first_gear[i].definition_id,second_gear[i].definition_id,"same template gear definitions")
		t.expect(first_gear[i].id!=second_gear[i].id,"independent item identity")
	t.expect(session.journey().survival.bodies["10"]!=session.journey().survival.bodies["11"],"separate anatomy instances")
	var snapshot: Dictionary=session.capture()
	for defect: String in ["format","binding","fingerprint","health","fields"]:
		var bad: Dictionary=snapshot.duplicate(true)
		match defect:
			"format": bad.world.format="sm2.world.survival.3"
			"binding": bad.world.creatures.bindings[0].template_id="campaign:type.archer"
			"fingerprint": bad.world.creatures.fingerprint="bad"
			"health": bad.world.bodies[0].hp=59
			"fields": bad.world.erase("creatures")
		t.expect(not session.restore(bad).ok,"reject tampered world "+defect)
		t.equal(session.capture(),snapshot,"failed restore preserves live world "+defect)
	t.expect(session.act(session.command("travel",0,"ruins")).ok,"travel to ruins")
	var battle: Dictionary=session.act(session.command("start_battle"))
	t.expect(battle.ok,"start template battle: "+str(battle.get("errors",[])))
	if not battle.ok: return
	t.equal(session.runner.view().actors[2].display_name,"Страж руин","authored name reaches combat view")
	t.expect(session.runner.state_copy().actor(3).anatomy!=null,"template enemy has full anatomy")
	t.equal(_profile_id(session._encounter.catalog,"p4:loadout.actor.3"),"campaign:profile.guard","selected actor profile compiled")
	t.equal(session._encounter.catalog.to_data().profiles.size(),content.catalog.to_data().profiles.size()+1,"only current enemy profile added")
	# Reach accepted hits using the same AI for every participant, without altering stats or RNG.
	var continuation: Sm2CheckpointSession
	var had_damage: bool=false
	for step_index: int in 300:
		if not session.world.busy(): break
		var result: Dictionary=_advance(session)
		t.expect(result.ok,"real battle step: "+str(result.get("errors",result.get("reason",""))))
		if not result.ok: return
		if step_index==10 and session.world.busy():
			var save_result: Dictionary=session.save_game()
			t.expect(save_result.ok,"save active template battle: "+str(save_result.get("errors",[])))
			continuation=Sm2CheckpointSession.new(content,ai.profile,session._store)
			var restored: Dictionary=continuation.load_game()
			t.expect(restored.ok,"load active template battle: "+str(restored.get("errors",[])))
			if not restored.ok: return
			t.equal(continuation.state_hash(),session.state_hash(),"active save/load exact")
		elif continuation!=null:
			t.expect(_advance(continuation).ok,"loaded battle continuation")
			t.equal(continuation.state_hash(),session.state_hash(),"identical continuation and outcomes")
		for actor: Sm2TacticalActor in session.runner.state_copy().actors.values():
			if actor.combat.hp<60 or not actor.spatial.alive: had_damage=true
	t.expect(not session.world.busy(),"battle finishes within bounded actions")
	t.expect(had_damage,"real battle inflicted anatomical damage")
	t.equal(session.journey().completed,1,"one encounter settled")
	var final_state: Sm2TacticalState=session.runner.state_copy()
	for actor: Dictionary in final_state.development.origin_actors():
		var id: String=actor.body_id
		t.equal(session.journey().survival.bodies[id].to_data(),final_state.survival.bodies[id].to_data(),"wounds and death persist "+id)
	var settled: Dictionary=session.capture()
	t.expect(session.save_game().ok,"save settled template encounter")
	t.expect(session.load_game().ok,"load settled template encounter")
	t.equal(session.state_hash(),Sm2Canonical.hash(settled),"closed battle and physical world exact")
	if session.world.hero_id()==0:
		t.expect(session.act(session.command("incarnate",8)).ok,"new clean carrier after death")
		if session.world.hero_id()==0: return
	var dead: Array[int]=[]
	for id: int in [2,4,10,11]:
		if not session.world.bodies[id].alive: dead.append(id)
	t.expect(not dead.is_empty(),"battle leaves a corpse")
	if not dead.is_empty():
		var corpse_items: Array[Dictionary]=session.journey().equipment(dead[0])
		t.expect(not corpse_items.is_empty(),"corpse retains its actual equipped items")
		if not corpse_items.is_empty():
			var corpse_item: String=corpse_items[0].id
			t.expect(session.act(session.command("drop_item",0,corpse_item)).ok,"recover exact corpse item to local ground")
			t.equal(session.journey().survival.inventory.items[corpse_item].place,"ground","corpse equipment retains ID after recovery")
			var recovered: String=session.state_hash()
			t.expect(session.save_game().ok and session.load_game().ok,"save/load recovered corpse item")
			t.equal(session.state_hash(),recovered,"recovered item location survives loading")
	# Remaining authored types select their parameters/actions while preserving hero psionics.
	session=Sm2CheckpointSession.new(content,ai.profile,Sm2SaveStore.new("user://world-creatures-route"))
	t.expect(session.new_game().ok,"independent objective route starts")
	t.expect(session.act(session.command("travel",0,"ruins")).ok,"objective route reaches ruins")
	t.expect(session.act(session.command("start_battle")).ok,"objective route first meeting")
	OUTING.retreat(session,t)
	var ids: Array=OUTING.finish_supplies(session,t)
	t.equal(ids.size(),4,"original objective still available after template encounter")
	var stash: String=OUTING.container(session,"stash")
	for id: String in ids: t.expect(session.act(session.command("store_item",int(stash),id)).ok,"deliver the four actual medicine instances")
	t.expect(Sm2ExpeditionView.new().build(session).complete,"main outing objective completes with template enemies")
	t.expect(session.act(session.command("travel",0,"ruins")).ok,"return for second meeting")
	t.expect(session.act(session.command("start_battle")).ok,"second template encounter starts")
	t.equal(_profile_id(session._encounter.catalog,"p4:loadout.actor.3"),"campaign:profile.raider","raider parameter profile")
	t.equal(_profile_id(session._encounter.catalog,"p4:loadout.actor.4"),"campaign:profile.archer","archer parameter profile")
	t.expect(session.save_game().ok and session.load_game().ok,"second meeting save/load")
	OUTING.retreat(session,t)
	t.expect(session.act(session.command("start_battle")).ok,"third encounter starts")
	var effects: Dictionary=session._encounter.effects.to_data()
	var granted: bool=false
	for p: Dictionary in effects.profiles:
		if p.id=="p4:loadout.actor.4": granted="sequences:ability.exhaustion" in p.actions and "status.poison" in p.immunities
	t.expect(granted,"enemy composed action and immunity come from template")
	t.expect(session.runner.state_copy().actor(4).anatomy!=null,"status user retains full anatomy")
	var applied: bool=false
	for i: int in 160:
		if not session.world.busy() or applied: break
		var next: Dictionary=_advance(session)
		t.expect(next.ok,"third encounter real action")
		if not next.ok: break
		applied=not session.runner.state_copy().effects.is_empty()
	t.expect(applied,"template status ability produces active effects in main battle")
	var third_save: Dictionary=session.save_game()
	t.expect(third_save.ok,"save encounter with template status: "+str(third_save.get("errors",[])))
	t.expect(session.load_game().ok,"load encounter with template status")
	_compatibility(t)
	t.complete_suite("world_creatures")

static func _compatibility(t: Sm2TestHarness) -> void:
	var directory: String="user://template-compatibility-"+str(Time.get_ticks_usec())
	var service: Sm2Campaigns=Sm2Campaigns.new(directory)
	var old: Sm2CheckpointSession=Sm2CheckpointSession.new(service.legacy_content,service.legacy_profile,service.store(0),service.history_repository)
	t.expect(old.new_game().ok,"old checkpoint starts under historical definitions")
	t.expect(old.act(old.command("travel",0,"ruins")).ok and old.act(old.command("start_battle")).ok,"old checkpoint active battle")
	t.expect(_advance(old).ok,"old battle real command")
	t.expect(old.save_game().ok,"old active checkpoint saved")
	var path: String=old._store._slot_path("survival_tissues")
	var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path)
	t.expect(service.inspect()[0].ok,"old active slot preview accepted")
	var loaded: Dictionary=service.open(0,true)
	t.expect(loaded.ok,"old checkpoint opens alongside new campaigns")
	if not loaded.ok: return
	var restored: Sm2CheckpointSession=loaded.session
	t.expect(restored.journey().world_creatures==null,"old campaign keeps historical mechanics")
	t.equal(restored.state_hash(),old.state_hash(),"old active world/battle not advanced on load")
	t.equal(FileAccess.get_file_as_bytes(path),bytes,"old source bytes untouched by opening")
	t.expect(_advance(old).ok and _advance(restored).ok,"both old continuations advance")
	t.equal(restored.state_hash(),old.state_hash(),"old continuation remains identical")
	var fresh: Dictionary=service.open(1,false)
	t.expect(fresh.ok and fresh.session.journey().world_creatures!=null,"new slot selects template profile")
	t.expect(fresh.session.save_game().ok,"new slot saves beside old active world")
	t.expect(service.inspect()[0].ok and service.inspect()[1].ok,"mixed-version slot cards")
	var tampered: Dictionary=fresh.session.capture(); tampered.fingerprint=service.legacy_content.journey_fingerprint
	t.expect(not service._validate(tampered).ok,"fingerprint cannot relabel new world as historical")

static func _validation(t: Sm2TestHarness,c: Dictionary) -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/creatures/world.json"))
	var raw: Dictionary={"version":Sm2CreatureCatalog.TYPES_VERSION,"profiles":data.profiles,"templates":data.templates,"encounters":[]}
	var types: Sm2CreatureCatalog=Sm2CreatureCatalog.new()
	var e: Dictionary=Sm2EffectSequenceContentLoader.load_scenario()
	t.expect(types.build(raw,c.catalog,c.combat,e.effects,{},["guard","raider","archer","poisoner"]).is_empty(),"definitions-only catalog validated without dummy encounter")
	var target: Sm2WorldCreatureCatalog=c.world_creatures.copy(); var before: String=target.fingerprint()
	for defect: String in ["version","duplicate","missing","party","anatomy","template"]:
		var bad: Dictionary=target.to_data()
		match defect:
			"version": bad.version="unsupported"
			"duplicate": bad.bindings.append(bad.bindings[0].duplicate(true))
			"missing": bad.bindings.pop_back()
			"party": bad.bindings[0].id="4"
			"anatomy": bad.bindings[0].anatomy_id="unknown"
			"template": bad.bindings[0].template_id="missing"
		t.expect(not target.build(bad,types,c.world_definition,c.meetings,c.survival,c.combat).is_empty(),"invalid binding rejected "+defect)
		t.equal(target.fingerprint(),before,"atomic catalog failure "+defect)
	var copy: Dictionary=target.actor(10); copy.definition.equipment_ids.clear()
	t.equal(target.actor(10).definition.equipment_ids.size(),4,"public template query defensive")
	var wrong_health: Dictionary=types.to_data(); wrong_health.profiles[0].combat.hp_max=59
	var wrong_types: Sm2CreatureCatalog=Sm2CreatureCatalog.new()
	t.expect(wrong_types.build(wrong_health,c.catalog,c.combat,e.effects,{},["guard","raider","archer","poisoner"]).is_empty(),"alternate HP is valid for isolated creature battles")
	t.expect(not target.build(target.to_data(),wrong_types,c.world_definition,c.meetings,c.survival,c.combat).is_empty(),"campaign refuses HP conflicting with anatomy")

static func _profile_id(c: Sm2TurnCatalog,id: String) -> String:
	for row: Dictionary in c.to_data().loadouts:
		if row.id==id: return row.profile_id
	return ""

static func _advance(s: Sm2CheckpointSession) -> Dictionary:
	var status: Dictionary=s.runner.status()
	for actor: Dictionary in status.actors:
		if actor.actor_id!=status.active_actor_id or actor.controller!="player" or actor.morale=="fleeing": continue
		var decision: Dictionary=s.runner._session.ai_decision(s._profile)
		if not decision.ok: return decision
		var result: Sm2CommandResult=s.attack(decision.command)
		return {"ok":result.accepted,"reason":result.code}
	return s.step()
