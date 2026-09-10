class_name Sm2OutcomeLedger
extends RefCounted
## Minimal campaign handoff boundary for M1. Reward numbers are test fixtures.

var _revision: int = 0
var _reward_total: int = 0
var _applied: Dictionary[String, bool] = {}

func apply(outcome: Dictionary, expected_revision: int, reward: int) -> Dictionary:
	if expected_revision != _revision:
		return {"ok":false, "code":"stale_campaign"}
	if not outcome.get("finished") is bool or outcome.get("finished") != true or not outcome.get("battle_id") is String:
		return {"ok":false, "code":"unfinished_or_invalid_outcome"}
	var battle_id: String = outcome["battle_id"]
	if battle_id.is_empty() or battle_id.length() > 128 or reward < 0 or reward > 1000000:
		return {"ok":false, "code":"invalid_reward_or_id"}
	if _applied.has(battle_id):
		return {"ok":false, "code":"already_applied"}
	if _applied.size() >= 10000 or _reward_total > 1000000000 - reward:
		return {"ok":false, "code":"reward_limit"}
	_applied[battle_id] = true
	_reward_total += reward
	_revision += 1
	return {"ok":true, "code":"applied"}

func capture() -> Dictionary:
	var ids: Array[String] = []
	for key: String in _applied:
		ids.append(key)
	ids.sort()
	return {"revision":str(_revision), "reward_total":str(_reward_total), "applied_encounters":ids}

func restore(data: Dictionary) -> bool:
	if data.size() != 3 or not data.get("revision") is String or not data.get("reward_total") is String or not data.get("applied_encounters") is Array:
		return false
	var raw_revision: String = data["revision"]
	var raw_reward: String = data["reward_total"]
	if not _valid_number(raw_revision) or not _valid_number(raw_reward):
		return false
	var next_revision: int = raw_revision.to_int()
	var next_reward: int = raw_reward.to_int()
	var incoming: Array = data["applied_encounters"]
	if incoming.size() > 10000 or next_revision != incoming.size() or next_reward > incoming.size() * 1000000:
		return false
	var candidate: Dictionary[String, bool] = {}
	for raw_id: Variant in incoming:
		if not raw_id is String:
			return false
		var encounter_id: String = raw_id
		if encounter_id.is_empty() or encounter_id.length() > 128 or candidate.has(encounter_id):
			return false
		candidate[encounter_id] = true
	_revision = next_revision
	_reward_total = next_reward
	_applied = candidate
	return true

static func _valid_number(value: String) -> bool:
	if value.is_empty() or value.length() > 10 or not value.is_valid_int():
		return false
	var parsed: int = value.to_int()
	return parsed >= 0 and parsed <= 1000000000 and str(parsed) == value
