class_name Sm2ActionRequirements
extends RefCounted
## Adapts existing action prices to shared predicates without changing refusal priority.
static func resources(actor: Sm2TacticalActor, ap_cost: int, fatigue_cost: int) -> Dictionary:
	return Sm2RuleCondition.evaluate({"kind":"all","children":[
		{"kind":"compare","fact":"ap","op":"gte","value":ap_cost,"reason":"insufficient_ap"},
		{"kind":"compare","fact":"fatigue_room","op":"gte","value":fatigue_cost,"reason":"fatigue_limit"}
	]}, {"ap":actor.spatial.ap,"fatigue_room":actor.spatial.fatigue_max-actor.spatial.fatigue})
