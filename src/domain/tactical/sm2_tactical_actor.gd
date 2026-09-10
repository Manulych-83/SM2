class_name Sm2TacticalActor
extends RefCounted
## Combat scheduling state owns one spatial projection, never duplicated vitals.
const MORALES: Array[String] = ["steady", "wavering", "breaking", "fleeing"]
var spatial: Sm2SpatialActor = Sm2SpatialActor.new()
var loadout_id: String = ""
var creator: int = 0
var morale: String = "steady"
var round_fatigue: int = 0
var round_morale: String = "steady"
var initiative: int = 0
var activation_started: bool = false
var wait_used: bool = false
var turn_done: bool = false
var reactions_left: int = 0
var combat: Sm2Combatant = null

static func from_setup(raw: Dictionary, catalog: Sm2TurnCatalog) -> Dictionary:
	if catalog == null or not Sm2Validate.fields(raw, ["actor_id", "loadout_id", "side", "owner", "controller", "creator", "q", "r", "fatigue", "alive", "on_field", "morale"]):
		return _failure("tactical actor: missing catalog or unexpected setup fields")
	if not raw.actor_id is int or raw.actor_id < 1 or raw.actor_id > 9223372036854775805 \
		or not raw.creator is int or raw.creator < 0 or raw.creator >= raw.actor_id \
		or not Sm2Validate.text(raw.loadout_id) or not catalog.has_loadout(raw.loadout_id) \
		or not raw.fatigue is int or not raw.morale is String or not raw.morale in MORALES:
		return _failure("tactical actor: invalid identity, loadout, creator or resources")
	var definition: Sm2TurnDefinition = catalog.definition(raw.loadout_id)
	var projected: Dictionary = Sm2SpatialActor.decode({"actor_id": raw.actor_id, "side": raw.side,
		"owner": raw.owner, "controller": raw.controller, "q": raw.q, "r": raw.r,
		"ap_max": definition.ap_max, "ap": 0, "fatigue_max": definition.fatigue_max,
		"fatigue": raw.fatigue, "alive": raw.alive, "on_field": raw.on_field})
	if not projected.ok:
		return _failure("tactical actor: " + str(projected.reason))
	var result: Sm2TacticalActor = Sm2TacticalActor.new()
	result.spatial = projected.actor
	result.loadout_id = raw.loadout_id
	result.creator = raw.creator
	result.morale = raw.morale
	result.round_fatigue = raw.fatigue
	result.round_morale = raw.morale
	result.turn_done = not result.spatial.occupies()
	return {"ok": true, "errors": PackedStringArray(), "actor": result}

func copy() -> Sm2TacticalActor:
	var result: Sm2TacticalActor = Sm2TacticalActor.new()
	# Explicit field copies also preserve a model while its candidate is being built.
	result.spatial.actor_id = spatial.actor_id
	result.spatial.side = spatial.side
	result.spatial.owner = spatial.owner
	result.spatial.controller = spatial.controller
	result.spatial.position = spatial.position
	result.spatial.ap_max = spatial.ap_max
	result.spatial.ap = spatial.ap
	result.spatial.fatigue_max = spatial.fatigue_max
	result.spatial.fatigue = spatial.fatigue
	result.spatial.alive = spatial.alive
	result.spatial.on_field = spatial.on_field
	result.loadout_id = loadout_id
	result.creator = creator
	result.morale = morale
	result.round_fatigue = round_fatigue
	result.round_morale = round_morale
	result.initiative = initiative
	result.activation_started = activation_started
	result.wait_used = wait_used
	result.turn_done = turn_done
	result.reactions_left = reactions_left
	result.combat = combat.copy() if combat != null else null
	return result

func view() -> Dictionary:
	var data: Dictionary = to_data()
	data.actor_id = spatial.actor_id
	data.creator = creator
	data.ap_max = spatial.ap_max
	data.fatigue_max = spatial.fatigue_max
	return data

func to_data() -> Dictionary:
	var data: Dictionary = {"actor_id": str(spatial.actor_id), "loadout_id": loadout_id,
		"side": spatial.side, "owner": spatial.owner, "controller": spatial.controller, "creator": str(creator),
		"q": spatial.position.x, "r": spatial.position.y, "ap": spatial.ap, "fatigue": spatial.fatigue,
		"alive": spatial.alive, "on_field": spatial.on_field, "morale": morale,
		"round_fatigue": round_fatigue, "round_morale": round_morale, "initiative": initiative,
		"activation_started": activation_started, "wait_used": wait_used, "turn_done": turn_done,
		"reactions_left": reactions_left}
	if combat != null:
		data["combat"] = combat.to_data()
	return data

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message]), "actor": null}
