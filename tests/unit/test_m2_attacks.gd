extends RefCounted

static func run(t: Sm2TestHarness) -> void:
	_math(t)
	_content(t)
	_hits(t)
	_preview(t)
	_shields(t)
	_bow(t)
	_death(t)
	_counter(t)
	_action_boundaries(t)
	t.complete_suite("m2_attacks")

static func _math(t: Sm2TestHarness) -> void:
	# Explicit oracles from COMBAT_RULES_M2 C/D, independent of command RNG.
	for row: Array in [[36,100,65,100,20,100,36,1], [36,20,65,100,20,100,20,16],
		[36,40,65,100,20,150,36,10], [36,0,65,100,20,150,0,54],
		[40,30,65,120,25,100,30,10], [36,36,65,100,20,100,36,7],
		[36,1000,65,100,20,100,36,0], [36,0,3,100,20,150,0,3]]:
		var actual: Dictionary = Sm2AttackResolver.damage_losses(row[0], row[1], row[2], row[3], row[4], row[5])
		t.equal([actual.armor_loss, actual.hp_loss], [row[6], row[7]], "combat math armor/HP oracle " + str(row))

static func _content(t: Sm2TestHarness) -> void:
	var loaded: Dictionary = Sm2CombatFixtures.loaded()
	t.expect(loaded.ok, "combat content loads")
	var catalog: Sm2CombatCatalog = loaded.combat
	t.equal(catalog.profile("m2:loadout.sword_fighter").hp_max, 60, "combat authored fighter HP")
	t.equal(catalog.gear("m2:equipment.shield").capacity, 24, "combat authored shield")
	t.equal(catalog.ability("m2:ability.axe_strike").armor_percent, 120, "combat authored axe armor multiplier")
	var before: String = catalog.fingerprint()
	var copied: Sm2CombatAbility = catalog.ability("m2:ability.sword_strike")
	copied.damage_max = 999
	var gear_copy: Sm2CombatGear = catalog.gear("m2:equipment.sword")
	gear_copy.abilities.clear()
	t.equal(catalog.ability("m2:ability.sword_strike").damage_max, 40, "combat definitions detached")
	t.equal(catalog.gear("m2:equipment.sword").abilities.size(), 1, "combat ability array detached")
	for kind: String in ["operation", "duplicate", "unknown_ability", "wrong_slot", "zone_weight", "bad_hp", "fraction", "twohand", "profile_link", "bad_type", "extra_field"]:
		var raw: Dictionary = JSON.parse_string(JSON.stringify(catalog.to_data()))
		match kind:
			"operation": raw.abilities[0].operation = "unimplemented_fire"
			"duplicate": raw.abilities.append(raw.abilities[0].duplicate(true))
			"unknown_ability": raw.equipment[0].abilities = ["missing"]
			"wrong_slot": raw.equipment[0].slot = "body"
			"zone_weight": raw.bodies[0].zones[0].weight = 24
			"bad_hp": raw.profiles[0].hp_max = 0
			"fraction": raw.profiles[0].melee_skill = 1.5
			"twohand":
				for entry: Dictionary in raw.equipment:
					if entry.id == "m2:equipment.sword": entry.two_handed = true
			"profile_link": raw.profiles[0].id = "missing"
			"bad_type": raw.equipment[0] = null
			"extra_field": raw.abilities[0].unknown = 1
		t.expect(not catalog.build(raw, loaded.catalog).is_empty(), "combat catalog rejects " + kind)
		t.equal(catalog.fingerprint(), before, "combat rejected catalog preserves published cache")
	var reordered: Dictionary = catalog.to_data()
	for key: String in ["profiles", "equipment", "abilities", "bodies"]:
		reordered[key].reverse()
	t.expect(catalog.build(reordered, loaded.catalog).is_empty(), "combat catalog reordered builds")
	t.equal(catalog.fingerprint(), before, "combat catalog normalized fingerprint")
	var battle: Sm2TacticalBattle = Sm2CombatFixtures.battle(t)
	var saved: Dictionary = battle.capture()
	var seen: Dictionary = {}
	for actor: Dictionary in saved.actors:
		for item: Dictionary in actor.combat.items:
			t.expect(not seen.has(item.item_id), "combat item IDs globally unique")
			seen[item.item_id] = true
	t.equal(seen.size(), 8, "combat two fully equipped actors have eight instances")
	t.equal(saved.next_item_id, "9", "combat deterministic item allocator")

