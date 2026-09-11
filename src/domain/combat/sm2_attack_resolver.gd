class_name Sm2AttackResolver
extends RefCounted
## Shared deterministic attack rules. The caller owns a detached transaction candidate.
const MAX_COUNTER: int = 9223372036854775806

static func extra_fatigue(state: Sm2TacticalState,actor_id: int) -> int:
	return state.development.extra_attack_fatigue(actor_id) if state.development!=null else 0

static func available_abilities(actor: Sm2TacticalActor, catalog: Sm2CombatCatalog, state: Sm2TacticalState=null) -> Array[String]:
	var result: Array[String] = []
	if actor.combat == null:
		return result
	if Sm2BodyCapabilityQuery.unarmed(actor,catalog) and not catalog.unarmed_ability().is_empty(): result.append(catalog.unarmed_ability())
	for slot: String in ["weapon", "shield"]:
		var item: Sm2CombatItem = actor.combat.item(slot)
		if item != null and (slot != "shield" or item.current > 0) and Sm2BodyCapabilityQuery.item_allowed(actor,catalog.gear(item.definition_id)):
			for id: String in catalog.gear(item.definition_id).abilities:
				if not result.has(id):
					result.append(id)
	if state!=null and state.development!=null and state.development.catalog.has_hybrids():
		var dev: Sm2BattleDevelopment=state.development
		if actor.spatial.actor_id==dev.catalog.hero():
			for id: String in dev.catalog.hybrids().ids():
				if dev.catalog.hybrids().ability(id).base_attack in result and dev.catalog.hybrids().available(dev.bodies[actor.spatial.actor_id],id): result.append(id)
	result.sort()
	return result

