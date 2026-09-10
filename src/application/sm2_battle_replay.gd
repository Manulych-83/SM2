class_name Sm2BattleReplay
extends RefCounted
## Replays recorded commands without invoking AI; events must match at every boundary.
static func replay(turns: Sm2TurnCatalog, combat: Sm2CombatCatalog, initial: Dictionary, history: Array, effects: Sm2EffectCatalog = null, magic: Sm2MagicCatalog = null, development: Sm2DevelopmentCatalog = null) -> Dictionary:
	if history.size() > 100000:
		return {"ok": false, "reason": "replay_limit", "index": 0}
	var session: Sm2TacticalSession = Sm2TacticalSession.new(turns, null, combat, true, effects, magic, development)
	var restored: Dictionary = session.restore_payload(initial)
	if not restored.ok:
		return {"ok": false, "reason": "replay_initial_state", "index": 0}
	for index: int in history.size():
		var entry: Variant = history[index]
		if not entry is Dictionary or not entry.get("command") is Dictionary or not entry.get("events") is Array or not entry.get("code") is String:
			return {"ok": false, "reason": "replay_entry", "index": index}
		var raw: Dictionary = entry.command
		var fields: Array[String] = ["kind", "actor_id", "expected_revision", "ability_id", "target_actor_id", "q", "r"]
		if development != null: fields.append("battle_id")
		if not Sm2Validate.fields(raw, fields) or (development != null and not Sm2Validate.text(raw.get("battle_id"))) or not raw.kind is String or not raw.ability_id is String or not Sm2Validate.decimal(raw.actor_id, 1) or not Sm2Validate.decimal(raw.expected_revision) or not Sm2Validate.decimal(raw.target_actor_id) or not Sm2Validate.integer(raw.q, 0, 63) or not Sm2Validate.integer(raw.r, 0, 63):
			return {"ok": false, "reason": "replay_command_shape", "index": index}
		var command: Sm2Command = Sm2Command.new()
		if development != null: command.battle_id = raw.battle_id
		command.kind = raw.kind
		command.actor_id = raw.actor_id.to_int()
		command.expected_revision = raw.expected_revision.to_int()
		command.ability_id = raw.ability_id
		command.target_actor_id = raw.target_actor_id.to_int()
		command.target = Vector2i(int(raw.q), int(raw.r))
		var result: Sm2CommandResult = session.execute(command)
		if not result.accepted or result.code != entry.code or Sm2Canonical.hash(result.events) != Sm2Canonical.hash(entry.events):
			return {"ok": false, "reason": "replay_diverged", "index": index}
		if session.view().finished:
			session.record_outcome()
	return {"ok": true, "commands": history.size(), "session": session.capture(), "hash": session.state_hash(), "outcome": session.outcome()}
