class_name Sm2EncounterFactory
extends RefCounted
## Compile the equipped projection only. No combinatorial pre-generated loadouts.
static func build(content: Dictionary, world: Sm2JourneyWorld) -> Dictionary:
	var origin: Dictionary=world.origin()
	var turn_raw: Dictionary=content.catalog.to_data()
	var setup: Dictionary=content.setup.duplicate(true)
	setup.battle_id=origin.battle_id; setup.scenario_id="p4:scenario.encounter."+str(world.completed+1)
	setup.seed=int(world.encounters[world.completed].seed)
	for index: int in origin.actors.size():
		var entry: Dictionary=origin.actors[index]
		var gear_ids: Array[String]=[]
		for item: Dictionary in entry.items: gear_ids.append(item.definition_id)
		var loadout: String="p4:loadout.actor."+str(index+1)
		turn_raw.loadouts.append({"id":loadout,"profile_id":"m2:profile.fighter","equipment_ids":gear_ids})
		setup.actors[index].loadout_id=loadout
		setup.actors[index].alive=int(entry.hp)>0; setup.actors[index].on_field=int(entry.hp)>0
	var turns: Sm2TurnCatalog=Sm2TurnCatalog.new()
	var errors: PackedStringArray=turns.build(turn_raw)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var combat: Sm2CombatCatalog=Sm2CombatCatalog.new()
	errors=combat.build(content.combat.to_data(),turns)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	errors=development.build(content.development.to_data(),content.development.progression(),combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var result: Dictionary={"ok":true,"catalog":turns,"combat":combat,"development":development,"origin":origin,"setup":setup}
	if development.has_psionics():
		var compiled: Dictionary=development.psionics().compile(turns,combat,origin,development.hero())
		if not compiled.ok: return compiled
		result.effects=compiled.effects; result.magic=compiled.magic
	return result