static func _hits(t: Sm2TestHarness) -> void:
	# Park-Miller seeds independently calculated: 11005 -> hit55 zone25 D39;
	# 36 -> hit56; 1231 -> hit1 zone26 D36. No injected production dice.
	for seed_value: int in [11005, 36, 1231]:
		var battle: Sm2TacticalBattle = Sm2CombatFixtures.battle(t, [2, 5], seed_value)
		var command: Sm2Command = Sm2CombatFixtures.command(battle, "sword_strike", 5)
		var before: String = battle.state_hash()
		var preview: Dictionary = battle.preview(command)
		t.equal(preview.hit_chance, 55, "combat example B exact hit threshold")
		t.equal(battle.state_hash(), before, "combat preview inert including RNG")
		var result: Sm2CommandResult = Sm2CombatFixtures.act(t, battle, "sword_strike", 5)
		var target: Dictionary = Sm2CombatFixtures.actor(battle.capture(), 5)
		var source: Dictionary = Sm2CombatFixtures.actor(battle.capture(), 2)
		t.equal([source.ap, source.fatigue], [5, 10], "combat attack costs even on miss")
		if seed_value == 36:
			t.equal(Sm2TurnTestFixtures.types(result.events), ["resources_spent", "attack_attempted", "attack_missed"], "combat H+1 miss has no zone or damage events")
			t.equal([target.combat.hp, Sm2CombatFixtures.item(target, "body").current], [65, 100], "combat miss no damage")
			t.equal(battle.capture().rng.draws, "1", "combat miss makes exactly one draw")
		else:
			t.equal(result.events[2].type, "attack_hit", "combat H included in successful range")
			t.equal(battle.capture().rng.draws, "3", "combat hit has three draws")
			if seed_value == 11005:
				t.equal([result.events[3].zone, result.events[3].zone_roll, result.events[3].raw_damage], ["head", 25, 39], "combat exact head boundary and damage RNG")
				t.equal([target.combat.hp, Sm2CombatFixtures.item(target, "head").current], [55, 1], "combat head damage oracle")
			else:
				t.equal([result.events[3].zone, result.events[3].zone_roll, result.events[3].raw_damage], ["body", 26, 36], "combat exact body boundary and damage RNG")
				t.equal([target.combat.hp, Sm2CombatFixtures.item(target, "body").current], [64, 64], "combat example C integrated HP/armor")
			t.equal(Sm2CombatFixtures.item(target, "shield").current, 24, "combat ordinary attack does not damage shield")

