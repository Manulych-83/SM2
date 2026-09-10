class_name Sm2TestDomain
extends RefCounted

static func run(t: Sm2TestHarness) -> void:
	_catalog(t)
	_rng(t)
	_start_and_isolation(t)
	_rejected_commands(t)
	_strike_and_victory(t)
	_summoning(t)
	_poison(t)
	_snapshots(t)
	_content_extension(t)
	t.complete_suite("unit")

static func _catalog(t: Sm2TestHarness) -> void:
	var raw: Dictionary = Sm2TestFixtures.raw_catalog()
	var catalog: Sm2Catalog = Sm2Catalog.new()
	t.equal(catalog.build(raw).size(), 0, "catalog accepts complete fixture")
	var fingerprint: String = catalog.fingerprint()
	raw.actors[0].hp = 999
	t.equal(catalog.actor("core:actor.vanguard").hp, 12, "raw mutation does not change catalog")
	var definition: Sm2ActorDefinition = catalog.actor("core:actor.vanguard")
	definition.hp = 888
	definition.abilities.clear()
	t.equal(catalog.actor("core:actor.vanguard").hp, 12, "definition accessor returns independent object")
	t.equal(catalog.actor("core:actor.vanguard").abilities.size(), 3, "definition lists are independent")
	var data: Dictionary = catalog.to_data()
	data.weapons.clear()
	t.expect(catalog.has_weapon("core:weapon.practice_blade"), "catalog export detached")
	t.equal(catalog.actor("absent"), null, "unknown actor gives null")
	t.equal(catalog.weapon("absent"), null, "unknown weapon gives null")
	t.equal(catalog.ability("absent"), null, "unknown ability gives null")
	t.equal(catalog.status("absent"), null, "unknown status gives null")
	var bad: Array[Dictionary] = []
	data = Sm2TestFixtures.raw_catalog()
	data.actors[0].hp = 1.5
	bad.append(data)
	data = Sm2TestFixtures.raw_catalog()
	data.actors[0].weapon_id = "core:ability.strike"
	bad.append(data)
	data = Sm2TestFixtures.raw_catalog()
	data.abilities[0].operation = "unknown"
	bad.append(data)
	data = Sm2TestFixtures.raw_catalog()
	data.abilities[1].status_id = "missing"
	bad.append(data)
	data = Sm2TestFixtures.raw_catalog()
	data.abilities[2].summon_template_id = "core:weapon.practice_blade"
	bad.append(data)
	data = Sm2TestFixtures.raw_catalog()
	data.actors[0].immunities = ["core:ability.strike"]
	bad.append(data)
	data = Sm2TestFixtures.raw_catalog()
	data.weapons[0].damage_max = 1
	bad.append(data)
	data = Sm2TestFixtures.raw_catalog()
	data.actors.append(data.actors[0].duplicate(true))
	bad.append(data)
	data = Sm2TestFixtures.raw_catalog()
	data.statuses[0].erase("duration")
	bad.append(data)
	data = Sm2TestFixtures.raw_catalog()
	data.abilities[0].status_id = "core:status.poison"
	bad.append(data)
	data = Sm2TestFixtures.raw_catalog()
	data.actors[0].abilities = ["core:ability.strike", "core:ability.strike"]
	bad.append(data)
	data = Sm2TestFixtures.raw_catalog()
	data.weapons[0].durability = true
	bad.append(data)
	data = Sm2TestFixtures.raw_catalog()
	data.actors[0].hp = "12"
	bad.append(data)
	for index: int in bad.size():
		t.expect(not catalog.build(bad[index]).is_empty(), "reject malformed catalog %d" % index)
		t.equal(catalog.fingerprint(), fingerprint, "bad catalog never publishes partially %d" % index)
	var reordered: Dictionary = Sm2TestFixtures.raw_catalog()
	reordered.actors.reverse()
	reordered.weapons.reverse()
	var second: Sm2Catalog = Sm2Catalog.new()
	t.equal(second.build(reordered).size(), 0, "reordered catalog valid")
	t.equal(second.fingerprint(), fingerprint, "definition order canonicalized")
	reordered.version = "new.version"
	second.build(reordered)
	t.expect(second.fingerprint() != fingerprint, "version metadata in fingerprint")

