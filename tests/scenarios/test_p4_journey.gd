extends RefCounted
const STRENGTH: String="p1:stat.strength"
const MELEE: String="p1:skill.melee"

static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2JourneyContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)

static func advance(s: Sm2JourneySession) -> Dictionary:
	var v: Dictionary=s.runner.view()
	for actor: Dictionary in v.actors:
		if actor.actor_id==v.active_actor_id and actor.controller=="player" and actor.morale!="fleeing":
			var decision: Dictionary=s.runner._session.ai_decision(s._profile)
			if not decision.ok: return decision
			var result: Sm2CommandResult=s.attack(decision.command)
			return {"ok":result.accepted,"code":result.code,"events":result.events}
	return s.step()

static func finish(s: Sm2JourneySession,t: Sm2TestHarness) -> void:
	for index: int in 300:
		if not s.world.busy(): return
		var result: Dictionary=advance(s)
		t.expect(result.ok,"P4 battle command accepted: "+str(result.get("code",result.get("reason",""))))
		if not result.ok: return
	t.expect(false,"P4 battle must finish within diagnostic budget")

static func run(t: Sm2TestHarness) -> void:
	var content: Dictionary=Sm2JourneyContentLoader.load_scenario()
	t.expect(content.ok,"P4 content validates: "+str(content.get("errors",[])))
	if not content.ok: t.complete_suite("p4_journey"); return
	var store: Sm2SaveStore=Sm2SaveStore.new("user://p4-tests")
	var s: Sm2JourneySession=make(store)
	var started: Dictionary=s.new_game()
	t.expect(started.ok,"P4 world initializes: "+str(started))
	if not started.ok: t.complete_suite("p4_journey"); return
	var sword: String=s.journey().equipment(2)[0].id
	var count: int=s.journey().items.size()
	var initial: Dictionary=s.capture()
	var stale: Sm2WorldCommand=s.command("transfer",6,sword)
	t.expect(s.act(stale).ok,"equipped sword transfers to stash")
	t.equal(s.journey().item(sword).owner_id,"6","stash owns same instance")
	t.equal(s.journey().item(sword).equipped,false,"transfer removes equipment")
	var before: String=s.state_hash()
	t.expect(not s.act(stale).ok,"duplicate transfer rejected"); t.equal(s.state_hash(),before,"duplicate transfer is inert")
	t.expect(s.act(s.command("transfer",4,sword)).ok,"companion receives same sword")
	t.expect(not s.act(s.command("equip",0,sword)).ok,"occupied weapon slot rejects second weapon")
	t.expect(s.act(s.command("transfer",2,sword)).ok,"hero retrieves sword")
	t.expect(s.act(s.command("equip",0,sword)).ok,"hero equips retrieved sword")
	t.equal(s.journey().items.size(),count,"transfers create no copies")
	t.expect(s.restore(initial).ok,"test restores initial fixture")
	t.expect(s.act(s.command("start_battle")).ok,"first encounter starts")
	t.equal(s.runner.capture().session.battle.schema_version,9,"new explicit battle schema")
	before=s.state_hash()
	for kind: String in ["equip","unequip","transfer","deposit","take","end_life","practice"]:
		t.expect(not s.act(s.command(kind,6,sword)).ok,"outside action locked during battle: "+kind)
		t.equal(s.state_hash(),before,"locked action preserves world/RNG/IDs")
	for index: int in 7:
		var result: Dictionary=advance(s); t.expect(result.ok,"first encounter advances")
	t.expect(s.save_game().ok,"mid-encounter save")
	var loaded: Sm2JourneySession=make(store)
	var load_result: Dictionary=loaded.load_game()
	t.expect(load_result.ok,"mid-encounter disk reload: "+str(load_result))
	if not load_result.ok: t.complete_suite("p4_journey"); return
	t.equal(loaded.state_hash(),s.state_hash(),"whole snapshot round trip")
	t.equal(advance(loaded),advance(s),"identical next command after load")
	t.equal(loaded.state_hash(),s.state_hash(),"identical resulting world after load")
	finish(s,t)
	t.equal(s.journey().completed,1,"first encounter settled once")
	if s.world.busy(): t.complete_suite("p4_journey"); return
	var after_first: Dictionary=s.capture()
	var xp: int=s.world.bodies[2].progress.tracks[STRENGTH].earned
	t.expect(xp>0,"first encounter earns body-specific practice")
	var damaged: bool=false
	for item: Dictionary in s.journey().items:
		if int(item.owner_id) in [2,4] and item.slot!="weapon" and int(item.current)<content.combat.gear(item.definition_id).capacity: damaged=true
	t.expect(damaged,"real fight changes persistent armor condition")
	before=s.state_hash()
	t.expect(s.restore(s.capture()).ok,"post-outcome load")
	t.equal(s.state_hash(),before,"loading does not settle outcome twice")
	t.equal(s.world.bodies[2].progress.tracks[STRENGTH].earned,xp,"loading grants no additional experience")
	if s.world.hero_id()==0: t.expect(s.act(s.command("incarnate",8)).ok,"dead first hero may reincarnate")
	var hero_id: int=s.world.hero_id()
	if hero_id==2:
		for index: int in 4: t.expect(s.act(s.command("practice",2)).ok,"camp practice on surviving body")
		t.expect(s.act(s.command("buy_node",2,"p1:node.strength_1")).ok,"buy node between encounters")
	var origin: Dictionary=s.journey().origin()
	t.expect(s.act(s.command("start_battle")).ok,"second distinct encounter starts")
	t.equal(s.runner.capture().session.battle.development.origin,origin,"second encounter keeps exact incoming baseline")
	t.equal(s.runner.capture().session.battle.development.members[0].body,origin.members[0].body,"XP and nodes carried unchanged at start")
	for index: int in 2:
		var actor: Dictionary=s.runner.capture().session.battle.actors[index]
		t.equal(actor.combat.hp,origin.actors[index].hp,"no free healing at encounter entry")
		for item_index: int in actor.combat.items.size():
			t.equal(actor.combat.items[item_index].current,origin.actors[index].items[item_index].current,"no free armor repair")
	for index: int in 6:
		var result: Dictionary=advance(s); t.expect(result.ok,"developed body fights in next encounter")
	before=s.state_hash()
	var corrupt: Dictionary=s.capture(); corrupt.active.session.battle.development.members[0].body.tracks[0].earned_total+=1
	t.expect(not s.restore(corrupt).ok,"fabricated practice rejected")
	t.equal(s.state_hash(),before,"bad practice load is atomic")
	corrupt=s.capture(); corrupt.world.items[0].owner_id="999"
	t.expect(not s.restore(corrupt).ok,"unknown item owner rejected"); t.equal(s.state_hash(),before,"bad item load is atomic")
	corrupt=s.capture(); corrupt.active.session.battle.development.origin.incarnation_id="999"
	t.expect(not s.restore(corrupt).ok,"foreign incarnation origin rejected")
	t.equal(s.state_hash(),before,"bad origin load is atomic")
	finish(s,t)
	t.equal(s.journey().completed,2,"second encounter settled")
	# New incarnation starts without gear; fists are an intrinsic ability, not an item.
	t.expect(s.restore(after_first).ok,"restore first-outcome branch for reincarnation scenario")
	if s.world.hero_id()!=0: t.expect(s.act(s.command("end_life")).ok,"old body ends life outside combat")
	var companion: Dictionary=s.world.bodies[4].to_data()
	var old_items: Array[Dictionary]=s.journey().equipment(2)
	t.expect(s.act(s.command("incarnate",8)).ok,"prepared pure human becomes new incarnation")
	t.equal(s.journey().equipment(8).size(),0,"new body has no fabricated equipment")
	t.equal(s.world.bodies[8].progress.tracks[STRENGTH].earned,0,"new body starts at zero practice")
	t.equal(s.world.bodies[4].to_data(),companion,"companion life and development unchanged")
	t.equal(s.journey().equipment(2),old_items,"old equipment remains with old body")
	var before_bare: Dictionary=s.capture()
	t.expect(s.act(s.command("start_battle")).ok,"new incarnation enters next encounter")
	var actor: Dictionary=s.runner.view().actors[0]
	t.expect(Sm2BattleText.item(actor,"weapon").is_empty(),"bare hands have no fake item")
	var decoded: Dictionary=Sm2DevelopmentSnapshot.decode(s.runner.capture().session.battle,s._encounter.catalog,s._encounter.combat,null,null,s._encounter.development,s._encounter.origin)
	t.expect(decoded.ok,"unarmed snapshot decodes")
	if decoded.ok: t.expect(Sm2AttackResolver.available_abilities(decoded.state.actor(1),s._encounter.combat).has("p4:ability.punch"),"shared ability query offers punch")
	finish(s,t)
	t.expect(s.world.bodies[8].progress.tracks[STRENGTH].earned>0,"punches grant strength practice")
	t.expect(s.world.bodies[8].progress.tracks[MELEE].earned>0,"punches grant melee practice")
	t.equal(s.world.bodies[8].progress.tracks["p1:skill.psionics"].earned,0,"punches grant no psionic practice")
	t.expect(s.restore(before_bare).ok,"restore before second-incarnation encounter")
	t.expect(s.act(s.command("transfer",8,sword)).ok,"new body retrieves old unique sword")
	t.expect(s.act(s.command("equip",0,sword)).ok,"new body equips recovered sword")
	t.equal(s.journey().item(sword).owner_id,"8","recovered item owner is new body")
	t.equal(s.journey().items.size(),count,"reincarnation and looting create no gear copies")
	t.expect(s.save_game().ok,"save recovered equipment")
	t.expect(loaded.load_game().ok,"reload recovered equipment")
	t.equal(loaded.state_hash(),s.state_hash(),"reincarnation plus inventory disk round trip")
	# Three authored encounters are consumed once, including after voluntary retreat.
	var route: Sm2JourneySession=make()
	t.expect(route.new_game().ok,"route world initializes")
	var seen_battles: Array[String]=[]
	for meeting: int in 3:
		t.expect(route.act(route.command("start_battle")).ok,"route encounter starts")
		var id: String=route.runner.view().battle_id
		t.expect(id not in seen_battles,"each encounter has a distinct persistent identity")
		seen_battles.append(id)
		for turn: int in 20:
			if not route.world.busy(): break
			var v: Dictionary=route.runner.view()
			var active: Dictionary={}
			for row: Dictionary in v.actors:
				if row.actor_id==v.active_actor_id: active=row
			if active.controller=="player" and active.morale!="fleeing":
				var command: Sm2Command=Sm2Command.new()
				command.actor_id=int(v.active_actor_id); command.expected_revision=int(v.revision); command.battle_id=v.battle_id
				command.kind="escape" if int(active.q)==0 else "move"
				command.target=Vector2i(0,int(active.r))
				var escaped: Sm2CommandResult=route.attack(command)
				t.expect(escaped.accepted,"legal route retreat: "+escaped.code)
				if not escaped.accepted: break
			else: t.expect(route.step().ok,"enemy follows normal scheduler during retreat")
		t.equal(route.journey().completed,meeting+1,"retreat also consumes this encounter")
		t.expect(not route.world.busy(),"route encounter finished")
	before=route.state_hash()
	t.expect(not route.act(route.command("start_battle")).ok,"completed encounters never respawn")
	t.equal(route.state_hash(),before,"attempting fourth encounter is inert")
	t.expect(route.restore(route.capture()).ok,"all three completed encounters restore")
	_punch_contract(t)
	_dead_companion(t)
	t.complete_suite("p4_journey")