static func preview(state: Sm2TacticalState, catalog: Sm2CombatCatalog, command: Sm2Command, reaction: bool = false, position_only: bool = false) -> Dictionary:
	var result: Dictionary = {"allowed": false, "reason": "", "ap_cost": 0, "fatigue_cost": 0,
		"ammo_cost": 0, "hit_chance": 0, "modifiers": {}, "zones": [],
		"expected_hp_loss_x100": 0, "expected_armor_loss_x100": 0, "line_of_sight": false}
	var source: Sm2TacticalActor = state.actor(command.actor_id)
	var target: Sm2TacticalActor = state.actor(command.target_actor_id)
	if source == null or source.combat == null or not source.spatial.occupies():
		return _deny(result, "actor_unavailable")
	if source.morale == "fleeing":
		return _deny(result, "fleeing_cannot_attack")
	if not available_abilities(source, catalog, state).has(command.ability_id):
		return _deny(result, "ability_unavailable")
	var ability: Sm2CombatAbility = catalog.ability(command.ability_id)
	if target == null or target.combat == null or not target.spatial.occupies():
		return _deny(result, "target_unavailable")
	if ability.mode == "self":
		if target != source:
			return _deny(result, "self_target_required")
		if source.combat.shieldwall_used:
			return _deny(result, "shieldwall_already_used")
	else:
		if source.spatial.side == target.spatial.side:
			return _deny(result, "enemy_target_required")
		var distance: int = Sm2Hex.distance(source.spatial.position, target.spatial.position)
		if distance < ability.range_min or distance > ability.range_max:
			return _deny(result, "attack_range")
		var height: int = int(state.field.cell(source.spatial.position).elevation) - int(state.field.cell(target.spatial.position).elevation)
		if ability.mode == "melee" and absi(height) > 1:
			return _deny(result, "elevation_gap")
		if ability.mode == "ranged":
			if not neighbors_threatening(state, source, catalog, true).is_empty():
				return _deny(result, "ranged_in_control")
			var los: Dictionary = Sm2SpatialQueries.los(state.field, source.spatial.position, target.spatial.position, state.occupancy())
			if not los.visible:
				return _deny(result, "line_of_sight_blocked")
			result.line_of_sight = true
	if ability.operation == "shield_break" and not target.combat.shield_intact():
		return _deny(result, "target_shield_missing")
	if reaction and (ability.operation != "damage" or ability.mode != "melee" or not neighbors_threatening(state, target, catalog, true).has(command.actor_id)):
		return _deny(result, "reaction_unavailable")
	var hybrid: Dictionary=Sm2HybridQuery.details(state,command.actor_id,ability.id)
	if not hybrid.is_empty():
		if reaction: return _deny(result,"reaction_unavailable")
		result["hybrid"]=hybrid
		result["mana_cost"]=hybrid.mana_cost
		result["cost_calculation"]=hybrid.cost_calculation
		if not state.mana.has(command.actor_id) or state.mana[command.actor_id].current<int(hybrid.mana_cost): return _deny(result,"insufficient_concentration")
	var ap_cost: int = 0 if reaction else ability.ap_cost
	var fatigue_cost: int = (5 if reaction else ability.fatigue_cost)+extra_fatigue(state,command.actor_id) if ability.mode!="self" else ability.fatigue_cost
	if not position_only and source.spatial.ap < ap_cost:
		return _deny(result, "insufficient_ap")
	if not position_only and source.spatial.fatigue_max - source.spatial.fatigue < fatigue_cost:
		return _deny(result, "fatigue_limit")
	if not position_only and ability.ammo_cost > 0 and source.combat.item("weapon").ammo < ability.ammo_cost:
		return _deny(result, "no_ammunition")
	if not position_only and ability.operation == "damage" and state.rng.draws >= MAX_COUNTER:
		return _deny(result, "rng_counter_limit")
	result.allowed = true
	if target.body_catalog!=null and not target.body_catalog.trauma(ability.id).is_empty():
		result["function_trauma"]=target.body_catalog.title(target.body_catalog.trauma(ability.id))
		if target.body_catalog.supports_prostheses(): result["function_sever"]=target.body_catalog.severs(ability.id)
	result.ap_cost = ap_cost
	result.fatigue_cost = fatigue_cost
	result.ammo_cost = ability.ammo_cost
	if ability.operation != "damage":
		result["shield_loss"] = mini(ability.shield_damage, target.combat.item("shield").current) if ability.operation == "shield_break" else 0
		return result
	if position_only:
		return result
	var modifiers: Dictionary = hit_modifiers(state, source, target, catalog, ability)
	result.modifiers = modifiers
	result.hit_chance = clampi(modifiers.skill + modifiers.ability + modifiers.height + modifiers.surround + modifiers.range - modifiers.defense, 5, 95)
	var hp_weighted: int = 0
	var armor_weighted: int = 0
	for zone: Dictionary in attack_zones(target,catalog,ability):
		var armor_item: Sm2CombatItem = target.combat.item(zone.id)
		var armor: int = armor_item.current if armor_item != null else 0
		var hp_min: int = 2147483647
		var hp_max: int = 0
		var armor_min: int = 2147483647
		var armor_max: int = 0
		var sum_hp: int = 0
		var sum_armor: int = 0
		for raw_damage: int in range(ability.damage_min, ability.damage_max + 1):
			var damage: Dictionary = damage_losses(raw_damage, armor, 2147483647 if target.anatomy!=null or target.barrier!=null or not hybrid.is_empty() else target.combat.hp, ability.armor_percent, ability.penetration_percent, zone.hp_percent)
			damage.hp_loss=Sm2BarrierRules.loss(target,int(damage.hp_loss)+int(hybrid.get("psionic_damage",0))).hp_loss
			hp_min = mini(hp_min, damage.hp_loss)
			hp_max = maxi(hp_max, damage.hp_loss)
			armor_min = mini(armor_min, damage.armor_loss)
			armor_max = maxi(armor_max, damage.armor_loss)
			sum_hp += damage.hp_loss
			sum_armor += damage.armor_loss
		hp_weighted += int(zone.weight) * sum_hp
		armor_weighted += int(zone.weight) * sum_armor
		result.zones.append({"id": zone.id, "chance": zone.weight, "hp_min": hp_min, "hp_max": hp_max, "armor_min": armor_min, "armor_max": armor_max})
	var denominator: int = 100 * (ability.damage_max - ability.damage_min + 1)
	result.expected_hp_loss_x100 = _div(int(result.hit_chance) * hp_weighted, denominator)
	result.expected_armor_loss_x100 = _div(int(result.hit_chance) * armor_weighted, denominator)
	return result

