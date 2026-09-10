class_name Sm2ActorState
extends RefCounted
var actor_id: int = 0
var template_id: String = ""
var side: String = ""
var owner: String = ""
var controller: String = ""
var creator: int = 0
var position: Vector2i = Vector2i.ZERO
var hp: int = 0
var ap: int = 0
var fatigue: int = 0
var eligible_round: int = 1
var last_acted_round: int = 0
var last_activation_round: int = 0
var weapon: Sm2ItemState
var effects: Array[Sm2EffectState] = []

func alive() -> bool:
	return hp > 0

func to_data() -> Dictionary:
	var effect_data: Array[Dictionary] = []
	for effect: Sm2EffectState in effects:
		effect_data.append(effect.to_data())
	return {"actor_id": str(actor_id), "template_id": template_id, "side": side, "owner": owner,
		"controller": controller, "creator": str(creator), "q": position.x, "r": position.y,
		"hp": hp, "ap": ap, "fatigue": fatigue, "eligible_round": str(eligible_round),
		"last_acted_round": str(last_acted_round), "last_activation_round": str(last_activation_round),
		"weapon": weapon.to_data(), "effects": effect_data}