static func _dead_companion(t: Sm2TestHarness) -> void:
	var content: Dictionary=Sm2JourneyContentLoader.load_scenario()
	content.meetings[0].seed=1
	content.journey_fingerprint=Sm2Canonical.hash(content.meetings)
	var s: Sm2JourneySession=Sm2JourneySession.new(content,Sm2AiContentLoader.load_profile().profile)
	t.expect(s.new_game().ok,"death oracle world initializes")
	t.expect(s.act(s.command("start_battle")).ok,"death oracle fight starts")
	finish(s,t)
	t.equal(s.world.hero_id(),0,"seed 1 oracle loses hero")
	t.expect(not s.world.bodies[4].alive,"seed 1 oracle loses companion")
	var companion: Dictionary=s.world.bodies[4].to_data()
	var sword: String=s.journey().equipment(4)[0].id
	t.expect(s.act(s.command("incarnate",8)).ok,"Soul survives actual battle death")
	t.expect(s.act(s.command("transfer",8,sword)).ok,"new hero retrieves fallen companion's item")
	t.expect(s.act(s.command("equip",0,sword)).ok,"recovered companion weapon is usable")
	t.expect(s.act(s.command("start_battle")).ok,"next encounter starts with dead companion absent")
	var actor: Dictionary=s.runner.capture().session.battle.actors[1]
	t.expect(not actor.alive and not actor.on_field and actor.combat.hp==0,"dead companion cannot participate or respawn")
	t.equal(s.world.bodies[4].to_data(),companion,"dead companion retains final development")
	t.expect(s.restore(s.capture()).ok,"encounter with dead companion restores")
	t.expect(advance(s).ok,"lone new incarnation takes an ordinary action")

