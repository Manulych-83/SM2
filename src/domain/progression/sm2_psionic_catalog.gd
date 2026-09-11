class_name Sm2PsionicCatalog
extends RefCounted
## Authored unlocks compile into the shared direct-damage/resource operations.
const VERSION: String="sm2.p5.psionics.content.1"
const SHIELD_VERSION: String="sm2.p5.psionics.content.3"
const GROWTH_VERSION: String="sm2.p5.psionics.content.2"
var _raw: Dictionary={}
var _abilities: Dictionary={}

func build(raw: Dictionary, progress: Sm2ProgressCatalog, combat: Sm2CombatCatalog) -> PackedStringArray:
	if progress==null or combat==null or not Sm2Validate.fields(raw,["version","track_id","concentration_max","concentration_per_round","abilities"]) or raw.version not in [VERSION,GROWTH_VERSION,SHIELD_VERSION]: return _error("psionic_shape")
	if not raw.track_id is String or progress.track(raw.track_id)==null or progress.track(raw.track_id).kind!="skill": return _error("psionic_track")
	if not Sm2Validate.integer(raw.concentration_max,1,10000) or not Sm2Validate.integer(raw.concentration_per_round,0,raw.concentration_max): return _error("psionic_resource")
	if not raw.abilities is Array or raw.abilities.is_empty() or raw.abilities.size()>1000: return _error("psionic_abilities")
	var abilities: Dictionary={}
	for entry: Variant in raw.abilities:
		var fields: Array[String]=["id","name","required_node","ap_cost","concentration_cost","range_min","range_max","damage","practice_xp"]
		if raw.version in [GROWTH_VERSION,SHIELD_VERSION]: fields.append_array(["damage_scaling","additional_awards"])
		var shield: bool=raw.version==SHIELD_VERSION and entry is Dictionary and entry.get("operation")=="self_barrier"
		if raw.version==SHIELD_VERSION: fields.append("operation")
		if shield:
			fields.erase("damage"); fields.erase("damage_scaling"); fields.append_array(["capacity","capacity_scaling"])
		if not entry is Dictionary or not Sm2Validate.fields(entry,fields): return _error("psionic_ability_shape")
		if raw.version==SHIELD_VERSION and entry.operation not in ["direct_hp_damage","self_barrier"]: return _error("psionic_operation")
		if not Sm2Validate.text(entry.id) or not Sm2Validate.text(entry.name) or abilities.has(entry.id) or combat.ability(entry.id)!=null: return _error("psionic_ability_id")
		if not entry.required_node is String or progress.node(entry.required_node)==null or progress.node(entry.required_node).track_id!=raw.track_id: return _error("psionic_node")
		for key: String in ["ap_cost","concentration_cost","range_min","range_max","capacity" if shield else "damage","practice_xp"]:
			if not Sm2Validate.integer(entry[key],1,64 if key.begins_with("range") else 10000): return _error("psionic_number")
		if shield and (entry.range_min!=1 or entry.range_max!=1): return _error("psionic_self_range")
		if entry.range_min>entry.range_max or entry.concentration_cost>raw.concentration_max: return _error("psionic_range")
		if raw.version in [GROWTH_VERSION,SHIELD_VERSION]:
			var reason: String=Sm2AbilityParameterQuery.validate(entry.capacity_scaling if shield else entry.damage_scaling,progress,int(entry.capacity if shield else entry.damage))
			if not reason.is_empty(): return _error(reason)
			if not entry.additional_awards is Dictionary or entry.additional_awards.is_empty() or entry.additional_awards.size()>64: return _error("psionic_extra_awards")
			for track: Variant in entry.additional_awards:
				if not track is String or progress.track(track)==null or progress.track(track).kind!="attribute" or not Sm2Validate.integer(entry.additional_awards[track],1,10000): return _error("psionic_extra_award")
		abilities[entry.id]=entry.duplicate(true)
		for key: String in ["ap_cost","concentration_cost","range_min","range_max","capacity" if shield else "damage","practice_xp"]: abilities[entry.id][key]=int(entry[key])
	_raw=raw.duplicate(true); _abilities=abilities
	_raw.concentration_max=int(raw.concentration_max); _raw.concentration_per_round=int(raw.concentration_per_round)
	_raw.abilities=[]
	for id: String in ids(): _raw.abilities.append(ability(id))
	return PackedStringArray()

