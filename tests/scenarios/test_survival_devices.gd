extends RefCounted
const BODY=preload("res://tests/scenarios/test_p4_body.gd")
const SEVER: String="p4:ability.sever_right"

static func make(content: Dictionary={}) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2SurvivalContentLoader.load_scenario(true) if content.is_empty() else content,Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://survival_devices_tests"))

static func loss_content() -> Dictionary:
	var c: Dictionary=Sm2SurvivalContentLoader.load_scenario(true)
	if not c.ok: return c
	var raw: Dictionary=c.combat.to_data()
	for gear: Dictionary in raw.equipment:
		if gear.id=="m2:equipment.sword": gear.abilities=[SEVER]
	var combat: Sm2CombatCatalog=Sm2CombatCatalog.new(); combat.build(raw,c.catalog)
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	development.build(c.development.to_data(),c.development.progression(),combat)
	c.combat=combat; c.development=development
	c.setup.actors[1].q=0; c.setup.actors[1].r=3; c.setup.actors[2].q=2; c.setup.actors[2].r=1; c.setup.actors[3].q=2; c.setup.actors[3].r=2
	c.journey_fingerprint=Sm2Canonical.hash([c.journey_fingerprint,raw,c.setup]); return c

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=loss_content()
	t.expect(c.ok,"survival devices content: "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("survival_devices"); return
	var s: Sm2JourneySession=make(c)
	var started: Dictionary=s.new_game()
	t.expect(started.ok,"new devices world: "+str(started.get("errors",[])))
	if not started.ok: t.complete_suite("survival_devices"); return
	t.equal(s.format_id(),"sm2.survival_journey_session.2","new explicit session")
	_offscreen_death(t,s)
	var device: String=s.journey().prostheses.items[0].id
	var before: String=s.state_hash()
	t.expect(not s.act(s.command("attach_device",2,device)).ok,"healthy arm cannot be replaced")
	t.equal(s.state_hash(),before,"invalid operation atomic")
	t.expect(s.save_game().ok,"new world saves")
	var loaded: Sm2JourneySession=make(c)
	t.expect(loaded.load_game().ok,"new world loads")
	t.equal(loaded.state_hash(),s.state_hash(),"device world exact disk roundtrip")
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"travel to loss fight")
	started=s.act(s.command("start_battle"))
	t.expect(started.ok,"start schema20 fight: "+str(started.get("errors",[])))
	if not started.ok: t.complete_suite("survival_devices"); return
	t.equal(s.runner.capture().session.battle.schema_version,20,"schema20")
	for index: int in 120:
		if not s.world.busy(): break
		var step: Dictionary=BODY.treatment_step(s)
		t.expect(step.ok,"loss battle advances: "+str(step))
		if not step.ok: break
	t.expect(not s.world.busy(),"loss encounter settles")
	t.expect(s.world.hero_id()==2 and s.world.bodies[2].functions.missing.right_hand,"hero survives with lost hand")
	if s.world.hero_id()!=2 or not s.world.bodies[2].functions.missing.right_hand: t.complete_suite("survival_devices"); return
	for id: int in [2,4]:
		if not s.world.bodies[id].alive: continue
		for wound: Dictionary in s.journey().survival.bodies[str(id)].wounds:
			if int(wound.rate)>0: t.expect(s.act(s.command("bandage",id,wound.id)).ok,"stop bleeding before travel")
	t.expect(s.act(s.command("travel",0,"camp")).ok,"return to workshop")
	var hp: int=s.world.bodies[2].hp
	var blood: int=s.journey().survival.bodies["2"].blood
	var xp: Dictionary=s.world.bodies[2].progress.to_data()
	var installed: Dictionary=s.act(s.command("attach_device",2,device))
	t.expect(installed.ok,"attach physical device: "+str(installed.get("errors",[])))
	t.equal(s.journey().survival.inventory.items[device].place,"installed","same item installed")
	t.expect(s.world.bodies[2].functions.working.right_hand,"device restores function")
	t.equal(s.world.bodies[2].hp,hp,"installation does not heal tissue")
	t.equal(s.journey().survival.bodies["2"].blood,blood,"installation does not replenish blood")
	t.equal(s.world.bodies[2].progress.to_data(),xp,"installation grants no XP")
	t.expect(s.save_game().ok,"installed device saves")
	t.expect(loaded.load_game().ok,"installed device loads")
	t.equal(loaded.state_hash(),s.state_hash(),"installed state exact")
	t.expect(s.act(s.command("detach_device",0,device)).ok,"detach onto ground")
	t.equal(s.journey().survival.inventory.items[device].place,"ground","explicit ground placement")
	t.expect(not s.world.bodies[2].functions.working.right_hand,"detachment loses function")
	t.expect(s.act(s.command("attach_device",2,device)).ok,"same device reinstalled")
	_independence(t,s,device)
	var original: String=s.state_hash()
	for kind: String in ["attach_device","store_item","drop_item"]:
		t.expect(not s.act(s.command(kind,2 if kind!="drop_item" else 0,device)).ok,"installed device operation refused: "+kind)
		t.equal(s.state_hash(),original,"invalid installed action atomic")
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"return with artificial hand")
	t.expect(not s.act(s.command("detach_device",0,device)).ok,"workshop required")
	t.expect(s.act(s.command("start_battle")).ok,"device enters second battle")
	if not s.world.busy(): t.complete_suite("survival_devices"); return
	for kind: String in Sm2SurvivalDevices.COMMANDS:
		original=s.state_hash()
		t.expect(not s.act(s.command(kind,0,device)).ok,"device service forbidden during battle")
		t.equal(s.state_hash(),original,"forbidden service leaves battle and world unchanged")
	var wounded_before: Dictionary=s.runner._session._battle._state.survival.bodies["2"].to_data()
	for index: int in 120:
		if not s.world.busy(): break
		var step: Dictionary=BODY.treatment_step(s)
		t.expect(step.ok,"device fight advances")
		if not step.ok: break
	t.expect(not s.world.busy(),"device fight settles")
	t.equal(s.journey().survival.inventory.items[device].current,0,"real hit breaks mechanical hand")
	t.equal(s.journey().survival.bodies["2"].to_data(),wounded_before,"device hits neither injure tissue nor create bleeding")
	t.expect(not s.world.bodies[2].functions.working.right_hand,"broken device loses function")
	t.expect(s.save_game().ok and loaded.load_game().ok,"broken device disk roundtrip")
	t.equal(s.state_hash(),loaded.state_hash(),"broken device exact state")
	for id: int in [2,4]:
		if not s.world.bodies[id].alive: continue
		for wound: Dictionary in s.journey().survival.bodies[str(id)].wounds:
			if int(wound.rate)>0: t.expect(s.act(s.command("bandage",id,wound.id)).ok,"treat companion after second fight before long road")
	t.expect(s.act(s.command("travel",0,"camp")).ok,"broken device returns to workshop")
	t.equal(s.journey().region.location_id,"camp","treated party actually reaches workshop")
	t.expect(not s.act(s.command("attach_device",2,device)).ok,"cannot reinstall an attached broken device")
	var count: int=Sm2SurvivalDevices.materials(s.journey().survival,s.journey()).size()
	t.expect(s.act(s.command("repair_device",0,device)).ok,"physical repair restores installed device")
	t.equal(Sm2SurvivalDevices.materials(s.journey().survival,s.journey()).size(),count-1,"one repair part consumed")
	t.equal(s.journey().survival.inventory.items[device].current,30,"repair restores device integrity")
	t.expect(s.world.bodies[2].functions.working.right_hand,"repair restores hand function")
	t.equal(s.journey().survival.bodies["2"].to_data(),wounded_before,"repair does not heal stump")
	t.expect(not s.act(s.command("repair_device",0,device)).ok,"no repair of healthy device")
	t.expect(s.save_game().ok and loaded.load_game().ok,"repaired state saves")
	t.expect(s.act(s.command("end_life")).ok,"end prosthetic life")
	t.equal(s.journey().survival.inventory.items[device].holder,"2","device stays on previous body")
	t.expect(s.act(s.command("incarnate",18)).ok,"clean camp carrier")
	if s.world.hero_id()==0: t.complete_suite("survival_devices"); return
	t.expect(not s.world.bodies[s.world.hero_id()].functions.missing.right_hand,"new carrier has natural arm")
	t.expect(s.act(s.command("detach_device",0,device)).ok,"retrieve same device from corpse onto ground")
	t.equal(s.journey().survival.inventory.items[device].holder,"camp","recovered device explicit place")
	t.expect(not s.act(s.command("attach_device",s.world.hero_id(),device)).ok,"new healthy body cannot take device")
	t.expect(s.save_game().ok and loaded.load_game().ok,"corpse retrieval persists")
	t.equal(s.state_hash(),loaded.state_hash(),"new life and physical device exact")
	t.complete_suite("survival_devices")

