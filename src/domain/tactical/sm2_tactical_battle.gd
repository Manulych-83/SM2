class_name Sm2TacticalBattle
extends RefCounted
## Transaction boundary: all rules resolve on a detached candidate before publication.
var _catalog: Sm2TurnCatalog
var _state: Sm2TacticalState = null
var _combat: Sm2CombatCatalog = null
var _consequences: bool = false
var _effects: Sm2EffectCatalog = null
var _magic: Sm2MagicCatalog = null
var _development: Sm2DevelopmentCatalog = null
var _origin: Dictionary = {}
var _survival: Sm2SurvivalState = null

func _init(catalog: Sm2TurnCatalog, combat: Sm2CombatCatalog = null, consequences: bool = false, effects: Sm2EffectCatalog = null, magic: Sm2MagicCatalog = null, development: Sm2DevelopmentCatalog = null, origin: Dictionary = {}, survival: Sm2SurvivalState = null) -> void:
	_survival=survival.copy() if survival!=null else null
	_consequences = consequences
	_catalog = Sm2TurnCatalog.new()
	if catalog != null:
		_catalog.build(catalog.to_data())
	if combat != null:
		_combat = Sm2CombatCatalog.new()
		_combat.build(combat.to_data(), _catalog)
	if effects != null:
		_effects = Sm2EffectCatalog.new()
		_effects.build(effects.to_data(), _combat)

	if magic != null:
		_magic = Sm2MagicCatalog.new()
		_magic.build(magic.to_data(),_combat,_effects)
	_origin = origin.duplicate(true)
	if development != null:
		_development = Sm2DevelopmentCatalog.new()
		_development.build(development.to_data(),development.progression(),_combat)

