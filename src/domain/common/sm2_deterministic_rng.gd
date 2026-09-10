class_name Sm2DeterministicRng
extends RefCounted
## Park-Miller 48271. Largest multiplication is below 2^47, so int64 is safe.
## Published sequence seed=1: 48271, 182605794, 1291394886, 1914720637.
const VERSION: String = "park_miller_48271.v1"
const MODULUS: int = 2147483647
const SPAN: int = MODULUS - 1
var state: int = 1
var draws: int = 0

func _init(seed_value: int = 1) -> void:
	state = seed_value % SPAN
	if state <= 0:
		state += SPAN

func next_value() -> int:
	state = (state * 48271) % MODULUS
	draws += 1
	return state

func range_inclusive(minimum: int, maximum: int) -> int:
	assert(minimum <= maximum and maximum - minimum < SPAN)
	var count: int = maximum - minimum + 1
	# Each accepted residue occurs exactly floor(SPAN/count) times.
	var limit: int = SPAN - SPAN % count
	var sample: int = next_value() - 1
	while sample >= limit:
		sample = next_value() - 1
	return minimum + sample % count
