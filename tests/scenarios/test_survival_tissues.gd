extends RefCounted
const DEVICES=preload("res://tests/scenarios/test_survival_devices.gd")
const BODY=preload("res://tests/scenarios/test_p4_body.gd")
const MUSCLE: String="p5:upgrade.muscles"
const IMPLANT: String="p5:upgrade.psi_amplifier"

static func content(loss: bool=false) -> Dictionary:
	var c: Dictionary=Sm2SurvivalContentLoader.load_scenario(true,true)
	if loss and c.ok:
		var authored: Dictionary=DEVICES.loss_content()
		c.combat=authored.combat; c.development=authored.development; c.setup=authored.setup
		c.journey_fingerprint=Sm2Canonical.hash([c.journey_fingerprint,c.combat.to_data(),c.setup])
	return c

static func make(c: Dictionary={}) -> Sm2JourneySession:
	return Sm2JourneySession.new(content() if c.is_empty() else c,Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://tissues-tests"))

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=content()
	t.expect(c.ok,"layered content: "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("survival_tissues"); return
	_layers(t,c.survival.to_data()); _supplies(t); _battle(t)
	t.complete_suite("survival_tissues")

static func _layers(t: Sm2TestHarness,rules: Dictionary) -> void:
	var skin: Sm2Anatomy=Sm2Anatomy.fresh(rules)
	t.equal(skin.injure("right_hand",4,true,rules),"","superficial cut")
	t.equal(skin.layers.right_hand,{"skin":2,"muscle":15,"bone":9},"cut damages only skin")
	t.equal(skin.rate(),60,"skin bleeding coefficient")
	t.expect(skin.working("right_hand"),"skin cut preserves hand function")
	var blunt: Sm2Anatomy=Sm2Anatomy.fresh(rules)
	blunt.injure("right_hand",14,false,rules)
	t.equal(blunt.layers.right_hand,{"skin":6,"muscle":1,"bone":9},"blunt damage reaches muscles through skin")
	t.expect(not blunt.working("right_hand"),"muscle threshold loses function before zero part total")
	t.equal(blunt.rate(),0,"closed injury does not create external bleeding")
	var deep: Sm2Anatomy=Sm2Anatomy.fresh(rules)
	deep.injure("right_hand",24,true,rules)
	t.equal(deep.layers.right_hand,{"skin":0,"muscle":0,"bone":6},"deep cut reaches bone in authored order")
	t.equal(deep.rate(),555,"bleeding sums damaged tissue coefficients")
	var layers: Dictionary=deep.layers.duplicate(true)
	deep.advance(6,rules); var blood: int=deep.blood
	t.equal(deep.bandage("1"),"","bandage deep wound")
	t.equal(deep.layers,layers,"bandage does not regrow tissue")
	deep.advance(600,rules); t.equal(deep.blood,blood,"bandage stops subsequent loss")
	t.expect(not deep.working("right_hand"),"bandage does not restore muscle function")
	for body: Sm2Anatomy in [skin,blunt,deep]:
		var decoded: Dictionary=Sm2Anatomy.decode(JSON.parse_string(JSON.stringify(body.to_data())),rules)
		t.expect(decoded.ok,"layered anatomy JSON decode")
		if decoded.ok: t.equal(decoded.body.to_data(),body.to_data(),"exact tissue wounds blood roundtrip")
	for defect: String in ["projection","layer","loss","rate","cut","foreign","format"]:
		var raw: Dictionary=deep.to_data()
		match defect:
			"projection": raw.tissues.right_hand+=1
			"layer": raw.layers.right_hand.skin=1
			"loss": raw.wounds[0].layer_losses.bone=0
			"rate": raw.wounds[0].initial_rate=554
			"cut": raw.wounds[0].cut=false
			"foreign": raw.layers.right_hand["unknown"]=0
			"format": raw.format="sm2.anatomy.1"
		t.expect(not Sm2Anatomy.decode(raw,rules).ok,"reject forged tissue "+defect)
	var fresh: Sm2Anatomy=Sm2Anatomy.fresh(rules)
	fresh.injure("heart",20,false,rules)
	t.equal(fresh.cause(rules),"organ:heart","organ destruction kills at full blood")
	t.expect(Sm2Anatomy.decode(fresh.to_data(),rules).ok,"fatal organ wound persists")
	var legacy: Dictionary=Sm2SurvivalContentLoader.load_scenario(true).survival.to_data()
	t.expect(not Sm2Anatomy.decode(deep.to_data(),legacy).ok,"old profile refuses layered anatomy")
	t.expect(not Sm2Anatomy.decode(Sm2Anatomy.fresh(legacy).to_data(),rules).ok,"new profile refuses old anatomy")
	for defect: String in ["capacity","threshold","order","binding"]:
		var raw: Dictionary=rules.duplicate(true)
		match defect:
			"capacity": raw.tissue_layers.right_hand[0].capacity+=1
			"threshold": raw.tissue_layers.right_hand[1].function_min=999
			"order": raw.tissue_layers.right_hand[0].blunt_order=0
			"binding": raw.supplies.care.parts="unknown"
		t.expect(not Sm2SurvivalCatalog.new().build(raw).is_empty(),"reject layered content "+defect)

static func _supplies(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=make()
	var started: Dictionary=s.new_game(); t.expect(started.ok,"physical supply world: "+str(started.get("errors",[])))
	if not started.ok: return
	t.equal(s.format_id(),"sm2.survival_journey_session.3","explicit new session")
	t.equal(s.journey().care.supplies.parts,10,"one physical stock replaces both earlier parts pools")
	t.equal(Sm2PhysicalSupplies.matching(s.journey().survival,"medical_kit").size(),12,"medicine is twelve individual physical items")
	t.equal(Sm2PhysicalSupplies.matching(s.journey().survival,"repair_parts").size(),10,"physical parts match projection")
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"travel to genetic cache")
	t.equal(Sm2PhysicalSupplies.matching(s.journey().survival,"repair_parts",s.journey()).size(),0,"camp stock inaccessible in ruins")
	t.expect(s.act(s.command("collect_upgrade",0,MUSCLE)).ok,"collect physical genetic dose")
	var item: String=Sm2PhysicalSupplies.matching(s.journey().survival,"genetic_dose")[0]
	t.equal(s.journey().survival.inventory.items[item].place,"ground","find has explicit ground placement")
	var backpack: String=""
	for id: String in s.journey().survival.inventory.ids():
		if s.journey().survival.inventory.items[id].definition_id=="backpack" and s.journey().survival.inventory.owner(id)==2: backpack=id
	t.expect(s.act(s.command("travel",0,"camp")).ok,"leave dose behind")
	deny(t,s,s.command("apply_upgrade",2,MUSCLE),"remote dose cannot install")
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"return for same item")
	t.expect(s.act(s.command("store_item",int(backpack),item)).ok,"put dose in actual backpack")
	t.expect(s.act(s.command("travel",0,"camp")).ok,"carry dose to workshop")
	t.equal(s.journey().survival.inventory.location(item,s.journey().region.bodies),"camp","item follows equipped container")
	t.expect(s.act(s.command("apply_upgrade",2,MUSCLE)).ok,"consume actual local dose")
	t.expect(not s.journey().survival.inventory.items.has(item),"consumed exact physical ID")
	t.equal(s.journey().upgrade_supply.remaining[MUSCLE],0,"projection cannot spend again")
	deny(t,s,s.command("apply_upgrade",2,MUSCLE),"repeat installation")
	t.expect(s.act(s.command("travel",0,"enclave")).ok,"visit implant workshop")
	t.expect(s.act(s.command("collect_upgrade",0,IMPLANT)).ok,"collect actual implant kit")
	t.expect(s.act(s.command("apply_upgrade",2,IMPLANT)).ok,"install kit alongside genetics")
	t.equal(s.world.bodies[2].upgrades.installed.size(),2,"combined paths preserved")
	roundtrip(t,s)
	var raw: Dictionary=s.capture(); raw.world.care.supplies[0].amount+=1
	var before: String=s.state_hash()
	t.expect(not s.restore(raw).ok,"forged abstract counter rejected")
	t.equal(s.state_hash(),before,"bad restore atomic")

static func _battle(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=make(content(true)); t.expect(s.new_game().ok,"authored layered encounter")
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"reach battle")
	t.expect(s.act(s.command("start_battle")).ok,"start layered battle")
	if not s.world.busy(): return
	t.equal(s.runner._session._battle.capture().schema_version,21,"schema21")
	for index: int in 120:
		if not s.world.busy(): break
		var result: Dictionary=BODY.treatment_step(s)
		t.expect(result.ok,"actual attack or reaction accepted: "+str(result.get("errors",[])))
		if not result.ok: return
		if index==3: roundtrip(t,s)
	t.expect(not s.world.busy(),"real encounter settles")
	if s.world.busy(): return
	t.expect(s.world.hero_id()==2,"hero survives encounter")
	if s.world.hero_id()!=2: return
	t.expect(s.journey().survival.missing["2"].has("right_hand"),"real severing destroys all natural hand tissues")
	t.equal(s.journey().survival.bodies["2"].layers.right_hand,{"skin":0,"muscle":0,"bone":0},"severed tissue state")
	bandage_all(t,s)
	t.expect(s.act(s.command("explore",0,"first_aid")).ok,"search awards physical medicine")
	var found: Array[String]=Sm2PhysicalSupplies.matching(s.journey().survival,"medical_kit",s.journey())
	t.equal(found.size(),int(s.journey().exploration_catalog.site("first_aid").rewards.medicine),"search physical award equals content")
	for id: String in found: t.equal(s.journey().survival.inventory.items[id].holder,"ruins","search item stays at find location")
	deny(t,s,s.command("explore",0,"first_aid"),"cannot harvest twice")
	t.expect(s.act(s.command("travel",0,"camp")).ok,"bandaged party travels home")
	var device: String=s.journey().prostheses.items[0].id
	var anatomy: Dictionary=s.journey().survival.bodies["2"].to_data()
	t.expect(s.act(s.command("attach_device",2,device)).ok,"physical parts install compatible prosthesis")
	t.equal(s.journey().survival.bodies["2"].to_data(),anatomy,"device leaves layered anatomy unchanged")
	t.expect(s.world.bodies[2].functions.working.right_hand,"device restores projected function")
	t.equal(s.journey().care.supplies.parts,9,"physical procedure updates common projection")
	roundtrip(t,s)
	t.expect(s.act(s.command("end_life")).ok,"end layered incarnation after encounter")
	t.expect(s.act(s.command("incarnate",18)).ok,"fresh local human corpse")
	t.equal(s.journey().survival.bodies["18"].wounds.size(),0,"new body has no old wounds")
	t.equal(s.journey().survival.bodies["18"].layers.right_hand,{"skin":6,"muscle":15,"bone":9},"new body gets fresh layers")
	t.equal(s.journey().survival.inventory.items[device].holder,"2","device remains with old body")
	roundtrip(t,s)

static func bandage_all(t: Sm2TestHarness,s: Sm2JourneySession) -> void:
	for body_id: int in [s.world.hero_id(),4]:
		if body_id==0 or not s.world.bodies[body_id].alive: continue
		for wound: Dictionary in s.journey().survival.bodies[str(body_id)].wounds.duplicate(true):
			if int(wound.rate)>0: t.expect(s.act(s.command("bandage",body_id,wound.id)).ok,"bandage actual wound")

static func deny(t: Sm2TestHarness,s: Sm2JourneySession,cmd: Sm2WorldCommand,label: String) -> void:
	var before: String=s.state_hash(); t.expect(not s.act(cmd).ok,label); t.equal(s.state_hash(),before,label+" atomic")

static func roundtrip(t: Sm2TestHarness,s: Sm2JourneySession) -> void:
	var before: String=s.state_hash()
	t.expect(s.save_game().ok,"save physical layered state")
	var other: Sm2JourneySession=make(s._content)
	var loaded: Dictionary=other.load_game(); t.expect(loaded.ok,"load layered state: "+str(loaded.get("errors",[])))
	if loaded.ok: t.equal(other.state_hash(),before,"layered world battle RNG and history exact")
