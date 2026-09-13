class_name Sm2ManaResolver
extends RefCounted

static func initialize(state: Sm2TacticalState) -> String:
	for id: int in state.sorted_ids():
		var profile: Sm2MagicProfile = state.magic_catalog.profile(state.actor(id).loadout_id)
		if profile == null: return "magic_profile_missing"
		var pool: Sm2ManaPool = Sm2ManaPool.new()
		pool.current = profile.mana_max
		state.mana[id] = pool
	return ""

static func recover_round(state: Sm2TacticalState, id: int, events: Array[Dictionary]) -> void:
	if state.magic_catalog == null or not state.actor(id).spatial.occupies(): return
	var profile: Sm2MagicProfile = state.magic_catalog.profile(state.actor(id).loadout_id)
	var pool: Sm2ManaPool = state.mana[id]
	var gained: int = mini(profile.mana_per_round,profile.mana_max-pool.current)
	pool.current += gained
	if gained > 0: events.append({"type":"concentration_recovered" if state.magic_catalog.is_psionic() else "mana_recovered","actor_id":str(id),"amount":gained,"current":pool.current,"maximum":profile.mana_max})

static func cost(state: Sm2TacticalState,actor_id: int,spell: Sm2SpellDefinition) -> Dictionary:
	if spell.channel=="psionic" and state.development!=null:
		return state.development.concentration_cost(actor_id,spell.mana_cost,spell.id)
	return Sm2PsionicCostQuery.resolve(spell.mana_cost)
