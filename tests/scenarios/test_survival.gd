extends RefCounted

static func make() -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2SurvivalContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://survival_test"))

static func run(t: Sm2TestHarness) -> void:
	var content: Dictionary=Sm2SurvivalContentLoader.load_scenario()
	t.expect(content.ok,"survival content: "+str(content.get("errors",[])))
	if not content.ok: t.complete_suite("survival"); return
	var rules: Dictionary=content.survival.to_data()
	var body: Sm2Anatomy=Sm2Anatomy.fresh(rules)
	t.equal(body.injure("right_hand",20,true,rules),"","cut applied")
	t.equal(body.blood,5000,"injury does not advance time")
	var split: Sm2Anatomy=body.copy()
	body.advance(60,rules)
	for i: int in 10: split.advance(6,rules)
	t.equal(body.to_data(),split.to_data(),"physiology partition invariant")
	t.expect(Sm2Anatomy.decode(body.to_data(),rules).ok,"anatomy strict roundtrip")
	t.equal(body.bandage("1"),"","bandage active wound")
	var blood: int=body.blood; body.advance(600,rules)
	t.equal(body.blood,blood,"bandage stops future blood loss")
	t.equal(body.tissues.right_hand,10,"bandage does not regrow tissue")
	body.injure("heart",20,false,rules)
	t.expect(not body.cause(rules).is_empty(),"critical organ death")
	t.expect(body.summary(rules)>0,"death with positive summary")
	var s: Sm2JourneySession=make()
	var started: Dictionary=s.new_game(); t.expect(started.ok,"new survival world: "+str(started.get("errors",[])))
	if not started.ok: t.complete_suite("survival"); return
	_boundaries(t,s,rules)
	t.expect(s.save_game().ok,"save new physical world")
	var loaded: Sm2JourneySession=make(); var restored: Dictionary=loaded.restore(JSON.parse_string(JSON.stringify(s.capture())))
	t.expect(restored.ok,"restore physical world: "+str(restored.get("errors",[])))
	t.equal(loaded.state_hash(),s.state_hash(),"exact physical world restore")
	var inv: Sm2PhysicalInventory=s.journey().survival.inventory
	var pocket: String=""; var sword: String=""; var pack: String=""
	for id: String in inv.ids():
		if inv.owner(id)!=s.world.hero_id(): continue
		if inv.items[id].definition_id=="pockets": pocket=id
		if inv.items[id].definition_id=="backpack": pack=id
		if inv.items[id].definition_id=="m2:equipment.sword": sword=id
	t.expect(not pocket.is_empty() and not sword.is_empty(),"fixture physical equipment")
	if not sword.is_empty():
		var before: String=s.state_hash()
		t.expect(not s.act(s.command("store_item",int(pocket),sword)).ok,"sword too large for pocket")
		t.equal(s.state_hash(),before,"failed placement atomic")
		t.expect(s.act(s.command("store_item",int(pack),sword)).ok,"sword into backpack")
		t.expect(s.act(s.command("wear_item",s.world.hero_id(),sword)).ok,"equip same sword")
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"travel with physical inventory")
	started=s.act(s.command("start_battle"))
	t.expect(started.ok,"start anatomical battle: "+str(started.get("errors",[])))
	if not started.ok: t.complete_suite("survival"); return
	t.equal(s.runner.capture().session.battle.schema_version,19,"new battle schema")
	t.expect(s.save_game().ok,"save active anatomical battle")
	restored=loaded.restore(JSON.parse_string(JSON.stringify(s.capture())))
	t.expect(restored.ok,"restore anatomical battle: "+str(restored.get("errors",[])))
	t.equal(loaded.state_hash(),s.state_hash(),"battle load no physiology tick")
	var steps: int=0
	var bandaged: int=0
	while s.world.busy() and steps<400:
		var state: Dictionary=s.runner.view()
		var actor: Dictionary={}
		for row: Dictionary in state.actors:
			if row.actor_id==state.active_actor_id: actor=row
		if actor.controller=="player":
			var chosen: Sm2Command=null
			for wound: Dictionary in actor.anatomy.wounds:
				if int(wound.rate)==0: continue
				var command: Sm2Command=Sm2Command.new()
				command.kind="bandage"; command.actor_id=int(actor.actor_id); command.target_actor_id=int(actor.actor_id); command.ability_id=wound.id; command.expected_revision=int(state.revision); command.battle_id=state.battle_id
				if s.runner.preview(command).allowed: chosen=command; break
			if chosen!=null:
				var before_count: int=s.runner.capture().session.battle.survival.inventory.items.size()
				var result: Sm2CommandResult=s.attack(chosen)
				t.expect(result.accepted,"real bandage command: "+result.code)
				if not result.accepted: break
				var after_bandage: String=s.state_hash()
				t.expect(not s.attack(chosen).accepted,"replayed bandage rejected")
				t.equal(s.state_hash(),after_bandage,"replayed bandage changes nothing")
				bandaged+=1; steps+=1
				if s.world.busy(): t.equal(s.runner.capture().session.battle.survival.inventory.items.size(),before_count-1,"bandage consumes one physical object")
				t.expect(loaded.restore(JSON.parse_string(JSON.stringify(s.capture()))).ok,"reload after real bandage")
				continue
			var decision: Dictionary=s.runner._session._battle.ai_decision(Sm2AiContentLoader.load_profile().profile)
			if not decision.get("ok",false): t.expect(false,"player diagnostic AI"); break
			var result: Sm2CommandResult=s.attack(decision.command)
			if not result.accepted: t.expect(false,"survival battle command: "+result.code); break
		else:
			var result: Dictionary=s.step()
			if not result.ok: t.expect(false,"survival AI step: "+str(result)); break
		steps+=1
	t.expect(not s.world.busy(),"anatomy fight reaches outcome")
	t.expect(bandaged>0,"fight exercised bandaging")
	t.expect(s.save_game().ok,"save anatomical outcome")
	t.expect(loaded.restore(JSON.parse_string(JSON.stringify(s.capture()))).ok,"load anatomical outcome")
	t.equal(loaded.state_hash(),s.state_hash(),"outcome exact roundtrip")
	if s.world.hero_id()!=0:
		t.expect(s.act(s.command("end_life")).ok,"end prepared fixture life")
	if s.world.hero_id()==0:
		t.expect(s.act(s.command("incarnate",8)).ok,"clean new incarnation")
		t.equal(s.journey().survival.bodies["8"].blood,5000,"new body healthy")
		t.equal(s.journey().survival.bodies["8"].wounds.size(),0,"new body has no previous wounds")
		t.expect(s.save_game().ok,"save after incarnation")
		t.expect(loaded.restore(JSON.parse_string(JSON.stringify(s.capture()))).ok,"load after incarnation")
	t.complete_suite("survival")

