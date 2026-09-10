class_name Sm2Hex
extends RefCounted
## Axial coordinates; integer differences are promoted before arithmetic.
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]

static func neighbors(position: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	# A Vector2i cannot represent all six neighbors at its integer boundary.
	if position.x <= -2147483648 or position.x >= 2147483647 or position.y <= -2147483648 or position.y >= 2147483647:
		return result
	for direction: Vector2i in DIRECTIONS:
		result.append(position + direction)
	return result

static func distance(left: Vector2i, right: Vector2i) -> int:
	var dq: int = int(left.x) - int(right.x)
	var dr: int = int(left.y) - int(right.y)
	@warning_ignore("integer_division")
	var result: int = (absi(dq) + absi(dr) + absi(dq + dr)) / 2
	return result

static func numeric_less(left: Vector2i, right: Vector2i) -> bool:
	return left.x < right.x if left.x != right.x else left.y < right.y

static func path_less(left: Array[Vector2i], right: Array[Vector2i]) -> bool:
	for index: int in mini(left.size(), right.size()):
		if left[index] != right[index]:
			return numeric_less(left[index], right[index])
	return left.size() < right.size()
