extends RefCounted
const FIXTURE=preload("res://tests/scenarios/test_survival_tissues.gd")
const JOURNEY=preload("res://tests/scenarios/test_p4_journey.gd")
const SHIELD=preload("res://tests/scenarios/test_p5_shield.gd")

static func container(s: Sm2JourneySession, definition: String, owner: int=0) -> String:
	var inv: Sm2PhysicalInventory=s.journey().survival.inventory
	for id: String in inv.ids():
		if inv.items[id].definition_id==definition and inv.owner(id)==owner: return id
	return ""

static func retreat(s: Sm2JourneySession,t: Sm2TestHarness) -> void:
	for i: int in 150:
		if not s.world.busy(): return
		var view: Dictionary=s.runner.view(); var player: bool=false
		for actor: Dictionary in view.actors:
			if int(actor.actor_id)!=int(view.active_actor_id) or actor.controller!="player" or actor.morale=="fleeing": continue
			player=true
			var command: Sm2Command=Sm2Command.new(); command.actor_id=int(actor.actor_id); command.expected_revision=int(view.revision); command.battle_id=view.battle_id
			command.kind="escape" if int(actor.q)==0 else "move"; command.target=Vector2i(0,int(actor.r))
			if not s.runner.preview(command).allowed: command.kind="end_turn"
			t.expect(s.attack(command).accepted,"real retreat command accepted")
		if not player: t.expect(s.step().ok,"real enemy step during retreat")
	t.expect(false,"retreat bounded")

static func finish_supplies(s: Sm2JourneySession,t: Sm2TestHarness) -> Array:
	t.expect(s.act(s.command("explore",0,"first_aid")).ok,"explore actual finite source")
	var v: Dictionary=Sm2ExpeditionView.new().build(s)
	t.expect(v.ok and v.ids.size()==4,"exact four source item identities")
	var ids: Array=v.ids.duplicate()
	var pack: String=container(s,"backpack",s.world.hero_id())
	for id: String in ids: t.expect(s.act(s.command("store_item",int(pack),id)).ok,"pick up actual source medicine")
	t.expect(s.act(s.command("travel",0,"camp")).ok,"return living body to camp")
	return ids