static func _rng(t: Sm2TestHarness) -> void:
	var rng: Sm2DeterministicRng = Sm2DeterministicRng.new(1)
	for expected: int in [48271, 182605794, 1291394886, 1914720637, 2078669041]:
		t.equal(rng.next_value(), expected, "Park-Miller published vector")
	t.equal(rng.draws, 5, "draw count retained")
	rng = Sm2DeterministicRng.new(1)
	t.equal(rng.range_inclusive(3, 5), 3, "bounded RNG vector 1")
	t.equal(rng.range_inclusive(3, 5), 5, "bounded RNG vector 2")
	t.equal(rng.range_inclusive(3, 5), 5, "bounded RNG vector 3")
	rng = Sm2DeterministicRng.new(182605794)
	# Next three raw values exceed the acceptance cutoff of this broad range.
	var broad: int = rng.range_inclusive(0, 1073741823)
	t.expect(broad >= 0 and broad <= 1073741823, "rejection sampler bounded result")
	t.expect(rng.draws > 1, "rejection sampler discards biased tail")
	var first: Sm2DeterministicRng = Sm2DeterministicRng.new(-9223372036854775807)
	var second: Sm2DeterministicRng = Sm2DeterministicRng.new(-9223372036854775807)
	for index: int in 32:
		t.equal(first.range_inclusive(0, 100), second.range_inclusive(0, 100), "negative seed deterministic %d" % index)
	t.equal(Sm2DeterministicRng.new(77).range_inclusive(4, 4), 4, "single value range")
	t.equal(Sm2Canonical.hash({"b": [2.0], "a": 1}), Sm2Canonical.hash({"a": 1.0, "b": [2]}), "canonical key order and JSON numeric roundtrip")
	t.expect(not Sm2Canonical.is_json_safe({"object": Sm2Command.new()}), "objects not JSON-safe")
	t.expect(not Sm2Canonical.is_json_safe({"bad": INF}), "nonfinite floats not JSON-safe")

static func _start_and_isolation(t: Sm2TestHarness) -> void:
	var catalog: Sm2Catalog = Sm2TestFixtures.catalog()
	var engine: Sm2BattleEngine = Sm2BattleEngine.new(catalog)
	var setup: Dictionary = Sm2TestFixtures.setup(1)
	t.expect(engine.start(setup).ok, "start fixture")
	t.equal(engine.view().active_actor_id, 1, "initiative chooses vanguard first")
	t.equal(engine.view().actors[1].actor_id, 2, "initial actor IDs deterministic")
	var before: String = engine.state_hash()
	setup.actors[0].q = 5
	var visible: Dictionary = engine.view()
	visible.actors[0].hp = 0
	visible.actors[0].abilities.clear()
	var snapshot: Dictionary = engine.capture()
	snapshot.actors[0].weapon.durability = 0
	snapshot.queue.clear()
	snapshot.sides.clear()
	var outcome: Dictionary = engine.outcome()
	outcome.participants[0].hp = 0
	t.equal(engine.state_hash(), before, "setup/view/snapshot/outcome never alias live graph")
	var raw: Dictionary = Sm2TestFixtures.raw_catalog()
	raw.actors[0].hp = 100
	catalog.build(raw)
	t.equal(engine.view().actors[0].hp_max, 12, "engine owns isolated catalog revision")
	var broken: Dictionary = Sm2TestFixtures.setup()
	broken.actors[1].q = 1
	t.expect(not engine.start(broken).ok, "start rejects duplicate hex")
	t.equal(engine.state_hash(), before, "failed start preserves prior battle")
	broken = Sm2TestFixtures.setup()
	broken.actors[0].q = 1.25
	t.expect(not engine.start(broken).ok, "start rejects fractional coordinate")
	broken = Sm2TestFixtures.setup()
	broken.actors[0].template_id = "unknown"
	t.expect(not engine.start(broken).ok, "start rejects missing template")
	broken = Sm2TestFixtures.setup()
	broken.actors[1].side = "company"
	t.expect(not engine.start(broken).ok, "start rejects one side")
	t.equal(engine.state_hash(), before, "all failed starts preserve state")
	var second: Sm2BattleEngine = _engine(t, 1)
	_take(t, engine, "use_ability", "core:ability.strike", 2)
	t.equal(second.state_hash(), before, "separate battle instances do not share state")
	t.equal(engine.view().actors[1].durability, 20, "same-definition weapons have separate wear")
	t.equal(engine.view().actors[0].durability, 19, "attacker weapon wear stored per item")

