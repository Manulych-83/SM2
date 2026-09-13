class_name Sm2EffectSequence
extends RefCounted
## Finite leaf operations. No ability invocation, recursive effects or event callbacks.
const MAX_STEPS: int = 16
const MAX_ID: int = 9223372036854775806
const FACTS: Dictionary = {"same_actor":false,"source_morale":"steady","target_morale":"steady","target_effect_count":0,"target_harmful_count":0}

static func validate(steps: Variant, definitions: Dictionary) -> String:
	if not steps is Array or steps.is_empty() or steps.size() > MAX_STEPS: return "effect_sequence_steps"
	for step: Variant in steps:
		if not step is Dictionary: return "effect_sequence_step"
		var fields: Array[String] = ["operation","effect_id","on_unavailable"]
		if step.has("when"): fields.append("when")
		if not Sm2Validate.fields(step,fields) or step.operation not in ["apply_effect","dispel_effects"] or step.on_unavailable not in ["skip","reject"] or not step.effect_id is String: return "effect_sequence_step"
		if (step.operation == "apply_effect" and not definitions.has(step.effect_id)) or (step.operation == "dispel_effects" and step.effect_id != ""): return "effect_sequence_reference"
		if step.has("when"):
			var condition: Dictionary = Sm2RuleCondition.evaluate(step.when,FACTS)
			if not condition.valid: return "effect_sequence_"+str(condition.reason)
	return ""

static func preview(state: Sm2TacticalState, command: Sm2Command, action: Sm2EffectAction) -> Dictionary:
	var catalog: Sm2EffectCatalog = state.effect_catalog
	var target: Sm2TacticalActor = state.actor(command.target_actor_id)
	var projected: Dictionary = {}
	for id: int in state.sorted_effect_ids():
		var instance: Sm2EffectInstance = state.effects[id]
		if instance.target_actor_id == command.target_actor_id:
			projected[instance.definition_id] = {"id":id,"remaining":instance.remaining}
	var others: int = state.effects.size()-projected.size()
	var allocated: int = 0
	var changed: bool = false
	var plan: Array[Dictionary] = []
	for step: Dictionary in action.steps:
		var row: Dictionary = {"operation":step.operation,"effect_id":step.effect_id,"applied":false,"reason":"","remove_definitions":[]}
		if step.has("when"):
			var facts: Dictionary = FACTS.duplicate()
			facts.same_actor = command.actor_id == command.target_actor_id
			facts.source_morale = state.actor(command.actor_id).morale; facts.target_morale = target.morale
			facts.target_effect_count = projected.size()
			for id: String in projected:
				if catalog.definition(id).polarity == "harmful": facts.target_harmful_count += 1
			var condition: Dictionary = Sm2RuleCondition.evaluate(step.when,facts)
			if not condition.valid: return _deny(condition.reason,plan)
			if not condition.matches: row.reason = "effect_condition_unmet"
		if row.reason.is_empty() and step.operation == "apply_effect":
			var definition: Sm2EffectDefinition = catalog.definition(step.effect_id)
			row["name"] = definition.name
			if catalog.immune(target.loadout_id,step.effect_id): row.reason = "effect_immune"
			elif projected.has(step.effect_id) and int(projected[step.effect_id].remaining) >= definition.duration: row.reason = "effect_already_full"
			else:
				if not projected.has(step.effect_id):
					if projected.size() >= Sm2EffectResolver.MAX_PER_ACTOR or others+projected.size() >= Sm2EffectResolver.MAX_TOTAL: return _deny("effect_limit",plan)
					if allocated >= MAX_ID-state.next_effect_id: return _deny("effect_id_limit",plan)
					allocated += 1
					projected[step.effect_id] = {"id":-allocated,"remaining":definition.duration}
				else: projected[step.effect_id].remaining = definition.duration
		elif row.reason.is_empty() and step.operation == "dispel_effects":
			var ordered: Array = projected.keys()
			ordered.sort_custom(func(a: String,b: String) -> bool:
				var ai: int = int(projected[a].id); var bi: int = int(projected[b].id)
				if (ai < 0) != (bi < 0): return ai > 0
				return ai < bi if ai > 0 else ai > bi)
			for id: String in ordered:
				var definition: Sm2EffectDefinition = catalog.definition(id)
				if definition.polarity == "harmful" and definition.dispellable: row.remove_definitions.append(id)
			if row.remove_definitions.is_empty(): row.reason = "no_dispellable_effects"
			for id: String in row.remove_definitions: projected.erase(id)
		if not row.reason.is_empty() and step.on_unavailable == "reject": return _deny(row.reason,plan)
		row.applied = row.reason.is_empty()
		changed = changed or row.applied
		plan.append(row)
	if not changed: return _deny("effect_sequence_no_change",plan)
	return {"allowed":true,"reason":"","sequence":plan,"projected_effects":projected}

static func execute(state: Sm2TacticalState, command: Sm2Command, plan: Array, events: Array[Dictionary]) -> void:
	for index: int in plan.size():
		var step: Dictionary = plan[index]
		if not step.applied:
			events.append({"type":"effect_step_skipped","actor_id":str(command.actor_id),"target_actor_id":str(command.target_actor_id),"step":index+1,"reason":step.reason})
		elif step.operation == "apply_effect":
			Sm2EffectResolver.apply_definition(state,command.actor_id,command.target_actor_id,step.effect_id,events)
		else:
			for id: String in step.remove_definitions:
				var instance: Sm2EffectInstance = Sm2EffectResolver.find(state,command.target_actor_id,id)
				Sm2EffectResolver.remove(state,instance.effect_id,"dispelled",events)

static func _deny(reason: String, plan: Array) -> Dictionary:
	return {"allowed":false,"reason":reason,"sequence":plan}
