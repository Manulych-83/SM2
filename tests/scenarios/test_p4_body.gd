extends RefCounted
const JOURNEY=preload("res://tests/scenarios/test_p4_journey.gd")
const PARTY=preload("res://tests/scenarios/test_p4_party.gd")
const RIGHT: String="p4:ability.hand_strike"
const LEFT: String="p4:ability.shield_hand_strike"

static func make(store: Sm2SaveStore=null) -> Sm2JourneySession:
	return Sm2JourneySession.new(Sm2BodyContentLoader.load_scenario(),Sm2AiContentLoader.load_profile().profile,store)

static func treatment_content() -> Dictionary:
	# Diagnostic encounter: enemies can only use the authored aimed strike.
	# This guarantees the test asks the AI to injure, without changing production tuning.
	var c: Dictionary=Sm2BodyContentLoader.load_scenario()
	var raw: Dictionary=c.combat.to_data()
	for gear: Dictionary in raw.equipment:
		if gear.id=="m2:equipment.sword": gear.abilities=[RIGHT]
	var combat: Sm2CombatCatalog=Sm2CombatCatalog.new(); combat.build(raw,c.catalog)
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	development.build(c.development.to_data(),c.development.progression(),combat)
	c.combat=combat; c.development=development
	c.setup.actors[2].q=2; c.setup.actors[2].r=1
	c.setup.actors[3].q=2; c.setup.actors[3].r=3
	c.journey_fingerprint=Sm2Canonical.hash([c.journey_fingerprint,raw,c.setup])
	return c

static func treatment_step(s: Sm2JourneySession) -> Dictionary:
	var v: Dictionary=s.runner.view()
	var wounded: bool=false
	for index: int in 2:
		for part: Dictionary in v.actors[index].body_functions.parts: wounded=wounded or not part.working
	for actor: Dictionary in v.actors:
		if actor.actor_id!=v.active_actor_id or actor.controller!="player" or actor.morale=="fleeing": continue
		var cmd: Sm2Command=Sm2Command.new()
		cmd.actor_id=int(actor.actor_id); cmd.expected_revision=int(v.revision); cmd.battle_id=v.battle_id
		cmd.kind="end_turn" if not wounded else "escape" if int(actor.q)==0 else "move"
		cmd.target=Vector2i(0,int(actor.r))
		var result: Sm2CommandResult=s.attack(cmd)
		return {"ok":result.accepted,"code":result.code,"events":result.events}
	return s.step()

static func fixture(c: Dictionary, seed_value: int=1, hurt: String="", capped: bool=false) -> Sm2TacticalBattle:
	var w: Sm2JourneyWorld=Sm2JourneyWorld.new(c.development.progression(),c.world_definition,c.combat,c.meetings,c.initial_loadout,c.development.body_functions())
	w.start("body-oracle")
	if capped:
		w.bodies[2].progress.tracks["p1:stat.strength"].earned=750000
		w.bodies[2].progress.tracks["p1:skill.melee"].earned=1000000
	if not hurt.is_empty(): w.bodies[2].functions.working[hurt]=false
	var e: Dictionary=Sm2EncounterFactory.build(c,w)
	e.setup.seed=seed_value; e.setup.actors[2].q=2; e.setup.actors[2].r=1
	var b: Sm2TacticalBattle=Sm2TacticalBattle.new(e.catalog,e.combat,true,null,null,e.development,e.origin)
	b.start(e.setup); return b

