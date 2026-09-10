class_name Sm2CombatSnapshot
extends RefCounted
const RULESET: String = "sm2.m2.attacks.1"
const CONSEQUENCE_RULESET: String = "sm2.m2.consequences.1"

static func decode(data: Dictionary, turns: Sm2TurnCatalog, catalog: Sm2CombatCatalog, consequences: bool = false) -> Dictionary:
	var schema: int = 4 if consequences else 3
	var ruleset: String = CONSEQUENCE_RULESET if consequences else RULESET
	if catalog == null or not catalog.matches(turns) or data.get("format") != "sm2.battle" or not Sm2Validate.integer(data.get("schema_version"), schema, schema) or data.get("ruleset") != ruleset or data.get("combat_fingerprint") != catalog.fingerprint() or not Sm2Validate.decimal(data.get("next_item_id"), 2):
		return _failure("combat_snapshot_version")
	if not data.get("actors") is Array:
		return _failure("combat_actors_shape")
	# Decode the scheduling projection using the existing strict contract. Extra
	# keys remain in the projection and are rejected, never silently discarded.
	var projection: Dictionary = data.duplicate(true)
	projection.erase("combat_fingerprint")
	projection.erase("next_item_id")
	if consequences:
		if not data.has("winner") or (data.winner != null and not Sm2Validate.text(data.winner)):
			return _failure("outcome_winner_shape")
		projection.erase("winner")
	projection.ruleset = Sm2TacticalState.RULESET
	projection.schema_version = 2
	var components: Dictionary = {}
	for raw: Variant in projection.actors:
		if not raw is Dictionary or not raw.get("combat") is Dictionary or not Sm2Validate.decimal(raw.get("actor_id"), 1, 9223372036854775805):
			return _failure("combat_actor_shape")
		components[raw.actor_id] = raw.combat
		raw.erase("combat")
	var decoded: Dictionary = Sm2TacticalSnapshot.decode(projection, turns, consequences)
	if not decoded.ok:
		return decoded
	var state: Sm2TacticalState = decoded.state
	state.winner = data.winner if consequences and data.winner != null else ""
	if consequences:
		var presence: Array[String] = Sm2BattleOutcome.presence(state)
		var reason: String = "opposition_removed" if presence.size() == 1 else "mutual_removal"
		if presence.size() < 2:
			if not state.finished or state.finish_reason != reason or state.winner != (presence[0] if presence.size() == 1 else ""):
				return _failure("outcome_presence_mismatch")
		elif not state.winner.is_empty() or (state.finished and state.finish_reason != "round_limit"):
			return _failure("outcome_presence_mismatch")
	state.combat_fingerprint = catalog.fingerprint()
	state.next_item_id = data.next_item_id.to_int()
	var seen_items: Dictionary[int, bool] = {}
	for id: int in state.sorted_ids():
		var actor: Sm2TacticalActor = state.actor(id)
		var raw: Dictionary = components[str(id)]
		if not Sm2Validate.fields(raw, ["hp", "items", "shieldwall_used", "shieldwall_source", "shieldwall_until_round"]) or not Sm2Validate.integer(raw.hp, 0, catalog.profile(actor.loadout_id).hp_max) or not raw.items is Array or not raw.shieldwall_used is bool or not Sm2Validate.decimal(raw.shieldwall_source) or not Sm2Validate.decimal(raw.shieldwall_until_round, 0, state.round_limit + 1):
			return _failure("combat_component_fields")
		if actor.spatial.alive != (int(raw.hp) > 0):
			return _failure("combat_hp_life_mismatch")
		var component: Sm2Combatant = Sm2Combatant.new()
		component.hp = int(raw.hp)
		component.shieldwall_used = raw.shieldwall_used
		component.shieldwall_source = raw.shieldwall_source.to_int()
		component.shieldwall_until_round = raw.shieldwall_until_round.to_int()
		var expected: Dictionary = catalog.slots(actor.loadout_id)
		if raw.items.size() != expected.size():
			return _failure("combat_item_count")
		var previous_slot: int = -1
		for item_raw: Variant in raw.items:
			if not item_raw is Dictionary or not Sm2Validate.fields(item_raw, ["item_id", "definition_id", "slot", "current", "ammo"]) or not Sm2Validate.decimal(item_raw.item_id, 1, state.next_item_id - 1) or not item_raw.slot is String or not expected.has(item_raw.slot) or item_raw.definition_id != expected[item_raw.slot]:
				return _failure("combat_item_reference")
			var item_id: int = item_raw.item_id.to_int()
			var slot_index: int = Sm2CombatCatalog.SLOTS.find(item_raw.slot)
			if seen_items.has(item_id) or slot_index <= previous_slot:
				return _failure("combat_item_duplicate_or_order")
			seen_items[item_id] = true
			previous_slot = slot_index
			var gear: Sm2CombatGear = catalog.gear(item_raw.definition_id)
			if not Sm2Validate.integer(item_raw.current, 0, gear.capacity) or not Sm2Validate.integer(item_raw.ammo, 0, gear.ammo):
				return _failure("combat_item_resources")
			var item: Sm2CombatItem = Sm2CombatItem.new()
			item.item_id = item_id
			item.definition_id = gear.id
			item.slot = gear.slot
			item.current = int(item_raw.current)
			item.ammo = int(item_raw.ammo)
			component.items[item.slot] = item
		actor.combat = component
		if component.shieldwall_used and not actor.activation_started:
			return _failure("shieldwall_before_activation")
		if component.shieldwall_source == 0:
			if component.shieldwall_until_round != 0:
				return _failure("shieldwall_missing_source")
			if component.shieldwall_used and actor.spatial.occupies() and actor.morale != "fleeing" and component.shield_intact():
				return _failure("shieldwall_effect_missing")
		else:
			if not actor.spatial.occupies() or actor.morale == "fleeing" or not component.shield_intact() or component.shieldwall_source != component.item("shield").item_id:
				return _failure("shieldwall_invalid_source")
			var has_wall: bool = false
			for ability_id: String in catalog.gear(component.item("shield").definition_id).abilities:
				has_wall = has_wall or catalog.ability(ability_id).operation == "shieldwall"
			if not has_wall:
				return _failure("shieldwall_ability_missing")
			if component.shieldwall_until_round == state.round:
				if state.round < 2 or actor.activation_started or component.shieldwall_used:
					return _failure("shieldwall_expiry_activation")
			elif component.shieldwall_until_round == state.round + 1:
				if not actor.activation_started or not component.shieldwall_used:
					return _failure("shieldwall_current_activation")
			else:
				return _failure("shieldwall_expiry_round")
	return {"ok": true, "state": state, "errors": PackedStringArray()}

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "state": null, "errors": PackedStringArray([reason])}
