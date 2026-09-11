class_name Sm2HybridCatalog
extends RefCounted
## Authored melee actions with a psionic component on the same successful hit.
const VERSION: String="sm2.p5.hybrid.content.1"
var _raw: Dictionary={}
var _abilities: Dictionary[String,Dictionary]={}

func build(raw: Dictionary,progress: Sm2ProgressCatalog,combat: Sm2CombatCatalog) -> PackedStringArray:
	if progress==null or progress.to_data().get("version")!=Sm2ProgressCatalog.CROSS_VERSION or combat==null: return PackedStringArray(["hybrid_dependencies"])
	if not Sm2Validate.fields(raw,["version","abilities"]) or raw.version!=VERSION or not raw.abilities is Array or raw.abilities.is_empty() or raw.abilities.size()>1000: return PackedStringArray(["hybrid_shape"])
	var rows: Dictionary[String,Dictionary]={}
	var physical: Dictionary={}
	for row: Dictionary in combat.to_data().abilities: physical[row.id]=row
	for entry: Variant in raw.abilities:
		if not entry is Dictionary or not Sm2Validate.fields(entry,["id","name","base_attack","required_node","concentration_cost","damage","damage_scaling","awards"]): return PackedStringArray(["hybrid_fields"])
		if not Sm2Validate.text(entry.id) or not Sm2Validate.text(entry.name) or rows.has(entry.id) or not entry.base_attack is String or not entry.required_node is String: return PackedStringArray(["hybrid_identity"])
		var base: Sm2CombatAbility=combat.ability(entry.base_attack)
		var node: Sm2ProgressNodeDefinition=progress.node(entry.required_node)
		if base==null or base.mode!="melee" or base.operation!="damage" or entry.id==entry.base_attack or not physical.has(entry.id) or node==null or node.extra_costs.is_empty() or node.extra_requirements.is_empty(): return PackedStringArray(["hybrid_reference"])
		var clone: Dictionary=physical[entry.id].duplicate(true); clone.id=entry.base_attack
		if clone!=physical[entry.base_attack]: return PackedStringArray(["hybrid_physical_profile"])
		if not Sm2Validate.integer(entry.concentration_cost,1,100) or not Sm2Validate.integer(entry.damage,1,10000): return PackedStringArray(["hybrid_numbers"])
		var error: String=Sm2AbilityParameterQuery.validate(entry.damage_scaling,progress,int(entry.damage))
		if not error.is_empty() or int(entry.damage_scaling.maximum)>10000: return PackedStringArray(["hybrid_scaling"])
		if not entry.awards is Dictionary or entry.awards.is_empty(): return PackedStringArray(["hybrid_awards"])
		for id: Variant in entry.awards:
			if not id is String or progress.track(id)==null or not Sm2Validate.integer(entry.awards[id],1,10000): return PackedStringArray(["hybrid_award"])
		for id: String in node.prices():
			if not entry.awards.has(id): return PackedStringArray(["hybrid_practice_directions"])
		rows[entry.id]=entry.duplicate(true)
		for id: String in rows[entry.id].awards: rows[entry.id].awards[id]=int(rows[entry.id].awards[id])
	for id: String in rows:
		if rows.has(rows[id].base_attack): return PackedStringArray(["hybrid_recursive_base"])
		for gear: Dictionary in combat.to_data().equipment:
			if id in gear.abilities: return PackedStringArray(["hybrid_equipment_grant"])
	_raw=raw.duplicate(true); _abilities=rows
	return PackedStringArray()

func to_data() -> Dictionary: return _raw.duplicate(true)
func ids() -> Array[String]:
	var result: Array[String]=[]; result.assign(_abilities.keys()); result.sort(); return result
func ability(id: String) -> Dictionary: return _abilities.get(id,{}).duplicate(true)
func available(body: Sm2ProgressBodyState,id: String) -> bool:
	if body==null or body is Sm2CompanionProgress or not _abilities.has(id): return false
	for track: Sm2ProgressTrackState in body.tracks.values():
		if _abilities[id].required_node in track.nodes: return true
	return false
func awards(id: String) -> Dictionary: return _abilities[id].awards.duplicate(true) if _abilities.has(id) else {}
func damage(id: String,body: Sm2ProgressBodyState,progress: Sm2ProgressCatalog,modifiers: Array[Dictionary]=[]) -> Dictionary:
	var entry: Dictionary=_abilities[id]
	return Sm2AbilityParameterQuery.resolve(int(entry.damage),entry.damage_scaling,body,progress,modifiers)