static func _rejected_commands(t: Sm2TestHarness) -> void:
	var engine: Sm2BattleEngine = _engine(t)
	var commands: Array[Sm2Command] = [
		Sm2TestFixtures.command("move", 2, 0, "", 0, Vector2i(3, 1)),
		Sm2TestFixtures.command("move", 1, 99, "", 0, Vector2i(0, 1)),
		Sm2TestFixtures.command("move", 1, 0, "", 0, Vector2i(-1, 1)),
		Sm2TestFixtures.command("move", 1, 0, "", 0, Vector2i(2, 1)),
		Sm2TestFixtures.command("move", 1, 0, "", 0, Vector2i(5, 3)),
		Sm2TestFixtures.command("teleport", 1, 0),
		Sm2TestFixtures.command("use_ability", 1, 0, "missing", 2),
		Sm2TestFixtures.command("use_ability", 1, 0, "core:ability.strike", 1),
		Sm2TestFixtures.command("use_ability", 1, 0, "core:ability.strike", 999),
		Sm2TestFixtures.command("use_ability", 1, 0, "core:ability.summon", 0, Vector2i(2, 1)),
		Sm2TestFixtures.command("use_ability", 1, 0, "core:ability.summon", 0, Vector2i(5, 3)),
		Sm2TestFixtures.command("use_ability", 1, 0, "core:ability.summon", 2, Vector2i(0, 1))]
	for index: int in commands.size():
		_rejected(t, engine, commands[index], "invalid command %d" % index)
	_rejected(t, engine, null, "null command")
	var command: Sm2Command = _command(engine, "use_ability", "core:ability.strike", 2)
	var before: String = engine.state_hash()
	for index: int in 20:
		var preview: Dictionary = engine.preview(command)
		t.expect(preview.allowed, "valid pure preview %d" % index)
		preview.damage_max = 999
	t.equal(engine.state_hash(), before, "repeated previews leave RNG, IDs, state untouched")
	t.equal(engine.preview(command).damage_max, 5, "preview dictionary detached")
	_take(t, engine, "use_ability", "core:ability.strike", 2)
	_take(t, engine, "use_ability", "core:ability.strike", 2)
	_rejected(t, engine, _command(engine, "move", "", 0, Vector2i(0, 1)), "AP exhaustion")
	engine = _engine(t)
	var snapshot: Dictionary = engine.capture()
	snapshot.actors[0].fatigue = 20
	t.expect(engine.restore(snapshot).ok, "restore fatigue-limit state")
	_rejected(t, engine, _command(engine, "use_ability", "core:ability.strike", 2), "fatigue limit")
	snapshot.actors[0].fatigue = 0
	snapshot.actors[0].weapon.durability = 0
	t.expect(engine.restore(snapshot).ok, "restore broken item")
	_rejected(t, engine, _command(engine, "use_ability", "core:ability.strike", 2), "broken weapon")
	engine = _engine(t)
	_take(t, engine, "move", "", 0, Vector2i(0, 1))
	_rejected(t, engine, _command(engine, "use_ability", "core:ability.strike", 2), "attack out of range")
	t.equal(engine.view().actors[0].ap, 3, "movement AP cost")
	t.equal(engine.view().actors[0].fatigue, 1, "movement fatigue cost")

