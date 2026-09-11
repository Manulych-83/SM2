extends RefCounted
const CARE=preload("res://tests/scenarios/test_p4_care.gd")
const PROSTHESIS=preload("res://tests/scenarios/test_p4_prosthesis.gd")
const BODY=preload("res://tests/scenarios/test_p4_body.gd")

static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2ExplorationContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)

static func fixture_content() -> Dictionary:
	var c: Dictionary=CARE.fixture_content()
	var source: Dictionary=Sm2ExplorationContentLoader.load_scenario()
	var raw: Dictionary=source.care.to_data()
	for resource: Dictionary in raw.resources: resource.initial=0
	var care: Sm2CareCatalog=Sm2CareCatalog.new(); care.build(raw)
	c.care=care; c["exploration"]=source.exploration
	c.journey_fingerprint=Sm2Canonical.hash([c.journey_fingerprint,care.to_data(),source.exploration.to_data()]); return c

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2ExplorationContentLoader.load_scenario()
	t.expect(c.ok,"exploration content validates "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("p4_exploration"); return
	var s: Sm2JourneySession=make(Sm2SaveStore.new("user://exploration-tests"))
	t.expect(s.new_game().ok,"exploration world starts")
	t.equal(s.format_id(),Sm2JourneySession.EXPLORATION_FORMAT,"explicit exploration format")
	var before: String=s.state_hash()
	t.expect(not s.act(s.command("explore",0,"workshop")).ok,"later site unavailable before first encounter")
	t.expect(not s.act(s.command("explore",0,"unknown")).ok,"unknown site refused")
	t.expect(not s.act(s.command("explore",4,"first_aid")).ok,"ambiguous target refused")
	t.equal(s.state_hash(),before,"invalid search atomic")
	var stale: Sm2WorldCommand=s.command("explore",0,"first_aid")
	var practice: Dictionary=s.world.bodies[2].progress.to_data()
	t.expect(s.act(s.command("explore",0,"first_aid")).ok,"first site collected")
	t.equal(s.journey().care.supplies.medicine,16,"loot may raise supplies above initial amount")
	t.equal(s.journey().exploration.minutes,30,"search time recorded")
	t.equal(s.journey().care.minutes,0,"search is not a medical procedure")
	t.equal(s.world.bodies[2].progress.to_data(),practice,"prepared search adds no undefined practice")
	before=s.state_hash()
	t.expect(not s.act(stale).ok,"stale search refused")
	t.expect(not s.act(s.command("explore",0,"first_aid")).ok,"fresh repeated search refused")
	t.equal(s.state_hash(),before,"site cannot produce duplicate loot or time")
	t.expect(s.save_game().ok,"collected site saved")
	var loaded: Sm2JourneySession=make(s._store)
	t.expect(loaded.load_game().ok,"collected site loaded")
	t.equal(s.state_hash(),loaded.state_hash(),"site save exact")
	t.expect(not loaded.act(loaded.command("explore",0,"first_aid")).ok,"load cannot refill collected site")
	t.expect(s.act(s.command("start_battle")).ok,"collected supplies enter encounter")
	before=s.state_hash()
	t.expect(not s.act(s.command("explore",0,"workshop")).ok,"search blocked during battle")
	t.equal(s.state_hash(),before,"busy search leaves RNG history and supplies intact")
	t.expect(s.save_game().ok and loaded.load_game().ok,"active exploration world save")
	t.equal(s.state_hash(),loaded.state_hash(),"active load exact")
	var journey: GDScript=load("res://tests/scenarios/test_p4_journey.gd")
	t.equal(journey.advance(s),journey.advance(loaded),"same following command after active load")
	_world(t)
	_limits(t,c)
	t.complete_suite("p4_exploration")

static func _world(t: Sm2TestHarness) -> void:
	var c: Dictionary=fixture_content()
	var s: Sm2JourneySession=Sm2JourneySession.new(c,Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://exploration-flow"))
	t.expect(s.new_game().ok and s.act(s.command("start_battle")).ok,"zero-supply real-injury fixture starts")
	PROSTHESIS.finish_retreat(s,t)
	t.expect(s.world.hero_id()==2 and s.world.bodies[2].hp==51,"actual HP loss before gathering")
	if s.world.hero_id()!=2: return
	t.expect(not s.act(s.command("heal_hp",2)).ok,"no medicine before search")
	t.expect(s.act(s.command("explore",0,"first_aid")).ok,"gather medicine from available point")
	t.expect(s.act(s.command("heal_hp",2)).ok,"gathered medicine pays real healing")
	t.equal(s.world.bodies[2].hp,60,"new medicine restores real lost HP")
	t.equal(s.journey().care.supplies.medicine,2,"healing consumes collected medicine")
	t.expect(s.act(s.command("explore",0,"workshop")).ok,"completed encounter unlocks workshop")
	t.equal(s.journey().care.supplies.parts,4,"workshop adds parts")
	t.expect(not s.act(s.command("explore",0,"supply_cache")).ok,"second threshold still locked")
	t.expect(s.act(s.command("start_battle")).ok,"next encounter with gathered resources")
	PROSTHESIS.finish_retreat(s,t)
	t.expect(s.act(s.command("explore",0,"supply_cache")).ok,"second encounter opens mixed supply cache")
	t.equal(s.journey().care.supplies.medicine,5,"mixed medicine award")
	t.equal(s.journey().care.supplies.parts,6,"mixed parts award")
	t.equal(s.journey().exploration.minutes,180,"all search durations summed once")
	t.expect(s.save_game().ok,"gather/spend history saves")
	var other: Sm2JourneySession=Sm2JourneySession.new(c,s._profile,s._store)
	t.expect(other.load_game().ok,"gather/spend history loads")
	t.equal(s.state_hash(),other.state_hash(),"gathered and consumed resources reconstruct")
	var before: String=s.state_hash()
	for defect: String in ["duplicate","empty","time","supply","history","format"]:
		var bad: Dictionary=s.capture()
		match defect:
			"duplicate": bad.world.exploration.collected.append("first_aid")
			"empty": bad.world.exploration.collected.clear()
			"time": bad.world.exploration.minutes=0
			"supply": bad.world.care.supplies[0].amount+=1
			"history": bad.history.back().command.content_id="first_aid"
			"format": bad.format=Sm2JourneySession.CARE_FORMAT
		t.expect(not s.restore(bad).ok,"exploration tamper refused "+defect)
		t.equal(s.state_hash(),before,"invalid load remains atomic")
	var resources: Dictionary=s.journey().care.to_data(); var sites: Dictionary=s.journey().exploration.to_data()
	var companion: Dictionary=s.world.bodies[4].to_data()
	t.expect(s.act(s.command("end_life")).ok,"end incarnation after collecting")
	t.expect(not s.act(s.command("explore",0,"first_aid")).ok,"unembodied Soul cannot search")
	t.expect(s.act(s.command("incarnate",8)).ok,"fresh incarnation")
	t.equal(s.journey().care.to_data(),resources,"incarnation no resource refill")
	t.equal(s.journey().exploration.to_data(),sites,"incarnation no site refill")
	t.equal(s.world.bodies[4].to_data(),companion,"search/life change preserves companion")
	t.expect(not s.act(s.command("explore",0,"first_aid")).ok,"new body cannot collect old site")
	t.expect(s.save_game().ok and other.load_game().ok,"new incarnation searched-world save")
	t.equal(s.state_hash(),other.state_hash(),"new incarnation exact")

static func _limits(t: Sm2TestHarness,c: Dictionary) -> void:
	for defect: String in ["duplicate","unknown","negative","fraction","threshold","invalid_id","over_capacity"]:
		var raw: Dictionary=c.exploration.to_data()
		match defect:
			"duplicate": raw.sites[1].id=raw.sites[0].id
			"unknown": raw.sites[0].rewards={"unobtainium":1}
			"negative": raw.sites[0].rewards.medicine=-1
			"fraction": raw.sites[0].minutes=1.5
			"threshold": raw.sites[0].after_encounters=100
			"invalid_id": raw.sites[0].id="invalid/site"
			"over_capacity": raw.sites[0].rewards.medicine=31
		t.expect(not Sm2ExplorationCatalog.new().build(raw,c.care,3).is_empty(),"invalid site data "+defect)
	var old: Sm2JourneySession=CARE.make(); t.expect(old.new_game().ok,"old care mode starts")
	var current: Sm2JourneySession=make(); t.expect(current.new_game().ok,"new exploration mode starts")
	t.expect(not old.restore(current.capture()).ok and not current.restore(old.capture()).ok,"old/new worlds do not cross load")
	var care_raw: Dictionary=c.care.to_data(); care_raw.version="sm2.care.content.1"
	t.expect(not Sm2CareCatalog.new().build(care_raw).is_empty(),"old resource definition rejects new capacity field")
	var world: Sm2JourneyWorld=current.journey().copy_world()
	world.care.supplies.medicine=29
	var before: Dictionary=world.capture()
	t.expect(not world.check(current.command("explore",0,"first_aid")).is_empty(),"overflow refuses whole site")
	t.equal(world.capture(),before,"overflow does not partially claim or add loot")
	world.care.supplies.medicine=26
	t.equal(world.check(current.command("explore",0,"first_aid")),"","exact capacity allowed")
	world.apply(current.command("explore",0,"first_aid"))
	t.equal(world.care.supplies.medicine,30,"exact capacity published on candidate")
	t.equal(current.journey().care.supplies.medicine,12,"candidate supplies detached")
	t.expect(current.journey().exploration.collected.is_empty(),"candidate sites detached")
	world.exploration.collected.append("first_aid")
	t.expect(not world.validate().is_empty(),"world invariant catches duplicate site")
	world=current.journey().copy_world(); world.exploration.minutes=Sm2ExplorationCatalog.TIME_LIMIT-29
	t.expect(not world.check(current.command("explore",0,"first_aid")).is_empty(),"search time overflow refused")
	world=current.journey().copy_world(); world.exploration.collected=["workshop"]; world.exploration.minutes=60
	t.expect(not world.validate().is_empty(),"world invariant catches prematurely collected site")
	world=current.journey().copy_world(); world.completed=2; world.care.supplies.medicine=20; world.care.supplies.parts=29
	before=world.capture()
	t.expect(not world.check(current.command("explore",0,"supply_cache")).is_empty(),"mixed reward overflow refuses entire collection")
	t.equal(world.capture(),before,"no partial medicine reward when parts overflow")
	world.care.supplies.parts=28
	t.equal(world.check(current.command("explore",0,"supply_cache")),"","mixed exact capacity allowed")
	world.apply(current.command("explore",0,"supply_cache"))
	t.equal(world.care.supplies.medicine,23,"mixed medicine award on candidate")
	t.equal(world.care.supplies.parts,30,"mixed parts at exact capacity")
	care_raw=c.care.to_data(); care_raw.resources[0].capacity=11
	t.expect(not Sm2CareCatalog.new().build(care_raw).is_empty(),"capacity below initial amount rejected")
	var changed: Dictionary=Sm2ExplorationContentLoader.load_scenario()
	var sites: Dictionary=changed.exploration.to_data(); sites.sites[0].rewards.medicine=5
	var definition: Sm2ExplorationCatalog=Sm2ExplorationCatalog.new(); t.expect(definition.build(sites,changed.care,3).is_empty(),"different authored reward validates")
	changed.exploration=definition; changed.journey_fingerprint=Sm2Canonical.hash([changed.journey_fingerprint,sites])
	var alternate: Sm2JourneySession=Sm2JourneySession.new(changed,current._profile)
	t.expect(not alternate.restore(current.capture()).ok,"changed reward fingerprint cannot reinterpret old collection")
