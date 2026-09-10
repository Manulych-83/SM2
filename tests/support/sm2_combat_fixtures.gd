class_name Sm2CombatFixtures
extends RefCounted

static func loaded() -> Dictionary:
	return Sm2CombatContentLoader.load_scenario()

static func setup(loaded: Dictionary, ids: Array[int] = [2, 5], seed_value: int = 1231) -> Dictionary:
	var result: Dictionary = loaded.setup.duplicate(true)
	result.seed = seed_value
	result.field = Sm2SpatialFixtures.field(8, 5).to_data()
	var actors: Array[Dictionary] = []
	for id: int in ids:
		for raw: Dictionary in result.actors:
			if raw.actor_id == id:
				var actor: Dictionary = raw.duplicate(true)
				actor.q = actors.size() + 1
				actor.r = 2
				actors.append(actor)
	result.actors = actors
	return result

static func battle(t: Sm2TestHarness, ids: Array[int] = [2, 5], seed_value: int = 1231) -> Sm2TacticalBattle:
	var content: Dictionary = loaded()
	t.expect(content.ok, "combat fixtures: authored content loads")
	var result: Sm2TacticalBattle = Sm2TacticalBattle.new(content.catalog, content.combat)
	var started: Dictionary = result.start(setup(content, ids, seed_value))
	t.expect(started.ok, "combat fixtures: start " + str(started.get("errors", [])))
	return result

static func command(battle: Sm2TacticalBattle, ability: String, target: int) -> Sm2Command:
	var result: Sm2Command = Sm2Command.new()
	result.kind = "use_ability"
	result.actor_id = battle.view().active_actor_id
	result.expected_revision = battle.view().revision
	result.ability_id = "m2:ability." + ability
	result.target_actor_id = target
	return result

static func actor(data: Dictionary, id: int) -> Dictionary:
	for raw: Dictionary in data.actors:
		if str(raw.actor_id) == str(id):
			return raw
	return {}

static func item(actor_data: Dictionary, slot: String) -> Dictionary:
	for raw: Dictionary in actor_data.combat.items:
		if raw.slot == slot:
			return raw
	return {}

static func untyped(battle: Sm2TacticalBattle) -> Dictionary:
	return JSON.parse_string(JSON.stringify(battle.capture()))

static func act(t: Sm2TestHarness, battle: Sm2TacticalBattle, ability: String, target: int) -> Sm2CommandResult:
	var before: Dictionary = battle.capture()
	var result: Sm2CommandResult = battle.execute(command(battle, ability, target))
	t.expect(result.accepted, "combat accepted " + ability + ": " + result.code)
	t.equal(result.revision, int(before.revision) + 1, "combat: one transaction revision")
	t.equal(battle.capture().next_item_id, before.next_item_id, "combat: item allocator unchanged by attacks")
	for i: int in result.events.size():
		t.expect(result.events[i].sequence == i and result.events[i].revision == str(result.revision), "combat: ordered event metadata")
	return result

static func end(t: Sm2TestHarness, battle: Sm2TacticalBattle, kind: String = "end_turn") -> Sm2CommandResult:
	var command: Sm2Command = Sm2TurnTestFixtures.command(battle, kind)
	var result: Sm2CommandResult = battle.execute(command)
	t.expect(result.accepted, "combat scheduler accepted " + kind + ": " + result.code)
	return result
