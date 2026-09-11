extends RefCounted
const JOURNEY=preload("res://tests/scenarios/test_p4_journey.gd")
const HYBRID=preload("res://tests/scenarios/test_p5_hybrids.gd")

static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2RegionContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)
static func move(s: Sm2JourneySession,id: String) -> Dictionary: return s.act(s.command("travel",0,id))
static func deny(t: Sm2TestHarness,s: Sm2JourneySession,command: Sm2WorldCommand,label: String) -> void:
	var before: String=s.state_hash(); t.expect(not s.act(command).ok,label); t.equal(s.state_hash(),before,label+" atomic")
static func roundtrip(t: Sm2TestHarness,s: Sm2JourneySession) -> void:
	var other: Sm2JourneySession=make(); t.expect(other.restore(JSON.parse_string(JSON.stringify(s.capture()))).ok,"region JSON restore")
	t.equal(other.state_hash(),s.state_hash(),"world history location clock battle exact")

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2RegionContentLoader.load_scenario(); t.expect(c.ok,"region content loads "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("p6_region"); return
	_catalog(t,c); _world(t); _life(t); _compatibility(t)
	t.complete_suite("p6_region")

static func _catalog(t: Sm2TestHarness,c: Dictionary) -> void:
	var valid: Dictionary=c.region.to_data(); var catalog: Sm2RegionCatalog=Sm2RegionCatalog.new()
	t.expect(catalog.build(valid,c).is_empty(),"map catalog valid")
	for key: String in ["bodies","sites","services","encounters","upgrades"]:
		var bad: Dictionary=valid.duplicate(true); bad[key].pop_back()
		t.expect(not catalog.build(bad,c).is_empty(),"reject incomplete "+key)
	for kind: String in ["unknown_place","self","negative","float","duplicate","unreachable","wrong_enemy"]:
		var bad: Dictionary=valid.duplicate(true)
		match kind:
			"unknown_place": bad.routes[0].to="void"
			"self": bad.routes[0].to=bad.routes[0].from
			"negative": bad.routes[0].seconds=-1
			"float": bad.routes[0].seconds=0.5
			"duplicate": bad.routes.append(bad.routes[0].duplicate(true))
			"unreachable": bad.routes=[]
			"wrong_enemy": bad.bodies[4].location="camp"
		t.expect(not catalog.build(bad,c).is_empty(),"reject map "+kind)
	t.equal(catalog.to_data(),valid,"failed build preserves catalog")
	var detached: Dictionary=catalog.to_data(); detached.locations[0].name="changed"
	t.equal(catalog.location("camp").name,"Лагерь","catalog read detached")

static func _world(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=make(Sm2SaveStore.new("user://region_test")); t.expect(s.new_game().ok,"new map")
	t.equal(s.journey().region.location_id,"camp","start camp"); t.equal(s.journey().region.seconds,0,"initial clock zero")
	deny(t,s,s.command("start_battle"),"no battle remotely")
	deny(t,s,s.command("explore",0,"first_aid"),"no remote search")
	deny(t,s,s.command("collect_upgrade",0,"p5:upgrade.psi_amplifier"),"no remote kit")
	deny(t,s,s.command("travel",0,"camp"),"no self route"); deny(t,s,s.command("travel",0,"void"),"no unknown route")
	var stale: Sm2WorldCommand=s.command("travel",0,"ruins")
	t.expect(s.act(s.command("practice",2,"p5:activity.psionics")).ok,"camp psi exercise")
	var practice_time: int=s._content.development.progression().activity("p5:activity.psionics").seconds
	t.equal(s.journey().region.seconds,practice_time,"exercise time from catalog")
	deny(t,s,stale,"stale travel")
	t.expect(s.act(s.command("deposit")).ok,"stone in camp stash")
	var equipment: Dictionary=s.journey().equipment(2)[0]
	t.expect(s.act(s.command("transfer",6,equipment.id)).ok,"gear stored in camp")
	t.expect(move(s,"ruins").ok,"walk ruins")
	t.equal(s.journey().region.seconds,practice_time+1800,"travel time exact")
	t.equal(s.journey().region.bodies["4"],"ruins","living companion travels")
	deny(t,s,s.command("take"),"no remote stone")
	deny(t,s,s.command("transfer",2,equipment.id),"no remote stash gear")
	deny(t,s,s.command("practice",2,"p5:activity.psionics"),"training requires camp")
	t.expect(s.act(s.command("explore",0,"first_aid")).ok,"local exploration")
	t.equal(s.journey().region.seconds,practice_time+3600,"exploration time exactly once")
	t.expect(s.act(s.command("collect_upgrade",0,"p5:upgrade.muscles")).ok,"local genetics kit")
	t.expect(move(s,"enclave").ok,"walk enclave")
	t.expect(s.act(s.command("collect_upgrade",0,"p5:upgrade.psi_amplifier")).ok,"local cyber kit")
	t.expect(s.act(s.command("apply_upgrade",2,"p5:upgrade.psi_amplifier")).ok,"local implant operation")
	deny(t,s,s.command("apply_upgrade",2,"p5:upgrade.muscles"),"genetics requires camp")
	t.expect(move(s,"camp").ok,"return camp")
	t.expect(s.act(s.command("apply_upgrade",2,"p5:upgrade.muscles")).ok,"combined paths retained")
	t.expect(s.act(s.command("transfer",2,equipment.id)).ok,"recover camp gear")
	t.expect(s.act(s.command("equip",0,equipment.id)).ok,"equip recovered gear")
	t.expect(s.act(s.command("take")).ok,"recover stone")
	t.expect(s.save_game().ok,"map save"); roundtrip(t,s)
	var hash_before: String=s.state_hash(); t.expect(move(s,"ruins").ok,"unsaved move"); t.expect(s.load_game().ok,"map load")
	t.equal(s.state_hash(),hash_before,"save restores former location and time")
	for field: String in ["seconds","location_id","visited","bodies"]:
		var bad: Dictionary=s.capture()
		match field:
			"seconds": bad.world.region.seconds+=1
			"location_id": bad.world.region.location_id="ruins"
			"visited": bad.world.region.visited=["camp"]
			"bodies": bad.world.region.bodies["2"]="ruins"
		t.expect(not s.restore(bad).ok,"reject forged map "+field); t.equal(s.state_hash(),hash_before,"failed restore atomic")
	var detached: Dictionary=s.view(); detached.region.bodies["2"]="void"
	t.equal(s.journey().region.bodies["2"],"camp","map view detached")
	var limit: Sm2JourneySession=make(); limit.new_game(); limit.journey().region.seconds=Sm2RegionCatalog.TIME_LIMIT
	deny(t,limit,limit.command("travel",0,"ruins"),"time overflow rollback")

static func _life(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=make(); t.expect(s.new_game().ok,"life map")
	t.expect(move(s,"enclave").ok,"visit enclave before battle")
	t.expect(s.act(s.command("collect_upgrade",0,"p5:upgrade.psi_amplifier")).ok,"prepare stronger hero")
	t.expect(s.act(s.command("apply_upgrade",2,"p5:upgrade.psi_amplifier")).ok,"install hero implant")
	t.expect(move(s,"ruins").ok,"travel to encounter")
	t.expect(s.act(s.command("explore",0,"first_aid")).ok,"persistent discovery")
	t.expect(s.act(s.command("start_battle")).ok,"local battle starts")
	deny(t,s,s.command("travel",0,"camp"),"cannot leave active battle")
	roundtrip(t,s)
	var time: int=s.journey().region.seconds
	JOURNEY.finish(s,t)
	t.equal(s.journey().region.seconds,time,"battle has no invented calendar duration")
	if s.world.hero_id()!=0: t.expect(s.act(s.command("end_life")).ok,"end hero life in ruins")
	t.equal(s.world.hero_id(),0,"soul unembodied")
	deny(t,s,s.command("travel",0,"camp"),"soul remains at death place")
	deny(t,s,s.command("incarnate",18),"no remote incarnation")
	var companion: Dictionary=s.world.bodies[4].to_data()
	var gear: Array[Dictionary]=s.journey().items.duplicate(true)
	var progress: Array[String]=s.world.soul.knowledge.duplicate()
	t.expect(s.act(s.command("incarnate",8)).ok,"local clean human embodiment")
	t.equal(s.journey().region.seconds,time,"embodiment instant")
	t.equal(s.world.bodies[4].to_data(),companion,"companion state preserved")
	t.equal(s.journey().items,gear,"items stay with owners")
	t.equal(s.world.soul.knowledge,progress,"Soul knowledge persists")
	t.expect(s.world.bodies[8].upgrades.installed.is_empty(),"new body no upgrades")
	t.equal(s.journey().region.bodies["2"],"ruins","old corpse local")
	t.expect(move(s,"camp").ok,"new body can travel")
	t.equal(s.journey().region.bodies["2"],"ruins","corpse does not follow")
	t.equal(s.journey().region.bodies["4"],"camp" if s.world.bodies[4].alive else "ruins","only living companion follows")
	var old_item: Dictionary={}
	for row: Dictionary in gear:
		if row.owner_id=="2": old_item=row; break
	deny(t,s,s.command("transfer",8,old_item.id),"no remote corpse loot")
	roundtrip(t,s)
	t.expect(move(s,"ruins").ok,"return for belongings")
	t.expect(s.act(s.command("transfer",8,old_item.id)).ok,"recover local corpse item")
	deny(t,s,s.command("explore",0,"first_aid"),"discovery not replenished after embodiment")
	t.expect(s.act(s.command("start_battle")).ok,"second encounter with new body")
	roundtrip(t,s)

static func _compatibility(t: Sm2TestHarness) -> void:
	var old: Sm2JourneySession=HYBRID.make(); old.new_game()
	var map: Sm2JourneySession=make(); map.new_game()
	t.expect(not map.restore(old.capture()).ok,"no silent old save migration")
	t.expect(not old.restore(map.capture()).ok,"old profile rejects map")
	t.expect(old.act(old.command("start_battle")).ok,"legacy single place encounter unchanged")
	var restored: Sm2JourneySession=HYBRID.make(); t.expect(restored.restore(old.capture()).ok,"legacy active battle restores")
	t.equal(restored.state_hash(),old.state_hash(),"legacy identical state")