func to_data() -> Dictionary: return _raw.duplicate(true)
func ids() -> Array[String]:
	var result: Array[String]=[]; result.assign(_abilities.keys()); result.sort(); return result
func ability(id: String) -> Dictionary: return _abilities.get(id,{}).duplicate(true)
func awards(id: String) -> Dictionary:
	if not _abilities.has(id): return {}
	var result: Dictionary={_raw.track_id:int(_abilities[id].practice_xp)}
	if grows():
		for track: String in _abilities[id].additional_awards: result[track]=int(_abilities[id].additional_awards[track])
	return result
func grows() -> bool: return _raw.get("version") in [GROWTH_VERSION,SHIELD_VERSION]
func shields() -> bool: return _raw.get("version")==SHIELD_VERSION
func capacity(id: String,body: Sm2ProgressBodyState,progress: Sm2ProgressCatalog,modifiers: Array[Dictionary]=[]) -> Dictionary:
	var a: Dictionary=ability(id)
	return Sm2AbilityParameterQuery.resolve(int(a.capacity),a.capacity_scaling,body,progress,modifiers)
func damage(id: String,body: Sm2ProgressBodyState,progress: Sm2ProgressCatalog,modifiers: Array[Dictionary]=[]) -> Dictionary:
	var a: Dictionary=ability(id)
	return Sm2AbilityParameterQuery.resolve(int(a.damage),a.damage_scaling,body,progress,modifiers) if grows() else {}
func available(body: Sm2ProgressBodyState, id: String) -> bool:
	return body!=null and not body is Sm2CompanionProgress and _abilities.has(id) and body.tracks.has(_raw.track_id) and _abilities[id].required_node in body.tracks[_raw.track_id].nodes

func compile(turns: Sm2TurnCatalog, combat: Sm2CombatCatalog, origin: Dictionary, hero: int) -> Dictionary:
	var effects_raw: Dictionary={"version":Sm2EffectCatalog.EMPTY_VERSION,"effects":[],"actions":[],"profiles":[]}
	var magic_raw: Dictionary={"version":Sm2MagicCatalog.SHIELD_VERSION if shields() else Sm2MagicCatalog.PSIONIC_VERSION,"spells":[],"profiles":[]}
	for id: String in ids():
		var a: Dictionary=ability(id)
		if a.get("operation")=="self_barrier":
			magic_raw.spells.append({"id":id,"name":a.name,"operation":"self_barrier","target_side":"self","ap_cost":a.ap_cost,"fatigue_cost":0,"mana_cost":a.concentration_cost,"range_min":1,"range_max":1,"capacity":a.capacity,"channel":"psionic"})
			continue
		magic_raw.spells.append({"id":id,"name":a.name,"operation":"direct_hp_damage","target_side":"enemy","ap_cost":a.ap_cost,"fatigue_cost":0,"mana_cost":a.concentration_cost,"range_min":a.range_min,"range_max":a.range_max,"damage":a.damage,"channel":"psionic"})
	var learned: Array[String]=[]
	for member: Dictionary in origin.members:
		if int(member.actor_id)!=hero: continue
		for track: Dictionary in member.body.tracks:
			if track.track_id!=_raw.track_id: continue
			for id: String in ids():
				if ability(id).required_node in track.owned_nodes: learned.append(id)
	var hero_loadout: String=""
	for index: int in origin.actors.size():
		if int(origin.actors[index].actor_id)==hero: hero_loadout="p4:loadout.actor."+str(index+1)
	for loadout: Dictionary in turns.to_data().loadouts:
		var is_hero: bool=loadout.id==hero_loadout
		effects_raw.profiles.append({"id":loadout.id,"actions":[],"immunities":[],"resistances":{}})
		magic_raw.profiles.append({"id":loadout.id,"mana_max":int(_raw.concentration_max) if is_hero else 0,"mana_per_round":int(_raw.concentration_per_round) if is_hero else 0,"arcane_resistance":0,"spells":learned if is_hero else []})
	var effects: Sm2EffectCatalog=Sm2EffectCatalog.new(); var errors: PackedStringArray=effects.build(effects_raw,combat)
	if not errors.is_empty(): return {"ok":false,"errors":errors}
	var magic: Sm2MagicCatalog=Sm2MagicCatalog.new(); errors=magic.build(magic_raw,combat,effects)
	return {"ok":errors.is_empty(),"errors":errors,"effects":effects,"magic":magic}

static func _error(reason: String) -> PackedStringArray: return PackedStringArray([reason])