static func _independence(t: Sm2TestHarness,s: Sm2JourneySession,device: String) -> void:
	# Explicit domain fixture: reopen the real severing wound only on a detached copy.
	var w: Sm2JourneyWorld=s.journey().copy_world()
	for wound: Dictionary in w.survival.bodies["2"].wounds: wound.rate=wound.initial_rate
	var blood: int=w.survival.bodies["2"].blood
	var rate: int=w.survival.bodies["2"].rate()
	var time: int=w.survival.seconds
	w.apply(s.command("detach_device",0,device))
	t.equal(w.survival.bodies["2"].rate(),rate,"detachment does not stop stump bleeding")
	var attach: Sm2WorldCommand=s.command("attach_device",2,device); attach.expected_revision=w.revision
	t.equal(w.check(attach),"","bleeding stump may accept matching device in fixture")
	w.apply(attach)
	t.expect(w.bodies[2].functions.working.right_hand,"device functions while stump bleeds")
	t.equal(w.survival.bodies["2"].rate(),rate,"attachment does not stop stump bleeding")
	t.equal(w.survival.seconds,time+40,"detach and attach take authored time")
	t.expect(w.survival.bodies["2"].blood<blood,"blood continues to leave during procedure")
	var no_parts: Sm2JourneyWorld=s.journey().copy_world()
	no_parts.survival.inventory.items[device].current=0; no_parts.survival.sync_world(no_parts)
	for id: String in no_parts.survival.inventory.ids():
		if no_parts.survival.inventory.items[id].definition_id=="repair_parts": no_parts.survival.inventory.items.erase(id)
	t.expect(not no_parts.check(s.command("repair_device",0,device)).is_empty(),"missing physical parts refuse repair")
	var invalid: Sm2SurvivalState=s.journey().survival.copy()
	invalid.inventory.items[device].slot="left_hand"
	t.expect(not Sm2SurvivalState.decode(invalid.to_data(),s.journey().survival).ok,"wrong attachment snapshot rejected")
	invalid=s.journey().survival.copy(); invalid.missing["2"].clear()
	t.expect(not Sm2SurvivalState.decode(invalid.to_data(),s.journey().survival).ok,"installed device requires missing biological part")
	invalid=s.journey().survival.copy(); invalid.inventory.items[device].current=31
	t.expect(not Sm2SurvivalState.decode(invalid.to_data(),s.journey().survival).ok,"device integrity cannot exceed definition")

static func _offscreen_death(t: Sm2TestHarness,s: Sm2JourneySession) -> void:
	var w: Sm2JourneyWorld=s.journey().copy_world()
	w.survival.bodies["10"].injure("right_hand",20,true,w.survival.catalog.to_data())
	w.survival.bodies["10"].blood=1501
	w.survival.sync_world(w)
	var before: int=w.survival.seconds
	w.apply(s.command("travel",0,"ruins"))
	t.equal(w.region.location_id,"ruins","offscreen enemy death does not interrupt party travel")
	t.equal(w.survival.seconds,before+1800,"full travel duration despite remote enemy death")
	t.expect(not w.bodies[10].alive,"remote enemy physiology still advances")
