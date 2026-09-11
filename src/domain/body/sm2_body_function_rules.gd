class_name Sm2BodyFunctionRules
extends RefCounted

static func after_hit(state: Sm2TacticalState, source: Sm2TacticalActor, target: Sm2TacticalActor, ability_id: String, hp_loss: int, events: Array[Dictionary]) -> void:
	if state.survival!=null: return
	if target.body_catalog==null or hp_loss<=0 or not target.spatial.alive: return
	var part: String=target.body_catalog.trauma(ability_id)
	var operation: String=_operation(target,ability_id)
	if part.is_empty() or operation.is_empty(): return
	target.body_functions.working[part]=false
	if operation=="sever": target.body_functions.missing[part]=true
	_clear_unusable_wall(target)
	state.body_changes.append({"actor_id":str(target.spatial.actor_id),"source_id":str(source.spatial.actor_id),"ability_id":ability_id,"part_id":part,"revision":str(state.revision+1)})
	if target.body_catalog.supports_prostheses(): state.body_changes.back()["operation"]=operation
	var event_type: String="body_part_lost" if operation=="sever" else "prosthesis_damaged" if not target.body_functions.prostheses.get(part,"").is_empty() else "body_function_lost"
	events.append({"type":event_type,"actor_id":str(source.spatial.actor_id),"target_actor_id":str(target.spatial.actor_id),"part_id":part,"name":target.body_catalog.title(part)})

static func restore_changes(raw: Variant, state: Sm2TacticalState) -> String:
	var enhanced: bool=state.development.catalog.has_prostheses()
	if not raw is Array or raw.size()>state.actors.size()*(64 if enhanced else 32): return "body_changes_shape"
	for id: int in state.sorted_ids(): _clear_unusable_wall(state.actor(id))
	var previous: int=0
	for row: Variant in raw:
		var fields: Array[String]=["actor_id","source_id","ability_id","part_id","revision"]
		if enhanced: fields.append("operation")
		if not row is Dictionary or not Sm2Validate.fields(row,fields) or not Sm2Validate.decimal(row.actor_id,1) or not Sm2Validate.decimal(row.source_id,1) or not Sm2Validate.decimal(row.revision,1,state.revision) or int(row.revision)<previous: return "body_change_fields"
		var target: Sm2TacticalActor=state.actor(int(row.actor_id))
		var source: Sm2TacticalActor=state.actor(int(row.source_id))
		if target==null or source==null or target.body_catalog==null or not row.ability_id is String or not row.part_id is String or source.spatial.side==target.spatial.side: return "body_change_actor"
		var operation: String=_operation(target,row.ability_id)
		if target.body_catalog.trauma(row.ability_id)!=row.part_id or operation.is_empty() or (enhanced and row.operation!=operation): return "body_change_transition"
		target.body_functions.working[row.part_id]=false
		if operation=="sever": target.body_functions.missing[row.part_id]=true
		_clear_unusable_wall(target)
		previous=int(row.revision)
	state.body_changes.assign(raw.duplicate(true))
	return ""

static func _operation(target: Sm2TacticalActor, ability_id: String) -> String:
	var part: String=target.body_catalog.trauma(ability_id)
	if part.is_empty(): return ""
	if target.body_catalog.severs(ability_id) and not target.body_functions.missing.get(part,false): return "sever"
	return "disable" if target.body_functions.working.get(part,false) else ""

static func _clear_unusable_wall(actor: Sm2TacticalActor) -> void:
	if not Sm2BodyCapabilityQuery.requirements(actor.body_functions,actor.body_catalog.required("shield")): actor.combat.clear_wall()
