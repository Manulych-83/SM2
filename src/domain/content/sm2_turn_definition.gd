class_name Sm2TurnDefinition
extends RefCounted
## Derived loadout values. Authored profiles and equipment remain the source.
var id: String = ""
var ap_max: int = 0
var fatigue_base: int = 0
var initiative_base: int = 0
var load_penalty: int = 0
var fatigue_max: int = 0

func copy() -> Sm2TurnDefinition:
	var result: Sm2TurnDefinition = Sm2TurnDefinition.new()
	result.id = id
	result.ap_max = ap_max
	result.fatigue_base = fatigue_base
	result.initiative_base = initiative_base
	result.load_penalty = load_penalty
	result.fatigue_max = fatigue_max
	return result
