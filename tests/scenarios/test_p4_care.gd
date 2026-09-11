extends RefCounted
const BODY=preload("res://tests/scenarios/test_p4_body.gd")
const PROSTHESIS=preload("res://tests/scenarios/test_p4_prosthesis.gd")

static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2CareContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)

static func fixture_content(sever: bool=false,limited: bool=false) -> Dictionary:
	var c: Dictionary=PROSTHESIS.loss_content() if sever else BODY.treatment_content()
	# Care always uses the prosthesis-capable body profile. Keep the aimed-only
	# diagnostic equipment when testing temporary trauma instead of loss.
	if not sever:
		c=Sm2CareContentLoader.load_scenario()
		var raw: Dictionary=c.combat.to_data()
		for gear: Dictionary in raw.equipment:
			if gear.id=="m2:equipment.sword": gear.abilities=[BODY.RIGHT]
		var combat: Sm2CombatCatalog=Sm2CombatCatalog.new(); combat.build(raw,c.catalog)
		var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new(); development.build(c.development.to_data(),c.development.progression(),combat)
		c.combat=combat; c.development=development
		c.setup.actors[2].q=2; c.setup.actors[2].r=1; c.setup.actors[3].q=2; c.setup.actors[3].r=3
	var care_raw: Dictionary=Sm2CareContentLoader.load_scenario().care.to_data()
	if limited: care_raw.resources[0].initial=1; care_raw.resources[1].initial=2
	var care: Sm2CareCatalog=Sm2CareCatalog.new(); care.build(care_raw); c["care"]=care
	c.journey_fingerprint=Sm2Canonical.hash([c.journey_fingerprint,c.combat.to_data(),c.setup,care.to_data()]); return c

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2CareContentLoader.load_scenario()
	t.expect(c.ok,"care content validates "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("p4_care"); return
	var s: Sm2JourneySession=make(); t.expect(s.new_game().ok,"care world starts")
	t.equal(s.format_id(),Sm2JourneySession.CARE_FORMAT,"separate care session")
	t.equal(s.journey().care.supplies.medicine,12,"prepared shared medicine")
	t.equal(s.journey().care.minutes,0,"no procedure time before action")
	var before: String=s.state_hash()
	t.expect(not s.act(s.command("heal_hp",2)).ok,"cannot treat full HP")
	t.expect(not s.act(s.command("heal_hp",3)).ok,"cannot treat enemy")
	t.expect(not s.act(s.command("heal_hp",8)).ok,"cannot treat corpse")
	t.equal(s.state_hash(),before,"invalid treatment no consumption")
	_healing(t)
	_devices(t,false)
	_devices(t,true)
	_limits(t,c)
	t.complete_suite("p4_care")

static func _healing(t: Sm2TestHarness) -> void:
	var c: Dictionary=fixture_content()
	var s: Sm2JourneySession=Sm2JourneySession.new(c,Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://care-tests"))
	t.expect(s.new_game().ok and s.act(s.command("start_battle")).ok,"care diagnostic injury encounter starts")
	t.equal(s.runner.capture().session.battle.schema_version,12,"camp extension preserves combat schema12")
	var before: String=s.state_hash()
	t.expect(not s.act(s.command("heal_hp",2)).ok,"HP treatment locked during encounter")
	t.equal(s.state_hash(),before,"busy treatment no resources or RNG change")
	for i: int in 3: t.expect(BODY.treatment_step(s).ok,"real damage advances")
	t.expect(s.save_game().ok,"care active battle saves")
	var loaded: Sm2JourneySession=Sm2JourneySession.new(c,s._profile,s._store)
	t.expect(loaded.load_game().ok,"care active battle loads")
	t.equal(s.state_hash(),loaded.state_hash(),"active state exact")
	t.equal(BODY.treatment_step(s),BODY.treatment_step(loaded),"same next action after load")
	PROSTHESIS.finish_retreat(s,t)
	t.expect(s.world.hero_id()==2 and s.world.bodies[2].hp==51,"actual enemy strike removed nine HP from surviving hero")
	if s.world.hero_id()!=2: return
	var body: Sm2WorldBody=s.world.bodies[2]
	var practice: Dictionary=body.progress.to_data()
	var stale: Sm2WorldCommand=s.command("heal_hand",2,"right_hand")
	t.expect(s.act(s.command("heal_hp",2)).ok,"treat actual HP loss")
	t.equal(s.world.bodies[2].hp,60,"treatment capped at body maximum")
	t.expect(not s.world.bodies[2].functions.working.right_hand,"HP healing does not heal functional trauma")
	t.equal(s.world.bodies[2].progress.to_data(),practice,"HP healing grants no practice")
	t.equal(s.journey().care.supplies.medicine,10,"one full procedure cost even near max HP")
	t.equal(s.journey().care.minutes,120,"procedure time counted once")
	before=s.state_hash()
	t.expect(not s.act(stale).ok,"stale procedure rejected")
	t.expect(not s.act(s.command("heal_hp",2)).ok,"repeat full HP treatment rejected")
	t.equal(s.state_hash(),before,"refused procedure preserves complete session")
	t.expect(s.act(s.command("heal_hand",2,"right_hand")).ok,"separate natural hand treatment")
	t.equal(s.journey().care.supplies.medicine,7,"hand treatment spends three medicine")
	t.equal(s.journey().care.minutes,360,"two procedure times accumulated")
	t.equal(s.world.bodies[2].hp,60,"functional healing does not add HP")
	t.expect(s.world.bodies[2].functions.working.right_hand,"natural hand works again")
	t.expect(s.save_game().ok and loaded.load_game().ok,"care operations round trip on disk")
	t.equal(s.state_hash(),loaded.state_hash(),"care history exact")
	before=s.state_hash()
	for defect: String in ["resources","time","hp","history","format","extra"]:
		var bad: Dictionary=s.capture()
		match defect:
			"resources": bad.world.care.supplies[0].amount+=1
			"time": bad.world.care.minutes=0
			"hp": bad.world.bodies[0].hp=59
			"history": bad.history.back().command.kind="heal_hp"
			"format": bad.format=Sm2JourneySession.PROSTHESIS_FORMAT
			"extra": bad.world.care["free"]=true
		t.expect(not s.restore(bad).ok,"care save forgery rejected "+defect)
		t.equal(s.state_hash(),before,"forged load atomic")
	var budget: Dictionary=s.journey().care.to_data()
	t.expect(s.act(s.command("end_life")).ok and s.act(s.command("incarnate",8)).ok,"new incarnation in same care world")
	t.equal(s.journey().care.to_data(),budget,"reincarnation neither refills nor spends supplies")
	t.expect(s.act(s.command("start_battle")).ok,"next encounter accepts healed/new origin")
	t.expect(s.save_game().ok and loaded.load_game().ok,"new incarnation active encounter care save")
	t.equal(s.journey().care.to_data(),budget,"battle start/load no implicit procedure")

static func _devices(t: Sm2TestHarness,limited: bool) -> void:
	var c: Dictionary=fixture_content(true,limited)
	var s: Sm2JourneySession=Sm2JourneySession.new(c,Sm2AiContentLoader.load_profile().profile)
	t.expect(s.new_game().ok and s.act(s.command("start_battle")).ok,"care prosthesis encounter starts")
	PROSTHESIS.finish_retreat(s,t)
	t.expect(s.world.hero_id()==2 and s.world.bodies[2].functions.missing.right_hand,"care hero has lost arm")
	if s.world.hero_id()!=2: return
	var device: String=s.journey().prostheses.items[0].id
	var alien: String=s.journey().prostheses.items[3].id
	var before: String=s.state_hash()
	t.expect(not s.act(s.command("install_prosthesis",2,alien)).ok,"incompatible item does not consume supplies")
	t.expect(not s.act(s.command("heal_hand",2,"right_hand")).ok,"cannot pay to regrow missing hand")
	t.equal(s.state_hash(),before,"invalid services no spending")
	t.expect(s.act(s.command("install_prosthesis",2,device)).ok,"pay for actual compatible installation")
	t.equal(s.journey().care.supplies.medicine,0 if limited else 11,"installation medicine debit")
	t.equal(s.journey().care.supplies.parts,0 if limited else 8,"installation parts debit")
	t.equal(s.journey().care.minutes,180,"installation elapsed time")
	t.expect(s.act(s.command("start_battle")).ok,"paid device enters next encounter")
	PROSTHESIS.finish_retreat(s,t)
	t.expect(s.world.hero_id()==2 and not s.journey().prostheses.item(device).working,"real encounter damages paid device")
	if s.world.hero_id()!=2: return
	if limited:
		before=s.state_hash()
		t.expect(not s.act(s.command("repair_prosthesis",0,device)).ok,"no parts refuses real repair")
		t.expect(not s.act(s.command("heal_hp",2)).ok,"no medicine refuses real wound treatment")
		t.equal(s.state_hash(),before,"insufficient supplies leave HP item time history intact")
	else:
		var hp: int=s.world.bodies[2].hp
		var practice: Dictionary=s.world.bodies[2].progress.to_data()
		t.expect(s.act(s.command("repair_prosthesis",0,device)).ok,"paid repair restores actual damaged device")
		t.equal(s.journey().care.supplies.parts,6,"repair parts debit")
		t.equal(s.journey().care.minutes,300,"repair time added")
		t.equal(s.world.bodies[2].hp,hp,"repair does not heal body")
		t.equal(s.world.bodies[2].progress.to_data(),practice,"repair does not grant practice")
		t.expect(s.act(s.command("heal_hp",2)).ok,"restore wounded body separately from device")
		t.equal(s.world.bodies[2].hp,mini(60,hp+20),"partial wound recovery is exactly up to twenty")
	var budget: Dictionary=s.journey().care.supplies.duplicate()
	var minutes: int=s.journey().care.minutes
	t.expect(s.act(s.command("remove_prosthesis",0,device)).ok,"removal needs time but no supplies")
	t.equal(s.journey().care.supplies,budget,"removal does not require unavailable resources")
	t.equal(s.journey().care.minutes,minutes+30,"removal time counted")
	t.expect(s.act(s.command("transfer_prosthesis",6,device)).ok,"transfer removed item to stash")
	t.equal(s.journey().care.minutes,minutes+30,"ordinary transfer is not a medical procedure")
	var copy: Sm2JourneySession=Sm2JourneySession.new(c,s._profile)
	t.expect(copy.restore(s.capture()).ok,"paid installation repair/removal history restores")
	t.equal(copy.state_hash(),s.state_hash(),"all costs reconstruct exactly once")

static func _limits(t: Sm2TestHarness,c: Dictionary) -> void:
	for defect: String in ["duplicate","unknown_cost","fraction","negative","missing_service","wrong_heal"]:
		var data: Dictionary=c.care.to_data()
		match defect:
			"duplicate": data.resources[1].id=data.resources[0].id
			"unknown_cost": data.services[0].cost={"unknown":1}
			"fraction": data.services[0].minutes=0.5
			"negative": data.services[0].cost.medicine=-1
			"missing_service": data.services.pop_back()
			"wrong_heal": data.services[1].heal_hp=10
		t.expect(not Sm2CareCatalog.new().build(data).is_empty(),"invalid service data rejected "+defect)
	var s: Sm2JourneySession=make(); t.expect(s.new_game().ok,"care boundaries fixture")
	var old: Sm2JourneySession=PROSTHESIS.make(); t.expect(old.new_game().ok,"old prosthesis profile")
	t.expect(not s.restore(old.capture()).ok and not old.restore(s.capture()).ok,"new camp format isolated from old free procedures")
	var world: Sm2JourneyWorld=s.journey().copy_world(); world.bodies[2].hp=40
	world.care.minutes=Sm2CareCatalog.TIME_LIMIT-119
	t.expect(not world.check(s.command("heal_hp",2)).is_empty(),"elapsed limit checked before operation")
	world.care.minutes=Sm2CareCatalog.TIME_LIMIT-120
	t.equal(world.check(s.command("heal_hp",2)),"","exact remaining time allowed")
	world.apply(s.command("heal_hp",2))
	t.equal(world.care.minutes,Sm2CareCatalog.TIME_LIMIT,"time ceiling exact")
	t.equal(world.bodies[2].hp,60,"time boundary valid procedure applies")
	t.equal(s.world.bodies[2].hp,60,"candidate does not mutate original")
	t.equal(s.journey().care.minutes,0,"candidate clock detached")
	world.care.supplies.medicine=-1
	t.expect(not world.validate().is_empty(),"negative supplies rejected by world invariant")
	world=s.journey().copy_world(); world.bodies[4].hp=39
	var companion: Dictionary=world.bodies[4].progress.to_data()
	t.equal(world.check(s.command("heal_hp",4)),"","living wounded companion can receive treatment")
	world.apply(s.command("heal_hp",4))
	t.equal(world.bodies[4].hp,59,"companion receives twenty HP")
	t.equal(world.bodies[4].progress.to_data(),companion,"companion treatment gives no overall XP")
	t.equal(world.care.supplies.medicine,10,"companion consumes the same shared medicine")
	world.bodies[4].alive=false; world.bodies[4].hp=0
	t.expect(not world.check(s.command("heal_hp",4)).is_empty(),"dead companion cannot be resurrected by treatment")
	world=s.journey().copy_world(); world.bodies[2].hp=35
	world.care.supplies.medicine=1
	var before: Dictionary=world.capture()
	t.expect(not world.check(s.command("heal_hp",2)).is_empty(),"one medicine is insufficient for two-unit procedure")
	t.equal(world.capture(),before,"read-only affordability does not partially spend")
	var changed: Dictionary=Sm2CareContentLoader.load_scenario()
	var costs: Dictionary=changed.care.to_data(); costs.services[0].minutes=60
	var new_catalog: Sm2CareCatalog=Sm2CareCatalog.new(); t.expect(new_catalog.build(costs).is_empty(),"different authored service price valid")
	changed.care=new_catalog; changed.journey_fingerprint=Sm2Canonical.hash([changed.journey_fingerprint,costs])
	var other: Sm2JourneySession=Sm2JourneySession.new(changed,s._profile)
	t.expect(not other.restore(s.capture()).ok,"changed price fingerprint cannot reinterpret old history")