static func command(b: Sm2TacticalBattle, ability: String=RIGHT) -> Sm2Command:
	var result: Sm2Command=PARTY.cmd(b,"use_ability",3); result.ability_id=ability; return result

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary=Sm2BodyContentLoader.load_scenario()
	t.expect(c.ok,"body content validates "+str(c.get("errors",[])))
	if not c.ok: t.complete_suite("p4_body"); return
	var b: Sm2TacticalBattle=fixture(c)
	t.expect(not b.view().is_empty(),"body encounter starts")
	if b.view().is_empty(): t.complete_suite("p4_body"); return
	t.equal(b.capture().schema_version,11,"body schema explicit")
	t.equal(b.preview(command(b)).zones.size(),1,"aimed arm hit has one protection zone")
	t.equal(b.preview(command(b)).zones[0].id,"body","prototype body armor protects arm")
	t.equal(b.preview(command(b)).zones[0].chance,100,"arm hit never chooses head")
	var original: String=b.state_hash()
	t.expect(b.restore(b.capture()).ok,"healthy body restores")
	t.equal(b.state_hash(),original,"healthy restore exact")
	var injured: Sm2TacticalBattle
	var miss: bool=false
	for seed_value: int in range(1,35):
		b=fixture(c,seed_value)
		original=b.state_hash()
		t.expect(b.preview(command(b)).allowed,"limb attack allowed")
		t.equal(b.state_hash(),original,"preview leaves body intact")
		var result: Sm2CommandResult=b.execute(command(b))
		t.expect(result.accepted,"real aimed strike accepted "+result.code)
		for event: Dictionary in result.events:
			if event.type=="attack_missed": miss=true; t.expect(b._state.actor(3).body_functions.working.right_hand,"miss does not injure")
			if event.type=="body_function_lost": injured=b
		if injured!=null and miss: break
	t.expect(injured!=null and miss,"both injury hit and miss exercised")
	if injured==null: t.complete_suite("p4_body"); return
	b=injured
	t.expect(not b._state.actor(3).body_functions.working.right_hand,"actual hit disables target hand")
	t.expect(not b.view().actors[2].abilities.has("m2:ability.sword_strike"),"disabled sword unavailable")
	t.expect(b.view().actors[2].abilities.has("m2:ability.shieldwall"),"other hand still holds shield")
	t.equal(b._state.development.bodies[3] if b._state.development.bodies.has(3) else null,null,"enemy has no hero progression")
	original=b.state_hash()
	t.expect(b.restore(b.capture()).ok,"injured battle restores")
	t.equal(b.state_hash(),original,"restore keeps injury and RNG")
	for defect: String in ["heal","remove_receipt","duplicate_receipt","foreign_part","schema"]:
		var bad: Dictionary=b.capture()
		match defect:
			"heal": bad.actors[2].body_functions.parts[1].working=true
			"remove_receipt": bad.body_changes.clear()
			"duplicate_receipt": bad.body_changes.append(bad.body_changes[0].duplicate(true))
			"foreign_part": bad.body_changes[0].part_id="wing"
			"schema": bad.schema_version=10
		t.expect(not b.restore(bad).ok,"reject forged body snapshot "+defect)
		t.equal(b.state_hash(),original,"failed load is atomic")
	_capabilities(t,c)
	_shield(t,c)
	_reaction(t)
	_world(t)
	t.complete_suite("p4_body")

