extends RefCounted
## Cross-layer tests use real commands, actual files, and fresh candidates.

static func run(t: Sm2TestHarness) -> void:
	var loaded: Dictionary = Sm2ContentLoader.load_catalog()
	t.expect(loaded.get("ok", false), "session: authored content loads")
	if not loaded.get("ok", false):
		return
	var catalog: Sm2Catalog = loaded["catalog"]
	t.equal(catalog.fingerprint(), Sm2TestFixtures.catalog().fingerprint(), "authored and pure fixtures match")
	var base: String = "user://tests/session_%s" % Time.get_ticks_usec()
	var store: Sm2SaveStore = Sm2SaveStore.new(base)
	var session: Sm2Session = Sm2Session.new(catalog, store)
	t.expect(not session.has_active_game(), "session starts closed")
	t.expect(not session.load_game().get("ok", false), "missing save refused")
	t.expect(not session.save_game().get("ok", false), "empty session cannot save")
	t.expect(not session.execute(Sm2Command.new()).accepted, "closed session cannot execute")
	t.expect(session.new_game().get("ok", false), "new game builds complete candidate")
	t.expect(not session.settle_battle(0).get("ok", false), "unfinished outcome cannot settle")
	var poison: Sm2Command = _command(session, "use_ability", "core:ability.venom", 2)
	t.expect(session.execute(poison).accepted, "poison accepted through application")
	t.expect(session.save_game().get("ok", false), "save with live poison")
	var restored: Sm2Session = Sm2Session.new(catalog, store)
	t.expect(restored.load_game().get("ok", false), "fresh session restores poison snapshot")
	t.equal(session.state_hash(), restored.state_hash(), "exact state after JSON disk roundtrip")
	var end_turn: Sm2Command = _command(session, "end_turn")
	_compare_step(t, session, restored, end_turn, "first poison activation")
	t.equal(_actor(session.view(), 2).get("hp"), 11, "poison ticks on restored carrier activation")
	_compare_step(t, session, restored, _command(session, "end_turn"), "opponent ends turn")
	var summon: Sm2Command = _command(session, "use_ability", "core:ability.summon", 0, Vector2i(1, 2))
	_compare_step(t, session, restored, summon, "summon after roundtrip")
	t.equal(session.view()["actors"].size(), 3, "summon adds actual actor")
	t.expect(session.save_game().get("ok", false), "summon identity and queue save")
	var after_summon: Sm2Session = Sm2Session.new(catalog, store)
	t.expect(after_summon.load_game().get("ok", false), "summoned actor restored")
	t.equal(session.state_hash(), after_summon.state_hash(), "summon state exactly preserved")
	for index: int in range(6):
		_compare_step(t, session, after_summon, _command(session, "end_turn"), "queue continuation %s" % index)
	var before: String = session.state_hash()
	var detached: Dictionary = session.capture()
	detached["campaign"]["applied_encounters"].append("alien")
	t.equal(session.state_hash(), before, "nested session snapshot detached")
	var invalid: Dictionary = session.capture()
	invalid["campaign"]["revision"] = "01"
	t.expect(not session.restore_payload(invalid).get("ok", false), "bad campaign candidate refused")
	t.equal(session.state_hash(), before, "bad second half leaves battle and campaign unchanged")
	invalid = session.capture()
	invalid["battle"]["extra_unknown_field"] = true
	t.expect(not session.restore_payload(invalid).get("ok", false), "bad battle candidate refused")
	t.equal(session.state_hash(), before, "bad battle leaves complete active session")
	invalid = session.capture()
	invalid["catalog"] = "unknown"
	t.expect(not session.restore_payload(invalid).get("ok", false), "changed content fingerprint refused")
	t.equal(session.state_hash(), before, "incompatible content keeps active session")
	invalid = session.capture()
	invalid["campaign"] = {"revision":"1", "reward_total":"10", "applied_encounters":[session.view()["battle_id"]]}
	t.expect(not session.restore_payload(invalid).get("ok", false), "unfinished battle cannot already be settled")
	t.equal(session.state_hash(), before, "cross-layer invalid candidate keeps session")
	# Envelope is valid but game data is not: loading must still preserve the live game.
	t.expect(store.save_slot(invalid).get("ok", false), "storage accepts structurally safe domain-invalid payload")
	t.expect(not session.load_game().get("ok", false), "application validates beyond envelope checksum")
	t.equal(session.state_hash(), before, "invalid disk candidate does not replace active game")
	_lifetime(t, catalog, base)
	_outcome_once(t, catalog, base + "_outcome")
	_extend_by_data(t)
	_external_catalog_isolation(t, base + "_catalog")
	var ledger: Sm2OutcomeLedger = Sm2OutcomeLedger.new()
	t.expect(not ledger.restore({"revision":"0", "reward_total":"1", "applied_encounters":[]}), "empty outcome history cannot contain rewards")
	t.complete_suite("scenario")

