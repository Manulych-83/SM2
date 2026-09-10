extends RefCounted
const SPELL: String = "m4:spell.arcane_bolt"

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary = Sm2MagicContentLoader.load_scenario()
	t.expect(c.ok,"magic authored content loads")
	if not c.ok: return
	_catalog(t,c)
	_damage(t,c)
	_resources(t,c)
	_denials(t,c)
	_storage(t,c)
	_full_battle(t,c)
	t.complete_suite("m4_magic")

static func _battle(t: Sm2TestHarness,c: Dictionary,ids: Array[int] = [2,4]) -> Sm2TacticalBattle:
	var result: Sm2TacticalBattle = Sm2TacticalBattle.new(c.catalog,c.combat,true,c.effects,c.magic)
	t.expect(result.start(Sm2CombatFixtures.setup(c,ids,1231)).ok,"magic fixture starts")
	return result

static func _cmd(b: Sm2TacticalBattle,kind: String = "use_ability",target: int = 4) -> Sm2Command:
	var cmd: Sm2Command = Sm2TurnTestFixtures.command(b,kind)
	cmd.ability_id = SPELL if kind == "use_ability" else ""
	cmd.target_actor_id = target if kind == "use_ability" else 0
	return cmd

static func _act(t: Sm2TestHarness,b: Sm2TacticalBattle,kind: String = "use_ability",target: int = 4) -> Sm2CommandResult:
	var revision: int = b.view().revision
	var result: Sm2CommandResult = b.execute(_cmd(b,kind,target))
	t.expect(result.accepted,"magic accepts "+kind+": "+result.code)
	t.equal(result.revision,revision+1,"root command has one revision")
	return result

static func _pool(data: Dictionary,id: int) -> Dictionary:
	for raw: Dictionary in data.mana:
		if raw.actor_id == str(id): return raw
	return {}

static func _actor(b: Sm2TacticalBattle,id: int) -> Dictionary: return Sm2CombatFixtures.actor(b.view(),id)

static func _catalog(t: Sm2TestHarness,c: Dictionary) -> void:
	var original: String = c.magic.fingerprint()
	for defect: String in ["operation","channel","zero_mana","negative_regen","resistance","reference","duplicate","collision","unknown_field","fraction"]:
		var raw: Dictionary = c.magic.to_data()
		match defect:
			"operation": raw.spells[0].operation = "run_script"
			"channel": raw.spells[0].channel = "poison"
			"zero_mana": raw.spells[0].mana_cost = 0
			"negative_regen": raw.profiles[0].mana_per_round = -1
			"resistance": raw.profiles[0].arcane_resistance = 101
			"reference": raw.profiles[0].spells = ["missing"]
			"duplicate": raw.spells.append(raw.spells[0])
			"collision": raw.spells[0].id = "m4:ability.poison"
			"unknown_field": raw.profiles[0].future = 1
			"fraction": raw.spells[0].damage = 2.5
		t.expect(not c.magic.build(raw,c.combat,c.effects).is_empty(),"catalog rejects "+defect)
		t.equal(c.magic.fingerprint(),original,"catalog failure atomic")
	c.magic.spell(SPELL).damage = 999
	c.magic.profile("m2:loadout.sword_fighter").mana_max = 999
	t.equal(c.magic.spell(SPELL).damage,18,"spell definition detached")
	t.equal(c.magic.profile("m2:loadout.sword_fighter").mana_max,24,"profile detached")
	var raw: Dictionary = c.magic.to_data()
	var extra: Dictionary = raw.spells[0].duplicate(true)
	extra.id = "test:spell.small"
	extra.damage = 7
	raw.spells.append(extra)
	for profile: Dictionary in raw.profiles: profile.spells.append(extra.id)
	var catalog: Sm2MagicCatalog = Sm2MagicCatalog.new()
	t.expect(catalog.build(raw,c.combat,c.effects).is_empty(),"new direct spell authored only with data")
	var alternate: Dictionary = c.duplicate()
	alternate.magic = catalog
	var b: Sm2TacticalBattle = _battle(t,alternate)
	var cmd: Sm2Command = _cmd(b)
	cmd.ability_id = extra.id
	t.expect(b.execute(cmd).accepted,"data-only spell executes")
	t.equal(_actor(b,4).combat.hp,53,"data-only spell has independent seven HP oracle")
	var missing: Sm2MagicCatalog = Sm2MagicCatalog.new()
	raw.profiles.remove_at(0)
	t.expect(missing.build(raw,c.combat,c.effects).is_empty(),"partial catalog allowed for other scenarios")
	alternate.magic = missing
	b = Sm2TacticalBattle.new(c.catalog,c.combat,true,c.effects,missing)
	t.expect(not b.start(c.setup).ok,"scenario requires profile coverage")

