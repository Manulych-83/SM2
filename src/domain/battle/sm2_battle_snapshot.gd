class_name Sm2BattleSnapshot
extends RefCounted
## Typed candidate parser. No publication, mutation or coercion before validation.

static func decode(data: Dictionary, catalog: Sm2Catalog) -> Dictionary:
	if not Sm2Validate.fields(data, ["format", "schema_version", "ruleset", "catalog_fingerprint", "battle_id", "width", "height",
		"revision", "round", "next_id", "actors", "queue", "sides", "finished", "winner", "rng"]):
		return _failure("snapshot: unexpected or missing fields")
	if data.format != "sm2.battle" or not Sm2Validate.integer(data.schema_version, 1, 1) \
		or data.ruleset != Sm2BattleState.RULESET or data.catalog_fingerprint != catalog.fingerprint():
		return _failure("snapshot: incompatible format, schema, ruleset or catalog")
	if not Sm2Validate.text(data.battle_id) or not Sm2Validate.integer(data.width, 1, 1000) or not Sm2Validate.integer(data.height, 1, 1000) \
		or not Sm2Validate.decimal(data.revision) or not Sm2Validate.decimal(data.round, 1) or not Sm2Validate.decimal(data.next_id, 1):
		return _failure("snapshot: invalid identity, bounds or decimal counters")
	if not data.actors is Array or data.actors.size() < 2 or data.actors.size() > 10000 \
		or not data.queue is Array or data.queue.size() > data.actors.size() or not Sm2Validate.string_list(data.sides) \
		or data.sides.size() != 2 or not data.finished is bool or not Sm2Validate.text(data.winner, true):
		return _failure("snapshot: invalid collections or outcome")
	if not data.rng is Dictionary or not Sm2Validate.fields(data.rng, ["version", "state", "draws"]) \
		or data.rng.version != Sm2DeterministicRng.VERSION or not Sm2Validate.decimal(data.rng.state, 1, Sm2DeterministicRng.SPAN) \
		or not Sm2Validate.decimal(data.rng.draws):
		return _failure("snapshot: invalid RNG")
	var candidate: Sm2BattleState = Sm2BattleState.new()
	candidate.battle_id = data.battle_id
	candidate.width = int(data.width)
	candidate.height = int(data.height)
	candidate.revision = data.revision.to_int()
	candidate.round = data.round.to_int()
	candidate.next_id = data.next_id.to_int()
	candidate.sides.assign(data.sides)
	candidate.finished = data.finished
	candidate.winner = data.winner
	candidate.rng.state = data.rng.state.to_int()
	candidate.rng.draws = data.rng.draws.to_int()
	var positions: Dictionary = {}
	var weapon_ids: Dictionary = {}
	var prior_id: int = 0
	for raw: Variant in data.actors:
		if not raw is Dictionary:
			return _failure("snapshot: actor must be a dictionary")
		var parsed: Dictionary = _parse_actor(raw, catalog, candidate)
		if not parsed.ok:
			return parsed
		var entry: Sm2ActorState = parsed.actor
		if entry.actor_id <= prior_id or entry.actor_id >= candidate.next_id:
			return _failure("snapshot: actor IDs must increase and precede next_id")
		prior_id = entry.actor_id
		if weapon_ids.has(entry.weapon.instance_id):
			return _failure("snapshot: duplicate item instance ID")
		weapon_ids[entry.weapon.instance_id] = true
		if entry.alive():
			if positions.has(entry.position):
				return _failure("snapshot: duplicate living position")
			positions[entry.position] = true
		candidate.actors.append(entry)
	var represented_sides: Dictionary = {}
	for entry: Sm2ActorState in candidate.actors:
		represented_sides[entry.side] = true
		if entry.creator > 0:
			if candidate.actor(entry.creator) == null or entry.creator >= entry.actor_id or entry.eligible_round < 2:
				return _failure("snapshot: invalid creator reference")
		elif entry.eligible_round != 1:
			return _failure("snapshot: initial actor must be eligible in round 1")
		for effect: Sm2EffectState in entry.effects:
			if candidate.actor(effect.source_actor_id) == null:
				return _failure("snapshot: missing effect source actor")
	if represented_sides.size() != 2:
		return _failure("snapshot: both original sides must be represented")
	var actual_queue: Array[int] = []
	for raw_id: Variant in data.queue:
		if not Sm2Validate.decimal(raw_id, 1):
			return _failure("snapshot: queue IDs must be decimal strings")
		var id: int = raw_id.to_int()
		if candidate.actor(id) == null or id in actual_queue:
			return _failure("snapshot: queue contains missing or duplicate actor")
		actual_queue.append(id)
	var declared_finished: bool = candidate.finished
	var declared_winner: String = candidate.winner
	candidate.update_outcome()
	if candidate.finished != declared_finished or candidate.winner != declared_winner:
		return _failure("snapshot: inconsistent victory")
	if candidate.finished:
		if not actual_queue.is_empty():
			return _failure("snapshot: finished battle has a queue")
	else:
		candidate.rebuild_queue(catalog)
		if candidate.queue != actual_queue or candidate.queue.is_empty():
			return _failure("snapshot: incomplete or unordered turn queue")
		for id: int in candidate.queue:
			var entry: Sm2ActorState = candidate.actor(id)
			if id == candidate.active_id():
				if entry.last_activation_round != candidate.round:
					return _failure("snapshot: active actor has not started activation")
			elif entry.last_activation_round >= candidate.round:
				return _failure("snapshot: pending actor has already started activation")
	return {"ok": true, "errors": PackedStringArray(), "state": candidate}

