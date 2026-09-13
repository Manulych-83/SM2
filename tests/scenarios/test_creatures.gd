extends RefCounted
const PATROL: String = "creatures:encounter.patrol"
const SENTRY: String = "creatures:encounter.sentry"

static func run(t: Sm2TestHarness) -> void:
	var c: Dictionary = Sm2CreatureContentLoader.load_catalog()
	t.expect(c.ok,"authored creature packages load: "+str(c.get("errors",[])))
	if not c.ok: return
	_validation(t,c)
	_runtime(t,c)
	_scale(t,c)
	_full(t,c)
	t.complete_suite("creatures")

static func _rebuild(catalog: Sm2CreatureCatalog,raw: Dictionary,c: Dictionary) -> PackedStringArray:
	var base: Dictionary = Sm2EffectSequenceContentLoader.load_scenario()
	var visuals: Array[String] = []; visuals.assign(c.visuals.keys())
	return catalog.build(raw,base.catalog,base.combat,base.effects,{"ruins":base.setup.field},visuals)

static func _validation(t: Sm2TestHarness,c: Dictionary) -> void:
	var catalog: Sm2CreatureCatalog = c.catalog
	var hash_before: String = catalog.fingerprint()
	for defect: String in ["version","duplicate","profile","body","parameter","gear","slot","action","immunity","resistance","appearance","behavior","field","actor","template","position","blocked","side","empty","limit"]:
		var raw: Dictionary = catalog.to_data()
		var definition: Dictionary = raw.templates[0]
		var meeting: Dictionary = raw.encounters[0]
		match defect:
			"version": raw.version = "unsupported"
			"duplicate": raw.templates.append(definition.duplicate(true))
			"profile": definition.profile_id = "missing"
			"body": raw.profiles[0].combat.body_id = "missing"
			"parameter": raw.profiles[0].turn.ap_max = 1.5
			"gear": definition.equipment_ids.append("missing")
			"slot": definition.equipment_ids.append("m2:equipment.sword")
			"action": definition.actions.append("missing")
			"immunity": definition.immunities = [123]
			"resistance": definition.resistances.poison = 101
			"appearance": definition.appearance_id = "missing"
			"behavior": definition.behavior_id = "future_policy"
			"field": meeting.field_id = "missing"
			"actor": meeting.actors[1].actor_id = meeting.actors[0].actor_id
			"template": meeting.actors[0].template_id = "missing"
			"position": meeting.actors[1].q = meeting.actors[0].q; meeting.actors[1].r = meeting.actors[0].r
			"blocked": meeting.actors[0].q = 63
			"side": meeting.actors[0].controller = "ai"
			"empty": meeting.actors = []
			"limit":
				while meeting.actors.size() <= 64: meeting.actors.append(meeting.actors[0].duplicate(true))
		t.expect(not _rebuild(catalog,raw,c).is_empty(),"invalid authoring rejected: "+defect)
		t.equal(catalog.fingerprint(),hash_before,"invalid build preserves live catalog")
	var detached: Dictionary = catalog.definition("creatures:type.raider")
	detached.equipment_ids.clear()
	t.expect(not catalog.definition("creatures:type.raider").equipment_ids.is_empty(),"definition nested fields detached")
	var altered: Dictionary = catalog.encounter(PATROL); altered.actors.clear()
	t.equal(catalog.encounter(PATROL).actors.size(),5,"encounter detached")
	t.expect(not catalog.compile("missing").ok,"unknown encounter fails")
	var raw: Dictionary = catalog.to_data()
	raw.templates.reverse(); raw.profiles.reverse(); raw.encounters.reverse()
	for meeting: Dictionary in raw.encounters: meeting.actors.reverse()
	var equivalent: Sm2CreatureCatalog = Sm2CreatureCatalog.new()
	t.expect(_rebuild(equivalent,raw,c).is_empty(),"reordered catalog valid")
	t.equal(equivalent.fingerprint(),hash_before,"non-semantic authoring order normalized")