func start(setup: Dictionary) -> Dictionary:
	if _development!=null and _development.ready() and _development.progression().is_party() and _origin.is_empty(): return _failure("party_requires_origin")
	if not _origin.is_empty() and _development==null: return _failure("origin_requires_development")
	if _development != null and (not _development.ready() or not _consequences or _combat == null): return _failure("development_requires_combat")
	if _development!=null and _development.has_psionics() and (_origin.is_empty() or _magic==null or not _magic.is_psionic()): return _failure("psionic_layers_required")
	if _development!=null and _development.has_psionics() and _development.has_psionic_shields()!=_magic.supports_shields(): return _failure("shield_layers_required")
	if _magic!=null and _magic.is_psionic() and (_development==null or not _development.has_psionics()): return _failure("psionic_development_required")
	if _magic != null and (_effects == null or _magic.fingerprint().is_empty()): return _failure("magic_requires_valid_effects")
	if _effects != null and (not _consequences or _effects.fingerprint().is_empty()): return _failure("effects_require_valid_consequences")
	if (_consequences and _combat == null) or (_combat != null and not _combat.matches(_catalog)):
		return _failure("incompatible_combat_catalog")
	if not Sm2Validate.fields(setup, ["battle_id", "scenario_id", "seed", "field", "round_limit", "actors"]):
		return _failure("setup_fields")
	if not Sm2Validate.text(setup.battle_id) or not Sm2Validate.text(setup.scenario_id) or typeof(setup.seed) != TYPE_INT:
		return _failure("setup_identity")
	if not setup.field is Dictionary or not Sm2Validate.integer(setup.round_limit, 1, 1000):
		return _failure("setup_field_or_limit")
	if not setup.actors is Array or setup.actors.is_empty() or setup.actors.size() > 4096:
		return _failure("actor_count")
	var candidate: Sm2TacticalState = Sm2TacticalState.new()
	candidate.survival=_survival.copy() if _survival!=null else null
	if candidate.survival!=null:
		candidate.survival.last_round=0
		candidate.survival_initial=Sm2Canonical.hash(_survival.to_data())
	candidate.consequences = _consequences
	candidate.effect_catalog = _effects
	candidate.magic_catalog = _magic
	candidate.field = Sm2Battlefield.new()
	var errors: PackedStringArray = candidate.field.build(setup.field)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	candidate.battle_id = setup.battle_id
	candidate.scenario_id = setup.scenario_id
	candidate.round_limit = int(setup.round_limit)
	candidate.rng = Sm2DeterministicRng.new(setup.seed)
	var occupied: Dictionary[Vector2i, bool] = {}
	for raw: Variant in setup.actors:
		if not raw is Dictionary:
			return _failure("actor_shape")
		var decoded: Dictionary = Sm2TacticalActor.from_setup(raw, _catalog)
		if not decoded.ok:
			return {"ok": false, "errors": decoded.errors}
		var actor: Sm2TacticalActor = decoded.actor
		var id: int = actor.spatial.actor_id
		if candidate.actors.has(id):
			return _failure("duplicate_actor_id")
		if not candidate.field.in_bounds(actor.spatial.position):
			return _failure("actor_out_of_bounds")
		if actor.spatial.occupies():
			if not candidate.field.cell(actor.spatial.position).passable:
				return _failure("actor_impassable")
			if occupied.has(actor.spatial.position):
				return _failure("duplicate_occupied_position")
			occupied[actor.spatial.position] = true
		candidate.actors[id] = actor
		candidate.next_actor_id = maxi(candidate.next_actor_id, id + 1)
		if not candidate.sides.has(actor.spatial.side):
			candidate.sides.append(actor.spatial.side)
	if candidate.sides.size() != 2 or occupied.is_empty():
		return _failure("initial_participants")
	candidate.sides.sort()
	for id: int in candidate.sorted_ids():
		var creator: int = candidate.actor(id).creator
		if creator != 0 and (creator >= id or not candidate.actors.has(creator)):
			return _failure("creator_reference")
	if _combat != null:
		candidate.combat_fingerprint = _combat.fingerprint()
		for id: int in candidate.sorted_ids():
			var actor: Sm2TacticalActor = candidate.actor(id)
			actor.combat = Sm2Combatant.new()
			actor.combat.hp = _combat.profile(actor.loadout_id).hp_max if actor.spatial.alive else 0
			var slots: Dictionary = _combat.slots(actor.loadout_id)
			for slot: String in Sm2CombatCatalog.SLOTS:
				if not slots.has(slot):
					continue
				var gear: Sm2CombatGear = _combat.gear(slots[slot])
				var item: Sm2CombatItem = Sm2CombatItem.new()
				item.item_id = candidate.next_item_id
				candidate.next_item_id += 1
				item.definition_id = gear.id
				item.slot = slot
				item.current = gear.capacity
				item.ammo = gear.ammo
				actor.combat.items[slot] = item
	if _magic != null:
		var mana_error: String = Sm2ManaResolver.initialize(candidate)
		if not mana_error.is_empty(): return _failure(mana_error)
	if _development != null:
		candidate.development = Sm2BattleDevelopment.new()
		var development_error: String = candidate.development.initialize(candidate,_development)
		if not development_error.is_empty(): return _failure(development_error)
		if not _origin.is_empty():
			var origin_error: String = Sm2EncounterOrigin.initialize(candidate,_development,_combat,_origin,true)
			if not origin_error.is_empty(): return _failure(origin_error)
	if _development!=null and _development.has_psionic_shields():
		for id: int in candidate.sorted_ids(): candidate.actor(id).barrier=Sm2BarrierState.new()
	if candidate.survival!=null:
		for id: int in candidate.sorted_ids(): Sm2SurvivalBattle.sync_actor(candidate,candidate.actor(id))
	var events: Array[Dictionary] = []
	Sm2TurnScheduler.advance(candidate, _catalog, events)
	if _consequences:
		Sm2BattleOutcome.evaluate(candidate, events)
	var checked: Dictionary = _decode(candidate.to_data(_catalog.fingerprint()))
	if not checked.ok:
		return {"ok": false, "errors": checked.errors}
	_state = checked.state
	return {"ok": true, "errors": PackedStringArray(), "events": _tag(events, _state)}

func preview(command: Sm2Command) -> Dictionary:
	var reason: String = _validate(command)
	if not reason.is_empty():
		return {"allowed": false, "reason": reason, "ap_cost": 0, "fatigue_cost": 0}
	if command.kind=="bandage": return Sm2SurvivalBattle.bandage_preview(_state,command)
	if _consequences and command.kind in ["move", "escape"]:
		return Sm2DepartureResolver.preview(_state, command)
	if command.kind == "move":
		return Sm2MovementResolver.preview(_state.field, _state.actor(command.actor_id).spatial, _state.occupancy(), command)
	if command.kind == "use_ability":
		if _magic != null and _magic.spell(command.ability_id) != null: return Sm2SpellResolver.preview(_state,command)
		if _effects != null and _effects.action(command.ability_id) != null: return Sm2EffectResolver.preview(_state,command)
		return Sm2AttackResolver.preview(_state, _combat, command)
	return {"allowed": true, "reason": "", "ap_cost": 0, "fatigue_cost": 0}