static func _punch_contract(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=make(); s.new_game()
	var sword: String=s.journey().equipment(2)[0].id
	t.expect(s.act(s.command("unequip",0,sword)).ok,"bare hand with shield fixture")
	var setup_data: Dictionary=Sm2EncounterFactory.build(s._content,s.journey())
	var hit_seen: bool=false; var miss_seen: bool=false
	for seed_value: int in range(1,41):
		var setup: Dictionary=setup_data.setup.duplicate(true)
		setup.seed=seed_value; setup.actors[0].q=2; setup.actors[2].q=3
		var battle: Sm2TacticalBattle=Sm2TacticalBattle.new(setup_data.catalog,setup_data.combat,true,null,null,setup_data.development,setup_data.origin)
		t.expect(battle.start(setup).ok,"adjacent punch encounter starts")
		var command: Sm2Command=Sm2Command.new()
		command.kind="use_ability"; command.ability_id="p4:ability.punch"; command.actor_id=1; command.target_actor_id=3; command.battle_id=setup.battle_id
		var preview_hash: String=battle.state_hash()
		t.expect(battle.preview(command).allowed,"shield does not prevent punch")
		t.equal(battle.state_hash(),preview_hash,"punch preview consumes no RNG or XP")
		var result: Sm2CommandResult=battle.execute(command)
		t.expect(result.accepted,"punch resolves through shared attack engine")
		for event: Dictionary in result.events:
			hit_seen=hit_seen or event.type=="attack_hit"; miss_seen=miss_seen or event.type=="attack_missed"
		var member: Dictionary=battle.capture().development.members[0]
		var progress: Sm2ProgressBodyState=Sm2ProgressRules.decode_body(member.body,s._content.development.progression()).body
		t.equal(progress.tracks[STRENGTH].earned,30,"hit or miss earns exactly one strength award")
		t.equal(progress.tracks[MELEE].earned,40,"hit or miss earns exactly one melee award")
		for actor_id: int in [1,2]:
			command=Sm2Command.new(); command.kind="end_turn"; command.actor_id=actor_id; command.expected_revision=int(battle.view().revision); command.battle_id=setup.battle_id
			t.expect(battle.execute(command).accepted,"reach departing enemy's activation")
		command=Sm2Command.new(); command.kind="move"; command.actor_id=3; command.target=Vector2i(4,1); command.expected_revision=int(battle.view().revision); command.battle_id=setup.battle_id
		result=battle.execute(command)
		t.expect(result.accepted,"enemy departs from unarmed threat")
		var reaction_seen: bool=false
		for event: Dictionary in result.events: reaction_seen=reaction_seen or event.type=="reaction_spent"
		t.expect(reaction_seen,"unarmed actor makes actual departure reaction")
		progress=Sm2ProgressRules.decode_body(battle.capture().development.members[0].body,s._content.development.progression()).body
		t.equal(progress.tracks[STRENGTH].earned,60,"reaction earns one further strength award")
		t.equal(progress.tracks[MELEE].earned,80,"reaction earns one further melee award")
		if hit_seen and miss_seen: break
	t.expect(hit_seen and miss_seen,"real RNG exercised both punch outcomes")