static func _runtime(t: Sm2TestHarness,c: Dictionary) -> void:
	var compiled: Dictionary = c.catalog.compile(PATROL)
	t.expect(compiled.ok,"patrol compiles")
	t.equal(compiled.setup.actors.size(),5,"variable encounter count from data")
	t.equal(compiled.catalog.to_data().loadouts.size(),4,"two instances share one template loadout")
	var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/creatures/patrol")
	var runner: Sm2CreatureBattleRunner = Sm2CreatureBattleRunner.new(compiled,c.profile,store,false,c.visuals)
	t.expect(runner.new_battle(compiled.setup).ok,"template battle starts")
	var view: Dictionary = runner.view()
	t.equal(Sm2CombatFixtures.actor(view,1).display_name,"Следопыт","name from definition")
	t.equal(Sm2CombatFixtures.actor(view,1).hp_max,45,"archer own HP profile")
	t.equal(Sm2CombatFixtures.actor(view,2).hp_max,80,"guard different HP profile")
	t.equal(Sm2CombatFixtures.actor(view,3).hp_max,55,"raider own HP profile")
	t.equal(Sm2CombatFixtures.actor(view,3).template_id,Sm2CombatFixtures.actor(view,4).template_id,"two raiders have same type")
	var first: Dictionary = Sm2BattleText.item(Sm2CombatFixtures.actor(view,3),"weapon")
	var second: Dictionary = Sm2BattleText.item(Sm2CombatFixtures.actor(view,4),"weapon")
	t.expect(first.item_id != second.item_id,"same gear definition gets unique physical battle IDs")
	# Damage is applied to a decoded actual battle state, then validated through runner restore.
	var snapshot: Dictionary = runner.capture()
	var decoded: Dictionary = Sm2EffectSnapshot.decode(snapshot.session.battle,compiled.catalog,compiled.combat,compiled.effects)
	t.expect(decoded.ok,"compiled snapshot decodes")
	var events: Array[Dictionary] = []
	Sm2HpApplication.apply(decoded.state,decoded.state.actor(3),1,7,events)
	snapshot.session.battle = decoded.state.to_data(compiled.catalog.fingerprint())
	t.expect(runner.restore(snapshot).ok,"damaged instance restores")
	t.equal(Sm2CombatFixtures.actor(runner.view(),3).combat.hp,48,"first instance damaged")
	t.equal(Sm2CombatFixtures.actor(runner.view(),4).combat.hp,55,"second instance untouched")
	t.equal(c.catalog.to_data().profiles.filter(func(p: Dictionary) -> bool: return p.id == "creatures:profile.raider")[0].combat.hp_max,55,"definition not damaged")
	var cmd: Sm2Command = Sm2Command.new()
	cmd.kind = "use_ability"; cmd.actor_id = 1; cmd.target_actor_id = 3; cmd.ability_id = "m2:ability.bow_shot"; cmd.expected_revision = runner.view().revision
	var before: String = runner.state_hash()
	t.expect(runner.preview(cmd).allowed,"template weapon uses existing action")
	t.equal(runner.state_hash(),before,"preview inert")
	t.expect(runner.execute_player(cmd).accepted,"actual weapon command")
	t.expect(runner.save_game().ok,"new mode writes slot")
	var fresh: Sm2CreatureBattleRunner = Sm2CreatureBattleRunner.new(compiled,c.profile,store,false,c.visuals)
	t.expect(fresh.load_game().ok,"fresh runner loads")
	t.equal(fresh.capture(),runner.capture(),"load no ticks or duplicated instances")
	t.equal(fresh.view(),runner.view(),"derived template names/visuals restored")
	t.equal(runner.copy().view(),runner.view(),"runner copy preserves read model")
	var saved: Dictionary = runner.capture()
	for defect: String in ["identity","loadout","side","count"]:
		var bad: Dictionary = saved.duplicate(true)
		match defect:
			"identity": bad.session.battle.actors[0].actor_id = "20"
			"loadout": bad.session.battle.actors[0].loadout_id = bad.session.battle.actors[1].loadout_id
			"side": bad.session.battle.actors[0].side = "opposition"
			"count": bad.session.battle.actors.pop_back()
		t.expect(not runner.restore(bad).ok,"template binding protected: "+defect)
		t.equal(runner.capture(),saved,"failed binding restore atomic")
	var other: Dictionary = c.catalog.compile(SENTRY)
	var wrong: Sm2CreatureBattleRunner = Sm2CreatureBattleRunner.new(other,c.profile,store,false,c.visuals)
	t.expect(not wrong.load_game().ok,"other encounter cannot reinterpret save")
	var raw: Dictionary = c.catalog.to_data(); raw.templates[0].name = "Изменённое имя"
	var changed: Sm2CreatureCatalog = Sm2CreatureCatalog.new(); t.expect(_rebuild(changed,raw,c).is_empty(),"changed catalog valid")
	wrong = Sm2CreatureBattleRunner.new(changed.compile(PATROL),c.profile,store,false,c.visuals)
	t.expect(not wrong.load_game().ok,"content fingerprint remains strict")