static func _preview(t: Sm2TestHarness) -> void:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var raw: Dictionary = content.combat.to_data()
	for profile: Dictionary in raw.profiles:
		if profile.id == "m2:profile.shieldbearer": profile.melee_defense = 15
	var catalog: Sm2CombatCatalog = Sm2CombatCatalog.new()
	t.expect(catalog.build(raw, content.catalog).is_empty(), "combat expectation fixture catalog")
	var battle: Sm2TacticalBattle = Sm2TacticalBattle.new(content.catalog, catalog)
	t.expect(battle.start(Sm2CombatFixtures.setup(content)).ok, "combat expectation starts")
	var snapshot: Dictionary = Sm2CombatFixtures.untyped(battle)
	var target: Dictionary = Sm2CombatFixtures.actor(snapshot, 5)
	Sm2CombatFixtures.item(target, "body").current = 0
	Sm2CombatFixtures.item(target, "head").current = 0
	t.expect(battle.restore(snapshot).ok, "combat armorless candidate restores")
	var check: Dictionary = battle.preview(Sm2CombatFixtures.command(battle, "sword_strike", 5))
	t.equal(check.hit_chance, 50, "combat expectation H50")
	t.equal(check.expected_hp_loss_x100, 1965, "combat example E exact expectation")
	t.equal(check.expected_armor_loss_x100, 0, "combat armorless expectation")
	t.equal([check.zones[0].hp_min, check.zones[0].hp_max, check.zones[1].hp_min, check.zones[1].hp_max], [45, 60, 30, 40], "combat conditional ranges per zone")
	# Height and a second surrounding melee ally are recomputed from positions.
	var surrounded: Sm2TacticalBattle = Sm2CombatFixtures.battle(t, [2, 5, 1])
	var state: Dictionary = Sm2CombatFixtures.untyped(surrounded)
	Sm2CombatFixtures.actor(state, 1).q = 2
	Sm2CombatFixtures.actor(state, 1).r = 1
	var field: Sm2Battlefield = Sm2SpatialFixtures.field(8, 5, [Sm2SpatialFixtures.tile(1, 2, "ground", 1)])
	state.field = field.to_data()
	state.field_fingerprint = field.fingerprint()
	t.expect(surrounded.restore(state).ok, "combat elevated surrounding fixture")
	check = surrounded.preview(Sm2CombatFixtures.command(surrounded, "sword_strike", 5))
	t.equal([check.modifiers.height, check.modifiers.surround, check.hit_chance], [10, 5, 70], "combat example B height and surrounding")
	for morale: String in ["wavering", "breaking", "fleeing"]:
		var moral: Sm2TacticalBattle = Sm2CombatFixtures.battle(t)
		var data: Dictionary = Sm2CombatFixtures.untyped(moral)
		var actor: Dictionary = Sm2CombatFixtures.actor(data, 5)
		actor.morale = morale
		actor.round_morale = morale
		actor.initiative = 67 if morale == "wavering" else (60 if morale == "breaking" else 75)
		t.expect(moral.restore(data).ok, "combat given target morale loads")
		var p: Dictionary = moral.preview(Sm2CombatFixtures.command(moral, "sword_strike", 5))
		t.equal(p.modifiers.base_defense, 9 if morale == "wavering" else (8 if morale == "breaking" else 0), "combat morale changes only own defense")
		t.equal(p.modifiers.shield, 15, "combat morale preserves item bonus")
	for skill: int in [0, 10000]:
		var changed: Dictionary = content.combat.to_data()
		for profile: Dictionary in changed.profiles:
			if profile.id == "m2:profile.fighter": profile.melee_skill = skill
		var cap_catalog: Sm2CombatCatalog = Sm2CombatCatalog.new()
		t.expect(cap_catalog.build(changed, content.catalog).is_empty(), "combat clamp fixture")
		var cap: Sm2TacticalBattle = Sm2TacticalBattle.new(content.catalog, cap_catalog)
		cap.start(Sm2CombatFixtures.setup(content))
		t.equal(cap.preview(Sm2CombatFixtures.command(cap, "sword_strike", 5)).hit_chance, 5 if skill == 0 else 95, "combat hit chance clamp")
		for seed_value: int in ([3855, 86] if skill == 0 else [2245, 76]):
			t.expect(cap.start(Sm2CombatFixtures.setup(content, [2, 5], seed_value)).ok, "combat boundary roll fixture starts")
			var result: Sm2CommandResult = Sm2CombatFixtures.act(t, cap, "sword_strike", 5)
			var expected_hit: bool = seed_value in [3855, 2245]
			t.equal(result.events[2].type, "attack_hit" if expected_hit else "attack_missed", "combat 5/6 and95/96 hit boundaries")