static func run(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=FIXTURE.make(); t.expect(s.new_game().ok,"production outing starts")
	var query: Sm2ExpeditionView=Sm2ExpeditionView.new()
	var before: String=s.state_hash(); var initial: Dictionary=s.capture()
	var v: Dictionary=query.build(s)
	if not v.ok:
		print("BRIEF_DIAGNOSTIC "+JSON.stringify(Sm2ExpeditionBrief.load_for(s.journey())))
		var copy: Sm2JourneySession=FIXTURE.make(); copy.world.start(s.world.world_id)
		print("WORLD_DIAGNOSTIC "+str(Sm2Canonical.hash(copy.world.capture())==Sm2Canonical.hash(s.world.capture())))
		t.expect(false,"objective projection failed"); t.complete_suite("expedition"); return
	t.expect(v.ok and not v.complete and v.stage=="prepare","initial objective")
	t.equal(s.state_hash(),before,"reading objective cannot award or mutate")
	t.equal(v.deposited,0,"twelve starter medicines do not count")
	v.steps.clear(); t.equal(query.build(s).steps.size(),3,"cache returns detached data")
	var bad: Dictionary=Sm2ExpeditionBrief.load_for(s.journey()); bad.quantity=3
	t.expect(not Sm2ExpeditionBrief.valid(bad,s.journey()),"brief count must match actual source")
	bad=Sm2ExpeditionBrief.load_for(s.journey()); bad.site="unknown"
	t.expect(not Sm2ExpeditionBrief.valid(bad,s.journey()),"brief validates referenced site")
	# Deliver the real supplies early: the first encounter still remains mandatory.
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"early search route")
	var ids: Array=finish_supplies(s,t)
	var stash: String=container(s,"stash")
	for id: String in ids: t.expect(s.act(s.command("store_item",int(stash),id)).ok,"deposit early source medicine")
	v=query.build(s); t.expect(not v.complete and v.deposited==4 and not v.encounter_done,"delivery alone cannot finish encounter objective")
	t.expect(s.restore(initial).ok,"reset isolated test through validated restore")
	SHIELD.learn(s,t)
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"production route")
	t.expect(s.act(s.command("start_battle")).ok,"production first encounter")
	before=s.state_hash(); v=query.build(s)
	t.expect(v.ok and v.stage=="battle" and not v.encounter_done,"active battle not falsely completed")
	t.equal(s.state_hash(),before,"active battle not advanced by objective")
	retreat(s,t)
	t.expect(not s.world.busy() and s.world.hero_id()!=0,"real retreat leaves hero available")
	FIXTURE.bandage_all(t,s)
	ids=finish_supplies(s,t); stash=container(s,"stash")
	v=query.build(s); t.expect(not v.complete and v.encounter_done,"carrying at camp is not delivery")
	for i: int in 3: t.expect(s.act(s.command("store_item",int(stash),ids[i])).ok,"partial delivery")
	v=query.build(s); t.expect(not v.complete and v.deposited==3,"partial delivery stays incomplete")
	t.expect(s.save_game().ok,"save partial progress in existing campaign format")
	var checkpoint: Dictionary=s.capture()
	t.expect(s.load_game().ok,"restore partial route")
	t.equal(query.build(s),v,"saved objective reconstructs exactly")
	var final_command: Sm2WorldCommand=s.command("store_item",int(stash),ids[3])
	t.expect(s.act(final_command).ok,"last source medicine deposited")
	v=query.build(s); t.expect(v.ok and v.complete,"actual whole episode completed")
	t.equal(v.summary.battle.title,"Отряд отступил","retreat never represented as victory")
	t.equal(v.summary.items,ids,"report records unique delivered IDs")
	t.expect(v.summary.practice.size()>0,"report includes earned preparation/search practice")
	var summary: Dictionary=v.summary.duplicate(true)
	before=s.state_hash(); t.expect(not s.act(final_command).ok,"stale delivery rejected")
	t.equal(s.state_hash(),before,"stale delivery awards nothing")
	for i: int in 3: t.equal(query.build(s).summary,summary,"repeated result never re-awards")
	t.equal(s.state_hash(),before,"report reading is strictly read only")
	t.expect(s.save_game().ok and s.load_game().ok,"completed route survives disk roundtrip")
	t.equal(query.build(s).summary,summary,"result remains frozen after save/load")
	# Later use/transfer and reincarnation do not revoke a recorded accomplishment.
	var pack: String=container(s,"backpack",s.world.hero_id())
	t.expect(s.act(s.command("store_item",int(pack),ids[0])).ok,"retrieve delivered supply afterwards")
	t.expect(s.act(s.command("end_life")).ok,"later incarnation change")
	t.expect(s.act(s.command("incarnate",18)).ok,"new ordinary body")
	t.equal(query.build(s).summary,summary,"historical result survives item moves and new body")
	t.expect(s.restore(checkpoint).ok,"load earlier checkpoint")
	t.expect(not query.build(s).complete,"cache cannot leak completion into earlier save")
	t.expect(s.act(s.command("end_life")).ok,"death during partial objective")
	t.expect(query.build(s).stage=="soul" and query.build(s).deposited==3,"partial progress survives body death")
	t.expect(s.act(s.command("incarnate",18)).ok,"new life continues partial objective")
	t.expect(s.act(s.command("store_item",int(stash),ids[3])).ok,"recover last medicine from previous corpse into stash")
	t.expect(query.build(s).complete and query.build(s).summary.incarnation==2,"second life can finish same objective")
	# Independent ordinary combat uses the actual authored AI decisions for both sides.
	var combat: Sm2JourneySession=FIXTURE.make(); t.expect(combat.new_game().ok,"ordinary combat world")
	SHIELD.learn(combat,t); t.expect(combat.act(combat.command("travel",0,"ruins")).ok,"ordinary journey")
	t.expect(combat.act(combat.command("start_battle")).ok,"ordinary encounter starts")
	JOURNEY.finish(combat,t)
	var report: Dictionary=Sm2BattleResultsView.build(combat)
	t.expect(not report.is_empty(),"ordinary encounter has a real report")
	print("EXPEDITION_ORDINARY_COMBAT "+JSON.stringify({"outcome":report.get("title"),"hero":combat.world.hero_id(),"party":report.get("party")}))
	t.expect(report.title=="Победа отряда" and combat.world.hero_id()!=0,"authored first encounter has a surviving winning route")
	FIXTURE.bandage_all(t,combat)
	var won_ids: Array=finish_supplies(combat,t)
	var won_stash: String=container(combat,"stash")
	for id: String in won_ids: t.expect(combat.act(combat.command("store_item",int(won_stash),id)).ok,"winning route deposits supplies")
	var won: Dictionary=Sm2ExpeditionView.new().build(combat)
	t.expect(won.ok and won.complete and won.summary.battle.title=="Победа отряда","complete real winning episode")
	t.complete_suite("expedition")
