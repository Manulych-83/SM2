extends RefCounted
const BODY=preload("res://tests/scenarios/test_p4_body.gd")
const PARTY=preload("res://tests/scenarios/test_p4_party.gd")
const RIGHT: String="p4:ability.sever_right"
const LEFT: String="p4:ability.sever_left"

static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2ProsthesisContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)

static func loss_content() -> Dictionary:
	# Diagnostic enemy equipment guarantees the new operation is exercised by AI.
	var c: Dictionary=Sm2ProsthesisContentLoader.load_scenario()
	var raw: Dictionary=c.combat.to_data()
	for gear: Dictionary in raw.equipment:
		if gear.id=="m2:equipment.sword": gear.abilities=[RIGHT]
	var combat: Sm2CombatCatalog=Sm2CombatCatalog.new(); combat.build(raw,c.catalog)
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	development.build(c.development.to_data(),c.development.progression(),combat)
	c.combat=combat; c.development=development
	c.setup.actors[2].q=2; c.setup.actors[2].r=1; c.setup.actors[3].q=2; c.setup.actors[3].r=3
	c.journey_fingerprint=Sm2Canonical.hash([c.journey_fingerprint,raw,c.setup]); return c

static func finish_retreat(s: Sm2JourneySession,t: Sm2TestHarness) -> void:
	for i: int in 100:
		if not s.world.busy(): break
		var result: Dictionary=BODY.treatment_step(s)
		t.expect(result.ok,"loss encounter advances "+str(result.get("code",result.get("reason",""))))
		if not result.ok: break
	t.expect(not s.world.busy(),"loss encounter settles")

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2ProsthesisContentLoader.load_scenario()
	t.expect(c.ok,"prosthesis content validates "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("p4_prosthesis"); return
	var b: Sm2TacticalBattle=BODY.fixture(c)
	t.expect(not b.view().is_empty(),"prosthesis encounter starts")
	if b.view().is_empty(): t.complete_suite("p4_prosthesis"); return
	t.equal(b.capture().schema_version,12,"explicit schema12")
	t.equal(b.capture().ruleset,Sm2EncounterOrigin.PROSTHESIS_RULESET,"explicit prosthesis ruleset")
	var hit: bool=false; var miss: bool=false
	for seed_value: int in range(1,35):
		b=BODY.fixture(c,seed_value)
		var hash_value: String=b.state_hash()
		t.expect(b.preview(BODY.command(b,RIGHT)).function_sever,"preview explains loss")
		t.equal(b.state_hash(),hash_value,"preview no mutation")
		var result: Sm2CommandResult=b.execute(BODY.command(b,RIGHT))
		t.expect(result.accepted,"sever action accepted "+result.code)
		for event: Dictionary in result.events:
			if event.type=="attack_missed": miss=true; t.expect(not b._state.actor(3).body_functions.missing.right_hand,"miss retains natural arm")
			if event.type=="body_part_lost": hit=true
		if hit and miss and b._state.actor(3).body_functions.missing.right_hand: break
	t.expect(hit and miss,"real hit and miss observed")
	t.expect(b._state.actor(3).body_functions.missing.right_hand,"real damage removes hand")
	t.expect(not b.view().actors[2].abilities.has("m2:ability.sword_strike"),"lost hand cannot wield sword")
	var hash_value: String=b.state_hash()
	t.expect(b.restore(b.capture()).ok,"lost hand snapshot restores")
	t.equal(hash_value,b.state_hash(),"loss snapshot exact")
	for defect: String in ["natural","working","operation","duplicate","schema"]:
		var bad: Dictionary=b.capture()
		match defect:
			"natural": bad.actors[2].body_functions.parts[1].missing=false
			"working": bad.actors[2].body_functions.parts[1].working=true
			"operation": bad.body_changes[0].operation="disable"
			"duplicate": bad.body_changes.append(bad.body_changes[0].duplicate(true))
			"schema": bad.schema_version=11
		t.expect(not b.restore(bad).ok,"reject loss forgery "+defect)
		t.equal(b.state_hash(),hash_value,"forgery atomic")
	b=BODY.fixture(c,1,"",true); hash_value=b.state_hash()
	var denied: Sm2CommandResult=b.execute(BODY.command(b,RIGHT))
	t.equal(denied.code,"experience_limit","late practice failure")
	t.equal(b.state_hash(),hash_value,"late failure rolls back loss and receipts")
	t.expect(denied.events.is_empty(),"late failure no events")
	# Loss also affects the shield hand and common passive defense.
	for seed_value: int in range(1,35):
		b=BODY.fixture(c,seed_value); t.expect(b.execute(BODY.command(b,LEFT)).accepted,"left sever action")
		if b._state.actor(3).body_functions.missing.left_hand: break
	t.expect(b._state.actor(3).body_functions.missing.left_hand,"left hand removed")
	t.equal(b.preview(BODY.command(b,"m2:ability.sword_strike")).modifiers.shield,0,"missing shield hand gives no defense")
	_world(t)
	_contracts(t,c)
	_transitions(t,c)
	_inventory_validation(t)
	t.complete_suite("p4_prosthesis")

static func _world(t: Sm2TestHarness) -> void:
	var c: Dictionary=loss_content()
	var s: Sm2JourneySession=Sm2JourneySession.new(c,Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://prosthesis-tests"))
	t.expect(s.new_game().ok,"prosthetic world starts")
	var device: String=s.journey().prostheses.items[0].id
	var alien: String=s.journey().prostheses.items[3].id
	var before: String=s.state_hash()
	t.expect(not s.act(s.command("install_prosthesis",2,device)).ok,"cannot replace healthy arm")
	t.equal(s.state_hash(),before,"invalid installation atomic")
	t.expect(s.act(s.command("start_battle")).ok,"loss fight starts")
	for kind: String in Sm2ProsthesisInventory.COMMANDS:
		t.expect(not s.act(s.command(kind,2,device)).ok,"prosthetic operation blocked in battle "+kind)
	for i: int in 3: t.expect(BODY.treatment_step(s).ok,"enemy loss action advances")
	t.expect(s.save_game().ok,"active loss saved")
	var loaded: Sm2JourneySession=Sm2JourneySession.new(c,s._profile,s._store)
	t.expect(loaded.load_game().ok,"active loss loaded")
	t.equal(s.state_hash(),loaded.state_hash(),"active save exact")
	t.equal(BODY.treatment_step(s),BODY.treatment_step(loaded),"same next action after load")
	finish_retreat(s,t)
	t.expect(s.world.hero_id()==2 and s.world.bodies[2].functions.missing.right_hand,"hero survives with lost hand")
	if s.world.hero_id()!=2 or not s.world.bodies[2].functions.missing.right_hand: return
	before=s.state_hash()
	t.expect(not s.act(s.command("heal_hand",2,"right_hand")).ok,"biological treatment cannot regrow arm")
	t.expect(not s.act(s.command("install_prosthesis",2,alien)).ok,"incompatible interface refused")
	t.equal(s.state_hash(),before,"rejected services unchanged")
	var xp: Dictionary=s.world.bodies[2].progress.to_data(); var hp: int=s.world.bodies[2].hp
	t.expect(s.act(s.command("install_prosthesis",2,device)).ok,"install prepared compatible prosthesis")
	t.equal(s.world.bodies[2].functions.prostheses.right_hand,device,"body references unique item")
	t.equal(s.journey().prostheses.item(device).owner_id,"2","installed item belongs to body")
	t.expect(s.world.bodies[2].functions.working.right_hand,"device restores right hand function")
	t.equal(s.world.bodies[2].progress.to_data(),xp,"installation awards no practice")
	t.equal(s.world.bodies[2].hp,hp,"installation awards no HP")
	before=s.state_hash()
	t.expect(not s.act(s.command("install_prosthesis",2,device)).ok,"cannot install twice")
	t.expect(not s.act(s.command("transfer_prosthesis",4,device)).ok,"installed device cannot transfer")
	t.equal(s.state_hash(),before,"duplicate installation and transfer atomic")
	t.expect(s.act(s.command("remove_prosthesis",0,device)).ok,"detach device")
	t.expect(not s.world.bodies[2].functions.working.right_hand,"detach removes artificial function")
	t.expect(s.act(s.command("transfer_prosthesis",4,device)).ok,"transfer loose device")
	t.expect(not s.act(s.command("install_prosthesis",2,device)).ok,"must transfer from companion before installation")
	t.expect(s.act(s.command("transfer_prosthesis",6,device)).ok,"device to stash")
	t.expect(s.act(s.command("install_prosthesis",2,device)).ok,"reinstall same device from stash")
	t.expect(s.save_game().ok and loaded.load_game().ok,"installed item disk save")
	t.equal(s.state_hash(),loaded.state_hash(),"world history restores installation")
	_damage(t,s,device)
	var companion: Dictionary=s.world.bodies[4].to_data()
	t.expect(s.act(s.command("end_life")).ok,"end prosthetic body life")
	t.equal(s.journey().prostheses.item(device).owner_id,"2","device stays with previous body")
	t.expect(s.act(s.command("incarnate",8)).ok,"incarnate in pure body")
	t.equal(s.world.bodies[4].to_data(),companion,"companion state persists")
	t.expect(not s.world.bodies[8].functions.missing.right_hand and s.world.bodies[8].functions.prostheses.right_hand.is_empty(),"new body natural with no implants")
	for track: Sm2ProgressTrackState in s.world.bodies[8].progress.tracks.values(): t.equal(track.earned,0,"new body no practice")
	t.expect(s.act(s.command("remove_prosthesis",0,device)).ok,"retrieve installed device from old corpse")
	t.expect(s.act(s.command("transfer_prosthesis",6,device)).ok,"old device to persistent stash")
	t.expect(not s.act(s.command("install_prosthesis",8,device)).ok,"cannot install into fresh healthy body")
	t.expect(s.save_game().ok and loaded.load_game().ok,"reincarnation and retrieval persist")
	t.equal(s.state_hash(),loaded.state_hash(),"new incarnation save exact")
	before=s.state_hash()
	for defect: String in ["duplicate","owner","missing","condition","history"]:
		var bad: Dictionary=s.capture()
		match defect:
			"duplicate": bad.world.prostheses.append(bad.world.prostheses[0].duplicate(true))
			"owner": bad.world.prostheses[0].owner_id="8"
			"missing": bad.world.prostheses.clear()
			"condition": bad.world.prostheses[0].working=false
			"history": bad.history[bad.history.size()-1].command.content_id="999999"
		t.expect(not s.restore(bad).ok,"world forgery refused "+defect)
		t.equal(s.state_hash(),before,"world forged load atomic")

static func _damage(t: Sm2TestHarness,s: Sm2JourneySession,device: String) -> void:
	t.expect(s.act(s.command("start_battle")).ok,"next fight with installed device")
	t.expect(s.runner.view().actors[0].abilities.has(RIGHT),"prosthesis restores real attack in next battle")
	finish_retreat(s,t)
	t.expect(s.world.hero_id()==2,"prosthetic hero survives second encounter")
	if s.world.hero_id()!=2: return
	t.expect(not s.journey().prostheses.item(device).working,"real hit damages installed device")
	t.equal(s.world.bodies[2].functions.prostheses.right_hand,device,"damage retains installed unique device")
	t.expect(not s.act(s.command("heal_hand",2,"right_hand")).ok,"treatment cannot fix prosthesis")
	t.expect(s.act(s.command("remove_prosthesis",0,device)).ok,"remove damaged device")
	t.expect(not s.act(s.command("install_prosthesis",2,device)).ok,"reinstallation cannot repair damage")
	var xp: Dictionary=s.world.bodies[2].progress.to_data()
	t.expect(s.act(s.command("repair_prosthesis",0,device)).ok,"repair loose device")
	t.expect(s.act(s.command("install_prosthesis",2,device)).ok,"install repaired device")
	t.equal(s.world.bodies[2].progress.to_data(),xp,"repair and installation grant no XP")

static func _contracts(t: Sm2TestHarness,c: Dictionary) -> void:
	var raw: Dictionary=c.development.to_data(); raw.version=Sm2DevelopmentCatalog.BODY_VERSION
	t.expect(not Sm2DevelopmentCatalog.new().build(raw,c.development.progression(),c.combat).is_empty(),"old body profile rejects new functions")
	var legacy: Sm2JourneySession=BODY.make(); t.expect(legacy.new_game().ok,"old body mode starts")
	var current: Sm2JourneySession=make(); t.expect(current.new_game().ok,"new profile starts independently")
	t.expect(not legacy.restore(current.capture()).ok and not current.restore(legacy.capture()).ok,"profiles cannot cross-load")
	var functions: Sm2BodyFunctionCatalog=c.development.body_functions()
	for defect: String in ["interface","unknown_part","unknown_starter","unknown_ability"]:
		var data: Dictionary=functions.to_data()
		match defect:
			"interface": data.parts[0].interface=""
			"unknown_part": data.prostheses[0].part_id="wing"
			"unknown_starter": data.starter_prostheses.append("unknown")
			"unknown_ability": data.sever_abilities["unknown"]="right_hand"
		t.expect(not Sm2BodyFunctionCatalog.new().build(data,c.combat,c.development.progression()).is_empty(),"invalid content rejected "+defect)

static func _transitions(t: Sm2TestHarness,c: Dictionary) -> void:
	# A natural injured hand may later be lost. Neither operation erases practice.
	var b: Sm2TacticalBattle=BODY.fixture(c)
	var target: Sm2TacticalActor=b._state.actor(3)
	var source: Sm2TacticalActor=b._state.actor(1)
	var initial: Dictionary=target.body_functions.to_data()
	var events: Array[Dictionary]=[]
	Sm2BodyFunctionRules.after_hit(b._state,source,target,BODY.RIGHT,1,events)
	t.expect(not target.body_functions.working.right_hand and not target.body_functions.missing.right_hand,"injury retains natural limb")
	Sm2BodyFunctionRules.after_hit(b._state,source,target,RIGHT,1,events)
	t.expect(target.body_functions.missing.right_hand,"injured natural limb can subsequently be lost")
	t.equal(b._state.body_changes.size(),2,"two distinct transitions recorded")
	var changes: Array[Dictionary]=b._state.body_changes.duplicate(true)
	target.body_functions=Sm2BodyFunctionState.decode(initial,target.body_catalog).state
	b._state.revision=1
	t.equal(Sm2BodyFunctionRules.restore_changes(changes,b._state),"","injury then sever receipt sequence reconstructs")
	t.expect(target.body_functions.missing.right_hand,"receipt reconstruction retains loss")
	Sm2BodyFunctionRules.after_hit(b._state,source,target,RIGHT,1,events)
	t.equal(b._state.body_changes.size(),2,"missing empty limb cannot be lost twice")
	b=BODY.fixture(c); target=b._state.actor(3); source=b._state.actor(1); events.clear()
	Sm2BodyFunctionRules.after_hit(b._state,source,target,RIGHT,0,events)
	t.expect(events.is_empty() and not target.body_functions.missing.right_hand,"zero HP loss cannot remove hand")
	target.spatial.alive=false
	Sm2BodyFunctionRules.after_hit(b._state,source,target,RIGHT,50,events)
	t.expect(events.is_empty(),"lethal damage does not apply survivor loss transition")
	# Real withdrawal reaction uses the same loss operation as a selected attack.
	var observed: bool=false
	for seed_value: int in range(1,35):
		b=BODY.fixture(loss_content(),seed_value)
		for i: int in 2: t.expect(b.execute(PARTY.cmd(b,"end_turn")).accepted,"reach departure reaction")
		var move: Sm2Command=PARTY.cmd(b,"move"); move.target=Vector2i(3,1)
		var result: Sm2CommandResult=b.execute(move)
		t.expect(result.accepted,"departure resolves")
		var reaction: bool=false; var loss: bool=false
		for event: Dictionary in result.events:
			reaction=reaction or event.type=="reaction_spent"; loss=loss or event.type=="body_part_lost"
		if reaction and loss: observed=true; break
	t.expect(observed,"real reaction can remove hand")
	# The common body query, rather than the interface, gates restored equipment.
	b=BODY.fixture(c); source=b._state.actor(1)
	source.body_functions.missing.right_hand=true; source.body_functions.working.right_hand=false
	var query: Sm2AiQueries=Sm2AiQueries.new(b._state,b._combat)
	t.expect(not query.attack(BODY.command(b,RIGHT),source.spatial.position).allowed,"AI cannot attack through missing hand")
	source.body_functions.prostheses.right_hand="99"; source.body_functions.working.right_hand=true
	t.expect(not query.attack(BODY.command(b,RIGHT),source.spatial.position).allowed,"AI projection remains detached")
	query=Sm2AiQueries.new(b._state,b._combat)
	t.expect(query.attack(BODY.command(b,RIGHT),source.spatial.position).allowed,"fresh AI projection uses restored hand")
	source.combat.items.erase("weapon"); source.combat.items.erase("shield")
	source.body_functions.working.left_hand=false
	t.expect(Sm2BodyCapabilityQuery.unarmed(source,b._combat),"working prosthesis can punch with free hand")
	source.body_functions.working.right_hand=false
	t.expect(not Sm2BodyCapabilityQuery.unarmed(source,b._combat),"damaged prosthesis cannot supply free-hand function")

static func _inventory_validation(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=make(); t.expect(s.new_game().ok,"inventory validation fixture starts")
	var before: String=s.state_hash()
	for defect: String in ["duplicate","foreign_owner","ordinary_id","missing_field","extra_field","orphan","wrong_condition"]:
		var world: Sm2JourneyWorld=s.journey().copy_world()
		match defect:
			"duplicate": world.prostheses.items[1].id=world.prostheses.items[0].id
			"foreign_owner": world.prostheses.items[0].owner_id="999"
			"ordinary_id": world.prostheses.items[0].id=world.items[0].id
			"missing_field": world.prostheses.items[0].erase("working")
			"extra_field": world.prostheses.items[0]["level"]=99
			"orphan":
				world.bodies[2].functions.missing.right_hand=true
				world.bodies[2].functions.prostheses.right_hand="999"
			"wrong_condition":
				world.bodies[2].functions.missing.right_hand=true
				world.bodies[2].functions.prostheses.right_hand=world.prostheses.items[0].id
				world.prostheses.items[0].owner_id="2"; world.prostheses.items[0].installed_part="right_hand"
				world.prostheses.items[0].working=false
		t.expect(not world.validate().is_empty(),"inventory invariant rejects "+defect)
		t.equal(s.state_hash(),before,"inventory candidate isolated")