static func _external_catalog_isolation(t: Sm2TestHarness, base: String) -> void:
	var catalog: Sm2Catalog = Sm2TestFixtures.catalog()
	var session: Sm2Session = Sm2Session.new(catalog, Sm2SaveStore.new(base))
	t.expect(session.new_game().get("ok", false), "isolated catalog session starts")
	var before: String = session.state_hash()
	var replacement: Dictionary = Sm2TestFixtures.raw_catalog()
	replacement["version"] = "test.changed.externally"
	t.expect(catalog.build(replacement).is_empty(), "external catalog rebuilt")
	t.equal(session.state_hash(), before, "external catalog mutation cannot change existing session")
	t.expect(session.save_game().get("ok", false), "isolated catalog still saves")
	t.expect(session.load_game().get("ok", false), "isolated catalog still restores")
	t.equal(session.state_hash(), before, "catalog isolated disk roundtrip")

static func _outcome_once(t: Sm2TestHarness, catalog: Sm2Catalog, base: String) -> void:
	var storage: Sm2SaveStore = Sm2SaveStore.new(base)
	var session: Sm2Session = Sm2Session.new(catalog, storage)
	t.expect(session.new_game(12345).get("ok", false), "settlement game starts")
	var steps: int = 0
	while not session.view().get("finished", false) and steps < 40:
		var state: Dictionary = session.view()
		var action: Sm2Command = _command(session, "end_turn")
		if state["active_actor_id"] == 1:
			var strike: Sm2Command = _command(session, "use_ability", "core:ability.strike", 2)
			if session.preview(strike).get("allowed", false):
				action = strike
		t.expect(session.execute(action).accepted, "settlement battle step %s" % steps)
		steps += 1
	t.expect(session.view().get("finished", false), "real commands finish battle")
	t.equal(session.view().get("winner"), "company", "fixture victory belongs to company")
	t.expect(not session.settle_battle(8).get("ok", false), "stale campaign revision rejected")
	t.expect(session.settle_battle(0).get("ok", false), "completed result applied once")
	t.equal(session.capture()["campaign"]["reward_total"], "10", "fixture reward granted exactly once")
	var committed: String = session.state_hash()
	t.expect(not session.settle_battle(1).get("ok", false), "repeat result rejected at current revision")
	t.equal(session.state_hash(), committed, "duplicate outcome has no side effects")
	t.expect(session.save_game().get("ok", false), "save settled outcome")
	var restored: Sm2Session = Sm2Session.new(catalog, storage)
	t.expect(restored.load_game().get("ok", false), "restore settled outcome")
	t.equal(restored.state_hash(), committed, "campaign reward and receipt persist")
	t.expect(not restored.settle_battle(1).get("ok", false), "reload cannot grant duplicate reward")
	t.equal(restored.state_hash(), committed, "reload duplicate stays unchanged")