static func _damage(t: Sm2TestHarness,c: Dictionary) -> void:
	for resistance: int in [0,25,50,100]:
		var raw: Dictionary = c.magic.to_data()
		for p: Dictionary in raw.profiles: p.arcane_resistance = resistance
		var magic: Sm2MagicCatalog = Sm2MagicCatalog.new()
		t.expect(magic.build(raw,c.combat,c.effects).is_empty(),"resistance profile")
		var adjusted: Dictionary = c.duplicate()
		adjusted.magic = magic
		var b: Sm2TacticalBattle = _battle(t,adjusted)
		var before: Dictionary = b.capture()
		var prediction: Dictionary = b.preview(_cmd(b))
		t.equal(b.capture(),before,"spell preview inert")
		var expected: int = {0:18,25:13,50:9,100:0}[resistance]
		t.equal(prediction.hp_loss,expected,"resistance floor oracle")
		var result: Sm2CommandResult = _act(t,b)
		t.equal(_actor(b,4).combat.hp,60-expected,"direct HP equals forecast")
		t.equal(Sm2CombatFixtures.actor(b.capture(),4).combat.items,Sm2CombatFixtures.actor(before,4).combat.items,"spell leaves target armor shield and helmet unchanged")
		t.equal(Sm2CombatFixtures.actor(b.capture(),2).combat.items,Sm2CombatFixtures.actor(before,2).combat.items,"spell leaves caster equipment unchanged")
		t.equal([_actor(b,2).mana,_actor(b,2).ap,_actor(b,2).fatigue],[16,5,6],"exact spell costs")
		for event: Dictionary in result.events: t.expect(event.type not in ["attack_hit","attack_missed","reaction_spent"],"spell has no weapon hit or reaction roll")
		if resistance >= 50: t.equal(b.capture().rng,before.rng,"small or zero damage has no morale RNG")
		else: t.equal(int(b.capture().rng.draws),int(before.rng.draws)+1,"large direct hit uses existing morale once")
	var b: Sm2TacticalBattle = _battle(t,c)
	var data: Dictionary = b.capture()
	Sm2CombatFixtures.actor(data,4).combat.hp = 18
	t.expect(b.restore(data).ok,"lethal fixture")
	t.expect(b.preview(_cmd(b)).lethal,"lethal forecast")
	var result: Sm2CommandResult = _act(t,b)
	t.expect(b.view().finished and b.view().winner == "company","spell death completes battle before scheduler")
	var deaths: int = 0
	for event: Dictionary in result.events:
		if event.type == "actor_died": deaths += 1
		t.expect(event.type != "mana_recovered","no recovery after outcome")
	t.equal(deaths,1,"one death from spell")
	t.equal(_actor(b,2).mana,16,"mana payment retained at outcome")
	b = _battle(t,c)
	data = b.capture()
	data.rng.draws = "9223372036854775806"
	t.expect(b.restore(data).ok,"RNG limit fixture")
	var hash_before: String = b.state_hash()
	result = b.execute(_cmd(b))
	t.equal(result.code,"rng_counter_limit","large-hit morale failure surfaced")
	t.expect(not result.accepted and result.events.is_empty(),"failed spell emits no committed events")
	t.equal(b.state_hash(),hash_before,"spell rollback includes mana AP HP RNG and revision")