static func hit_modifiers(state: Sm2TacticalState, source: Sm2TacticalActor, target: Sm2TacticalActor,
	catalog: Sm2CombatCatalog, ability: Sm2CombatAbility) -> Dictionary:
	var ranged: bool = ability.mode == "ranged"
	var skill: int = Sm2CombatStatQuery.explain(state,source,catalog,"ranged_skill" if ranged else "melee_skill").value
	var defense: int = Sm2CombatStatQuery.explain(state,target,catalog,"ranged_defense" if ranged else "melee_defense").value
	var shield: int = 0
	var wall: int = 0
	if Sm2BodyCapabilityQuery.shield(target,catalog):
		var gear: Sm2CombatGear = catalog.gear(target.combat.item("shield").definition_id)
		shield = gear.ranged_defense if ranged else gear.melee_defense
		if target.combat.shieldwall_source != 0:
			for id: String in gear.abilities:
				var effect: Sm2CombatAbility = catalog.ability(id)
				if effect.operation == "shieldwall":
					wall = effect.ranged_bonus if ranged else effect.melee_bonus
	var height_delta: int = int(state.field.cell(source.spatial.position).elevation) - int(state.field.cell(target.spatial.position).elevation)
	var surround: int = 0 if ranged else 5 * mini(3, maxi(0, neighbors_threatening(state, target, catalog, false).size() - 1))
	return {"skill": skill, "ability": ability.hit_bonus, "height": 10 * signi(height_delta), "surround": surround,
		"range": -4 * (Sm2Hex.distance(source.spatial.position, target.spatial.position) - 2) if ranged else 0,
		"base_defense": defense, "shield": shield, "shieldwall": wall, "defense": defense + shield + wall}

static func neighbors_threatening(state: Sm2TacticalState, target: Sm2TacticalActor,
	catalog: Sm2CombatCatalog, require_reaction: bool) -> Array[int]:
	var result: Array[int] = []
	for id: int in state.sorted_ids():
		var actor: Sm2TacticalActor = state.actor(id)
		if actor.spatial.side == target.spatial.side or not actor.spatial.occupies() or actor.morale == "fleeing" or actor.combat == null:
			continue
		if Sm2Hex.distance(actor.spatial.position, target.spatial.position) != 1 or absi(int(state.field.cell(actor.spatial.position).elevation) - int(state.field.cell(target.spatial.position).elevation)) > 1:
			continue
		if require_reaction and (actor.reactions_left == 0 or actor.spatial.fatigue_max - actor.spatial.fatigue < 5+extra_fatigue(state,id)):
			continue
		var weapon_item: Sm2CombatItem = actor.combat.item("weapon")
		if require_reaction and weapon_item != null and catalog.gear(weapon_item.definition_id).two_handed:
			continue
		for ability_id: String in available_abilities(actor,catalog):
			var ability: Sm2CombatAbility = catalog.ability(ability_id)
			if ability.operation == "damage" and ability.mode == "melee":
				result.append(id)
				break
	return result

static func damage_losses(damage: int, armor: int, hp: int, armor_percent: int, penetration_percent: int, location_percent: int) -> Dictionary:
	var armor_loss: int = mini(armor, _div(damage * armor_percent, 100))
	var after: int = armor - armor_loss
	var penetrating: int = maxi(0, _div(damage * penetration_percent, 100) - _div(after, 10))
	var overflow: int = maxi(0, damage - armor)
	return {"armor_loss": armor_loss, "armor_after": after, "penetrating": penetrating, "overflow": overflow,
		"hp_loss": mini(hp, _div(maxi(penetrating, overflow) * location_percent, 100))}

