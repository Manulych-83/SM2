extends RefCounted
const BURST: String = "m4:spell.arcane_burst"

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary = Sm2AreaContentLoader.load_scenario()
	t.expect(c.ok,"area content loads")
	if not c.ok: return
	_catalog(t,c)
	_geometry(t)
	_terrain(t,c)
	_damage(t,c)
	_atomic(t,c)
	_ai(t,c)
	_full(t,c)
	t.complete_suite("m4_areas")

static func setup(c: Dictionary) -> Dictionary:
	var data: Dictionary = Sm2CombatFixtures.setup(c,[3,4,5,2],1231)
	for actor: Dictionary in data.actors:
		match int(actor.actor_id):
			4: actor.q = 3; actor.r = 1
			5: actor.q = 3; actor.r = 2
			2: actor.q = 2; actor.r = 3
	return data

static func battle(t: Sm2TestHarness,c: Dictionary) -> Sm2TacticalBattle:
	var b: Sm2TacticalBattle = Sm2TacticalBattle.new(c.catalog,c.combat,true,c.effects,c.magic)
	t.expect(b.start(setup(c)).ok,"area fixture starts")
	return b

static func command(b: Sm2TacticalBattle, center: Vector2i = Vector2i(2,2)) -> Sm2Command:
	var cmd: Sm2Command = Sm2TurnTestFixtures.command(b,"use_ability")
	cmd.ability_id = BURST
	cmd.target = center
	return cmd

static func _restore(t: Sm2TestHarness,b: Sm2TacticalBattle,data: Dictionary) -> void:
	var result: Dictionary = b.restore(data)
	t.expect(result.ok,"area fixture snapshot valid "+str(result.get("errors",[])))

static func mana(data: Dictionary, id: int) -> Dictionary:
	for pool: Dictionary in data.mana:
		if str(pool.actor_id) == str(id): return pool
	return {}

static func _catalog(t: Sm2TestHarness,c: Dictionary) -> void:
	var original: String = c.magic.fingerprint()
	for defect: String in ["radius","radius_bool","radius_max","version","side","operation","missing"]:
		var raw: Dictionary = c.magic.to_data()
		for spell: Dictionary in raw.spells:
			if spell.id != BURST: continue
			match defect:
				"radius": spell.radius = 0
				"radius_bool": spell.radius = true
				"radius_max": spell.radius = 4
				"version": raw.version = "sm2.m4.magic.content.1"
				"side": spell.target_side = "all"
				"operation": spell.operation = "arbitrary_script"
				"missing": spell.erase("radius")
		t.expect(not c.magic.build(raw,c.combat,c.effects).is_empty(),"invalid area content "+defect)
		t.equal(c.magic.fingerprint(),original,"catalog failure atomic")
	var old: Dictionary = Sm2MagicContentLoader.load_scenario()
	var b: Sm2TacticalBattle = battle(t,c)
	var legacy: Sm2TacticalBattle = Sm2TacticalBattle.new(old.catalog,old.combat,true,old.effects,old.magic)
	t.expect(legacy.start(setup(old)).ok,"legacy magic still starts")
	t.equal([b.capture().schema_version,b.capture().ruleset],[7,Sm2MagicSnapshot.AREA_RULESET],"area version explicit")
	t.expect(not b.restore(legacy.capture()).ok and not legacy.restore(b.capture()).ok,"no implicit schema migration")
	var data: Dictionary = b.capture()
	data.schema_version = 6
	t.expect(not b.restore(data).ok,"wrong area schema rejected")

static func _geometry(t: Sm2TestHarness) -> void:
	var field: Sm2Battlefield = Sm2SpatialFixtures.field(8,5)
	var cells: Array[Vector2i] = Sm2AreaGeometry.disc(field,Vector2i(3,2),1)
	t.equal(cells,[Vector2i(2,2),Vector2i(2,3),Vector2i(3,1),Vector2i(3,2),Vector2i(3,3),Vector2i(4,1),Vector2i(4,2)],"independent seven-cell axial oracle")
	t.equal(Sm2AreaGeometry.disc(field,Vector2i.ZERO,1),[Vector2i(0,0),Vector2i(0,1),Vector2i(1,0)],"edge clipped without duplicates")
	t.equal(Sm2AreaGeometry.disc(Sm2SpatialFixtures.field(10,10),Vector2i(4,4),3).size(),37,"radius three disc")
	var wall: Sm2Battlefield = Sm2SpatialFixtures.field(8,5,[Sm2SpatialFixtures.tile(3,2,"ground",0,false,true)])
	t.expect(not Sm2AreaGeometry.footprint(wall,Vector2i(2,2),3).has(Vector2i(4,2)),"terrain blocks blast propagation beyond wall")