static func _shields(t: Sm2TestHarness) -> void:
	var wall: Sm2TacticalBattle = Sm2CombatFixtures.battle(t, [2, 5])
	Sm2CombatFixtures.act(t, wall, "shieldwall", 2)
	_reject(t, wall, Sm2CombatFixtures.command(wall, "shieldwall", 2), "shieldwall_already_used")
	Sm2CombatFixtures.end(t, wall, "wait")
	var prediction: Dictionary = wall.preview(Sm2CombatFixtures.command(wall, "spear_thrust", 2))
	t.equal(prediction.modifiers.shieldwall, 15, "combat active wall melee bonus")
	Sm2CombatFixtures.end(t, wall)
	t.expect(Sm2CombatFixtures.actor(wall.capture(), 2).combat.shieldwall_source != "0", "combat Wait retains shield effect")
	var axe: Sm2TacticalBattle = Sm2CombatFixtures.battle(t, [4, 1])
	var before: Dictionary = axe.capture()
	Sm2CombatFixtures.act(t, axe, "split_shield", 1)
	t.equal(Sm2CombatFixtures.item(Sm2CombatFixtures.actor(axe.capture(), 1), "shield").current, 8, "combat first shield break 24 to8")
	Sm2CombatFixtures.act(t, axe, "split_shield", 1)
	var target: Dictionary = Sm2CombatFixtures.actor(axe.capture(), 1)
	t.equal([Sm2CombatFixtures.item(target, "shield").current, target.combat.hp], [0, 65], "combat second shield break0 noHP")
	t.equal([Sm2CombatFixtures.actor(axe.capture(), 4).ap, Sm2CombatFixtures.actor(axe.capture(), 4).fatigue], [1, 30], "combat two splits cost8AP30fatigue")
	t.equal(axe.capture().rng, before.rng, "combat shield break no RNG")
	t.equal(Sm2CombatFixtures.actor(axe.view(), 1).fatigue_max, 65, "combat broken shield retains load")
	_reject(t, axe, Sm2CombatFixtures.command(axe, "split_shield", 1), "target_shield_missing")
	# The first normal turn of actor2 expires last round's wall, not round start.
	var lifecycle: Sm2TacticalBattle = Sm2CombatFixtures.battle(t, [3, 2, 5])
	Sm2CombatFixtures.end(t, lifecycle)
	Sm2CombatFixtures.act(t, lifecycle, "shieldwall", 2)
	Sm2CombatFixtures.end(t, lifecycle, "wait")
	Sm2CombatFixtures.end(t, lifecycle)
	Sm2CombatFixtures.end(t, lifecycle)
	var pending: Dictionary = Sm2CombatFixtures.actor(lifecycle.capture(), 2)
	t.equal([lifecycle.view().round, pending.activation_started, pending.combat.shieldwall_used, pending.combat.shieldwall_until_round], [2, false, false, "2"], "combat wall remains across round resource reset")
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var restored: Sm2TacticalBattle = Sm2TacticalBattle.new(content.catalog, content.combat)
	t.expect(restored.restore(Sm2CombatFixtures.untyped(lifecycle)).ok, "combat wall between round and activation restores")
	t.equal(restored.state_hash(), lifecycle.state_hash(), "combat wall restore no extra scheduling")
	var next: Sm2CommandResult = Sm2CombatFixtures.end(t, lifecycle)
	var resumed: Sm2CommandResult = Sm2CombatFixtures.end(t, restored)
	t.equal(next.events, resumed.events, "combat wall expiry deterministic after reload")
	t.expect(Sm2TurnTestFixtures.types(next.events).has("shieldwall_expired"), "combat first activation expires wall")
	t.equal(Sm2CombatFixtures.actor(lifecycle.capture(), 2).combat.shieldwall_source, "0", "combat wall source cleared")

