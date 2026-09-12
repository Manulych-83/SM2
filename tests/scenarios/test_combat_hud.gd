extends RefCounted
const IMPLANTS = preload("res://tests/scenarios/test_p5_implants.gd")
const TISSUES = preload("res://tests/scenarios/test_survival_tissues.gd")
const HYBRIDS = preload("res://tests/scenarios/test_p5_hybrids.gd")

static func run(t: Sm2TestHarness) -> void:
	for enhanced: bool in [false,true]:
		var battle: Sm2TacticalBattle = IMPLANTS.fixture(t,enhanced)
		var before: String = battle.state_hash()
		for ability: String in ["m2:ability.sword_strike","p5:ability.impulse","p5:ability.shield"]:
			var request: Sm2Command = Sm2CombatHudView.command(battle.view(),"use_ability",ability,1 if ability.ends_with("shield") else 3)
			var check: Dictionary = battle.preview(request); t.expect(check.allowed,"cost reference is actual allowed action")
			var cost: Dictionary = battle.ability_cost(1,ability)
			for key: String in ["ap_cost","fatigue_cost","mana_cost"]: t.equal(cost.get(key,0),check.get(key,0),"display price equals executable price "+key)
			if ability == "p5:ability.impulse": t.equal(cost.mana_cost,7 if enhanced else 6,"implant concentration surcharge included")
			if ability == "m2:ability.sword_strike": t.equal(cost.fatigue_cost,12 if enhanced else 10,"genetic fatigue surcharge included")
			cost.ap_cost = 900; t.equal(battle.state_hash(),before,"editing price does not change rules or state")
		t.equal(battle.ability_cost(1,"unknown"),{},"unknown ability has no invented price")
		t.equal(battle.ability_cost(999,"m2:ability.sword_strike"),{},"unknown actor")
		t.equal(battle.state_hash(),before,"queries preserve battle and RNG")
		var hybrid: Sm2TacticalBattle = HYBRIDS.fixture(t,1,enhanced)
		var cost: Dictionary = hybrid.ability_cost(1,HYBRIDS.ID)
		var check: Dictionary = hybrid.preview(HYBRIDS.command(hybrid))
		t.expect(check.allowed,"hybrid price reference allowed")
		for key: String in ["ap_cost","fatigue_cost","mana_cost"]: t.equal(cost[key],check[key],"hybrid shares both physical and psionic costs")
	var s: Sm2JourneySession = TISSUES.make(); t.expect(s.new_game().ok,"HUD world starts")
	t.expect(s.act(s.command("travel",0,"ruins")).ok,"HUD reaches ruins")
	t.expect(s.act(s.command("start_battle")).ok,"HUD starts encounter")
	var before: String = s.state_hash(); var state: Dictionary = s.runner.view()
	var rows: Array[Dictionary] = Sm2CombatHudView.actions(s.runner,state,true)
	for row: Dictionary in rows:
		t.equal(row.revision,state.revision,"rendered action captures revision")
		t.equal(row.battle_id,state.battle_id,"rendered action captures battle")
		t.equal(row.actor_id,state.active_actor_id,"rendered action captures acting unit")
		if row.id == "m2:ability.sword_strike":
			t.expect(not row.allowed,"no melee targets initially")
			t.equal(row.cost.ap_cost,4,"unavailable ability still shows genuine price")
	var card: Dictionary = Sm2CombatHudView.card(state.actors[0]); card.ap[0] = 999
	rows.clear()
	var queue: Array[Dictionary] = Sm2CombatHudView.queue(state)
	var expected: Array = state.main_queue.duplicate(); expected.append_array(state.deferred_queue)
	var actual: Array = []
	for row: Dictionary in queue: actual.append(row.id)
	t.equal(actual,expected,"queue keeps domain order including deferred actors")
	t.equal(s.state_hash(),before,"all HUD read models detached and read-only")
	t.complete_suite("combat_hud")