static func _resources(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle = _battle(t,c)
	t.equal(_actor(b,2).mana,24,"battle starts with full mana")
	_act(t,b)
	_act(t,b,"wait")
	t.equal(_actor(b,2).mana,16,"Wait gives no mana")
	_act(t,b,"end_turn")
	t.equal([b.view().active_actor_id,_actor(b,2).mana],[2,16],"deferred resume gives no mana")
	var result: Sm2CommandResult = _act(t,b,"end_turn")
	t.equal([b.view().round,_actor(b,2).mana],[2,20],"next round gives exactly four mana")
	var recovered: int = 0
	for event: Dictionary in result.events:
		if event.type == "mana_recovered": recovered += 1
	t.equal(recovered,1,"only depleted actor has recovery event")
	_act(t,b,"end_turn")
	_act(t,b,"end_turn")
	t.equal(_actor(b,2).mana,24,"mana capped at maximum")
	b = _battle(t,c)
	var data: Dictionary = b.capture()
	Sm2CombatFixtures.actor(data,2).ap = 4
	data.revision = "1"
	data.effects = [{"effect_id":"1","definition_id":"m4:effect.cover","source_actor_id":"2","target_actor_id":"2","remaining":2,"applied_revision":"1"}]
	data.next_effect_id = "2"
	t.expect(b.restore(data).ok,"last AP effect fixture")
	_act(t,b)
	t.equal([b.capture().effects[0].remaining,b.view().active_actor_id],[1,4],"AP0 spell ends activation and ticks effect once")
	# Leaving the field freezes that actor's mana during later rounds.
	b = _battle(t,c,[2,4,1])
	data = b.capture()
	Sm2CombatFixtures.actor(data,2).q = 0
	_pool(data,2).current = 8
	t.expect(b.restore(data).ok,"escape mana fixture")
	_act(t,b,"escape")
	for i: int in 6:
		if b.view().finished or b.view().round >= 2: break
		_act(t,b,"end_turn")
	t.equal(_actor(b,2).mana,8,"escaped caster does not recover mana")

static func _denials(t: Sm2TestHarness,c: Dictionary) -> void:
	for defect: String in ["mana","ap","fatigue","range","ally","fleeing","stale","unknown","not_granted"]:
		var b: Sm2TacticalBattle = _battle(t,c)
		var data: Dictionary = b.capture()
		match defect:
			"mana": _pool(data,2).current = 7
			"ap": Sm2CombatFixtures.actor(data,2).ap = 3
			"fatigue": Sm2CombatFixtures.actor(data,2).fatigue = _actor(b,2).fatigue_max-5
			"range": Sm2CombatFixtures.actor(data,4).q = 7
			"fleeing": Sm2CombatFixtures.actor(data,2).morale = "fleeing"
			"not_granted":
				var raw: Dictionary = c.magic.to_data()
				for profile: Dictionary in raw.profiles: profile.spells = []
				var adjusted: Dictionary = c.duplicate()
				adjusted.magic = Sm2MagicCatalog.new()
				adjusted.magic.build(raw,c.combat,c.effects)
				b = _battle(t,adjusted)
				data = b.capture()
		t.expect(b.restore(data).ok,"denial fixture "+defect)
		var cmd: Sm2Command = _cmd(b)
		if defect == "ally": cmd.target_actor_id = 2
		if defect == "stale": cmd.expected_revision = 99
		if defect == "unknown": cmd.ability_id = "missing"
		var before: String = b.state_hash()
		t.expect(not b.preview(cmd).allowed,"preview denies "+defect)
		t.expect(not b.execute(cmd).accepted,"execute denies "+defect)
		t.equal(b.state_hash(),before,"denied spell inert "+defect)
	var b: Sm2TacticalBattle = _battle(t,c,[2,1,4])
	t.equal(b.preview(_cmd(b)).reason,"line_of_sight_blocked","unit blocks magical ray")
	var before: String = b.state_hash()
	t.expect(not b.execute(_cmd(b)).accepted,"blocked ray rejected")
	t.equal(b.state_hash(),before,"blocked spell costs nothing")

static func _storage(t: Sm2TestHarness,c: Dictionary) -> void:
	var b: Sm2TacticalBattle = _battle(t,c)
	_act(t,b)
	var snapshot: Dictionary = b.capture()
	for defect: String in ["version","fingerprint","negative","overflow","extra","missing","duplicate","order","actor","bool"]:
		var data: Dictionary = snapshot.duplicate(true)
		match defect:
			"version": data.schema_version = 5
			"fingerprint": data.magic_fingerprint = "wrong"
			"negative": data.mana[0].current = -1
			"overflow": data.mana[0].current = 25
			"extra": data.mana[0].maximum = 24
			"missing": data.mana.pop_back()
			"duplicate": data.mana[1] = data.mana[0]
			"order": data.mana.reverse()
			"actor": data.mana[1].actor_id = "999"
			"bool": data.mana[0].current = true
		t.expect(not b.restore(data).ok,"invalid magic snapshot "+defect)
		t.equal(b.capture(),snapshot,"invalid snapshot restore inert")
	var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/m4_magic")
	var runner: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,Sm2AiContentLoader.load_profile().profile,store,false,c.effects,c.magic)
	t.expect(runner.new_battle(Sm2CombatFixtures.setup(c,[2,4],1231)).ok,"magic runner starts")
	var initial: Dictionary = runner.capture().session
	var command: Sm2Command = Sm2Command.new()
	command.kind = "use_ability"
	command.ability_id = SPELL
	command.actor_id = 2
	command.target_actor_id = 4
	var cast: Sm2CommandResult = runner.execute_player(command)
	t.expect(cast.accepted,"runner casts")
	var history: Array[Dictionary] = [{"command":Sm2TacticalAi.command_data(command),"events":cast.events,"code":cast.code}]
	t.expect(runner.save_game().ok,"magic disk save")
	var restored: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,Sm2AiContentLoader.load_profile().profile,store,false,c.effects,c.magic)
	t.expect(restored.load_game().ok,"magic disk restore")
	t.equal(restored.capture(),runner.capture(),"restore exactly includes spent mana and RNG")
	var legacy: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,Sm2AiContentLoader.load_profile().profile,store,false,c.effects)
	t.expect(not legacy.restore(runner.capture()).ok,"effects-only runner rejects magic")
	t.expect(not store.has_slot(Sm2BattleRunner.EFFECT_SLOT) and not store.has_slot(Sm2BattleRunner.SLOT),"legacy slots remain absent")
	command.kind = "end_turn"
	command.ability_id = ""
	command.target_actor_id = 0
	command.expected_revision = runner.view().revision
	cast = runner.execute_player(command)
	t.equal(restored.execute_player(command).events,cast.events,"same continuation command")
	history.append({"command":Sm2TacticalAi.command_data(command),"events":cast.events,"code":cast.code})
	for i: int in 30:
		if runner.view().finished or runner.view().active_actor_id == 2: break
		var a: Dictionary = runner.step()
		var z: Dictionary = restored.step()
		t.expect(a.ok and z.ok,"AI continues magic battle")
		t.equal(a,z,"AI continuation events equal")
		if a.has("command"): history.append(a)
	t.equal(restored.capture(),runner.capture(),"future state equal including round mana")
	var replay: Dictionary = Sm2BattleReplay.replay(c.catalog,c.combat,initial,history,c.effects,c.magic)
	t.expect(replay.ok,"magic command replay without AI")
	t.equal(replay.session,runner.capture().session,"magic replay state equal")
	var session: Sm2TacticalSession = Sm2TacticalSession.new(c.catalog,store,c.combat,true,c.effects,c.magic)
	t.expect(session.restore_payload(initial).ok and session.save_game().ok and session.has_save(),"standalone magic session slot consistent")
	t.expect(not store.has_slot("m4_effects_prototype"),"standalone session preserves effects slot")

