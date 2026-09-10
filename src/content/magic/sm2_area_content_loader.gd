class_name Sm2AreaContentLoader
extends RefCounted
static func load_scenario() -> Dictionary:
	var content: Dictionary = Sm2MagicContentLoader.load_scenario("res://content/m4/areas.tres")
	if content.ok:
		content.setup.battle_id = "m4_area_demo"
		content.setup.scenario_id = "m4:scenario.areas"
	return content
