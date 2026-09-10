class_name Sm2BattleOutcome
extends RefCounted

static func presence(state: Sm2TacticalState) -> Array[String]:
	var result: Array[String] = []
	for side: String in state.sides:
		for id: int in state.sorted_ids():
			if state.actor(id).spatial.side == side and state.actor(id).spatial.occupies():
				result.append(side)
				break
	return result

static func evaluate(state: Sm2TacticalState, events: Array[Dictionary]) -> void:
	var remaining: Array[String] = presence(state)
	if remaining.size() == 2 and not state.finished:
		return
	var reason: String = "round_limit" if remaining.size() == 2 else ("opposition_removed" if remaining.size() == 1 else "mutual_removal")
	var winner: String = remaining[0] if remaining.size() == 1 else ""
	if state.finished and state.finish_reason == reason and state.winner == winner and reason != "round_limit":
		return
	state.finished = true
	state.finish_reason = reason
	state.winner = winner
	state.phase = "finished"
	state.main_queue.clear()
	state.deferred_queue.clear()
	for id: int in state.sorted_ids():
		state.actor(id).spatial.ap = 0
		state.actor(id).turn_done = true
	events.append({"type": "battle_finished", "reason": reason, "winner": winner if not winner.is_empty() else null})

static func view(state: Sm2TacticalState) -> Dictionary:
	var participants: Array[Dictionary] = []
	var counts: Dictionary = {}
	for side: String in state.sides:
		counts[side] = {"dead": 0, "escaped": 0, "on_field": 0}
	for id: int in state.sorted_ids():
		var actor: Sm2TacticalActor = state.actor(id)
		participants.append(actor.view())
		var category: String = "dead" if not actor.spatial.alive else ("on_field" if actor.spatial.on_field else "escaped")
		counts[actor.spatial.side][category] += 1
	return {"battle_id": state.battle_id, "finished": state.finished, "reason": state.finish_reason,
		"winner": state.winner if not state.winner.is_empty() else null, "round": state.round,
		"participants": participants, "counts": counts}