static func _terrain(t: Sm2TestHarness,c: Dictionary) -> void:
	for defect: String in ["blocked_center","blocked_ray","range"]:
		var b: Sm2TacticalBattle = Sm2TacticalBattle.new(c.catalog,c.combat,true,c.effects,c.magic)
		var data: Dictionary = setup(c)
		if defect == "blocked_center": data.field = Sm2SpatialFixtures.field(8,5,[Sm2SpatialFixtures.tile(2,2,"ground",0,false,true)]).to_data()
		if defect == "blocked_ray":
			data.field = Sm2SpatialFixtures.field(8,5,[Sm2SpatialFixtures.tile(2,2,"ground",0,false,true)]).to_data()
		t.expect(b.start(data).ok,"terrain fixture starts")
		var cmd: Sm2Command = command(b,Vector2i(3,2) if defect == "blocked_ray" else Vector2i(6,2) if defect == "range" else Vector2i(2,2))
		var expected: String = "area_center_blocked" if defect == "blocked_center" else "line_of_sight_blocked" if defect == "blocked_ray" else "attack_range"
		t.equal(b.preview(cmd).reason,expected,"terrain refusal "+defect)
		var before: Dictionary = b.capture()
		t.expect(not b.execute(cmd).accepted,"invalid terrain cast refused")
		t.equal(b.capture(),before,"terrain failure inert")