func execute(command: Sm2Command) -> Sm2CommandResult:
	var result: Sm2CommandResult = Sm2CommandResult.new()
	result.revision = _state.revision if _state != null else 0
	var check: Dictionary = preview(command)
	if not check.allowed:
		result.code = check.reason
		return result
	var candidate: Sm2TacticalState = _state.copy()
	var events: Array[Dictionary] = []
	if command.kind == "buy_node":
		candidate.development.purchase(command,events)
		candidate.revision += 1
		var purchase_checked: Dictionary = _decode(candidate.to_data(_catalog.fingerprint()))
		if not purchase_checked.ok:
			result.code = "candidate_invalid"
			return result
		_state = purchase_checked.state
		result.accepted = true; result.code = "accepted"; result.revision = _state.revision; result.events = _tag(events,_state)
		return result
	var accepted_code: String = "accepted"
	if _consequences:
		var context: Sm2ConsequenceContext = Sm2ConsequenceContext.new()
		if candidate.survival!=null:
			candidate.survival_context=context; candidate.survival_combat=_combat
		var resolved: Dictionary = {"accepted": true, "code": "accepted", "events": []}
		if command.kind=="bandage":
			resolved=Sm2SurvivalBattle.bandage(candidate,command)
		elif command.kind in ["move", "escape"]:
			resolved = Sm2DepartureResolver.resolve(candidate, _combat, command, context)
		elif command.kind == "use_ability":
			if _magic != null and _magic.spell(command.ability_id) != null:
				resolved = Sm2SpellResolver.resolve(candidate,_combat,command,context)
			elif _effects != null and _effects.action(command.ability_id) != null:
				resolved = Sm2EffectResolver.resolve(candidate,command)
			else:
				resolved = Sm2AttackResolver.resolve(candidate, _combat, command, false, context)
		if not resolved.accepted:
			result.code = resolved.code
			return result
		accepted_code = resolved.code
		events.assign(resolved.events)
		Sm2BattleOutcome.evaluate(candidate, events)
		if not candidate.finished:
			if command.kind == "wait":
				Sm2TurnScheduler.wait_active(candidate, _catalog, events)
			elif _effects != null and candidate.actor(command.actor_id).spatial.occupies() and (command.kind == "end_turn" or candidate.actor(command.actor_id).spatial.ap == 0):
				Sm2TurnScheduler.finish_active(candidate,events,command.kind != "end_turn")
				var effect_error: String = Sm2EffectResolver.end_activation(candidate,command.actor_id,_combat,context,events)
				if not effect_error.is_empty():
					result.code = effect_error
					return result
				if not candidate.finished: Sm2TurnScheduler.advance(candidate,_catalog,events)
			elif command.kind == "end_turn":
				Sm2TurnScheduler.end_active(candidate, _catalog, events)
			elif not candidate.actor(command.actor_id).spatial.occupies():
				Sm2TurnScheduler.advance(candidate, _catalog, events)
			else:
				Sm2TurnScheduler.after_action(candidate, _catalog, events)
			Sm2BattleOutcome.evaluate(candidate, events)
	else:
		match command.kind:
			"move":
				var resolved: Dictionary = Sm2MovementResolver.resolve(candidate.field,
					candidate.actor(command.actor_id).spatial, candidate.occupancy(), command)
				if not resolved.accepted:
					result.code = resolved.code
					return result
				candidate.actor(command.actor_id).spatial = resolved.actor
				events.assign(resolved.events)
				Sm2TurnScheduler.after_action(candidate, _catalog, events)
			"wait":
				Sm2TurnScheduler.wait_active(candidate, _catalog, events)
			"end_turn":
				Sm2TurnScheduler.end_active(candidate, _catalog, events)
			"use_ability":
				var resolved: Dictionary = Sm2AttackResolver.resolve(candidate, _combat, command)
				if not resolved.accepted:
					result.code = resolved.code
					return result
				events.assign(resolved.events)
				Sm2TurnScheduler.after_action(candidate, _catalog, events)
	if not candidate.survival_error.is_empty():
		result.code=candidate.survival_error; return result
	if _effects != null: Sm2EffectResolver.cleanup(candidate,events)
	candidate.revision += 1
	var checked: Dictionary = _decode(candidate.to_data(_catalog.fingerprint()))
	if not checked.ok:
		result.code = "candidate_invalid"
		return result
	_state = checked.state
	result.accepted = true
	result.code = accepted_code
	result.revision = _state.revision
	result.events = _tag(events, _state)
	return result

func capture() -> Dictionary:
	return _state.to_data(_catalog.fingerprint()) if _state != null else {}

func restore(snapshot: Dictionary) -> Dictionary:
	var decoded: Dictionary = _decode(snapshot)
	if not decoded.ok:
		return {"ok": false, "errors": decoded.errors}
	_state = decoded.state
	return {"ok": true, "errors": PackedStringArray()}