static func _full_battle(t: Sm2TestHarness,c: Dictionary) -> void:
	var profile: Sm2AiProfile = Sm2AiContentLoader.load_profile().profile
	var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/m4_magic_full")
	var runner: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,profile,store,true,c.effects,c.magic)
	t.expect(runner.new_battle(c.setup).ok,"full authored magic battle starts")
	var initial: Dictionary = runner.capture().session
	var cmd: Sm2Command = Sm2Command.new()
	cmd.kind = "use_ability"
	cmd.ability_id = SPELL
	cmd.actor_id = 3
	cmd.target_actor_id = 4
	var cast: Sm2CommandResult = runner.execute_player(cmd)
	t.expect(cast.accepted,"full map starts with a player spell")
	var history: Array[Dictionary] = [{"command":Sm2TacticalAi.command_data(cmd),"events":cast.events,"code":cast.code}]
	t.expect(runner.save_game().ok,"full battle checkpoint after spell")
	var restored: Sm2BattleRunner = Sm2BattleRunner.new(c.catalog,c.combat,profile,store,true,c.effects,c.magic)
	t.expect(restored.load_game().ok,"full battle checkpoint loaded")
	var played: Dictionary = runner.run_to_end()
	var continued: Dictionary = restored.run_to_end()
	t.expect(played.ok and played.status == "finished","full 3v3 magic battle completes")
	t.equal(continued,played,"full battle loaded continuation matches")
	# Persist the replay contract, not AI diagnostic scores with non-string keys.
	for entry: Dictionary in played.history:
		history.append({"command":entry.command,"events":entry.events,"code":entry.code})
	var replay: Dictionary = Sm2BattleReplay.replay(c.catalog,c.combat,initial,history,c.effects,c.magic)
	t.expect(replay.ok,"full magic battle replay succeeds")
	t.equal(replay.session,runner.capture().session,"full magic replay final state exact")
	var saved_trace: Dictionary = store.save_slot({"initial":initial,"history":history,"final":runner.capture()},"trace")
	t.expect(saved_trace.ok,"full magic trace saved in test runtime: "+str(saved_trace.get("errors",[])))