static func _strike_and_victory(t: Sm2TestHarness) -> void:
	var engine: Sm2BattleEngine = _engine(t, 1)
	var control: Sm2BattleEngine = _engine(t, 1)
	var strike: Sm2Command = _command(engine, "use_ability", "core:ability.strike", 2)
	engine.preview(strike)
	var result: Sm2CommandResult = engine.execute(strike)
	t.expect(result.accepted, "first strike accepted")
	t.equal(engine.view().actors[1].hp, 9, "first fixed-seed damage vector")
	t.equal(engine.view().actors[0].ap, 2, "strike AP cost")
	t.equal(engine.view().actors[0].fatigue, 3, "strike fatigue cost")
	t.equal(result.revision, 1, "one revision per accepted command")
	control.execute(strike)
	t.equal(engine.state_hash(), control.state_hash(), "preview did not change actual roll")
	result.events[0].amount = 999
	t.equal(engine.state_hash(), control.state_hash(), "event mutation cannot change live state")
	_take(t, engine, "use_ability", "core:ability.strike", 2)
	t.equal(engine.view().actors[1].hp, 4, "second seeded strike")
	_take(t, engine, "end_turn")
	t.equal(engine.view().active_actor_id, 2, "end turn advances to opponent")
	_take(t, engine, "end_turn")
	t.equal(engine.view().round, 2, "round rolls over")
	t.equal(engine.view().actors[0].ap, 4, "AP restores at new activation")
	t.equal(engine.view().actors[0].fatigue, 4, "fatigue recovers by two")
	result = _take(t, engine, "use_ability", "core:ability.strike", 2)
	t.equal(result.events[0].amount, 4, "overkill truncated to remaining HP")
	var death_count: int = 0
	for event: Dictionary in result.events:
		if event.type == "death":
			death_count += 1
	t.equal(death_count, 1, "death emitted exactly once")
	t.expect(engine.outcome().finished, "battle finished")
	t.equal(engine.outcome().winner, "company", "correct winner")
	t.equal(engine.view().active_actor_id, 0, "finished battle has no active actor")
	_rejected(t, engine, _command(engine, "end_turn"), "commands rejected after victory")
	var restored: Sm2BattleEngine = _engine(t)
	t.expect(restored.restore(engine.capture()).ok, "finished snapshot restores")
	t.equal(restored.state_hash(), engine.state_hash(), "finished state hash stable")

static func _summoning(t: Sm2TestHarness) -> void:
	var engine: Sm2BattleEngine = _engine(t)
	var before_rng: Dictionary = engine.capture().rng
	_take(t, engine, "use_ability", "core:ability.summon", 0, Vector2i(0, 1))
	t.equal(engine.view().actors.size(), 3, "summon adds separate participant")
	t.equal(engine.view().actors[2].actor_id, 3, "summon allocates next deterministic ID")
	t.equal(engine.view().actors[2].creator, 1, "summon records creator")
	t.equal(engine.view().actors[2].owner, "company", "summon owner retained")
	t.equal(engine.view().actors[2].controller, "player", "summon controller separate")
	t.equal(engine.view().actors[2].side, "company", "summon joins source side")
	t.equal(engine.capture().rng, before_rng, "summon does not consume damage RNG")
	t.equal(engine.capture().queue, ["1", "2"], "summon excluded from current round")
	var clone: Sm2BattleEngine = _engine(t)
	t.expect(clone.restore(engine.capture()).ok, "summoned graph restores")
	t.equal(clone.state_hash(), engine.state_hash(), "summoned graph snapshot identical")
	_take(t, engine, "end_turn")
	_take(t, engine, "end_turn")
	t.equal(engine.capture().queue, ["1", "2", "3"], "summon enters next round sorted by initiative")
	_take(t, engine, "end_turn")
	_take(t, engine, "end_turn")
	t.equal(engine.view().active_actor_id, 3, "summon receives own activation")
	t.equal(engine.view().actors[2].ap, 2, "summon uses own template AP")
	t.equal(clone.view().round, 1, "restored clone has independent mutable graph")
	t.equal(engine.capture().next_id, "4", "ID allocator persisted")

