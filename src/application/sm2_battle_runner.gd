class_name Sm2BattleRunner
extends RefCounted
## One step, one ordinary command. Self-play is an explicit diagnostic mode.
const FORMAT: String = "sm2.ai_run.1"
const SLOT: String = "m2_ai_run"
var _effects: Sm2EffectCatalog = null
var _magic: Sm2MagicCatalog = null
var _development: Sm2DevelopmentCatalog = null
var _origin: Dictionary = {}
var _survival: Sm2SurvivalState = null
const DEVELOPMENT_FORMAT: String = "sm2.development_run.1"
const DEVELOPMENT_SLOT: String = "p2_development_run"
const MAGIC_FORMAT: String = "sm2.magic_run.1"
const MAGIC_SLOT: String = "m4_magic_run"
const AREA_FORMAT: String = "sm2.areas_run.1"
const AREA_SLOT: String = "m4_area_run"
const EFFECT_FORMAT: String = "sm2.effects_run.1"
const EFFECT_SLOT: String = "m4_effects_run"

func save_slot() -> String: return DEVELOPMENT_SLOT if _development != null else AREA_SLOT if _magic != null and _magic.supports_areas() else MAGIC_SLOT if _magic != null else EFFECT_SLOT if _effects != null else SLOT
func format_id() -> String: return ("sm2.hybrid_encounter_run.1" if _origin.get("version")==Sm2EncounterOrigin.HYBRID_RULESET else "sm2.implant_encounter_run.1" if _origin.get("version")==Sm2EncounterOrigin.IMPLANT_RULESET else "sm2.upgrade_encounter_run.1" if _origin.get("version")==Sm2EncounterOrigin.UPGRADE_RULESET else "sm2.psionic_shield_encounter_run.1" if _origin.get("version")==Sm2EncounterOrigin.PSIONIC_SHIELD_RULESET else "sm2.psionic_growth_encounter_run.1" if _origin.get("version")==Sm2EncounterOrigin.PSIONIC_GROWTH_RULESET else "sm2.psionic_encounter_run.1" if _origin.get("version")==Sm2EncounterOrigin.PSIONIC_RULESET else "sm2.prosthesis_encounter_run.1" if _origin.get("version")==Sm2EncounterOrigin.PROSTHESIS_RULESET else "sm2.body_encounter_run.1" if _origin.get("version")==Sm2EncounterOrigin.BODY_RULESET else "sm2.party_encounter_run.1" if _origin.get("version")==Sm2EncounterOrigin.PARTY_RULESET else "sm2.encounter_run.1") if not _origin.is_empty() else DEVELOPMENT_FORMAT if _development != null else AREA_FORMAT if _magic != null and _magic.supports_areas() else MAGIC_FORMAT if _magic != null else EFFECT_FORMAT if _effects != null else FORMAT

var _turns: Sm2TurnCatalog
var _combat: Sm2CombatCatalog
var _profile: Sm2AiProfile
var _session: Sm2TacticalSession
var _store: Sm2SaveStore
var _self_play: bool
var _key: String = ""
var _attempts: int = 0
var _error: String = ""

func _init(turns: Sm2TurnCatalog, combat: Sm2CombatCatalog, profile: Sm2AiProfile,
	store: Sm2SaveStore = null, self_play: bool = false, effects: Sm2EffectCatalog = null, magic: Sm2MagicCatalog = null, development: Sm2DevelopmentCatalog = null, origin: Dictionary = {}, survival: Sm2SurvivalState = null) -> void:
	_turns = Sm2TurnCatalog.new()
	_turns.build(turns.to_data())
	_combat = Sm2CombatCatalog.new()
	_combat.build(combat.to_data(), _turns)
	if effects != null:
		_effects = Sm2EffectCatalog.new()
		_effects.build(effects.to_data(),_combat)
	if magic != null:
		_magic = Sm2MagicCatalog.new()
		_magic.build(magic.to_data(),_combat,_effects)
	_survival=survival.copy() if survival!=null else null
	_origin = origin.duplicate(true)
	if development != null:
		_development = Sm2DevelopmentCatalog.new()
		_development.build(development.to_data(),development.progression(),_combat)
	_profile = Sm2AiProfile.new()
	_profile.build(profile.to_data())
	_store = store
	_self_play = self_play
	_session = Sm2TacticalSession.new(_turns, store, _combat, true, _effects, _magic, _development, _origin, _survival)

func new_battle(setup: Dictionary) -> Dictionary:
	if _profile.to_data().is_empty():
		return {"ok": false, "errors": PackedStringArray(["ai_profile_missing"])}
	var result: Dictionary = _session.new_battle(setup)
	if result.ok:
		_key = _activation_key(_session.view())
		_attempts = 0
		_error = ""
	return result

func view() -> Dictionary:
	return _session.view()

func preview(command: Sm2Command) -> Dictionary:
	return _session.preview(command)

func ability_cost(actor_id: int, ability_id: String) -> Dictionary:
	return _session.ability_cost(actor_id,ability_id)

func reachable(actor_id: int) -> Dictionary:
	return _session.reachable(actor_id)

func outcome() -> Dictionary:
	return _session.outcome()

func record_outcome() -> Dictionary:
	return _session.record_outcome()

func error_reason() -> String:
	return _error

