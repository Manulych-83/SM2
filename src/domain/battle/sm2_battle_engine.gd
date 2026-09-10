class_name Sm2BattleEngine
extends RefCounted
## Commands are the write boundary. Godot scenes and persistence never own state.
var _catalog: Sm2Catalog
var _state: Sm2BattleState = null
var _handlers: Dictionary = {}
var _poison: Sm2PoisonHandler = Sm2PoisonHandler.new()

func _init(catalog: Sm2Catalog) -> void:
	_catalog = Sm2Catalog.new()
	_catalog.build(catalog.to_data())
	_handlers = {"damage": Sm2DamageHandler.new(), "status": _poison, "summon": Sm2SummonHandler.new()}

func start(setup: Dictionary) -> Dictionary:
	if _catalog.version().is_empty():
		return _failure("start: empty catalog")
	if not Sm2Validate.fields(setup, ["battle_id", "seed", "width", "height", "actors"]) or not Sm2Validate.text(setup.get("battle_id")) \
		or not setup.get("seed") is int or not Sm2Validate.integer(setup.get("width"), 1, 1000) or not Sm2Validate.integer(setup.get("height"), 1, 1000) \
		or not setup.get("actors") is Array or setup.actors.size() < 2 or setup.actors.size() > 10000:
		return _failure("start: invalid setup fields, bounds, seed or actors")
	var candidate: Sm2BattleState = Sm2BattleState.new()
	candidate.battle_id = setup.battle_id
	candidate.width = int(setup.width)
	candidate.height = int(setup.height)
	candidate.rng = Sm2DeterministicRng.new(setup.seed)
	for raw: Variant in setup.actors:
		if not raw is Dictionary or not Sm2Validate.fields(raw, ["template_id", "side", "owner", "controller", "q", "r"]) \
			or not Sm2Validate.text(raw.template_id) or not _catalog.has_actor(raw.template_id) \
			or not Sm2Validate.text(raw.side) or not Sm2Validate.text(raw.owner) or not Sm2Validate.text(raw.controller) \
			or not Sm2Validate.integer(raw.q, 0, candidate.width - 1) or not Sm2Validate.integer(raw.r, 0, candidate.height - 1):
			return _failure("start: invalid actor fields, template, side, control or position")
		var position: Vector2i = Vector2i(int(raw.q), int(raw.r))
		if candidate.occupied(position):
			return _failure("start: overlapping actors")
		if not raw.side in candidate.sides:
			candidate.sides.append(raw.side)
		candidate.spawn(_catalog.actor(raw.template_id), _catalog, raw.side, raw.owner, raw.controller, position)
	if candidate.sides.size() != 2:
		return _failure("start: exactly two sides required in M1")
	candidate.rebuild_queue(_catalog)
	candidate.actor(candidate.active_id()).last_activation_round = 1
	_state = candidate
	return {"ok": true, "errors": PackedStringArray()}

func preview(command: Sm2Command) -> Dictionary:
	var result: Dictionary = {"allowed": false, "reason": "", "ap_cost": 0, "fatigue_cost": 0, "damage_min": 0, "damage_max": 0}
	var reason: String = _validate_base(command)
	if not reason.is_empty():
		result.reason = reason
		return result
	var source: Sm2ActorState = _state.actor(command.actor_id)
	match command.kind:
		"move":
			result.ap_cost = 1
			result.fatigue_cost = 1
			if not _state.in_bounds(command.target):
				reason = "out_of_bounds"
			elif _state.occupied(command.target):
				reason = "occupied"
			elif Sm2BattleState.distance(source.position, command.target) != 1:
				reason = "not_adjacent"
		"use_ability":
			var definition: Sm2ActorDefinition = _catalog.actor(source.template_id)
			if not command.ability_id in definition.abilities:
				reason = "unknown_ability"
			else:
				var ability: Sm2AbilityDefinition = _catalog.ability(command.ability_id)
				result.ap_cost = ability.ap_cost
				result.fatigue_cost = ability.fatigue_cost
				if ability.operation == "damage":
					var weapon: Sm2WeaponDefinition = _catalog.weapon(source.weapon.definition_id)
					result.damage_min = weapon.damage_min + ability.damage_bonus
					result.damage_max = weapon.damage_max + ability.damage_bonus
				var handler: Sm2AbilityHandler = _handlers.get(ability.operation)
				reason = "unsupported_operation" if handler == null else handler.validate(_state, _catalog, source, ability, command)
		"end_turn":
			pass
		_:
			reason = "unknown_command"
	if reason.is_empty():
		if source.ap < int(result.ap_cost):
			reason = "insufficient_ap"
		elif source.fatigue + int(result.fatigue_cost) > _catalog.actor(source.template_id).max_fatigue:
			reason = "fatigue_limit"
	result.reason = reason
	result.allowed = reason.is_empty()
	return result

