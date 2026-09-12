class_name Sm2BattleMotion
extends RefCounted
## Local display time only; keeps no runner, world, commands or RNG reference.
const DURATION: float = 0.38
const MOVE_DURATION: float = 0.18
var cues: Array[Dictionary] = []
var elapsed: float = 0.0

func clear() -> void:
	cues.clear(); elapsed = 0.0

func play(events: Array[Dictionary], actors: Array) -> void:
	var positions: Dictionary = {}; var ranged: Dictionary = {}
	for actor: Dictionary in actors:
		positions[int(actor.actor_id)] = Vector2i(int(actor.q), int(actor.r))
		ranged[int(actor.actor_id)] = str(Sm2BattleText.item(actor, "weapon").get("definition_id", "")).ends_with("bow")
	for event: Dictionary in events:
		var kind: String = str(event.get("type", ""))
		if kind not in ["attack_hit", "attack_missed", "spell_cast", "moved", "barrier_cast"]: continue
		var source: int = int(event.get("actor_id", 0)); var target: int = int(event.get("target_actor_id", 0))
		if kind in ["moved", "barrier_cast"]: target = source
		if not positions.has(source) or not positions.has(target): continue
		var origin: Vector2i = positions[source]; var destination: Vector2i = positions[target]
		if kind == "moved":
			if not event.has_all(["from_q", "from_r", "q", "r"]): continue
			origin = Vector2i(int(event.from_q), int(event.from_r)); destination = Vector2i(int(event.q), int(event.r))
			positions[source] = destination
		cues.append({"kind": kind, "source": source, "target": target, "from": origin, "to": destination, "hit": kind != "attack_missed", "psi": kind in ["spell_cast", "barrier_cast"], "ranged": ranged[source] or kind == "spell_cast"})
	# Bound visual latency even when input or a test submits actions faster than drawing.
	while cues.size() > 8: cues.pop_front(); elapsed = 0.0

func advance(delta: float) -> void:
	if cues.is_empty(): return
	elapsed += maxf(delta, 0.0)
	while not cues.is_empty() and elapsed >= duration():
		elapsed -= duration(); cues.pop_front()
	if cues.is_empty(): elapsed = 0.0

func phase() -> float:
	return clampf(elapsed / duration(), 0, 1)

func duration() -> float:
	return MOVE_DURATION if not cues.is_empty() and cues[0].kind == "moved" else DURATION

func offset(id: int, from: Vector2, to: Vector2, radius: float) -> Vector2:
	if cues.is_empty(): return Vector2.ZERO
	var cue: Dictionary = cues[0]; var direction: Vector2 = (to - from).normalized()
	if cue.kind in ["moved", "barrier_cast"]: return Vector2.ZERO
	var pulse: float = sin(phase() * PI)
	if id == int(cue.source) and not cue.ranged: return direction * radius * 0.30 * pulse
	if id == int(cue.target) and cue.hit: return direction * radius * 0.10 * pulse
	return Vector2.ZERO

func segment(id: int, actual: Vector2i) -> Dictionary:
	# Earliest pending involvement determines the display position. This prevents
	# teleporting to the final cell when several commands arrive between frames.
	for index: int in cues.size():
		var cue: Dictionary = cues[index]
		if int(cue.source) == id:
			if cue.kind == "moved":
				var blend: float = smoothstep(0.0, 1.0, phase()) if index == 0 else 0.0
				return {"from": cue.from, "to": cue.to, "blend": blend}
			return {"from": cue.from, "to": cue.from, "blend": 0.0}
		if int(cue.target) == id: return {"from": cue.to, "to": cue.to, "blend": 0.0}
	return {"from": actual, "to": actual, "blend": 0.0}
