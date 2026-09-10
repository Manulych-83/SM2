class_name Sm2BattleDice
extends RefCounted
const MAX_COUNTER: int = 9223372036854775806

static func roll(rng: Sm2DeterministicRng, minimum: int, maximum: int) -> int:
	var count: int = maximum - minimum + 1
	var limit: int = Sm2DeterministicRng.SPAN - Sm2DeterministicRng.SPAN % count
	while rng.draws < MAX_COUNTER:
		var sample: int = rng.next_value() - 1
		if sample < limit:
			return minimum + sample % count
	return 0