func view() -> Dictionary:
	if _state == null:
		return {}
	var actors: Array[Dictionary] = []
	for id: int in _state.sorted_ids():
		var actor_view: Dictionary = _state.actor(id).view()
		if _development!=null and _development.has_upgrades(): actor_view["upgrade_attack_fatigue"]=_state.development.extra_attack_fatigue(id)
		if _state.development != null and _state.development.bodies.has(id):
			actor_view["development"] = _state.development.view(_state,id)
			actor_view["display_name"] = "Герой" if id == _development.hero() else "Спутник"
			actor_view["melee_stat"] = Sm2CombatStatQuery.explain(_state,_state.actor(id),_combat,"melee_skill")
		if _combat != null:
			actor_view["hp_max"] = _combat.profile(_state.actor(id).loadout_id).hp_max
			actor_view["abilities"] = Sm2AttackResolver.available_abilities(_state.actor(id), _combat, _state)
		if _development!=null and _development.has_hybrids():
			actor_view["hybrids"]=[]
			for ability_id: String in actor_view.get("abilities",[]):
				var details: Dictionary=Sm2HybridQuery.details(_state,id,ability_id)
				if not details.is_empty(): details["id"]=ability_id; actor_view.hybrids.append(details)
		if _effects != null:
			actor_view.abilities.append_array(_effects.grants(_state.actor(id).loadout_id))
			actor_view["effect_actions"] = []
			for action_id: String in _effects.grants(_state.actor(id).loadout_id): actor_view.effect_actions.append(_effects.action(action_id).to_data())
			actor_view["effects"] = Sm2EffectResolver.describe_actor(_state,_state.actor(id))
			actor_view["effect_profile"] = _effects.profile(_state.actor(id).loadout_id)
			actor_view["stats"] = {}
			for stat: String in Sm2EffectCatalog.STATS: actor_view.stats[stat] = Sm2CombatStatQuery.explain(_state,_state.actor(id),_combat,stat)
		if _magic != null:
			var profile: Sm2MagicProfile = _magic.profile(_state.actor(id).loadout_id)
			if _magic.is_psionic(): actor_view["psionic"]=true
			actor_view["mana"] = _state.mana[id].current
			actor_view["magic_profile"] = profile.to_data()
			actor_view["spells"] = []
			for spell_id: String in profile.spells:
				actor_view.abilities.append(spell_id)
				var spell_view: Dictionary=_magic.spell(spell_id).to_data()
				spell_view.mana_cost=Sm2ManaResolver.cost(_state,id,_magic.spell(spell_id)).total
				actor_view.spells.append(spell_view)
		if _state.survival!=null:
			actor_view["anatomy"]=_state.actor(id).anatomy.to_data()
			actor_view["bandage_ap"]=int(_state.survival.catalog.to_data().bandage_ap)
			for wound: Dictionary in actor_view.anatomy.wounds: wound["name"]=_state.survival.catalog.part_name(wound.part)
		actors.append(actor_view)
	return {"ruleset": str(_origin.version) if not _origin.is_empty() else Sm2DevelopmentSnapshot.RULESET if _development != null else Sm2MagicSnapshot.AREA_RULESET if _magic != null and _magic.supports_areas() else Sm2MagicSnapshot.RULESET if _magic != null else Sm2EffectSnapshot.RULESET if _effects != null else Sm2CombatSnapshot.CONSEQUENCE_RULESET if _consequences else (Sm2CombatSnapshot.RULESET if _combat != null else Sm2TacticalState.RULESET), "battle_id": _state.battle_id,
		"scenario_id": _state.scenario_id, "round": _state.round, "round_limit": _state.round_limit,
		"revision": _state.revision, "active_actor_id": _state.active_id(), "phase": _state.phase,
		"finished": _state.finished, "finish_reason": _state.finish_reason, "winner": _state.winner if not _state.winner.is_empty() else null,
		"main_queue": _state.main_queue.duplicate(), "deferred_queue": _state.deferred_queue.duplicate(),
		"sides": _state.sides.duplicate(), "field": _state.field.to_data(), "actors": actors}

func outcome() -> Dictionary:
	return Sm2BattleOutcome.view(_state) if _consequences and _state != null else {}

func ai_decision(profile: Sm2AiProfile) -> Dictionary:
	if not _consequences or _state == null or profile == null:
		return {"ok": false, "reason": "ai_requires_consequence_battle"}
	var decision: Dictionary = Sm2TacticalAi.decide(view(), Sm2AiQueries.new(_state, _combat), profile)
	if _development != null and decision.get("ok",false): decision.command.battle_id = _state.battle_id
	return decision

