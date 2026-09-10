class_name Sm2SpatialActor
extends RefCounted
## Detached spatial projection, not a second definition of combat stats or life rules.
var actor_id: int = 0
var side: String = ""
var owner: String = ""
var controller: String = ""
var position: Vector2i = Vector2i.ZERO
var ap_max: int = 9
var ap: int = 9
var fatigue_max: int = 65
var fatigue: int = 0
var alive: bool = true
var on_field: bool = true

static func decode(raw: Dictionary) -> Dictionary:
	if not Sm2Validate.fields(raw, ["actor_id", "side", "owner", "controller", "q", "r",
		"ap_max", "ap", "fatigue_max", "fatigue", "alive", "on_field"]):
		return {"ok": false, "reason": "actor_fields", "actor": null}
	if not raw.actor_id is int or raw.actor_id < 1 or raw.actor_id > 9223372036854775806 \
		or not Sm2Validate.text(raw.side) or not Sm2Validate.text(raw.owner) or not Sm2Validate.text(raw.controller) \
		or not raw.q is int or not raw.r is int or not raw.alive is bool or not raw.on_field is bool:
		return {"ok": false, "reason": "actor_identity", "actor": null}
	for field_name: String in ["ap_max", "ap", "fatigue_max", "fatigue"]:
		if not raw[field_name] is int:
			return {"ok": false, "reason": "actor_resources", "actor": null}
	if raw.ap_max < 1 or raw.ap_max > 1000 or raw.ap < 0 or raw.ap > raw.ap_max \
		or raw.fatigue_max < 0 or raw.fatigue_max > 10000 or raw.fatigue < 0 or raw.fatigue > raw.fatigue_max \
		or raw.q < 0 or raw.q > 63 or raw.r < 0 or raw.r > 63:
		return {"ok": false, "reason": "actor_bounds", "actor": null}
	var actor: Sm2SpatialActor = Sm2SpatialActor.new()
	actor.actor_id = raw.actor_id
	actor.side = raw.side
	actor.owner = raw.owner
	actor.controller = raw.controller
	actor.position = Vector2i(raw.q, raw.r)
	actor.ap_max = raw.ap_max
	actor.ap = raw.ap
	actor.fatigue_max = raw.fatigue_max
	actor.fatigue = raw.fatigue
	actor.alive = raw.alive
	actor.on_field = raw.on_field
	return {"ok": true, "reason": "", "actor": actor}

func copy() -> Sm2SpatialActor:
	return decode(view()).actor as Sm2SpatialActor

func occupies() -> bool:
	return alive and on_field

func view() -> Dictionary:
	return {"actor_id": actor_id, "side": side, "owner": owner, "controller": controller,
		"q": position.x, "r": position.y, "ap_max": ap_max, "ap": ap,
		"fatigue_max": fatigue_max, "fatigue": fatigue, "alive": alive, "on_field": on_field}

func to_data() -> Dictionary:
	var data: Dictionary = view()
	data.actor_id = str(actor_id)
	return data