func execute(command: Sm2Command) -> Sm2CommandResult:
	var result: Sm2CommandResult = Sm2CommandResult.new()
	result.revision = _state.revision if _state != null else 0
	var check: Dictionary = preview(command)
	if not check.allowed:
		result.code = check.reason
		return result
	var source: Sm2ActorState = _state.actor(command.actor_id)
	var events: Array[Dictionary] = []
	source.ap -= int(check.ap_cost)
	source.fatigue += int(check.fatigue_cost)
	match command.kind:
		"move":
			source.position = command.target
			events.append({"type": "moved", "actor_id": str(source.actor_id), "q": source.position.x, "r": source.position.y})
		"use_ability":
			var ability: Sm2AbilityDefinition = _catalog.ability(command.ability_id)
			var handler: Sm2AbilityHandler = _handlers[ability.operation]
			handler.apply(_state, _catalog, source, ability, command, events)
		"end_turn":
			source.last_acted_round = _state.round
			_state.queue.erase(source.actor_id)
			events.append({"type": "turn_ended", "actor_id": str(source.actor_id)})
	_state.update_outcome()
	if command.kind == "end_turn" and not _state.finished:
		_advance_activation(events)
	_state.revision += 1
	result.accepted = true
	result.code = "accepted"
	result.revision = _state.revision
	result.events.assign(events.duplicate(true))
	return result

func _advance_activation(events: Array[Dictionary]) -> void:
	while not _state.finished:
		if _state.queue.is_empty():
			_state.round += 1
			_state.rebuild_queue(_catalog)
			events.append({"type": "round_started", "round": str(_state.round)})
		var active: Sm2ActorState = _state.actor(_state.active_id())
		var definition: Sm2ActorDefinition = _catalog.actor(active.template_id)
		active.ap = definition.ap
		active.fatigue = maxi(0, active.fatigue - 2)
		active.last_activation_round = _state.round
		events.append({"type": "turn_started", "actor_id": str(active.actor_id)})
		_poison.tick(_state, _catalog, active, events)
		_state.update_outcome()
		if active.alive() or _state.finished:
			return
		active.last_acted_round = _state.round

func _validate_base(command: Sm2Command) -> String:
	if _state == null:
		return "not_started"
	if command == null:
		return "invalid_command"
	if _state.finished:
		return "battle_finished"
	if command.expected_revision != _state.revision:
		return "stale_revision"
	if _state.revision >= 9223372036854775806 or _state.round >= 9223372036854775805 or _state.rng.draws >= 9223372036854775000:
		return "counter_limit"
	if command.actor_id != _state.active_id():
		return "not_active_actor"
	return ""

func view() -> Dictionary:
	if _state == null:
		return {}
	var actors: Array[Dictionary] = []
	for entry: Sm2ActorState in _state.actors:
		var definition: Sm2ActorDefinition = _catalog.actor(entry.template_id)
		var effects: Array[Dictionary] = []
		for effect: Sm2EffectState in entry.effects:
			effects.append(effect.to_data())
		actors.append({"actor_id": entry.actor_id, "template_id": entry.template_id, "name": definition.name,
			"side": entry.side, "owner": entry.owner, "controller": entry.controller, "creator": entry.creator,
			"q": entry.position.x, "r": entry.position.y, "hp": entry.hp, "hp_max": definition.hp,
			"ap": entry.ap, "ap_max": definition.ap, "fatigue": entry.fatigue, "fatigue_max": definition.max_fatigue,
			"alive": entry.alive(), "abilities": Array(definition.abilities).duplicate(), "weapon_id": entry.weapon.definition_id,
			"durability": entry.weapon.durability, "effects": effects, "eligible_round": entry.eligible_round})
	return {"battle_id": _state.battle_id, "revision": _state.revision, "round": _state.round,
		"active_actor_id": _state.active_id(), "finished": _state.finished, "winner": _state.winner, "actors": actors}

func capture() -> Dictionary:
	return _state.to_data(_catalog.fingerprint()) if _state != null else {}

func restore(snapshot: Dictionary) -> Dictionary:
	var decoded: Dictionary = Sm2BattleSnapshot.decode(snapshot, _catalog)
	if not decoded.ok:
		return {"ok": false, "errors": decoded.errors}
	_state = decoded.state
	return {"ok": true, "errors": PackedStringArray()}

func state_hash() -> String:
	return Sm2Canonical.hash(capture())

func outcome() -> Dictionary:
	if _state == null:
		return {}
	var participants: Array[Dictionary] = []
	for entry: Sm2ActorState in _state.actors:
		participants.append({"actor_id": str(entry.actor_id), "template_id": entry.template_id, "side": entry.side,
			"owner": entry.owner, "controller": entry.controller, "creator": str(entry.creator), "alive": entry.alive(), "hp": entry.hp})
	return {"battle_id": _state.battle_id, "winner": _state.winner, "finished": _state.finished, "participants": participants}

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}