static func resolve(state: Sm2TacticalState, catalog: Sm2CombatCatalog, command: Sm2Command, reaction: bool = false, context: Sm2ConsequenceContext = null) -> Dictionary:
	var check: Dictionary = preview(state, catalog, command, reaction)
	if not check.allowed:
		return {"accepted": false, "code": check.reason, "events": []}
	var source: Sm2TacticalActor = state.actor(command.actor_id)
	var target: Sm2TacticalActor = state.actor(command.target_actor_id)
	var ability: Sm2CombatAbility = catalog.ability(command.ability_id)
	var events: Array[Dictionary] = []
	var hybrid: Dictionary=check.get("hybrid",{})
	if not hybrid.is_empty():
		state.mana[command.actor_id].current-=int(hybrid.mana_cost)
		events.append({"type":"hybrid_started","actor_id":str(command.actor_id),"target_actor_id":str(command.target_actor_id),"ability_id":ability.id,"name":hybrid.name})
		events.append({"type":"concentration_spent","actor_id":str(command.actor_id),"amount":hybrid.mana_cost,"current":state.mana[command.actor_id].current})
	source.spatial.ap -= int(check.ap_cost)
	source.spatial.fatigue += int(check.fatigue_cost)
	if reaction:
		source.reactions_left -= 1
		events.append({"type": "reaction_spent", "actor_id": str(command.actor_id), "target_actor_id": str(command.target_actor_id)})
	if ability.ammo_cost > 0: source.combat.item("weapon").ammo -= ability.ammo_cost
	events.append({"type": "resources_spent", "actor_id": str(command.actor_id), "ap": check.ap_cost, "fatigue": check.fatigue_cost, "ammo": ability.ammo_cost})
	if ability.operation == "shieldwall":
		source.combat.shieldwall_used = true
		source.combat.shieldwall_source = source.combat.item("shield").item_id
		source.combat.shieldwall_until_round = state.round + 1
		events.append({"type": "shieldwall_started", "actor_id": str(command.actor_id), "item_id": str(source.combat.shieldwall_source), "until_round": str(state.round + 1)})
	elif ability.operation == "shield_break":
		var shield: Sm2CombatItem = target.combat.item("shield")
		var loss: int = mini(shield.current, ability.shield_damage)
		shield.current -= loss
		events.append({"type": "shield_damaged", "actor_id": str(command.actor_id), "target_actor_id": str(command.target_actor_id), "item_id": str(shield.item_id), "loss": loss, "remaining": shield.current})
		if shield.current == 0:
			target.combat.clear_wall()
			events.append({"type": "shield_destroyed", "target_actor_id": str(command.target_actor_id), "item_id": str(shield.item_id)})
	else:
		events.append({"type": "attack_attempted", "actor_id": str(command.actor_id), "target_actor_id": str(command.target_actor_id), "ability_id": ability.id, "hit_chance": check.hit_chance})
		var hit_roll: int = Sm2BattleDice.roll(state.rng, 1, 100)
		if hit_roll == 0:
			return {"accepted": false, "code": "rng_counter_limit", "events": []}
		var hit: bool = hit_roll <= int(check.hit_chance)
		events.append({"type": "attack_hit" if hit else "attack_missed", "actor_id": str(command.actor_id), "target_actor_id": str(command.target_actor_id), "hit_chance": check.hit_chance, "roll": hit_roll})
		if hit:
			var zone_roll: int = Sm2BattleDice.roll(state.rng, 1, 100)
			var damage_roll: int = Sm2BattleDice.roll(state.rng, ability.damage_min, ability.damage_max) if zone_roll > 0 else 0
			if zone_roll == 0 or damage_roll == 0:
				return {"accepted": false, "code": "rng_counter_limit", "events": []}
			var zone: Dictionary = {}
			var ceiling: int = 0
			for candidate: Dictionary in attack_zones(target,catalog,ability):
				ceiling += int(candidate.weight)
				if zone_roll <= ceiling:
					zone = candidate
					break
			var armor: Sm2CombatItem = target.combat.item(zone.id)
			var losses: Dictionary = damage_losses(damage_roll, armor.current if armor != null else 0,
				2147483647 if target.anatomy!=null or target.barrier!=null or not hybrid.is_empty() else target.combat.hp, ability.armor_percent, ability.penetration_percent, zone.hp_percent)
			events.append({"type": "damage_rolled", "target_actor_id": str(command.target_actor_id), "zone": zone.id, "zone_roll": zone_roll, "raw_damage": damage_roll})
			if armor != null:
				armor.current = losses.armor_after
			events.append({"type": "armor_damaged", "target_actor_id": str(command.target_actor_id), "zone": zone.id, "loss": losses.armor_loss, "remaining": losses.armor_after})
			if not hybrid.is_empty():
				events.append({"type":"hybrid_damage","actor_id":str(command.actor_id),"target_actor_id":str(command.target_actor_id),"ability_id":ability.id,"physical":losses.hp_loss,"psionic":hybrid.psionic_damage})
			var hit_part: String=target.body_catalog.trauma(ability.id) if target.body_catalog!=null and not target.body_catalog.trauma(ability.id).is_empty() else "head" if zone.id=="head" else "torso"
			if state.survival!=null:
				# Barrier is spent in channel order; psionic damage cannot create a cut.
				var physical: int=Sm2BarrierRules.absorb(target,int(losses.hp_loss),events)
				var psionic: int=Sm2BarrierRules.absorb(target,int(hybrid.get("psionic_damage",0)),events)
				Sm2HpApplication.apply(state,target,command.actor_id,physical,events,hit_part,ability.mode in ["melee","ranged"] and not ability.id.contains("unarmed"))
				if target.spatial.alive: Sm2HpApplication.apply(state,target,command.actor_id,psionic,events,hit_part,false)
				losses.hp_loss=physical+psionic
			else:
				losses.hp_loss=Sm2BarrierRules.absorb(target,int(losses.hp_loss)+int(hybrid.get("psionic_damage",0)),events)
				Sm2HpApplication.apply(state,target,command.actor_id,int(losses.hp_loss),events,hit_part,ability.mode in ["melee","ranged"] and not ability.id.contains("unarmed"))
			Sm2BodyFunctionRules.after_hit(state,source,target,ability.id,int(losses.hp_loss),events)
			if context != null and not Sm2MoraleResolver.after_hit(state, catalog, target, int(losses.hp_loss), context, events):
				return {"accepted": false, "code": "rng_counter_limit", "events": []}
	if state.development != null and ability.operation == "damage":
		var practice_error: String = state.development.award(command.actor_id,ability.id,events)
		if not practice_error.is_empty(): return {"accepted":false,"code":practice_error,"events":[]}
	return {"accepted": true, "code": "accepted", "events": events}

static func morale_percent(morale: String) -> int:
	return 90 if morale == "wavering" else (80 if morale == "breaking" else 100)

static func attack_zones(target: Sm2TacticalActor, catalog: Sm2CombatCatalog, ability: Sm2CombatAbility) -> Array:
	if target.body_catalog!=null and not target.body_catalog.trauma(ability.id).is_empty():
		return [{"id":target.body_catalog.armor_slot(),"weight":100,"hp_percent":100}]
	return catalog.zones(target.loadout_id)

static func _div(numerator: int, denominator: int) -> int:
	@warning_ignore("integer_division")
	var result: int = numerator / denominator
	return result

static func _deny(result: Dictionary, reason: String) -> Dictionary:
	result.reason = reason
	return result
