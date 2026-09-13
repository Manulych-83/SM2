class_name Sm2EncounterFactory
extends RefCounted
## Compile the equipped projection only. No combinatorial pre-generated loadouts.
static func build(content: Dictionary, world: Sm2JourneyWorld) -> Dictionary:
	var origin: Dictionary=world.origin()
	var turn_raw: Dictionary=content.catalog.to_data()
	var combat_raw: Dictionary=content.combat.to_data()
	var profiles: Dictionary={}
	if world.world_creatures!=null: turn_raw.version="sm2.world_creatures.turns.1."+world.world_creatures.fingerprint()
	var setup: Dictionary=content.setup.duplicate(true)
	setup.battle_id=origin.battle_id; setup.scenario_id="p4:scenario.encounter."+str(world.completed+1)
	setup.seed=int(world.encounters[world.completed].seed)
	for index: int in origin.actors.size():
		var entry: Dictionary=origin.actors[index]
		var gear_ids: Array[String]=[]
		for item: Dictionary in entry.items: gear_ids.append(item.definition_id)
		var loadout: String="p4:loadout.actor."+str(index+1)
		var profile_id: String="m2:profile.fighter"
		var template: Dictionary=world.world_creatures.actor(int(entry.body_id)) if world.world_creatures!=null else {}
		if not template.is_empty():
			profile_id=template.profile.id
			if not profiles.has(profile_id):
				var parameters: Dictionary=template.profile.turn.duplicate(true); parameters.id=profile_id; turn_raw.profiles.append(parameters)
				parameters=template.profile.combat.duplicate(true); parameters.id=profile_id; combat_raw.profiles.append(parameters)
				profiles[profile_id]=true
		turn_raw.loadouts.append({"id":loadout,"profile_id":profile_id,"equipment_ids":gear_ids})
		setup.actors[index].loadout_id=loadout
		setup.actors[index].alive=int(entry.hp)>0; setup.actors[index].on_field=int(entry.hp)>0
	var turns: Sm2TurnCatalog=Sm2TurnCatalog.new()
	var errors: PackedStringArray=turns.build(turn_raw)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var combat: Sm2CombatCatalog=Sm2CombatCatalog.new()
	errors=combat.build(combat_raw,turns)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
	errors=development.build(content.development.to_data(),content.development._shared_progression(),combat,true)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var result: Dictionary={"ok":true,"catalog":turns,"combat":combat,"development":development,"origin":origin,"setup":setup}
	if development.has_psionics():
		var compiled: Dictionary=development.psionics().compile(turns,combat,origin,development.hero())
		if not compiled.ok: return compiled
		result.effects=compiled.effects; result.magic=compiled.magic
		if world.world_creatures!=null:
			var effects_raw: Dictionary=world.world_creatures.effects()
			effects_raw.profiles=compiled.effects.to_data().profiles
			for index: int in origin.actors.size():
				var template: Dictionary=world.world_creatures.actor(int(origin.actors[index].body_id))
				if template.is_empty(): continue
				for profile: Dictionary in effects_raw.profiles:
					if profile.id=="p4:loadout.actor."+str(index+1):
						for key: String in ["actions","immunities","resistances"]: profile[key]=template.definition[key].duplicate(true)
			var effects: Sm2EffectCatalog=Sm2EffectCatalog.new(); errors=effects.build(effects_raw,combat)
			if not errors.is_empty(): return {"ok":false,"errors":errors}
			var magic: Sm2MagicCatalog=Sm2MagicCatalog.new(); errors=magic.build(compiled.magic.to_data(),combat,effects)
			if not errors.is_empty(): return {"ok":false,"errors":errors}
			result.effects=effects; result.magic=magic
	return result
