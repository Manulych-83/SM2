class_name Sm2M1Scenario
extends RefCounted
## Authored technical scenario. This is not the combat balance of the final game.

static func setup(seed_value: int = 12345) -> Dictionary:
	return {
		"battle_id": "sm2.m1.encounter.1", "seed": seed_value, "width": 6, "height": 4,
		"actors": [
			{"template_id": "core:actor.vanguard", "side": "company", "owner": "company", "controller": "player", "q": 1, "r": 1},
			{"template_id": "core:actor.raider", "side": "opposition", "owner": "opposition", "controller": "ai", "q": 2, "r": 1}
		]
	}