static func _scale(t: Sm2TestHarness,c: Dictionary) -> void:
	var raw: Dictionary = c.catalog.to_data()
	while raw.templates.size() < 3000:
		var definition: Dictionary = raw.templates[0].duplicate(true)
		definition.id = "creatures:type.generated_%s" % raw.templates.size()
		if raw.profiles.size() < 3000:
			var profile: Dictionary = raw.profiles[0].duplicate(true)
			profile.id = "creatures:profile.generated_%s" % raw.templates.size()
			profile.combat.hp_max = 30+raw.templates.size()%100
			raw.profiles.append(profile); definition.profile_id = profile.id
		raw.templates.append(definition)
	var catalog: Sm2CreatureCatalog = Sm2CreatureCatalog.new()
	var started: int = Time.get_ticks_usec()
	t.expect(_rebuild(catalog,raw,c).is_empty(),"3000 definitions and every link validate")
	var build_ms: float = (Time.get_ticks_usec()-started)/1000.0
	t.equal(catalog.count(),3000,"all definitions indexed")
	started = Time.get_ticks_usec()
	var compiled: Dictionary = catalog.compile(PATROL)
	var compile_ms: float = (Time.get_ticks_usec()-started)/1000.0
	t.expect(compiled.ok,"large catalog selected encounter compiles")
	t.equal(compiled.catalog.to_data().loadouts.size(),4,"only four used types in runtime catalog")
	t.equal(compiled.catalog.to_data().profiles.size(),3,"only three referenced parameter profiles")
	var runner: Sm2CreatureBattleRunner = Sm2CreatureBattleRunner.new(compiled,c.profile,Sm2SaveStore.new("user://tests/creatures/large"),false,c.visuals)
	t.expect(runner.new_battle(compiled.setup).ok,"real battle from3000")
	t.equal(runner.view().actors.size(),5,"definitions not spawned as instances")
	t.expect(runner.save_game().ok and runner.load_game().ok,"3000 catalog real save/load")
	# The final synthetic definition also works when explicitly referenced by a spawn.
	raw.encounters[0].actors[0].template_id = raw.templates[-1].id
	t.expect(_rebuild(catalog,raw,c).is_empty(),"last generated definition referenced")
	compiled = catalog.compile(PATROL)
	t.equal(compiled.bindings[1].template_id,raw.templates[-1].id,"no first-N template truncation")
	var oversized: Dictionary = raw.duplicate(true); var extra: Dictionary = raw.templates[0].duplicate(true); extra.id = "one_too_many"; oversized.templates.append(extra)
	t.expect(not _rebuild(catalog,oversized,c).is_empty(),"explicit template cap")
	DirAccess.make_dir_recursive_absolute("res://outputs/creatures-1")
	var file: FileAccess = FileAccess.open("res://outputs/creatures-1/scale.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"types":3000,"active_types":4,"actors":5,"validation_ms":build_ms,"selected_compile_ms":compile_ms,"scope":"one local sample; validation includes loading small base content, not full world acceptance"},"\t")); file.close()

static func _full(t: Sm2TestHarness,c: Dictionary) -> void:
	var compiled: Dictionary = c.catalog.compile(PATROL)
	var store: Sm2SaveStore = Sm2SaveStore.new("user://tests/creatures/full")
	var runner: Sm2CreatureBattleRunner = Sm2CreatureBattleRunner.new(compiled,c.profile,store,true,c.visuals)
	t.expect(runner.new_battle(compiled.setup).ok,"selfplay fixture starts")
	var initial: Dictionary = runner.capture().session
	var history: Array[Dictionary] = []
	for i: int in 5:
		var step: Dictionary = runner.step(); t.expect(step.ok,"template AI opening command")
		if step.has("command"): history.append({"command":step.command,"events":step.events,"code":step.code})
	t.expect(runner.save_game().ok,"active template battle saves")
	var restored: Sm2CreatureBattleRunner = Sm2CreatureBattleRunner.new(compiled,c.profile,store,true,c.visuals)
	t.expect(restored.load_game().ok,"active battle loads")
	var end: Dictionary = runner.run_to_end(2000)
	var continuation: Dictionary = restored.run_to_end(2000)
	t.expect(end.ok and end.status == "finished","five actor template battle completes")
	t.expect(runner.view().round < 100,"battle not a round-limit stalemate")
	t.equal(continuation,end,"loaded AI decisions and events exact")
	var retries: int = 0
	for entry: Dictionary in end.history:
		retries += int(entry.retries)
		history.append({"command":entry.command,"events":entry.events,"code":entry.code})
	t.equal(retries,0,"no illegal AI action retries")
	var replay: Dictionary = Sm2BattleReplay.replay(compiled.catalog,compiled.combat,initial,history,compiled.effects)
	t.expect(replay.ok,"existing replay understands compiled templates")
	t.equal(replay.session,runner.capture().session,"replayed final state exact")
