class_name Sm2MovementResolver
extends RefCounted
## Reusable step rules. The caller owns activation/revision and publishes the candidate.

static func preview(field: Sm2Battlefield, actor: Sm2SpatialActor,
	occupied: Array[Vector2i], command: Sm2Command) -> Dictionary:
	var result: Dictionary = {"allowed": false, "reason": "", "ap_cost": 0, "fatigue_cost": 0}
	if actor == null or not actor.occupies():
		result.reason = "actor_unavailable"
		return result
	if command == null:
		result.reason = "invalid_command"
		return result
	if command.kind != "move":
		result.reason = "unsupported_command"
		return result
	if command.actor_id != actor.actor_id:
		result.reason = "actor_mismatch"
		return result
	result = Sm2SpatialQueries.step(field, actor.position, command.target, occupied)
	if result.allowed:
		if actor.ap < int(result.ap_cost):
			result.reason = "insufficient_ap"
			result.allowed = false
		elif actor.fatigue_max - actor.fatigue < int(result.fatigue_cost):
			result.reason = "fatigue_limit"
			result.allowed = false
	return result

static func resolve(field: Sm2Battlefield, actor: Sm2SpatialActor,
	occupied: Array[Vector2i], command: Sm2Command) -> Dictionary:
	var check: Dictionary = preview(field, actor, occupied, command)
	if not check.allowed:
		return {"accepted": false, "code": check.reason, "actor": null, "events": []}
	var candidate: Sm2SpatialActor = actor.copy()
	candidate.ap -= int(check.ap_cost)
	candidate.fatigue += int(check.fatigue_cost)
	candidate.position = command.target
	var events: Array[Dictionary] = [
		{"type": "resources_spent", "actor_id": str(actor.actor_id),
			"ap": int(check.ap_cost), "fatigue": int(check.fatigue_cost)},
		{"type": "moved", "actor_id": str(actor.actor_id), "from_q": actor.position.x,
			"from_r": actor.position.y, "q": candidate.position.x, "r": candidate.position.y}
	]
	return {"accepted": true, "code": "accepted", "actor": candidate, "events": events}