static func _capabilities(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle=fixture(c,1,"right_hand")
	var before: String=b.state_hash()
	t.expect(not b.execute(command(b)).accepted,"injured source cannot attack")
	t.equal(b.state_hash(),before,"rejected attack preserves XP HP RNG")
	t.expect(b.execute(PARTY.cmd(b,"end_turn")).accepted,"injured source can end turn")
	var actor: Sm2TacticalActor=b._state.actor(1)
	t.expect(not Sm2AttackResolver.neighbors_threatening(b._state,b._state.actor(3),b._combat,true).has(1),"injured weapon cannot react")
	t.expect(not Sm2BodyCapabilityQuery.unarmed(actor,b._combat),"held shield is not a free hand")
	actor.combat.items.erase("shield")
	t.expect(Sm2BodyCapabilityQuery.unarmed(actor,b._combat),"free healthy left hand can punch")
	t.expect(Sm2AttackResolver.available_abilities(actor,b._combat).has("p4:ability.punch"),"shared query exposes free-hand punch")
	actor.body_functions.working.left_hand=false
	t.expect(not Sm2BodyCapabilityQuery.unarmed(actor,b._combat),"two injured hands cannot punch")
	var bow: Sm2CombatGear=b._combat.gear("m2:equipment.bow")
	t.expect(not Sm2BodyCapabilityQuery.item_allowed(actor,bow),"bow requires both hands")
	var query: Sm2AiQueries=Sm2AiQueries.new(b._state,b._combat)
	var attack: Sm2Command=command(b); attack.actor_id=1
	t.expect(not query.attack(attack,actor.spatial.position).allowed,"AI does not use disabled weapon")
	actor.body_functions.working.right_hand=true
	t.expect(not query.attack(attack,actor.spatial.position).allowed,"AI body projection detached")

static func _shield(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle
	for seed_value: int in range(1,35):
		b=fixture(c,seed_value)
		var result: Sm2CommandResult=b.execute(command(b,LEFT))
		t.expect(result.accepted,"left-hand strike executes")
		if not b._state.actor(3).body_functions.working.left_hand: break
	t.expect(not b._state.actor(3).body_functions.working.left_hand,"shield hand injured")
	var forecast: Dictionary=b.preview(command(b,"m2:ability.sword_strike"))
	t.equal(forecast.modifiers.shield,0,"injured shield gives no passive defense")
	t.expect(not b.view().actors[2].abilities.has("m2:ability.shieldwall"),"injured hand cannot use shieldwall")
	t.expect(b.view().actors[2].abilities.has("m2:ability.sword_strike"),"right-hand weapon still usable")
	# Late XP refusal after a landed injury must revert function, receipt and damage.
	b=fixture(c)
	var raw: Dictionary=b.capture(); raw.rng.draws="9223372036854775806"
	t.expect(b.restore(raw).ok,"RNG ceiling fixture valid")
	var before: String=b.state_hash()
	t.expect(not b.execute(command(b)).accepted,"RNG exhaustion refuses aimed attack")
	t.equal(b.state_hash(),before,"refusal leaves body receipts and RNG unchanged")
	b=fixture(c,1,"",true)
	before=b.state_hash()
	var denied: Sm2CommandResult=b.execute(command(b))
	t.equal(denied.code,"experience_limit","late XP refusal after resolving aimed attack")
	t.equal(b.state_hash(),before,"late refusal rolls back damage, injury and receipt")
	t.expect(denied.events.is_empty(),"failed injury publishes no events")

static func _reaction(t: Sm2TestHarness) -> void:
	var observed: bool=false
	for seed_value: int in range(1,35):
		var b: Sm2TacticalBattle=fixture(treatment_content(),seed_value)
		for i: int in 2: t.expect(b.execute(PARTY.cmd(b,"end_turn")).accepted,"reach enemy departure")
		var move: Sm2Command=PARTY.cmd(b,"move"); move.target=Vector2i(3,1)
		var result: Sm2CommandResult=b.execute(move)
		t.expect(result.accepted,"reaction resolves through common attack")
		var reaction: bool=false; var injury: bool=false
		for event: Dictionary in result.events:
			if event.type=="reaction_spent": reaction=true
			if event.type=="body_function_lost": injury=true
		if reaction and injury: observed=true; break
	t.expect(observed,"real aimed reaction can cause injury")

static func _world(t: Sm2TestHarness) -> void:
	var s: Sm2JourneySession=Sm2JourneySession.new(treatment_content(),Sm2AiContentLoader.load_profile().profile,Sm2SaveStore.new("user://body-tests"))
	t.expect(s.new_game().ok,"functional world starts")
	t.expect(s.act(s.command("start_battle")).ok,"functional world battle starts")
	t.expect(not s.act(s.command("heal_hand",2,"right_hand")).ok,"healing locked in combat")
	for i: int in 3: t.expect(treatment_step(s).ok,"world battle advances")
	t.expect(s.save_game().ok,"functional active save")
	var other: Sm2JourneySession=Sm2JourneySession.new(treatment_content(),s._profile,s._store)
	t.expect(other.load_game().ok,"functional active load")
	t.equal(s.state_hash(),other.state_hash(),"active round trip exact")
	t.equal(treatment_step(s),treatment_step(other),"same next command after load")
	# Retreat is the player's existing exit if an arm injury makes combat untenable.
	for i: int in 800:
		if not s.world.busy(): break
		var result: Dictionary=treatment_step(s)
		t.expect(result.ok,"functional fight advances to outcome")
		if not result.ok: break
	t.expect(not s.world.busy(),"functional battle completes")
	t.expect(s.save_game().ok and other.load_game().ok,"outcome saved without replaying injuries")
	t.equal(s.state_hash(),other.state_hash(),"closed outcome exact")
	if s.world.hero_id()==0: t.expect(s.act(s.command("incarnate",8)).ok,"new body after defeat")
	var healed: int=0
	for body_id: int in [s.world.hero_id(),4]:
		if not s.world.bodies[body_id].alive: continue
		for part: String in s.journey().body_catalog.ids():
			if s.world.bodies[body_id].functions.working[part]: continue
			var hp: int=s.world.bodies[body_id].hp
			var progress: Dictionary=s.world.bodies[body_id].progress.to_data()
			t.expect(s.act(s.command("heal_hand",body_id,part)).ok,"treatment restores injured living member")
			t.equal(s.world.bodies[body_id].hp,hp,"treatment grants no HP")
			t.equal(s.world.bodies[body_id].progress.to_data(),progress,"treatment grants no XP")
			var hash_value: String=s.state_hash()
			t.expect(not s.act(s.command("heal_hand",body_id,part)).ok,"duplicate treatment rejected")
			t.equal(s.state_hash(),hash_value,"duplicate treatment atomic")
			healed+=1
	t.expect(healed>0,"full fixture exercises actual injury and treatment")
	t.expect(s.save_game().ok and other.load_game().ok,"treatment disk round trip")
	t.equal(s.state_hash(),other.state_hash(),"treatment history exact")
	var companion: Dictionary=s.world.bodies[4].to_data()
	t.expect(s.act(s.command("end_life")).ok,"end current life")
	var next_body: int=8 if s.world.bodies[8].alive==false and s.world.eligible(8).is_empty() else 9
	t.expect(s.act(s.command("incarnate",next_body)).ok,"new healthy incarnation")
	for working: bool in s.world.bodies[next_body].functions.working.values(): t.expect(working,"new body starts with healthy functions")
	t.equal(s.world.bodies[4].to_data(),companion,"companion functions and growth retained")
	t.expect(s.act(s.command("start_battle")).ok,"new body enters next meeting")
	t.expect(s.save_game().ok and other.load_game().ok,"new incarnation battle persists")