static func _bow(t: Sm2TestHarness) -> void:
	var content: Dictionary = Sm2CombatFixtures.loaded()
	var setup: Dictionary = Sm2CombatFixtures.setup(content, [3, 5], 36)
	setup.actors[1].q = 6
	var battle: Sm2TacticalBattle = Sm2TacticalBattle.new(content.catalog, content.combat)
	t.expect(battle.start(setup).ok, "combat bow starts")
	var preview: Dictionary = battle.preview(Sm2CombatFixtures.command(battle, "bow_shot", 5))
	t.equal([preview.hit_chance, preview.modifiers.range], [33, -12], "combat bow range penalty against authored defense5")
	Sm2CombatFixtures.act(t, battle, "bow_shot", 5)
	t.equal(Sm2CombatFixtures.item(Sm2CombatFixtures.actor(battle.capture(), 3), "weapon").ammo, 7, "combat missed bow consumes one arrow")
	var snapshot: Dictionary = Sm2CombatFixtures.untyped(battle)
	Sm2CombatFixtures.item(Sm2CombatFixtures.actor(snapshot, 3), "weapon").ammo = 1
	t.expect(battle.restore(snapshot).ok, "combat last arrow candidate")
	Sm2CombatFixtures.act(t, battle, "bow_shot", 5)
	Sm2CombatFixtures.end(t, battle)
	Sm2CombatFixtures.end(t, battle)
	_reject(t, battle, Sm2CombatFixtures.command(battle, "bow_shot", 5), "no_ammunition")
	var blocked: Dictionary = Sm2CombatFixtures.setup(content, [3, 5])
	blocked.actors[1].q = 4
	blocked.field = Sm2SpatialFixtures.field(8, 5, [Sm2SpatialFixtures.tile(2, 2, "ground", 0, false, true)]).to_data()
	t.expect(battle.start(blocked).ok, "combat blocked ray starts")
	_reject(t, battle, Sm2CombatFixtures.command(battle, "bow_shot", 5), "line_of_sight_blocked")
	var control: Dictionary = Sm2CombatFixtures.setup(content, [3, 5, 4])
	control.actors[1].q = 1
	control.actors[1].r = 1
	control.actors[2].q = 5
	t.expect(battle.start(control).ok, "combat bow control starts")
	_reject(t, battle, Sm2CombatFixtures.command(battle, "bow_shot", 4), "ranged_in_control")
	var free: Dictionary = Sm2CombatFixtures.untyped(battle)
	Sm2CombatFixtures.actor(free, 5).reactions_left = 0
	t.expect(battle.restore(free).ok, "combat exhausted controller restores")
	t.expect(battle.preview(Sm2CombatFixtures.command(battle, "bow_shot", 4)).allowed, "combat no reaction permits otherwise legal shot")
	free = Sm2CombatFixtures.untyped(battle)
	Sm2CombatFixtures.actor(free, 5).reactions_left = 1
	Sm2CombatFixtures.actor(free, 5).fatigue = 61
	t.expect(battle.restore(free).ok, "combat tired controller loads")
	t.expect(battle.preview(Sm2CombatFixtures.command(battle, "bow_shot", 4)).allowed, "combat less than5 free fatigue cannot control shot")
	for morale: String in ["wavering", "breaking", "fleeing"]:
		battle.start(setup)
		var moral_state: Dictionary = Sm2CombatFixtures.untyped(battle)
		var archer: Dictionary = Sm2CombatFixtures.actor(moral_state, 3)
		archer.morale = morale
		archer.round_morale = morale
		archer.initiative = 93 if morale == "wavering" else (83 if morale == "breaking" else 104)
		t.expect(battle.restore(moral_state).ok, "combat shooter morale loads")
		if morale == "fleeing":
			_reject(t, battle, Sm2CombatFixtures.command(battle, "bow_shot", 5), "fleeing_cannot_attack")
		else:
			t.equal(battle.preview(Sm2CombatFixtures.command(battle, "bow_shot", 5)).modifiers.skill, 58 if morale == "wavering" else 52, "combat morale scales attack skill with floor")
	# Example E uses a deliberately different own ranged defense of10.
	var raw: Dictionary = content.combat.to_data()
	for profile: Dictionary in raw.profiles:
		if profile.id == "m2:profile.shieldbearer": profile.ranged_defense = 10
	var example_catalog: Sm2CombatCatalog = Sm2CombatCatalog.new()
	example_catalog.build(raw, content.catalog)
	var example: Sm2TacticalBattle = Sm2TacticalBattle.new(content.catalog, example_catalog)
	example.start(setup)
	t.equal(example.preview(Sm2CombatFixtures.command(example, "bow_shot", 5)).hit_chance, 28, "combat exact example E ranged chance")
	Sm2CombatFixtures.end(t, example, "wait")
	Sm2CombatFixtures.act(t, example, "shieldwall", 5)
	Sm2CombatFixtures.end(t, example)
	t.equal(example.preview(Sm2CombatFixtures.command(example, "bow_shot", 5)).hit_chance, 5, "combat exact example E ranged wall25 reaches minimum")

static func _death(t: Sm2TestHarness) -> void:
	var battle: Sm2TacticalBattle = Sm2CombatFixtures.battle(t)
	var snapshot: Dictionary = Sm2CombatFixtures.untyped(battle)
	var victim: Dictionary = Sm2CombatFixtures.actor(snapshot, 5)
	victim.combat.hp = 1
	Sm2CombatFixtures.item(victim, "body").current = 0
	Sm2CombatFixtures.item(victim, "head").current = 0
	t.expect(battle.restore(snapshot).ok, "combat wounded fixture restores")
	var result: Sm2CommandResult = Sm2CombatFixtures.act(t, battle, "sword_strike", 5)
	t.equal(Sm2TurnTestFixtures.types(result.events).count("actor_died"), 1, "combat exactly one death event")
	victim = Sm2CombatFixtures.actor(battle.capture(), 5)
	t.equal([victim.combat.hp, victim.alive, victim.ap, victim.reactions_left, victim.turn_done], [0, false, 0, 0, true], "combat death stable state")
	t.equal(battle.view().main_queue, [2], "combat killed pending actor removed")
	_reject(t, battle, Sm2CombatFixtures.command(battle, "sword_strike", 5), "target_unavailable")
	var step: Sm2Command = Sm2TurnTestFixtures.command(battle, "move", Vector2i(2, 2))
	t.expect(battle.execute(step).accepted, "combat corpse frees occupied cell")
	Sm2CombatFixtures.end(t, battle)
	t.equal(battle.view().round, 2, "combat dead actor does not block next round")

