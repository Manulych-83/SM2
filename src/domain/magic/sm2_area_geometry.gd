class_name Sm2AreaGeometry
extends RefCounted
## Axial hex disc in stable q/r order. Bounds are always supplied by the battlefield.
static func disc(field: Sm2Battlefield, center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for q: int in range(center.x-radius,center.x+radius+1):
		for r: int in range(center.y-radius,center.y+radius+1):
			var cell: Vector2i = Vector2i(q,r)
			if field.in_bounds(cell) and Sm2Hex.distance(center,cell) <= radius: result.append(cell)
	return result

static func footprint(field: Sm2Battlefield, center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in disc(field,center,radius):
		# Terrain stops propagation; participants do not shield other participants.
		if cell == center or Sm2SpatialQueries.los(field,center,cell,[]).visible: result.append(cell)
	return result
