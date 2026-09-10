class_name Sm2JourneyContentLoader
extends RefCounted
static func load_scenario() -> Dictionary:
	var base: Dictionary=Sm2LifeContentLoader.load_scenario()
	if not base.ok: return base
	var spec: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/p4/journey.json"))
	if not spec is Dictionary or not Sm2Validate.fields(spec,["version","initial_loadout","encounters","unarmed","unarmed_awards"]) or spec.version!="sm2.p4.location.1" or not spec.encounters is Array or spec.encounters.is_empty() or spec.encounters.size()>100: return _error("journey_content")
	if not spec.initial_loadout is String or not base.catalog.has_loadout(spec.initial_loadout): return _error("journey_initial_loadout")
	var world_raw: Dictionary=base.world_definition.to_data()
	var seen: Array[int]=[]
	for encounter: Variant in spec.encounters:
		if not encounter is Dictionary or not Sm2Validate.fields(encounter,["name","enemies","seed"]) or not Sm2Validate.text(encounter.name) or not Sm2Validate.integer(encounter.seed,1,2147483647) or not encounter.enemies is Array or encounter.enemies.size()!=2: return _error("journey_encounter")
		for enemy: Variant in encounter.enemies:
			if not Sm2Validate.integer(enemy,10,100000) or int(enemy) in seen or int(enemy)==12: return _error("journey_enemy")
			var id: int=int(enemy); seen.append(id)
			if base.world_definition.body(id).is_empty(): world_raw.bodies.append({"id":id,"name":"Страж: "+encounter.name,"human":true,"enhanced":false,"prepared":false,"alive":true})
	world_raw.bodies.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.id)<int(b.id))
	var definition: Sm2LifeDefinition=Sm2LifeDefinition.new()
	var errors: PackedStringArray=definition.build(world_raw)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var combat_raw: Dictionary=base.combat.to_data()
	combat_raw.version="sm2.p4.combat.1"; combat_raw["unarmed_ability"]="p4:ability.punch"; combat_raw.abilities.append(spec.unarmed)
	var combat: Sm2CombatCatalog=Sm2CombatCatalog.new()
	errors=combat.build(combat_raw,base.catalog)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	var rules: Dictionary=base.development.to_data(); rules.awards["p4:ability.punch"]=spec.unarmed_awards
	errors=development.build(rules,base.development.progression(),combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	base.combat=combat; base.development=development; base.world_definition=definition; base["meetings"]=spec.encounters.duplicate(true)
	base["journey_fingerprint"]=Sm2Canonical.hash(spec)
	base["initial_loadout"]=spec.initial_loadout
	return base
static func _error(reason: String) -> Dictionary: return {"ok":false,"errors":PackedStringArray([reason])}