func retreat_decision() -> Dictionary:
	var decision: Dictionary = Sm2RetreatPolicy.decide(view()) if _consequences and _state != null else {"ok": false, "reason": "consequences_required"}
	if _development != null and decision.get("ok",false): decision.command.battle_id = _state.battle_id
	return decision

func state_hash() -> String:
	return Sm2Canonical.hash(capture())

func reachable(actor_id: int) -> Dictionary:
	if not _available(actor_id):
		return {"ok": false, "reason": "actor_unavailable", "cells": []}
	var actor: Sm2SpatialActor = _state.actor(actor_id).spatial
	return Sm2SpatialQueries.reachable(_state.field, actor.position, _state.occupancy(), actor.ap, actor.fatigue_max - actor.fatigue)

func route(actor_id: int, target: Vector2i) -> Dictionary:
	if not _available(actor_id):
		return {"ok": false, "reason": "actor_unavailable", "path": [], "ap_cost": 0, "fatigue_cost": 0}
	var actor: Sm2SpatialActor = _state.actor(actor_id).spatial
	return Sm2SpatialQueries.route(_state.field, actor.position, target, _state.occupancy(), actor.ap_max, actor.fatigue_max)

func line_of_sight(from_id: int, to_id: int) -> Dictionary:
	if not _available(from_id) or not _available(to_id):
		return {"ok": false, "reason": "actor_unavailable", "visible": false, "cells": [], "blockers": []}
	return Sm2SpatialQueries.los(_state.field, _state.actor(from_id).spatial.position,
		_state.actor(to_id).spatial.position, _state.occupancy())

func _available(id: int) -> bool:
	return _state != null and _state.actors.has(id) and _state.actor(id).spatial.occupies()

func _validate(command: Sm2Command) -> String:
	if _state == null:
		return "not_started"
	if command == null:
		return "invalid_command"
	if _development != null and command.battle_id != _state.battle_id: return "wrong_battle"
	if _development != null and command.kind == "buy_node":
		if command.expected_revision != _state.revision: return "stale_revision"
		if _state.revision >= 9223372036854775806: return "counter_limit"
		return _state.development.purchase_error(_state,command)
	if _state.finished:
		return "battle_finished"
	if command.expected_revision != _state.revision:
		return "stale_revision"
	if _state.revision >= 9223372036854775806:
		return "counter_limit"
	if command.actor_id != _state.active_id():
		return "not_active_actor"
	if command.kind not in (["move", "wait", "end_turn","bandage"] if _survival!=null else ["move", "wait", "end_turn"]) and not (_combat != null and command.kind == "use_ability") and not (_consequences and command.kind == "escape"):
		return "unsupported_command"
	if command.kind == "wait":
		var actor: Sm2TacticalActor = _state.actor(command.actor_id)
		if actor.wait_used:
			return "wait_already_used"
		if actor.morale == "fleeing":
			return "fleeing_cannot_wait"
		if _state.phase != "main":
			return "wait_phase"
		if actor.spatial.ap <= 0:
			return "no_ap"
	return ""

func _decode(snapshot: Dictionary) -> Dictionary:
	if _survival!=null: return Sm2SurvivalBattle.decode(snapshot,_catalog,_combat,_effects,_magic,_development,_origin,_survival)
	if _development != null:
		if not _consequences or _combat == null: return _failure("development_requires_combat")
		return Sm2DevelopmentSnapshot.decode(snapshot,_catalog,_combat,_effects,_magic,_development,_origin)
	if _magic != null:
		if not _consequences or _effects == null: return _failure("magic_requires_effects")
		return Sm2MagicSnapshot.decode(snapshot,_catalog,_combat,_effects,_magic)
	if _effects != null:
		if not _consequences: return _failure("effects_require_consequences")
		return Sm2EffectSnapshot.decode(snapshot,_catalog,_combat,_effects)
	if _consequences and _combat == null:
		return _failure("consequences_require_combat_catalog")
	if _combat != null:
		return Sm2CombatSnapshot.decode(snapshot, _catalog, _combat, _consequences)
	return Sm2TacticalSnapshot.decode(snapshot, _catalog)

static func _tag(events: Array[Dictionary], state: Sm2TacticalState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(events.duplicate(true))
	for index: int in result.size():
		result[index]["battle_id"] = state.battle_id
		result[index]["revision"] = str(state.revision)
		result[index]["sequence"] = index
	return result

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([reason])}
