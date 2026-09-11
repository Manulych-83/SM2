extends RefCounted
const OLD=preload("res://tests/scenarios/test_p4_exploration.gd")
const PROSTHESIS=preload("res://tests/scenarios/test_p4_prosthesis.gd")
const JOURNEY=preload("res://tests/scenarios/test_p4_journey.gd")
const SEARCH: String="p4s:skill.search"
const PERCEPTION: String="p4a:stat.perception"

static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2SearchContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)

static func fixture_content() -> Dictionary:
	var c: Dictionary=OLD.fixture_content(); var source: Dictionary=Sm2SearchContentLoader.load_scenario()
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	var errors: PackedStringArray=development.build(c.development.to_data(),source.development.progression(),c.combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	c.development=development; c.exploration=source.exploration
	c.journey_fingerprint=Sm2Canonical.hash([c.journey_fingerprint,development.fingerprint(),c.exploration.to_data()]); return c

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2SearchContentLoader.load_scenario()
	t.expect(c.ok,"search content validates "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("p4_search"); return
	var s: Sm2JourneySession=make(Sm2SaveStore.new("user://search-tests"))
	t.expect(s.new_game().ok,"search world starts")
	t.equal(s.format_id(),Sm2JourneySession.SEARCH_FORMAT,"new explicit format")
	t.equal(s.slot_name(),Sm2JourneySession.SEARCH_SLOT,"separate search slot")
	var original: Dictionary=s.world.bodies[2].progress.to_data(); var companion: Dictionary=s.world.bodies[4].to_data()
	var before: String=s.state_hash()
	for id: String in ["workshop","unknown"]: t.expect(not s.act(s.command("explore",0,id)).ok,"unavailable search "+id)
	t.equal(s.state_hash(),before,"invalid search no practice or loot")
	var stale: Sm2WorldCommand=s.command("explore",0,"first_aid")
	t.expect(s.act(s.command("explore",0,"first_aid")).ok,"real completed search")
	t.equal(s.world.bodies[2].progress.tracks[SEARCH].earned,50,"search own XP")
	t.equal(s.world.bodies[2].progress.tracks[PERCEPTION].earned,10,"perception own XP")
	for track: Dictionary in original.tracks:
		if track.track_id in [SEARCH,PERCEPTION]: continue
		t.equal(s.world.bodies[2].progress.tracks[track.track_id].earned,0,"no unrelated practice "+track.track_id)
	t.equal(s.world.bodies[4].to_data(),companion,"companion receives no hero search XP")
	t.equal(s.journey().care.supplies.medicine,16,"loot accompanies practice")
	t.equal(s.world.bodies[2].drills,0,"search is not a camp drill")
	before=s.state_hash()
	t.expect(not s.act(stale).ok and not s.act(s.command("explore",0,"first_aid")).ok,"stale and duplicate search rejected")
	t.equal(s.state_hash(),before,"duplicate has no reward time or history")
	t.expect(s.save_game().ok,"search practice saved")
	var restored: Sm2JourneySession=make(s._store)
	t.expect(restored.load_game().ok,"search practice loaded")
	t.equal(restored.state_hash(),before,"load exact with no extra XP")
	var bad: Dictionary=s.capture()
	for body: Dictionary in bad.world.bodies:
		if body.id!="2": continue
		for track: Dictionary in body.progress.tracks:
			if track.track_id==SEARCH: track.earned_total+=1
	t.expect(not s.restore(bad).ok,"forged XP inconsistent with history rejected")
	t.equal(s.state_hash(),before,"rejected load does not publish")
	t.expect(s.act(s.command("start_battle")).ok,"practice projects into actual battle")
	before=s.state_hash()
	t.expect(not s.act(s.command("explore",0,"workshop")).ok,"search blocked in battle")
	t.equal(s.state_hash(),before,"busy search does not touch battle RNG")
	t.expect(s.save_game().ok and restored.load_game().ok,"active battle with expanded tracks reloads")
	t.equal(restored.state_hash(),s.state_hash(),"active origin exact")
	t.equal(JOURNEY.advance(s),JOURNEY.advance(restored),"same next action after active load")
	t.equal(restored.state_hash(),s.state_hash(),"next battle state exact")
	_limits(t,c)
	_lives(t)
	t.complete_suite("p4_search")

static func _lives(t: Sm2TestHarness) -> void:
	var c: Dictionary=fixture_content(); t.expect(c.ok,"real injury fixture validates")
	var s: Sm2JourneySession=Sm2JourneySession.new(c,Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://search-lives"))
	t.expect(s.new_game().ok and s.act(s.command("explore",0,"first_aid")).ok,"practice before battle")
	t.expect(s.act(s.command("start_battle")).ok,"first real battle")
	PROSTHESIS.finish_retreat(s,t)
	if s.world.hero_id()!=2: t.expect(false,"hero survives fixture"); return
	t.equal(s.world.bodies[2].progress.tracks[SEARCH].earned,50,"battle does not train search")
	t.equal(s.world.bodies[2].progress.tracks[PERCEPTION].earned,10,"battle does not train perception")
	t.expect(s.act(s.command("heal_hp",2)).ok,"found medicine restores actual wound")
	t.equal(s.world.bodies[2].progress.tracks[SEARCH].earned,50,"healing does not train search")
	t.expect(s.act(s.command("explore",0,"workshop")).ok,"second search trains same body")
	var progress: Sm2ProgressCatalog=c.development.progression()
	t.equal(progress.track(SEARCH).describe(s.world.bodies[2].progress.tracks[SEARCH].earned).level,2,"100 earned automatically raises search level")
	t.equal(s.world.bodies[2].progress.tracks[SEARCH].spent,0,"automatic growth spends nothing")
	var old_body: Dictionary=s.world.bodies[2].progress.to_data()
	var companion: Dictionary=s.world.bodies[4].to_data(); var knowledge: Array=s.world.soul.knowledge.duplicate()
	t.expect(s.act(s.command("end_life")).ok,"old life ends")
	var before: String=s.state_hash()
	t.expect(not s.act(s.command("explore",0,"supply_cache")).ok,"soul alone cannot search")
	t.equal(s.state_hash(),before,"no body no XP")
	t.expect(s.act(s.command("incarnate",8)).ok,"clean body incarnation")
	t.equal(s.world.bodies[8].progress.tracks[SEARCH].earned,0,"new body search resets")
	t.equal(s.world.bodies[8].progress.tracks[PERCEPTION].earned,0,"new body perception resets")
	t.equal(s.world.bodies[2].progress.to_data(),old_body,"old body practice stays with old body")
	t.equal(s.world.bodies[4].to_data(),companion,"companion growth preserved")
	t.equal(s.world.soul.knowledge,knowledge,"soul knowledge preserved")
	t.expect(not s.act(s.command("explore",0,"first_aid")).ok,"new body cannot farm collected site")
	t.expect(s.act(s.command("start_battle")).ok,"new body participates in next encounter")
	PROSTHESIS.finish_retreat(s,t)
	if s.world.hero_id()!=8: t.expect(false,"new hero survives fixture"); return
	t.expect(s.act(s.command("explore",0,"supply_cache")).ok,"uncollected site trains new body")
	t.equal(s.world.bodies[8].progress.tracks[SEARCH].earned,50,"only own post-incarnation search XP")
	t.equal(s.world.bodies[8].progress.tracks[PERCEPTION].earned,10,"only own perception practice")
	t.equal(s.journey().exploration.minutes,180,"world time remains cumulative across lives")
	t.expect(s.save_game().ok,"cross-life practice saved")
	var restored: Sm2JourneySession=Sm2JourneySession.new(c,s._profile,s._store)
	t.expect(restored.load_game().ok,"cross-life practice history restored")
	t.equal(restored.state_hash(),s.state_hash(),"history assigns each search to correct incarnation")

static func _limits(t: Sm2TestHarness,c: Dictionary) -> void:
	var progress: Sm2ProgressCatalog=c.development.progression()
	for defect: String in ["unknown","zero","negative","fraction","overflow","empty","missing","old_version"]:
		var raw: Dictionary=c.exploration.to_data()
		match defect:
			"unknown": raw.sites[0].practice={"no:track":1}
			"zero": raw.sites[0].practice[SEARCH]=0
			"negative": raw.sites[0].practice[SEARCH]=-1
			"fraction": raw.sites[0].practice[SEARCH]=1.5
			"overflow": raw.sites[0].practice[SEARCH]=Sm2ProgressCatalog.XP_LIMIT+1
			"empty": raw.sites[0].practice={}
			"missing": raw.sites[0].erase("practice")
			"old_version": raw.version="sm2.exploration.content.1"
		t.expect(not Sm2ExplorationCatalog.new().build(raw,c.care,3,progress).is_empty(),"strict practice content "+defect)
	t.expect(not Sm2ExplorationCatalog.new().build(c.exploration.to_data(),c.care,3).is_empty(),"practice requires progression catalog")
	var s: Sm2JourneySession=make(); t.expect(s.new_game().ok,"limit fixture starts")
	var old: Sm2JourneySession=OLD.make(); t.expect(old.new_game().ok,"old exploration starts")
	t.expect(not s.restore(old.capture()).ok and not old.restore(s.capture()).ok,"old and new profiles cannot cross-load")
	t.expect(not old._content.development.progression().track_ids().has(SEARCH),"old catalog unchanged")
	var w: Sm2JourneyWorld=s.journey().copy_world()
	w.bodies[2].progress.tracks[PERCEPTION].earned=Sm2ProgressCatalog.XP_LIMIT-9
	var before: Dictionary=w.capture()
	t.expect(not w.check(s.command("explore",0,"first_aid")).is_empty(),"second award overflow refuses whole search")
	t.equal(w.capture(),before,"no partial search XP loot or time at cap")
	w.bodies[2].progress.tracks[PERCEPTION].earned=Sm2ProgressCatalog.XP_LIMIT-10
	t.equal(w.check(s.command("explore",0,"first_aid")),"","exact XP cap accepted")
	w.apply(s.command("explore",0,"first_aid"))
	t.equal(w.bodies[2].progress.tracks[PERCEPTION].earned,Sm2ProgressCatalog.XP_LIMIT,"exact XP cap applied")
	t.equal(s.world.bodies[2].progress.tracks[PERCEPTION].earned,0,"candidate practice detached")
	w=s.journey().copy_world(); w.care.supplies.medicine=29; before=w.capture()
	t.expect(not w.check(s.command("explore",0,"first_aid")).is_empty(),"loot capacity blocks practice too")
	t.equal(w.capture(),before,"full stash earns no practice")
	var changed: Dictionary=Sm2SearchContentLoader.load_scenario(); var raw: Dictionary=changed.exploration.to_data()
	raw.sites[0].practice[SEARCH]=51
	var catalog: Sm2ExplorationCatalog=Sm2ExplorationCatalog.new()
	t.expect(catalog.build(raw,c.care,3,progress).is_empty(),"alternative award validates")
	changed.exploration=catalog; changed.journey_fingerprint=Sm2Canonical.hash([changed.journey_fingerprint,raw])
	var other: Sm2JourneySession=Sm2JourneySession.new(changed,s._profile)
	t.expect(not other.restore(s.capture()).ok,"changed award cannot reinterpret history")
