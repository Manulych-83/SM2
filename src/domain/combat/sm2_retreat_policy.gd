class_name Sm2RetreatPolicy
extends RefCounted
## Reads only a detached battle view; each decision is one ordinary command.
static func decide(view: Dictionary) -> Dictionary:
	if view.is_empty() or view.finished:
		return {"ok": false, "reason": "battle_unavailable"}
	var actor: Dictionary = {}
	var occupied: Array[Vector2i] = []
	for entry: Dictionary in view.actors:
		if entry.alive and entry.on_field:
			occupied.append(Vector2i(int(entry.q), int(entry.r)))
		if entry.actor_id == view.active_actor_id:
			actor = entry
	if actor.is_empty():
		return {"ok": false, "reason": "active_actor_missing"}
	var field: Sm2Battlefield = Sm2Battlefield.new()
	if not field.build(view.field).is_empty():
		return {"ok": false, "reason": "invalid_field"}
	var origin: Vector2i = Vector2i(int(actor.q), int(actor.r))
	var route: Dictionary = Sm2SpatialQueries.route_to_boundary(field, origin, occupied, int(actor.ap_max), int(actor.fatigue_max))
	var command: Sm2Command = Sm2Command.new()
	command.kind = "end_turn"
	command.actor_id = int(view.active_actor_id)
	command.expected_revision = int(view.revision)
	if not route.ok:
		return {"ok": true, "reason": "unreachable", "command": command} if route.reason == "unreachable" else {"ok": false, "reason": route.reason}
	var ap: int = 2
	var fatigue: int = 4
	if not route.path.is_empty():
		command.target = route.path[0]
		var price: Dictionary = Sm2SpatialQueries.step(field, origin, command.target, occupied)
		ap = int(price.ap_cost)
		fatigue = int(price.fatigue_cost)
	if int(actor.ap) >= ap and int(actor.fatigue_max) - int(actor.fatigue) >= fatigue:
		command.kind = "escape" if route.path.is_empty() else "move"
	return {"ok": true, "reason": "", "command": command, "route": route}