static func _parse_actor(data: Dictionary, catalog: Sm2Catalog, state: Sm2BattleState) -> Dictionary:
	if not Sm2Validate.fields(data, ["actor_id", "template_id", "side", "owner", "controller", "creator", "q", "r", "hp", "ap", "fatigue",
		"eligible_round", "last_acted_round", "last_activation_round", "weapon", "effects"]):
		return _failure("actor: missing or unexpected fields")
	if not Sm2Validate.decimal(data.actor_id, 1) or not Sm2Validate.text(data.template_id) or not catalog.has_actor(data.template_id) \
		or not Sm2Validate.text(data.side) or not data.side in state.sides or not Sm2Validate.text(data.owner) or not Sm2Validate.text(data.controller) \
		or not Sm2Validate.decimal(data.creator) or not Sm2Validate.integer(data.q, 0, state.width - 1) or not Sm2Validate.integer(data.r, 0, state.height - 1):
		return _failure("actor: invalid identity, references, control or position")
	var definition: Sm2ActorDefinition = catalog.actor(data.template_id)
	if not Sm2Validate.integer(data.hp, 0, definition.hp) or not Sm2Validate.integer(data.ap, 0, definition.ap) \
		or not Sm2Validate.integer(data.fatigue, 0, definition.max_fatigue) \
		or not Sm2Validate.decimal(data.eligible_round, 1, state.round + 1) or not Sm2Validate.decimal(data.last_acted_round, 0, state.round) \
		or not Sm2Validate.decimal(data.last_activation_round, 0, state.round):
		return _failure("actor: invalid vitals or activation counters")
	if data.last_acted_round.to_int() > data.last_activation_round.to_int() \
		or (data.last_activation_round.to_int() > 0 and data.last_activation_round.to_int() < data.eligible_round.to_int()):
		return _failure("actor: inconsistent activation counters")
	if not data.weapon is Dictionary or not Sm2Validate.fields(data.weapon, ["instance_id", "definition_id", "durability"]) \
		or not Sm2Validate.decimal(data.weapon.instance_id, 1) or not Sm2Validate.text(data.weapon.definition_id) or not catalog.has_weapon(data.weapon.definition_id):
		return _failure("actor: invalid weapon definition or instance")
	var weapon_definition: Sm2WeaponDefinition = catalog.weapon(data.weapon.definition_id)
	if not Sm2Validate.integer(data.weapon.durability, 0, weapon_definition.durability):
		return _failure("actor: invalid weapon durability")
	if not data.effects is Array or data.effects.size() > 1000:
		return _failure("actor: effects must be a bounded array")
	var entry: Sm2ActorState = Sm2ActorState.new()
	entry.actor_id = data.actor_id.to_int()
	entry.template_id = data.template_id
	entry.side = data.side
	entry.owner = data.owner
	entry.controller = data.controller
	entry.creator = data.creator.to_int()
	entry.position = Vector2i(int(data.q), int(data.r))
	entry.hp = int(data.hp)
	entry.ap = int(data.ap)
	entry.fatigue = int(data.fatigue)
	entry.eligible_round = data.eligible_round.to_int()
	entry.last_acted_round = data.last_acted_round.to_int()
	entry.last_activation_round = data.last_activation_round.to_int()
	entry.weapon = Sm2ItemState.new()
	entry.weapon.instance_id = data.weapon.instance_id.to_int()
	entry.weapon.definition_id = data.weapon.definition_id
	entry.weapon.durability = int(data.weapon.durability)
	var seen: Dictionary = {}
	for raw_effect: Variant in data.effects:
		if not raw_effect is Dictionary or not Sm2Validate.fields(raw_effect, ["status_id", "source_actor_id", "remaining"]) \
			or not Sm2Validate.text(raw_effect.status_id) or not catalog.has_status(raw_effect.status_id) \
			or not Sm2Validate.decimal(raw_effect.source_actor_id, 1):
			return _failure("actor: invalid status reference or source ID")
		if seen.has(raw_effect.status_id) or raw_effect.status_id in definition.immunities \
			or not Sm2Validate.integer(raw_effect.remaining, 1, catalog.status(raw_effect.status_id).duration):
			return _failure("actor: duplicate, immune or invalid-duration status")
		seen[raw_effect.status_id] = true
		var effect: Sm2EffectState = Sm2EffectState.new()
		effect.status_id = raw_effect.status_id
		effect.source_actor_id = raw_effect.source_actor_id.to_int()
		effect.remaining = int(raw_effect.remaining)
		entry.effects.append(effect)
	return {"ok": true, "actor": entry, "errors": PackedStringArray()}

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}