static func _damage(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle = battle(t,c)
	var before: Dictionary = b.capture()
	var preview: Dictionary = b.preview(command(b))
	t.expect(preview.allowed,"empty center with enemies in ring allowed")
	t.equal(preview.targets.map(func(hit: Dictionary) -> int: return int(hit.actor_id)),[4,5],"only enemies in stable numeric order")
	t.equal(preview.targets.map(func(hit: Dictionary) -> int: return int(hit.hp_loss)),[14,7],"per-target resistance oracle 0 and 50 percent")
	t.equal(preview.hp_loss,21,"aggregate forecast")
	t.equal(b.capture(),before,"preview has no side effects")
	preview.targets[0].hp_loss = 999
	t.equal(b.preview(command(b)).hp_loss,21,"preview detached")
	var result: Sm2CommandResult = b.execute(command(b))
	t.expect(result.accepted,"area resolves")
	var after: Dictionary = b.capture()
	t.equal(Sm2CombatFixtures.actor(after,4).combat.hp,46,"first enemy loses 14")
	t.equal(Sm2CombatFixtures.actor(after,5).combat.hp,58,"second enemy loses 7")
	t.equal(Sm2CombatFixtures.actor(after,2),Sm2CombatFixtures.actor(before,2),"ally inside area wholly unchanged")
	t.equal(Sm2CombatFixtures.actor(after,3).combat,Sm2CombatFixtures.actor(before,3).combat,"caster inside area unharmed and items untouched")
	t.equal(Sm2CombatFixtures.actor(after,3).ap,4,"five AP paid once")
	t.equal(mana(after,3).current,12,"twelve mana paid once")
	t.equal(int(after.revision),int(before.revision)+1,"one transaction revision")
	t.equal(result.events.filter(func(e: Dictionary) -> bool: return e.type == "mana_spent").size(),1,"one mana event")
	for i: int in result.events.size(): t.equal(result.events[i].sequence,i,"stable event numbering")
	# Both last enemies die before outcome; no morality roll for actors already dead.
	b = battle(t,c)
	before = b.capture()
	Sm2CombatFixtures.actor(before,4).combat.hp = 14
	Sm2CombatFixtures.actor(before,5).combat.hp = 7
	_restore(t,b,before)
	result = b.execute(command(b))
	t.expect(result.accepted and b.view().finished,"one explosion kills both last enemies")
	t.equal(result.events.filter(func(e: Dictionary) -> bool: return e.type == "actor_died").size(),2,"two deaths")
	t.equal(result.events.filter(func(e: Dictionary) -> bool: return e.type == "battle_finished").size(),1,"one outcome after full explosion")
	t.equal(b.capture().rng,before.rng,"dead targets do not roll morale")
	# A last-AP cast ticks the caster's existing effect exactly once.
	b = battle(t,c)
	before = b.capture()
	before.revision = "1"
	before.next_effect_id = "2"
	before.effects = [{"effect_id":"1","definition_id":"m4:effect.poison","source_actor_id":"4","target_actor_id":"3","remaining":3,"applied_revision":"1"}]
	Sm2CombatFixtures.actor(before,3).ap = 5
	_restore(t,b,before)
	t.expect(b.execute(command(b)).accepted,"last AP area accepted")
	t.equal(Sm2CombatFixtures.actor(b.capture(),3).combat.hp,45,"one poison tick after last AP area")
	t.equal(b.capture().effects[0].remaining,2,"one effect duration decrement")
	# Zero loss remains legal for the player, without spurious morale rolls.
	var raw: Dictionary = c.magic.to_data()
	for profile: Dictionary in raw.profiles: profile.arcane_resistance = 100
	var immune: Dictionary = c.duplicate()
	immune.magic = Sm2MagicCatalog.new()
	t.expect(immune.magic.build(raw,c.combat,c.effects).is_empty(),"resistance fixture catalog")
	b = battle(t,immune)
	before = b.capture()
	t.equal(b.preview(command(b)).hp_loss,0,"full resistance area forecast zero")
	t.expect(b.execute(command(b)).accepted,"zero-damage area paid legally")
	t.equal(b.capture().rng,before.rng,"zero damage no morale RNG")

static func _atomic(t: Sm2TestHarness,c: Dictionary) -> void:
	for defect: String in ["bounds","empty","actor_target","mana","ap","fatigue","stale","rng"]:
		var b: Sm2TacticalBattle = battle(t,c)
		var data: Dictionary = b.capture()
		match defect:
			"mana": mana(data,3).current = 11
			"ap": Sm2CombatFixtures.actor(data,3).ap = 4
			"fatigue": Sm2CombatFixtures.actor(data,3).fatigue = 70
			"rng": data.rng.draws = "9223372036854775806"
		_restore(t,b,data)
		var cmd: Sm2Command = command(b)
		match defect:
			"bounds": cmd.target = Vector2i(-1,2)
			"empty": cmd.target = Vector2i(0,2)
			"actor_target": cmd.target_actor_id = 4
			"stale": cmd.expected_revision += 1
		var before: Dictionary = b.capture()
		var result: Sm2CommandResult = b.execute(cmd)
		t.expect(not result.accepted,"invalid area rejected "+defect)
		t.expect(result.events.is_empty(),"failure has no events "+defect)
		t.equal(b.capture(),before,"failed cast state RNG ID revision inert "+defect)

static func _ai(t: Sm2TestHarness,c: Dictionary) -> void:
	var p: Sm2AiProfile = Sm2AiContentLoader.load_profile(Sm2AiContentLoader.AREA_PATH).profile
	var b: Sm2TacticalBattle = battle(t,c)
	var data: Dictionary = b.capture()
	Sm2CombatFixtures.actor(data,4).combat.hp = 14
	Sm2CombatFixtures.actor(data,5).combat.hp = 7
	_restore(t,b,data)
	var before: String = b.state_hash()
	var decision: Dictionary = b.ai_decision(p)
	t.expect(decision.ok,"area AI decides")
	t.equal(decision.command.ability_id,BURST,"AI chooses winning multi-target spell")
	t.equal(decision.command.target_actor_id,0,"AI aims at a cell")
	t.expect(b.preview(decision.command).allowed,"AI cell legal")
	t.equal(b.state_hash(),before,"AI does not mutate battle")
	t.equal(Sm2TacticalAi.command_data(b.ai_decision(p).command),Sm2TacticalAi.command_data(decision.command),"repeatable center choice")
	data.rng.state = "76"
	data.rng.draws = "999"
	_restore(t,b,data)
	t.equal(Sm2TacticalAi.command_data(b.ai_decision(p).command),Sm2TacticalAi.command_data(decision.command),"area AI cannot see future RNG")
	var raw: Dictionary = p.to_data()
	raw.query_limit = 50
	p.build(raw)
	before = b.state_hash()
	t.equal(b.ai_decision(p).reason,"ai_query_limit","area work bounded")
	t.equal(b.state_hash(),before,"budget failure inert")

static func _full(t: Sm2TestHarness,c: Dictionary) -> void:
	var p: Sm2AiProfile = Sm2AiContentLoader.load_profile(Sm2AiContentLoader.AREA_PATH).profile
	for seed_value: int in [20260909,1,76]:
		var initial_setup: Dictionary = c.setup.duplicate(true)
		initial_setup.seed = seed_value
		var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/m4_areas/"+str(seed_value))
		var runner: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,p,store,true,c.effects,c.magic)
		t.expect(runner.new_battle(initial_setup).ok,"full area battle starts")
		var initial: Dictionary = runner.capture().session
		var history: Array[Dictionary] = []
		for i: int in 6:
			var step: Dictionary = runner.step()
			t.expect(step.ok,"opening area AI command")
			if step.has("command"): history.append({"command":step.command,"events":step.events,"code":step.code})
		t.expect(runner.save_game().ok,"area runner saves")
		var restored: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,p,store,true,c.effects,c.magic)
		t.expect(restored.load_game().ok,"area runner loads")
		var played: Dictionary = runner.run_to_end(2000)
		t.expect(played.ok and played.status == "finished" and int(runner.view().round) < 100,"area battle resolves before round limit")
		t.equal(restored.run_to_end(2000),played,"loaded area decisions and events identical")
		var retries: int = 0
		for entry: Dictionary in played.history:
			history.append({"command":entry.command,"events":entry.events,"code":entry.code})
			retries += int(entry.retries)
		t.equal(retries,0,"no rejected command retries")
		var casts: int = 0
		for entry: Dictionary in history:
			for event: Dictionary in entry.events:
				if event.type == "area_spell_cast": casts += 1
		t.expect(casts > 0,"full AI battle actually uses areas")
		var replay: Dictionary = Sm2BattleReplay.replay(c.catalog,c.combat,initial,history,c.effects,c.magic)
		t.expect(replay.ok,"area replay without AI")
		t.equal(replay.session,runner.capture().session,"area replay final state")
		t.expect(store.save_slot({"seed":seed_value,"initial":initial,"history":history,"area_casts":casts,"final":runner.capture()},"trace").ok,"area trace recorded")