func capture() -> Dictionary:
	return {"format": format_id(), "profile": _profile.fingerprint(), "self_play": _self_play, "session": _session.capture(),
		"activation_key": _key, "attempts": _attempts, "error": _error}

func state_hash() -> String:
	return Sm2Canonical.hash(capture())

func step() -> Dictionary:
	if not _error.is_empty():
		return {"ok": false, "reason": _error}
	var current: Dictionary = view()
	if current.is_empty():
		return {"ok": false, "reason": "no_session"}
	if current.finished:
		return {"ok": true, "status": "finished", "record": _session.record_outcome()}
	var actor: Dictionary = {}
	for entry: Dictionary in current.actors:
		if entry.actor_id == current.active_actor_id:
			actor = entry
	if not _self_play and actor.controller != "ai" and actor.morale != "fleeing":
		return {"ok": true, "status": "player_turn"}
	_sync()
	for retry: int in 2:
		if _attempts >= int(_profile.to_data().attempt_limit):
			return _fail("ai_attempt_limit")
		_attempts += 1
		var decision: Dictionary = _session.ai_decision(_profile)
		if not decision.ok:
			return _fail(decision.reason)
		var result: Sm2CommandResult = _session.execute(decision.command)
		if result.accepted:
			_sync()
			var record: Dictionary = _session.record_outcome() if view().finished else {}
			return {"ok": true, "status": "finished" if view().finished else "advanced", "choice": decision.choice,
				"command": Sm2TacticalAi.command_data(decision.command), "code": result.code, "events": result.events,
				"retries": retry, "record": record}
		if retry == 1:
			return _fail("ai_command_rejected:" + result.code)
	return _fail("ai_internal_error")

func execute_player(command: Sm2Command) -> Sm2CommandResult:
	var current: Dictionary = view()
	if command != null and command.kind == "buy_node" and _development != null and _error.is_empty():
		return _session.execute(command)
	var allowed: bool = false
	if _error.is_empty() and not current.is_empty() and not current.finished:
		for actor: Dictionary in current.actors:
			if actor.actor_id == current.active_actor_id:
				allowed = actor.controller == "player" and actor.morale != "fleeing"
	if not allowed:
		var denied: Sm2CommandResult = Sm2CommandResult.new()
		denied.code = "not_player_turn"
		denied.revision = int(current.get("revision", 0))
		return denied
	var result: Sm2CommandResult = _session.execute(command)
	if result.accepted:
		_sync()
	return result

func run_to_end(command_limit: int = 10000) -> Dictionary:
	var history: Array[Dictionary] = []
	if command_limit < 1 or command_limit > 100000:
		return {"ok": false, "reason": "invalid_runner_limit", "history": history}
	for index: int in command_limit:
		var result: Dictionary = step()
		if not result.ok:
			return {"ok": false, "reason": result.reason, "history": history}
		if result.has("command"):
			history.append(result)
		if result.status in ["finished", "player_turn"]:
			return {"ok": true, "status": result.status, "history": history, "outcome": _session.outcome()}
	return {"ok": false, "reason": "runner_command_limit", "history": history}

func restore(payload: Dictionary) -> Dictionary:
	if not Sm2Validate.fields(payload, ["format", "profile", "self_play", "session", "activation_key", "attempts", "error"]) or payload.format != format_id() or payload.profile != _profile.fingerprint() or not payload.self_play is bool or payload.self_play != _self_play:
		return {"ok": false, "errors": PackedStringArray(["ai_run_version"])}
	if not payload.session is Dictionary or not payload.activation_key is String or not payload.error is String or payload.error.length() > 256 or not Sm2Validate.integer(payload.attempts, 0, int(_profile.to_data().get("attempt_limit", 0))):
		return {"ok": false, "errors": PackedStringArray(["ai_run_fields"])}
	var candidate: Sm2TacticalSession = Sm2TacticalSession.new(_turns, _store, _combat, true, _effects, _magic, _development, _origin, _survival)
	var checked: Dictionary = candidate.restore_payload(payload.session)
	if not checked.ok:
		return checked
	if payload.activation_key != _activation_key(candidate.view()) or (candidate.view().finished and int(payload.attempts) != 0):
		return {"ok": false, "errors": PackedStringArray(["ai_run_activation"])}
	_session = candidate
	_key = payload.activation_key
	_attempts = int(payload.attempts)
	_error = payload.error
	return {"ok": true, "errors": PackedStringArray()}

func save_game() -> Dictionary:
	if _store == null or view().is_empty():
		return {"ok": false, "errors": PackedStringArray(["no_session_or_store"])}
	return _store.save_slot(capture(), save_slot())

func load_game() -> Dictionary:
	if _store == null:
		return {"ok": false, "errors": PackedStringArray(["no_store"])}
	var loaded: Dictionary = _store.load_slot(save_slot())
	return restore(loaded.payload) if loaded.ok else loaded

func _sync() -> void:
	var next: String = _activation_key(view())
	if next != _key:
		_key = next
		_attempts = 0

static func _activation_key(data: Dictionary) -> String:
	if data.is_empty() or data.finished:
		return ""
	return Sm2Canonical.hash([data.battle_id, data.round, data.phase, str(data.active_actor_id)])

func _fail(reason: String) -> Dictionary:
	_error = reason
	return {"ok": false, "reason": reason}