static func _extend_by_data(t: Sm2TestHarness) -> void:
	var raw: Dictionary = Sm2TestFixtures.raw_catalog()
	raw["version"] = "test.expansion.1"
	raw["weapons"].append({"id":"test:weapon.crystal", "name":"Кристалл", "damage_min":8, "damage_max":8, "durability":40})
	raw["statuses"].append({"id":"test:status.ember", "name":"Тление", "tick_damage":2, "duration":3})
	raw["actors"].append({"id":"test:actor.elemental", "name":"Элементаль", "hp":7, "ap":3, "max_fatigue":12, "initiative":5, "weapon_id":"test:weapon.crystal", "abilities":["core:ability.strike"], "immunities":["test:status.ember"]})
	raw["abilities"].append({"id":"test:ability.call_elemental", "name":"Вызов элементаля", "operation":"summon", "ap_cost":2, "fatigue_cost":1, "range":1, "damage_bonus":0, "status_id":"", "summon_template_id":"test:actor.elemental"})
	raw["abilities"].append({"id":"test:ability.ember", "name":"Тление", "operation":"status", "ap_cost":2, "fatigue_cost":1, "range":1, "damage_bonus":0, "status_id":"test:status.ember", "summon_template_id":""})
	raw["actors"][0]["weapon_id"] = "test:weapon.crystal"
	raw["actors"][0]["abilities"].append("test:ability.call_elemental")
	raw["actors"][0]["abilities"].append("test:ability.ember")
	var catalog: Sm2Catalog = Sm2Catalog.new()
	t.expect(catalog.build(raw).is_empty(), "new content definitions validate without engine edits")
	var battle: Sm2BattleEngine = Sm2BattleEngine.new(catalog)
	t.expect(battle.start(Sm2TestFixtures.setup()).get("ok", false), "expanded content battle starts")
	t.expect(battle.execute(Sm2TestFixtures.command("use_ability", 1, battle.view()["revision"], "core:ability.strike", 2)).accepted, "new weapon uses common attack")
	t.equal(_actor(battle.view(), 2).get("hp"), 4, "new weapon damage read from content")
	t.expect(battle.execute(Sm2TestFixtures.command("use_ability", 1, battle.view()["revision"], "test:ability.call_elemental", 0, Vector2i(1, 2))).accepted, "new summon ability uses registered operation")
	t.equal(_actor(battle.view(), 3).get("template_id"), "test:actor.elemental", "new template creates actual summoned actor")
	t.equal(_actor(battle.view(), 3).get("hp_max"), 7, "new actor stats loaded from definition")
	# A separate start tests the new periodic effect with its own parameters.
	t.expect(battle.start(Sm2TestFixtures.setup()).get("ok", false), "expanded status scenario starts")
	t.expect(battle.execute(Sm2TestFixtures.command("use_ability", 1, battle.view()["revision"], "test:ability.ember", 2)).accepted, "new status ability accepted")
	t.expect(battle.execute(Sm2TestFixtures.command("end_turn", 1, battle.view()["revision"])).accepted, "carrier activation follows")
	t.equal(_actor(battle.view(), 2).get("hp"), 10, "new periodic damage uses definition")

static func _lifetime(t: Sm2TestHarness, catalog: Sm2Catalog, base: String) -> void:
	var candidate: Sm2Session = Sm2Session.new(catalog, Sm2SaveStore.new(base))
	candidate.new_game()
	var reference: WeakRef = weakref(candidate)
	candidate = null
	t.expect(reference.get_ref() == null, "session released without reference cycle")

static func _compare_step(t: Sm2TestHarness, left: Sm2Session, right: Sm2Session, command: Sm2Command, label: String) -> void:
	var a: Sm2CommandResult = left.execute(command)
	var b: Sm2CommandResult = right.execute(command)
	t.expect(a.accepted and b.accepted, label + ": accepted both")
	t.equal(Sm2Canonical.hash(a.events), Sm2Canonical.hash(b.events), label + ": event equality")
	t.equal(left.state_hash(), right.state_hash(), label + ": exact hash equality")

static func _command(session: Sm2Session, kind: String, ability: String = "", target_id: int = 0, tile: Vector2i = Vector2i.ZERO) -> Sm2Command:
	var state: Dictionary = session.view()
	return Sm2TestFixtures.command(kind, state["active_actor_id"], state["revision"], ability, target_id, tile)

static func _actor(view: Dictionary, actor_id: int) -> Dictionary:
	for actor: Dictionary in view.get("actors", []):
		if actor.get("actor_id") == actor_id:
			return actor
	return {}