static func _poison(t: Sm2TestHarness) -> void:
	var engine: Sm2BattleEngine = _engine(t)
	_take(t, engine, "use_ability", "core:ability.venom", 2)
	t.equal(engine.view().actors[1].hp, 12, "poison does not tick on application")
	_take(t, engine, "use_ability", "core:ability.venom", 2)
	t.equal(engine.view().actors[1].effects.size(), 1, "poison reapplication refreshes one effect")
	t.equal(engine.view().actors[0].effects.size(), 0, "effect lists belong to each actor")
	_take(t, engine, "end_turn")
	t.equal(engine.view().actors[1].hp, 11, "poison first activation tick")
	t.equal(engine.view().actors[1].effects[0].remaining, 1, "poison duration decremented once")
	var clone: Sm2BattleEngine = _engine(t)
	t.expect(clone.restore(engine.capture()).ok, "mid-poison snapshot restores")
	_take(t, engine, "end_turn")
	_take(t, engine, "end_turn")
	t.equal(engine.view().actors[1].hp, 10, "poison second activation tick")
	t.equal(engine.view().actors[1].effects.size(), 0, "poison expires after two ticks")
	_take(t, clone, "end_turn")
	_take(t, clone, "end_turn")
	t.equal(engine.state_hash(), clone.state_hash(), "poison continuation deterministic after restore")
	engine = _engine(t)
	var snapshot: Dictionary = engine.capture()
	snapshot.actors[1].hp = 1
	t.expect(engine.restore(snapshot).ok, "restore near-death target")
	_take(t, engine, "use_ability", "core:ability.venom", 2)
	var result: Sm2CommandResult = _take(t, engine, "end_turn")
	t.expect(engine.view().finished, "poison death resolves victory before input")
	var deaths: int = 0
	for event: Dictionary in result.events:
		if event.type == "death":
			deaths += 1
	t.equal(deaths, 1, "poison lethal tick emits one death")
	t.expect(clone.restore(engine.capture()).ok, "lethal tick snapshot valid")
	var raw: Dictionary = Sm2TestFixtures.raw_catalog()
	raw.actors[1].immunities = ["core:status.poison"]
	var catalog: Sm2Catalog = Sm2Catalog.new()
	t.equal(catalog.build(raw).size(), 0, "immune actor catalog valid")
	engine = Sm2BattleEngine.new(catalog)
	t.expect(engine.start(Sm2TestFixtures.setup()).ok, "immune actor fixture starts")
	_rejected(t, engine, _command(engine, "use_ability", "core:ability.venom", 2), "poison immunity validated before costs")

static func _snapshots(t: Sm2TestHarness) -> void:
	var engine: Sm2BattleEngine = _engine(t, 1)
	_take(t, engine, "use_ability", "core:ability.venom", 2)
	var snapshot: Dictionary = engine.capture()
	t.expect(Sm2Canonical.is_json_safe(snapshot), "snapshot contains only precise JSON-safe values")
	var decoded: Variant = JSON.parse_string(JSON.stringify(snapshot))
	t.expect(decoded is Dictionary, "snapshot JSON parses")
	var clone: Sm2BattleEngine = _engine(t)
	t.expect(clone.restore(decoded).ok, "JSON floats accepted only after integral validation")
	t.equal(clone.state_hash(), engine.state_hash(), "JSON roundtrip exact state hash")
	decoded.actors[0].weapon.durability = 0
	t.equal(clone.state_hash(), engine.state_hash(), "restore source detached from candidate")
	var malformed: Array[Dictionary] = []
	var bad: Dictionary = snapshot.duplicate(true)
	bad.ruleset = "future"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.catalog_fingerprint = "wrong"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.schema_version = true
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.revision = 1
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.next_id = "2"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[1].actor_id = "1"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[0].hp = 1.25
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[0].hp = true
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[0].hp = 13
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[0].ap = -1
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[0].fatigue = 21
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[0].template_id = "core:weapon.practice_blade"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[0].weapon.definition_id = "core:actor.raider"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[0].weapon.durability = -1
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[1].weapon.instance_id = "1"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[1].effects[0].source_actor_id = "999"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[1].effects[0].status_id = "core:ability.venom"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[1].effects[0].remaining = 3
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[1].effects.append(bad.actors[1].effects[0].duplicate(true))
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.queue = ["2", "1"]
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.queue = ["1"]
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.queue = ["1", "999"]
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.queue = ["1", "1"]
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[0].last_activation_round = "0"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[1].last_activation_round = "1"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[1].q = 1
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.rng.state = "0"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.rng.state = "2147483647"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.rng.version = "other"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.revision = "01"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.revision = "9223372036854775808"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.finished = true
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.winner = "company"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.actors[0].creator = "2"
	malformed.append(bad)
	bad = snapshot.duplicate(true)
	bad.unexpected = "reject"
	malformed.append(bad)
	for index: int in malformed.size():
		var prior: String = clone.state_hash()
		t.expect(not clone.restore(malformed[index]).ok, "candidate parser rejects corruption %d" % index)
		t.equal(clone.state_hash(), prior, "restore failure is atomic %d" % index)
	_take(t, engine, "end_turn")
	_take(t, clone, "end_turn")
	t.equal(clone.state_hash(), engine.state_hash(), "rejected restores do not affect future commands")
	engine = _engine(t)
	snapshot = engine.capture()
	snapshot.revision = "9007199254740993"
	snapshot.actors[0].actor_id = "9007199254740993"
	snapshot.actors[0].weapon.instance_id = "9007199254740993"
	snapshot.actors[1].actor_id = "9007199254740994"
	snapshot.actors[1].weapon.instance_id = "9007199254740994"
	snapshot.queue = ["9007199254740993", "9007199254740994"]
	snapshot.next_id = "9007199254740995"
	decoded = JSON.parse_string(JSON.stringify(snapshot))
	t.expect(clone.restore(decoded).ok, "IDs above 2^53 survive typed decimal parser")
	t.equal(clone.capture().next_id, "9007199254740995", "next ID exact above 2^53")
	_take(t, clone, "end_turn")
	t.equal(clone.capture().revision, "9007199254740994", "large revision increments exactly")
	t.equal(clone.view().active_actor_id, 9007199254740994, "large actor reference preserved")
	snapshot = engine.capture()
	snapshot.revision = "9223372036854775806"
	t.expect(clone.restore(snapshot).ok, "near int64 bound parses exactly")
	_rejected(t, clone, _command(clone, "end_turn"), "counter exhaustion prevents overflow")

