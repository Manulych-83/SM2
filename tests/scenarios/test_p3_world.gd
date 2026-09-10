extends RefCounted
const NODE: String="p1:node.strength_1"
const STRENGTH: String="p1:stat.strength"

static func make(seed_value: int=20260910, store: Sm2SaveStore=null) -> Sm2LifeSession:
	var content: Dictionary=Sm2LifeContentLoader.load_scenario()
	content.setup.seed=seed_value
	return Sm2LifeSession.new(content,Sm2AiContentLoader.load_profile().profile,store)

static func advance(session: Sm2LifeSession) -> Dictionary:
	var state: Dictionary=session.runner.view()
	var active: Dictionary={}
	for actor: Dictionary in state.actors:
		if actor.actor_id==state.active_actor_id: active=actor
	if active.get("controller")=="player" and active.get("morale")!="fleeing":
		var decision: Dictionary=session.runner._session.ai_decision(session._profile)
		if not decision.ok: return decision
		var result: Sm2CommandResult=session.attack(decision.command)
		return {"ok":result.accepted,"code":result.code,"events":result.events}
	return session.step()

static func run(t: Sm2TestHarness) -> void:
	var extension_source: Dictionary={}
	for seed_value: int in [20260910,1,76]:
		var store: Sm2SaveStore=Sm2SaveStore.new("user://p3-tests/%s" % seed_value)
		var s: Sm2LifeSession=make(seed_value,store)
		var started: Dictionary=s.new_game(); t.expect(started.ok,"P3 world initializes: "+str(started))
		if not started.ok: t.complete_suite("p3_world"); return
		var before: String=s.state_hash()
		var stale: Sm2WorldCommand=s.command("deposit")
		stale.world_id="foreign"; t.expect(not s.act(stale).ok,"foreign world rejected"); t.equal(s.state_hash(),before,"foreign command inert")
		stale=s.command("deposit"); t.expect(s.act(stale).ok,"unique item moves to stash")
		before=s.state_hash(); t.expect(not s.act(stale).ok,"duplicate command rejected"); t.equal(s.state_hash(),before,"duplicate item transfer inert")
		t.equal(s.world.item_owner,6,"stash is sole owner")
		t.expect(s.act(s.command("start_battle")).ok,"world starts authored encounter")
		before=s.state_hash(); t.expect(not s.act(s.command("practice",2)).ok,"no outside practice during encounter"); t.equal(s.state_hash(),before,"locked body inert")
		var count: int=0
		while not s.runner.view().finished and count<200:
			var advanced: Dictionary=advance(s); t.expect(advanced.ok,"real world battle step: "+str(advanced.get("code",advanced.get("reason",""))))
			if not advanced.ok: break
			count+=1
			if count==10:
				t.expect(s.save_game().ok,"mid-battle whole-world disk save")
				var other: Sm2LifeSession=make(seed_value,store)
				t.expect(other.load_game().ok,"mid-battle world disk reload")
				t.equal(other.state_hash(),s.state_hash(),"world plus binding plus battle round trip")
				var a: Dictionary=advance(s); var b: Dictionary=advance(other)
				t.equal(a,b,"same next battle result after reload"); t.equal(s.state_hash(),other.state_hash(),"same next world state")
		t.expect(s.runner.view().finished,"real encounter finishes")
		if not s.runner.view().finished: t.complete_suite("p3_world"); return
		t.expect(not s.world.receipt.is_empty(),"outcome receipt stored atomically")
		var receipt: String=s.world.receipt
		before=s.state_hash(); t.expect(s.step().ok,"repeated terminal step accepted without reward"); t.equal(s.state_hash(),before,"terminal retry does not reapply result")
		var companion: Dictionary=s.world.bodies[4].to_data()
		t.equal(s.world.bodies[2].alive,seed_value!=1,"oracle hero survival")
		t.equal(s.world.bodies[4].alive,seed_value==20260910,"oracle companion survival")
		var knowledge: Array[String]=s.world.soul.knowledge.duplicate()
		if s.world.hero_id()!=0:
			for index: int in 4: t.expect(s.act(s.command("practice",2)).ok,"old hero trains in world")
			t.expect(s.act(s.command("buy_node",2,NODE)).ok,"old hero buys actual node")
			t.expect(s.act(s.command("end_life")).ok,"controlled death closes incarnation")
		var old_body: Dictionary=s.world.bodies[2].to_data()
		t.equal(s.world.hero_id(),0,"Soul has no carrier")
		t.expect(s.save_game().ok,"save between lives")
		t.expect(s.load_game().ok,"reload between lives stays disembodied")
		before=s.state_hash(); t.expect(not s.act(s.command("incarnate",9)).ok,"enhanced corpse rejected"); t.equal(s.state_hash(),before,"enhanced rejection preserves IDs and all state")
		t.expect(not s.act(s.command("incarnate",2)).ok,"own former body unavailable")
		var embody: Sm2WorldCommand=s.command("incarnate",8)
		t.expect(s.act(embody).ok,"prepared pure human embodied")
		t.equal([s.world.hero_id(),s.world.soul.incarnation_id,s.world.next_id],[8,13,14],"new distinct incarnation uses existing corpse identity")
		for value: Sm2ProgressTrackState in s.world.bodies[8].progress.tracks.values():
			t.equal([value.earned,value.spent,value.nodes],[0,0,[]],"new body has no inherited practice or nodes")
		t.equal(s.world.bodies[2].to_data(),old_body,"former body and its practice remain")
		t.equal(s.world.bodies[4].to_data(),companion,"companion unchanged across death and embodiment")
		t.equal(s.world.soul.knowledge,knowledge,"Soul knowledge persists")
		t.equal(s.world.item_owner,6,"same item stays in same stash")
		t.equal(s.world.receipt,receipt,"battle consequence persists through life change")
		before=s.state_hash(); t.expect(not s.act(embody).ok,"duplicate incarnation rejected"); t.equal(s.state_hash(),before,"no duplicate resurrection or ID")
		t.expect(s.act(s.command("take")).ok,"new body retrieves existing item")
		t.equal(s.capture().world.item,{"id":"7","definition_id":"p3:item.memory_stone","owner_id":"8"},"identity preserved, owner changed")
		t.expect(s.act(s.command("practice",8)).ok,"new body can develop again")
		t.equal(s.world.bodies[8].progress.tracks[STRENGTH].earned,30,"fresh body earns only its own first practice")
		t.expect(s.save_game().ok,"save after new embodiment")
		t.expect(s.load_game().ok,"load after new embodiment")
		t.equal(s.world.item_owner,8,"load does not copy item into stash")
		var valid: Dictionary=s.capture(); before=s.state_hash()
		for mutation: String in ["receipt","soul","item","body_id","xp","incarnation","allocator","binding","duplicate","version","living_donor"]:
			var bad: Dictionary=valid.duplicate(true)
			match mutation:
				"receipt": bad.world.receipt="wrong"
				"soul": bad.world.soul.incarnation_id="3"
				"item": bad.world.item.owner_id="999"
				"body_id": bad.world.bodies[2].progress.id="2"
				"xp": bad.world.bodies[2].progress.tracks[0].earned_total+=1
				"incarnation": bad.world.incarnations[0].ended=false
				"allocator": bad.world.next_id="13"
				"binding": bad.world.binding[0].body_id="8"
				"duplicate": bad.world.bodies.append(bad.world.bodies[0].duplicate(true))
				"version": bad.format="sm2.development_run.1"
				"living_donor": bad.world.bodies[3].alive=true; bad.world.bodies[3].hp=60
			t.expect(not s.restore(bad).ok,"reject corrupt world "+mutation); t.equal(s.state_hash(),before,"corrupt restore inert "+mutation)
		var saved_view: Dictionary=s.view(); saved_view.bodies[0].tracks.clear()
		t.equal(s.state_hash(),before,"read model detached")
		t.expect(s.act(s.command("end_life")).ok,"second life can end without resetting place")
		t.equal(s.world.item_owner,8,"carried item stays at its dead body")
		t.expect(not s.act(s.command("incarnate",8)).ok,"used carrier not reusable")
		t.expect(s.save_game().ok,"terminal fixture world remains saveable")
		if seed_value==20260910: extension_source=s.capture()
	var extended_content: Dictionary=Sm2LifeContentLoader.load_scenario()
	var raw_definition: Dictionary=extended_content.world_definition.to_data()
	var definition: Sm2LifeDefinition=Sm2LifeDefinition.new()
	for bad_id: int in [2,7,12]:
		var bad: Dictionary=raw_definition.duplicate(true); bad.bodies.append({"id":bad_id,"name":"duplicate","human":true,"enhanced":false,"prepared":true,"alive":false})
		t.expect(not definition.build(bad).is_empty(),"definition rejects reserved/duplicate body ID")
	raw_definition.bodies.append({"id":15,"name":"Ещё один носитель","human":true,"enhanced":false,"prepared":true,"alive":false})
	t.expect(definition.build(raw_definition).is_empty(),"another carrier can be authored as data")
	extended_content.world_definition=definition
	var extension: Sm2LifeSession=Sm2LifeSession.new(extended_content,Sm2AiContentLoader.load_profile().profile)
	t.expect(extension.new_game().ok,"extended world initializes without code change")
	t.expect(not extension.restore(extension_source).ok,"changed content cannot silently migrate old save")
	t.expect(extension.act(extension.command("start_battle")).ok,"extended world starts encounter")
	for index: int in 200:
		if extension.runner.view().finished: break
		var advanced: Dictionary=advance(extension)
		if not advanced.ok: t.expect(false,"extended battle command accepted"); break
	if extension.world.hero_id()!=0: t.expect(extension.act(extension.command("end_life")).ok,"first extended life ends")
	t.expect(extension.act(extension.command("incarnate",8)).ok,"first alternate carrier")
	t.expect(extension.act(extension.command("end_life")).ok,"second extended life ends")
	t.expect(extension.act(extension.command("incarnate",15)).ok,"third life uses data-added carrier")
	t.equal([extension.world.hero_id(),extension.world.next_id,extension.world.incarnations.size()],[15,18,3],"allocator avoids authored entity IDs")
	t.expect(extension.act(extension.command("take")).ok,"third carrier retrieves relic left on original corpse")
	t.equal(extension.world.item_owner,15,"corpse-to-body transfer preserves one item")
	t.complete_suite("p3_world")