static func _boundaries(t: Sm2TestHarness,s: Sm2JourneySession,rules: Dictionary) -> void:
	var world: Sm2JourneyWorld=s.journey().copy_world() as Sm2JourneyWorld
	var hero: String=str(world.hero_id())
	world.survival.bodies[hero].injure("right_hand",20,true,rules)
	world.survival.sync_world(world)
	var command: Sm2WorldCommand=s.command("bandage",world.hero_id(),"1")
	t.equal(world.check(command),"","out of combat bandage allowed")
	var count: int=world.survival.inventory.items.size()
	var start: int=world.survival.seconds
	world.apply(command)
	t.equal(world.survival.bodies[hero].rate(),0,"out of combat bandage stops bleeding")
	t.equal(world.survival.bodies[hero].blood,4940,"treatment takes time before stopping bleeding")
	t.equal(world.survival.seconds,start+6,"world treatment advances six seconds once")
	t.equal(world.survival.inventory.items.size(),count-1,"world treatment consumes one item")
	t.equal(world.survival.bodies[hero].tissues.right_hand,10,"world bandage does not restore hand")
	world=s.journey().copy_world() as Sm2JourneyWorld
	world.survival.bodies[hero].injure("right_hand",20,true,rules)
	world.survival.bodies[hero].blood=1501
	world.survival.sync_world(world)
	count=world.survival.inventory.items.size(); start=world.survival.seconds
	command=s.command("bandage",world.hero_id(),"1")
	world.apply(command)
	t.equal(world.hero_id(),0,"death interrupts bandaging and releases Soul")
	var no_body: Sm2WorldCommand=Sm2WorldCommand.new()
	no_body.kind="wear_item"; no_body.world_id=world.world_id; no_body.expected_revision=world.revision; no_body.incarnation_id=world.soul.incarnation_id
	t.expect(not world.check(no_body).is_empty(),"bodyless equipment rejected without crash")
	no_body.kind="bandage"
	t.expect(not world.check(no_body).is_empty(),"bodyless bandage rejected without crash")
	t.equal(world.survival.seconds,start+1,"world stops at first critical event")
	t.equal(world.survival.inventory.items.size(),count,"interrupted bandage consumes no material")
	world=s.journey().copy_world() as Sm2JourneyWorld
	world.survival.bodies[hero].injure("right_hand",20,true,rules)
	world.survival.bodies[hero].blood=1501
	world.survival.sync_world(world); start=world.survival.seconds
	command=s.command("travel",0,"ruins")
	world.apply(command)
	t.equal(world.region.location_id,"camp","death interrupts travel before arrival")
	t.equal(world.survival.seconds,start+1,"travel stops at death time")
	var inv: Sm2PhysicalInventory=s.journey().survival.inventory.copy()
	var belt: String=""; var bandage: String=""
	for id: String in inv.ids():
		if inv.owner(id)!=int(hero): continue
		if inv.items[id].definition_id=="belt": belt=id
		if inv.items[id].definition_id=="bandage": bandage=id
	var malformed: Sm2PhysicalInventory=inv.copy()
	malformed.items[belt]={"id":belt}
	t.expect(not malformed.validate(s.journey().survival.catalog,[hero,"4"],["camp","ruins","enclave"]).is_empty(),"malformed referenced parent rejected without crash")
	for id: int in range(900001,900004): inv.add(id,"bandage","container",belt)
	t.expect(not inv.move_error(bandage,"container",belt,s.journey().survival.catalog).is_empty(),"duplicate placement refused")
	inv.add(900004,"bandage","ground","camp")
	t.expect(not inv.move_error("900004","container",belt,s.journey().survival.catalog).is_empty(),"container volume enforced")
	var mass_rules: Dictionary=rules.duplicate(true)
	for row: Dictionary in mass_rules.items:
		if row.id=="belt": row.max_mass=75
	var mass_catalog: Sm2SurvivalCatalog=Sm2SurvivalCatalog.new()
	t.expect(mass_catalog.build(mass_rules).is_empty(),"custom container mass limit data")
	var weighed: Sm2PhysicalInventory=Sm2PhysicalInventory.new()
	weighed.add(1,"belt","ground","camp"); weighed.add(2,"bandage","container","1"); weighed.add(3,"bandage","ground","camp")
	t.expect(not weighed.move_error("3","container","1",mass_catalog).is_empty(),"mass cap rejects despite free volume")
	var no_material: Sm2JourneyWorld=s.journey().copy_world() as Sm2JourneyWorld
	no_material.survival.bodies[hero].injure("right_hand",1,true,rules)
	for id: String in no_material.survival.inventory.ids():
		if no_material.survival.inventory.owner(id)==int(hero) and no_material.survival.inventory.items[id].definition_id=="bandage": no_material.survival.inventory.items.erase(id)
	t.expect(not no_material.check(s.command("bandage",int(hero),"1")).is_empty(),"no material cannot bandage")