static func _counter(t: Sm2TestHarness) -> void:
	var battle: Sm2TacticalBattle = Sm2CombatFixtures.battle(t)
	_reject(t, battle, Sm2CombatFixtures.command(battle, "bow_shot", 5), "ability_unavailable")
	_reject(t, battle, Sm2CombatFixtures.command(battle, "sword_strike", 2), "enemy_target_required")
	var snapshot: Dictionary = Sm2CombatFixtures.untyped(battle)
	snapshot.rng.draws = "9223372036854775805"
	t.expect(battle.restore(snapshot).ok, "combat RNG near ceiling restores")
	var before: String = battle.state_hash()
	var result: Sm2CommandResult = battle.execute(Sm2CombatFixtures.command(battle, "sword_strike", 5))
	t.expect(not result.accepted and result.code == "rng_counter_limit", "combat RNG ceiling during hit rejects whole candidate")
	t.equal(battle.state_hash(), before, "combat rollback after partial candidate dice/costs")

static func _action_boundaries(t: Sm2TestHarness) -> void:
	var battle: Sm2TacticalBattle = Sm2CombatFixtures.battle(t)
	var state: Dictionary = Sm2CombatFixtures.untyped(battle)
	var actor: Dictionary = Sm2CombatFixtures.actor(state, 2)
	actor.ap = 4
	actor.fatigue = 63
	t.expect(battle.restore(state).ok, "combat exact AP/fatigue candidate")
	var result: Sm2CommandResult = Sm2CombatFixtures.act(t, battle, "sword_strike", 5)
	t.equal([Sm2CombatFixtures.actor(battle.capture(), 2).fatigue, battle.view().active_actor_id], [73, 5], "combat attack fills fatigue and auto-ends on AP0")
	t.expect(Sm2TurnTestFixtures.types(result.events).has("turn_ended"), "combat AP0 attack emits automatic turn end")
	battle = Sm2CombatFixtures.battle(t)
	state = Sm2CombatFixtures.untyped(battle)
	Sm2CombatFixtures.actor(state, 2).fatigue = 64
	t.expect(battle.restore(state).ok, "combat excessive fatigue fixture")
	_reject(t, battle, Sm2CombatFixtures.command(battle, "sword_strike", 5), "fatigue_limit")
	state = Sm2CombatFixtures.untyped(battle)
	Sm2CombatFixtures.actor(state, 2).fatigue = 0
	Sm2CombatFixtures.actor(state, 2).ap = 3
	t.expect(battle.restore(state).ok, "combat insufficient AP fixture")
	_reject(t, battle, Sm2CombatFixtures.command(battle, "sword_strike", 5), "insufficient_ap")
	# Kill a waiting actor in the deferred queue, preserving the current attacker.
	battle = Sm2CombatFixtures.battle(t, [2, 4], 1231)
	Sm2CombatFixtures.end(t, battle, "wait")
	state = Sm2CombatFixtures.untyped(battle)
	var victim: Dictionary = Sm2CombatFixtures.actor(state, 2)
	victim.combat.hp = 1
	Sm2CombatFixtures.item(victim, "body").current = 0
	Sm2CombatFixtures.item(victim, "head").current = 0
	t.expect(battle.restore(state).ok, "combat wounded waiter loads")
	result = Sm2CombatFixtures.act(t, battle, "axe_strike", 2)
	t.expect(battle.view().deferred_queue.is_empty(), "combat killed waiter removed from deferred")
	t.equal(battle.view().active_actor_id, 4, "combat kill does not interrupt attacker with remaining AP")
	t.equal(Sm2TurnTestFixtures.types(result.events).count("actor_died"), 1, "combat deferred death exactly once")

static func _reject(t: Sm2TestHarness, battle: Sm2TacticalBattle, command: Sm2Command, code: String) -> void:
	var before: String = battle.state_hash()
	var preview: Dictionary = battle.preview(command)
	t.expect(not preview.allowed and preview.reason == code, "combat preview rejects " + code + " got " + str(preview))
	var result: Sm2CommandResult = battle.execute(command)
	t.expect(not result.accepted and result.code == code and result.events.is_empty(), "combat execute rejects " + code)
	t.equal(battle.state_hash(), before, "combat rejected command preserves full state and RNG")