static func _content_extension(t: Sm2TestHarness) -> void:
	var raw: Dictionary = Sm2TestFixtures.raw_catalog()
	var new_actor: Dictionary = raw.actors[0].duplicate(true)
	new_actor.id = "test:actor.heavy"
	new_actor.weapon_id = "core:weapon.heavy_practice_blade"
	new_actor.initiative = 8
	raw.actors.append(new_actor)
	var catalog: Sm2Catalog = Sm2Catalog.new()
	t.equal(catalog.build(raw).size(), 0, "new actor and weapon composition added as data")
	var setup: Dictionary = Sm2TestFixtures.setup(1)
	setup.actors[0].template_id = "test:actor.heavy"
	var engine: Sm2BattleEngine = Sm2BattleEngine.new(catalog)
	t.expect(engine.start(setup).ok, "new content starts without engine changes")
	t.equal(engine.view().active_actor_id, 1, "equal initiative breaks ties by actor ID")
	t.equal(engine.preview(_command(engine, "use_ability", "core:ability.strike", 2)).damage_min, 5, "preview uses equipped definition values")
	_take(t, engine, "use_ability", "core:ability.strike", 2)
	t.equal(engine.view().actors[1].hp, 7, "new weapon data drives actual damage")
	t.equal(engine.view().actors[0].durability, 15, "new weapon data drives instance durability")

static func _engine(t: Sm2TestHarness, seed_value: int = 12345) -> Sm2BattleEngine:
	var engine: Sm2BattleEngine = Sm2BattleEngine.new(Sm2TestFixtures.catalog())
	t.expect(engine.start(Sm2TestFixtures.setup(seed_value)).ok, "test battle starts")
	return engine

static func _command(engine: Sm2BattleEngine, kind: String, ability: String = "", target_actor: int = 0,
	position: Vector2i = Vector2i.ZERO) -> Sm2Command:
	var visible: Dictionary = engine.view()
	return Sm2TestFixtures.command(kind, visible.active_actor_id, visible.revision, ability, target_actor, position)

static func _take(t: Sm2TestHarness, engine: Sm2BattleEngine, kind: String, ability: String = "", target_actor: int = 0,
	position: Vector2i = Vector2i.ZERO) -> Sm2CommandResult:
	var result: Sm2CommandResult = engine.execute(_command(engine, kind, ability, target_actor, position))
	t.expect(result.accepted, "accepted %s %s: %s" % [kind, ability, result.code])
	return result

static func _rejected(t: Sm2TestHarness, engine: Sm2BattleEngine, command: Sm2Command, label: String) -> void:
	var before: String = engine.state_hash()
	t.expect(not engine.preview(command).allowed, label + " preview rejects")
	var result: Sm2CommandResult = engine.execute(command)
	t.expect(not result.accepted, label + " execute rejects")
	t.expect(not result.code.is_empty(), label + " reason supplied")
	t.equal(result.events.size(), 0, label + " no emitted events")
	t.equal(engine.state_hash(), before, label + " snapshot/RNG/ID/revision unchanged")
