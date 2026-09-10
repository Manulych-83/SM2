class_name Sm2TestFixtures
extends RefCounted

static func setup(seed_value: int = 12345) -> Dictionary:
	return Sm2M1Scenario.setup(seed_value)

static func raw_catalog() -> Dictionary:
	return {
		"version": "core.m1.1",
		"actors": [
			{"id":"core:actor.vanguard", "name":"Страж", "hp":12, "ap":4, "max_fatigue":20, "initiative":10, "weapon_id":"core:weapon.practice_blade", "abilities":["core:ability.strike", "core:ability.venom", "core:ability.summon"], "immunities":[]},
			{"id":"core:actor.raider", "name":"Налётчик", "hp":12, "ap":4, "max_fatigue":20, "initiative":8, "weapon_id":"core:weapon.practice_blade", "abilities":["core:ability.strike"], "immunities":[]},
			{"id":"core:actor.wisp", "name":"Огонёк", "hp":4, "ap":2, "max_fatigue":10, "initiative":6, "weapon_id":"core:weapon.practice_blade", "abilities":["core:ability.strike"], "immunities":[]}
		],
		"weapons": [
			{"id":"core:weapon.practice_blade", "name":"Учебный клинок", "damage_min":3, "damage_max":5, "durability":20},
			{"id":"core:weapon.heavy_practice_blade", "name":"Тяжёлый учебный клинок", "damage_min":5, "damage_max":7, "durability":16}
		],
		"abilities": [
			{"id":"core:ability.strike", "name":"Удар", "operation":"damage", "ap_cost":2, "fatigue_cost":3, "range":1, "damage_bonus":0, "status_id":"", "summon_template_id":""},
			{"id":"core:ability.venom", "name":"Отравление", "operation":"status", "ap_cost":2, "fatigue_cost":2, "range":1, "damage_bonus":0, "status_id":"core:status.poison", "summon_template_id":""},
			{"id":"core:ability.summon", "name":"Призыв огонька", "operation":"summon", "ap_cost":3, "fatigue_cost":4, "range":1, "damage_bonus":0, "status_id":"", "summon_template_id":"core:actor.wisp"}
		],
		"statuses": [{"id":"core:status.poison", "name":"Яд", "tick_damage":1, "duration":2}]
	}

static func catalog() -> Sm2Catalog:
	var result: Sm2Catalog = Sm2Catalog.new()
	var errors: PackedStringArray = result.build(raw_catalog())
	if not errors.is_empty():
		push_error("Broken test fixture: " + str(errors))
	return result

static func command(kind: String, actor_id: int, revision: int, ability_id: String = "", target_actor: int = 0, tile: Vector2i = Vector2i.ZERO) -> Sm2Command:
	var request: Sm2Command = Sm2Command.new()
	request.kind = kind
	request.actor_id = actor_id
	request.expected_revision = revision
	request.ability_id = ability_id
	request.target_actor_id = target_actor
	request.target = tile
	return request
