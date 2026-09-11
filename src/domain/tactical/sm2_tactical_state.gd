class_name Sm2TacticalState
extends RefCounted
var survival: Sm2SurvivalState = null
var survival_initial: String = ""
var survival_error: String = ""
var survival_context: Sm2ConsequenceContext = null
var survival_combat: Sm2CombatCatalog = null
const RULESET: String = "sm2.m2.turns.1"
var battle_id: String = ""
var scenario_id: String = ""
var body_changes: Array[Dictionary]=[]
var field: Sm2Battlefield = null
var round_limit: int = 100
var round: int = 0
var revision: int = 0
var next_actor_id: int = 1
var actors: Dictionary[int, Sm2TacticalActor] = {}
var sides: Array[String] = []
var main_queue: Array[int] = []
var deferred_queue: Array[int] = []
var phase: String = "main"
var finished: bool = false
var finish_reason: String = ""
var rng: Sm2DeterministicRng = Sm2DeterministicRng.new()
var combat_fingerprint: String = ""
var next_item_id: int = 1
var consequences: bool = false
var winner: String = ""
var effect_catalog: Sm2EffectCatalog = null
var effects: Dictionary[int, Sm2EffectInstance] = {}
var next_effect_id: int = 1
var magic_catalog: Sm2MagicCatalog = null
var mana: Dictionary[int, Sm2ManaPool] = {}
var development: Sm2BattleDevelopment = null

func sorted_effect_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(effects.keys())
	ids.sort()
	return ids

func actor(id: int) -> Sm2TacticalActor:
	return actors.get(id, null) as Sm2TacticalActor

func active_id() -> int:
	if finished:
		return 0
	if phase == "main" and not main_queue.is_empty():
		return main_queue[0]
	if phase == "deferred" and not deferred_queue.is_empty():
		return deferred_queue[0]
	return 0

func sorted_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(actors.keys())
	ids.sort()
	return ids

func occupancy() -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for id: int in sorted_ids():
		var entry: Sm2TacticalActor = actor(id)
		if entry.spatial.occupies():
			positions.append(entry.spatial.position)
	return positions

func copy() -> Sm2TacticalState:
	var result: Sm2TacticalState = Sm2TacticalState.new()
	result.survival=survival.copy() if survival!=null else null
	result.survival_initial=survival_initial; result.survival_error=survival_error
	result.battle_id = battle_id
	result.scenario_id = scenario_id
	if field != null:
		result.field = Sm2Battlefield.new()
		result.field.build(field.to_data())
	result.round_limit = round_limit
	result.body_changes.assign(body_changes.duplicate(true))
	result.round = round
	result.revision = revision
	result.next_actor_id = next_actor_id
	for id: int in sorted_ids():
		result.actors[id] = actor(id).copy()
	result.sides.assign(sides)
	result.main_queue.assign(main_queue)
	result.deferred_queue.assign(deferred_queue)
	result.phase = phase
	result.finished = finished
	result.finish_reason = finish_reason
	result.rng.state = rng.state
	result.rng.draws = rng.draws
	result.combat_fingerprint = combat_fingerprint
	result.next_item_id = next_item_id
	result.consequences = consequences
	result.winner = winner
	result.magic_catalog = magic_catalog
	if development != null: result.development = development.copy()
	for id: int in mana: result.mana[id] = mana[id].copy()
	result.effect_catalog = effect_catalog
	result.next_effect_id = next_effect_id
	for id: int in sorted_effect_ids(): result.effects[id] = effects[id].copy()
	return result

func to_data(catalog_fingerprint: String) -> Dictionary:
	var actor_data: Array[Dictionary] = []
	for id: int in sorted_ids():
		actor_data.append(actor(id).to_data())
	var main_data: Array[String] = []
	for id: int in main_queue:
		main_data.append(str(id))
	var deferred_data: Array[String] = []
	for id: int in deferred_queue:
		deferred_data.append(str(id))
	var data: Dictionary = {"format": "sm2.battle", "schema_version": 2, "ruleset": RULESET,
		"catalog_fingerprint": catalog_fingerprint, "battle_id": battle_id, "scenario_id": scenario_id,
		"field": field.to_data() if field != null else {}, "field_fingerprint": field.fingerprint() if field != null else "",
		"round_limit": round_limit, "round": str(round), "revision": str(revision), "next_actor_id": str(next_actor_id),
		"actors": actor_data, "sides": Array(sides).duplicate(), "main_queue": main_data, "deferred_queue": deferred_data,
		"phase": phase, "active_actor_id": str(active_id()), "finished": finished, "finish_reason": finish_reason,
		"rng": {"version": Sm2DeterministicRng.VERSION, "state": str(rng.state), "draws": str(rng.draws)}}
	if not combat_fingerprint.is_empty():
		data.schema_version = 3
		data.ruleset = Sm2CombatSnapshot.RULESET
		data["combat_fingerprint"] = combat_fingerprint
		data["next_item_id"] = str(next_item_id)
	if consequences:
		data.schema_version = 4
		data.ruleset = Sm2CombatSnapshot.CONSEQUENCE_RULESET
		data["winner"] = winner if not winner.is_empty() else null
	if effect_catalog != null:
		data.schema_version = 5
		data.ruleset = Sm2EffectSnapshot.RULESET
		data["effect_fingerprint"] = effect_catalog.fingerprint()
		data["next_effect_id"] = str(next_effect_id)
		var entries: Array[Dictionary] = []
		for id: int in sorted_effect_ids(): entries.append(effects[id].to_data())
		data["effects"] = entries
	if magic_catalog != null:
		data.schema_version = 7 if magic_catalog.supports_areas() else 6
		data.ruleset = Sm2MagicSnapshot.AREA_RULESET if magic_catalog.supports_areas() else Sm2MagicSnapshot.RULESET
		data["magic_fingerprint"] = magic_catalog.fingerprint()
		var pools: Array[Dictionary] = []
		for id: int in sorted_ids(): pools.append({"actor_id":str(id),"current":mana[id].current})
		data["mana"] = pools
	if development != null:
		data.schema_version = Sm2EncounterOrigin.schema(development.catalog,development.origin)
		data.ruleset = Sm2DevelopmentSnapshot.RULESET if development.origin.is_empty() else str(development.origin.version)
		data["development"] = development.to_data()
		if development.catalog.has_body_functions(): data["body_changes"]=body_changes.duplicate(true)
	if survival!=null:
		data.schema_version=19; data.ruleset=Sm2SurvivalBattle.RULESET
		data["survival"]=survival.to_data(); data["survival_initial"]=survival_initial
	return data
