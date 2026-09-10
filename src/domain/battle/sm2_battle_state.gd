class_name Sm2BattleState
extends RefCounted
const RULESET: String = "sm2.m1.fixture.1"
var battle_id: String = ""
var width: int = 0
var height: int = 0
var revision: int = 0
var round: int = 1
var next_id: int = 1
var actors: Array[Sm2ActorState] = []
var queue: Array[int] = []
var sides: Array[String] = []
var finished: bool = false
var winner: String = ""
var rng: Sm2DeterministicRng = Sm2DeterministicRng.new()

func actor(id: int) -> Sm2ActorState:
	for entry: Sm2ActorState in actors:
		if entry.actor_id == id:
			return entry
	return null

func active_id() -> int:
	return queue[0] if not queue.is_empty() and not finished else 0

func in_bounds(position: Vector2i) -> bool:
	return position.x >= 0 and position.y >= 0 and position.x < width and position.y < height

func occupied(position: Vector2i) -> bool:
	for entry: Sm2ActorState in actors:
		if entry.alive() and entry.position == position:
			return true
	return false

static func distance(left: Vector2i, right: Vector2i) -> int:
	var delta: Vector2i = left - right
	return maxi(maxi(absi(delta.x), absi(delta.y)), absi(delta.x + delta.y))

func spawn(template: Sm2ActorDefinition, catalog: Sm2Catalog, side: String, owner: String,
	controller: String, position: Vector2i, creator: int = 0, eligible_round: int = 1) -> Sm2ActorState:
	var entry: Sm2ActorState = Sm2ActorState.new()
	entry.actor_id = next_id
	next_id += 1
	entry.template_id = template.id
	entry.side = side
	entry.owner = owner
	entry.controller = controller
	entry.position = position
	entry.creator = creator
	entry.eligible_round = eligible_round
	entry.hp = template.hp
	entry.ap = template.ap
	entry.weapon = Sm2ItemState.new()
	entry.weapon.instance_id = entry.actor_id
	entry.weapon.definition_id = template.weapon_id
	entry.weapon.durability = catalog.weapon(template.weapon_id).durability
	actors.append(entry)
	return entry

func rebuild_queue(catalog: Sm2Catalog) -> void:
	queue.clear()
	for entry: Sm2ActorState in actors:
		if entry.alive() and entry.eligible_round <= round and entry.last_acted_round < round:
			queue.append(entry.actor_id)
	queue.sort_custom(func(left: int, right: int) -> bool:
		var left_speed: int = catalog.actor(actor(left).template_id).initiative
		var right_speed: int = catalog.actor(actor(right).template_id).initiative
		return left_speed > right_speed if left_speed != right_speed else left < right)

func damage(target: Sm2ActorState, amount: int, source_id: int, cause: String, events: Array[Dictionary]) -> void:
	if not target.alive():
		return
	var actual: int = mini(target.hp, amount)
	target.hp -= actual
	events.append({"type": "damage", "actor_id": str(target.actor_id), "source_actor_id": str(source_id), "amount": actual, "cause": cause})
	if not target.alive():
		events.append({"type": "death", "actor_id": str(target.actor_id), "source_actor_id": str(source_id), "cause": cause})
		queue.erase(target.actor_id)

func update_outcome() -> void:
	var living: Array[String] = []
	for entry: Sm2ActorState in actors:
		if entry.alive() and not entry.side in living:
			living.append(entry.side)
	finished = living.size() < 2
	winner = living[0] if finished and living.size() == 1 else ""
	if finished:
		queue.clear()

func to_data(fingerprint: String) -> Dictionary:
	var actor_data: Array[Dictionary] = []
	for entry: Sm2ActorState in actors:
		actor_data.append(entry.to_data())
	var queue_data: Array[String] = []
	for id: int in queue:
		queue_data.append(str(id))
	return {"format": "sm2.battle", "schema_version": 1, "ruleset": RULESET,
		"catalog_fingerprint": fingerprint, "battle_id": battle_id, "width": width, "height": height,
		"revision": str(revision), "round": str(round), "next_id": str(next_id), "actors": actor_data,
		"queue": queue_data, "sides": Array(sides).duplicate(), "finished": finished, "winner": winner,
		"rng": {"version": Sm2DeterministicRng.VERSION, "state": str(rng.state), "draws": str(rng.draws)}}
