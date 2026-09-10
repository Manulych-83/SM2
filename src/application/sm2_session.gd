class_name Sm2Session
extends RefCounted
## Application composition. UI receives detached data, never a mutable battle.

const SESSION_FORMAT: String = "sm2.session.m1.1"
const FIXTURE_REWARD: int = 10
var _catalog: Sm2Catalog
var _store: Sm2SaveStore
var _battle: Sm2BattleEngine
var _ledger: Sm2OutcomeLedger

func _init(catalog_value: Sm2Catalog, storage: Sm2SaveStore) -> void:
	_catalog = Sm2Catalog.new()
	_catalog.build(catalog_value.to_data())
	_store = storage

func new_game(seed_value: int = 12345) -> Dictionary:
	var candidate: Sm2BattleEngine = Sm2BattleEngine.new(_catalog)
	var result: Dictionary = candidate.start(Sm2M1Scenario.setup(seed_value))
	if not result.get("ok", false):
		return result
	_battle = candidate
	_ledger = Sm2OutcomeLedger.new()
	return {"ok":true, "errors":PackedStringArray()}

func has_active_game() -> bool:
	return _battle != null

func has_save() -> bool:
	return _store.has_slot()

func view() -> Dictionary:
	if _battle == null:
		return {}
	return _battle.view()

func state_hash() -> String:
	return Sm2Canonical.hash(capture())

func capture() -> Dictionary:
	if _battle == null:
		return {}
	return {"format":SESSION_FORMAT, "catalog":_catalog.fingerprint(), "battle":_battle.capture(), "campaign":_ledger.capture()}

func save_game() -> Dictionary:
	if _battle == null:
		return _failure("Нет открытой истории для сохранения.")
	return _store.save_slot(capture())

func load_game() -> Dictionary:
	var result: Dictionary = _store.load_slot()
	if not result.get("ok", false):
		return result
	return restore_payload(result["payload"])

func restore_payload(payload: Dictionary) -> Dictionary:
	if payload.size() != 4 or payload.get("format") != SESSION_FORMAT or payload.get("catalog") != _catalog.fingerprint():
		return _failure("Сохранение использует несовместимый формат или набор контента.")
	if not payload.get("battle") is Dictionary or not payload.get("campaign") is Dictionary:
		return _failure("Структура сохранения повреждена.")
	var candidate: Sm2BattleEngine = Sm2BattleEngine.new(_catalog)
	var restored: Dictionary = candidate.restore(payload["battle"])
	if not restored.get("ok", false):
		return restored
	var candidate_ledger: Sm2OutcomeLedger = Sm2OutcomeLedger.new()
	if not candidate_ledger.restore(payload["campaign"]):
		return _failure("История результатов повреждена.")
	var candidate_view: Dictionary = candidate.view()
	var recorded: Array = candidate_ledger.capture()["applied_encounters"]
	if recorded.has(candidate_view["battle_id"]) and not candidate_view["finished"]:
		return _failure("Незавершённый бой не может иметь применённый результат.")
	_battle = candidate
	_ledger = candidate_ledger
	return {"ok":true, "errors":PackedStringArray()}

func execute(command: Sm2Command) -> Sm2CommandResult:
	if _battle == null:
		var refused: Sm2CommandResult = Sm2CommandResult.new()
		refused.accepted = false
		refused.code = "no_session"
		return refused
	return _battle.execute(command)

func preview(command: Sm2Command) -> Dictionary:
	if _battle == null:
		return {"allowed":false, "reason":"no_session", "ap_cost":0, "fatigue_cost":0, "damage_min":0, "damage_max":0}
	return _battle.preview(command)

func settle_battle(expected_campaign_revision: int) -> Dictionary:
	if _battle == null:
		return _failure("Нет открытой истории.")
	var outcome: Dictionary = _battle.outcome()
	var reward: int = FIXTURE_REWARD if outcome.get("winner") == "company" else 0
	return _ledger.apply(outcome, expected_campaign_revision, reward)

func close_game() -> void:
	_battle = null
	_ledger = null

static func _failure(message: String) -> Dictionary:
	return {"ok":false, "errors":PackedStringArray([message])}
