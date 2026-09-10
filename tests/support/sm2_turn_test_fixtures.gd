class_name Sm2TurnTestFixtures
extends RefCounted
## Small independent turn oracles; authored game profiles live only in content/m2.
static func catalog(ap_max: int = 9, tied: bool = false) -> Sm2TurnCatalog:
	var result: Sm2TurnCatalog = Sm2TurnCatalog.new()
	result.build({"version": "test.1", "profiles": [
		{"id": "test:fast", "ap_max": ap_max, "fatigue_base": 100, "initiative_base": 100},
		{"id": "test:normal", "ap_max": ap_max, "fatigue_base": 100, "initiative_base": 100 if tied else 80},
		{"id": "test:slow", "ap_max": ap_max, "fatigue_base": 100, "initiative_base": 60}],
		"equipment": [{"id": "test:gear", "load_penalty": 0}],
		"loadouts": [{"id": "test:fast", "profile_id": "test:fast", "equipment_ids": ["test:gear"]},
			{"id": "test:normal", "profile_id": "test:normal", "equipment_ids": ["test:gear"]},
			{"id": "test:slow", "profile_id": "test:slow", "equipment_ids": ["test:gear"]}]})
	return result

static func setup(round_limit: int = 100) -> Dictionary:
	return {"battle_id": "test:turns", "scenario_id": "test:turns", "seed": 20260909,
		"round_limit": round_limit, "field": Sm2SpatialFixtures.field().to_data(), "actors": [
			actor(1, "test:fast", 0, 0), actor(2, "test:normal", 4, 0), actor(3, "test:slow", 0, 3)]}

static func actor(id: int, loadout: String, q: int, r: int) -> Dictionary:
	return {"actor_id": id, "loadout_id": loadout, "side": "company" if id == 1 else "opposition",
		"owner": "fixture", "controller": "fixture", "creator": 0, "q": q, "r": r,
		"fatigue": 0, "alive": true, "on_field": true, "morale": "steady"}

static func command(battle: Sm2TacticalBattle, kind: String, target: Vector2i = Vector2i.ZERO) -> Sm2Command:
	return Sm2SpatialFixtures.command(battle.view().active_actor_id, battle.view().revision, target, kind)

static func types(events: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for event: Dictionary in events:
		result.append(event.type)
	return result
